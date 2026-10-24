#!/usr/bin/env python3
"""Actual pre-GX NV unloader, actual EEPROM byte port and Intel dual-clock FIFO.

Adapted method from the read-only Asterix runner. Original NV bytes are private;
generated build data are ignored. Never changes DUT, FIFO model or original ROM.
"""
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = Path('/opt/intelFPGA_lite/21.1/quartus/eda/sim_lib/altera_mf.v')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    build = ROOT / 'build/verification/nv-unloader'
    build.mkdir(parents=True, exist_ok=True)
    inputs = [ROOT / 'sim/tb_pregx_nv_unloader.sv',
              ROOT / 'platform/pocket/interface/data_unloader.sv',
              ROOT / 'rtl/er5911.sv', ROOT / 'target/pocket/core_top.sv',
              Path(__file__).resolve()]
    hashes = {str(path.relative_to(ROOT)): sha(path) for path in inputs}
    with zipfile.ZipFile(ROOT / 'roms/gaiapols.zip') as archive:
        nv = archive.read('gaiapols.nv')
    if hashlib.sha1(nv).hexdigest() != '19343b47b60bf4e212d844fce28e7a1bd54c7012' or len(nv) != 128:
        raise ValueError('original Gaiapolis NV does not match pinned MAME')
    seed = build / 'gaiapols-original-nv.hex'
    seed.write_text(''.join(f'{byte:02x}\n' for byte in nv))
    version = subprocess.run(['iverilog', '-V'], capture_output=True, text=True)
    (build / 'iverilog-version.log').write_text(version.stdout + version.stderr)
    # Icarus 10.3 lacks always_ff parsing. Syntax-only compile copy keeps the
    # same @(posedge clk) blocks and assignments; the root RTL stays untouched.
    eeprom_copy = build / 'er5911-iverilog.sv'
    eeprom_copy.write_text(inputs[2].read_text().replace('always_ff', 'always'))
    compile_log = build / 'compile.log'
    with compile_log.open('w') as output:
        result = subprocess.run(['iverilog', '-g2012', '-s', 'tb_pregx_nv_unloader',
                                 '-o', str(build / 'unloader.vvp'),
                                 str(inputs[0]), str(inputs[1]), str(eeprom_copy), str(VENDOR)],
                                stdout=output, stderr=subprocess.STDOUT)
    (build / 'compile.exit').write_text(f'{result.returncode}\n')
    if result.returncode:
        print(compile_log.read_text())
        return result.returncode
    cases = {}
    for phase in [1700, 8900]:
        for endian in [0, 1]:
            label = f'original-phase{phase}-endian{endian}'
            log = build / f'{label}.log'
            with log.open('w') as output:
                result = subprocess.run(['vvp', str(build / 'unloader.vvp'),
                                         f'+PHASE_PS={phase}', f'+ENDIAN={endian}'],
                                        cwd=build, stdout=output, stderr=subprocess.STDOUT)
            (build / f'{label}.exit').write_text(f'{result.returncode}\n')
            text = log.read_text()
            marks = [line[12:] for line in text.splitlines() if line.startswith('RESULT_JSON ')]
            case = json.loads(marks[-1]) if marks else {'passed': False}
            case.update(exit_status=result.returncode, vendor_underflow='Underflow' in text,
                        vendor_overflow='Overflow' in text, log_sha256=sha(log))
            cases[label] = case
            print(label, json.dumps(case), flush=True)
    checks = {
        'original_output_words_correct': all(c['mismatches'] == 0 for c in cases.values()),
        'no_response_fifo_empty_pops': all(c['empty_response_pops'] == 0 for c in cases.values()),
        'no_vendor_fifo_underflow_overflow': all(not c['vendor_underflow'] and not c['vendor_overflow'] for c in cases.values()),
        'sources_unchanged': all(sha(ROOT / name) == value for name, value in hashes.items()),
    }
    report = {
        'passed': all(checks.values()), 'reviewer': 'research agent',
        'scope': 'Original current root unloader and EEPROM byte port, unmodified Intel dcfifo model; APF bridge stimuli, initial original NV and distinct existing-save fixture; physical Pocket, full APF save scheduler and serial EEPROM excluded.',
        'sources_sha256': hashes, 'vendor_dcfifo': {'path': str(VENDOR), 'sha256': sha(VENDOR)},
        'generated_compile_copies': {'er5911': {'path': str(eeprom_copy.relative_to(ROOT)),
                                     'sha256': sha(eeprom_copy), 'transformation': 'always_ff -> always; unchanged event/assignments'}},
        'original_nv_sha256': hashlib.sha256(nv).hexdigest(), 'seed_hex_sha256': sha(seed),
        'word_bytes': 1, 'read_mem_clock_delay': 4,
        'clock_mhz': {'apf': 74.25, 'memory': 96}, 'spacing_apf_cycles': [80, 160, 240],
        'hold_apf_cycles': 3, 'checks': checks, 'cases': cases,
        'total_transactions': sum(c.get('transactions', 0) for c in cases.values()),
        'hardware_verified': False,
    }
    (ROOT / 'evidence/nv-unloader.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
