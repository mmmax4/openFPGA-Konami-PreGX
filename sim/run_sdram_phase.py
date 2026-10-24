#!/usr/bin/env python3
"""Four-state actual-controller phase gate with immutable original negative.

Build one Icarus job. The compile copy is byte-identical to the controller; VERILATOR selects
the equivalent direct positive DDR clock carrier. Modern Icarus is required.
Private seed words are byte-identical to the Gaiapolis tile ROM loader region.
"""
import argparse
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'build/verification/sdram-phase'
DATASHEET_SHA256 = 'bb49458b366aecffa8f16156b1afe1f19899071cd11181972c9822fbcd146fa5'
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def verified_datasheet():
    """Prefer the persistent private reference; retain the historical cache fallback."""
    candidates = (ROOT/'private/reference/AS4C32M16MSA-6BIN.pdf',
                  Path('/tmp/pregx-msdram.pdf'))
    for path in candidates:
        if path.exists():
            # An existing but altered reference must not be silently bypassed.
            if sha(path) != DATASHEET_SHA256:
                raise ValueError(f'datasheet SHA256 mismatch: {path}')
            return path
    raise FileNotFoundError('Verified AS4C32M16MSA datasheet required: '+
                            ', '.join(str(path) for path in candidates))

HISTORICAL_RANGES = {
    'slow85':((4287,4550),(2633,2912)),
    'slow0':((4212,4440),(2711,3028)),
    'fast85':((2135,2245),(1183,1330)),
    'fast0':((2040,2079),(1228,1301))}

def load_fit_ranges(path):
    """Read the extractor's combined setup/hold envelope, never physical delays."""
    body = path.read_bytes()
    extracted = json.loads(body, parse_float=Decimal)
    if extracted.get('schema') != 'pregx-sdram-full-path-v1' or extracted.get('path_count') != 128:
        raise ValueError('fit ranges require the complete 128-path extractor schema')
    if extracted.get('scope') not in ('diagnostic-old', 'new-fit'):
        raise ValueError('fit ranges scope must be diagnostic-old or new-fit')
    provenance = extracted['provenance']
    if extracted['scope'] == 'new-fit' and provenance.get('canonical_compile_bound') is not True:
        raise ValueError('new-fit ranges require canonical compile/artifact binding')
    identities = [extracted['extractor'], extracted['paths_tsv'], provenance['audit_manifest']]
    identities += provenance.get('artifacts', [])
    if provenance.get('compile_manifest'):
        identities.append(provenance['compile_manifest'])
    for item in identities:
        source_path = Path(item['path'])
        if not source_path.is_absolute():
            source_path = ROOT/source_path
        if sha(source_path) != item['sha256']:
            raise ValueError(f'fit ranges provenance changed: {source_path}')
    ranges = {}
    for corner in extracted['corner_intervals_ns']:
        name = corner['model']+str(corner['temperature_c'])
        if name not in HISTORICAL_RANGES or name in ranges:
            raise ValueError(f'unknown/duplicate fit corner: {name}')
        checks = corner['checks']
        if [checks[k]['count'] for k in ('setup','hold','combined')] != [16,16,32]:
            raise ValueError(f'incomplete setup/hold corner: {name}')
        equivalent = checks['combined']['sta_equivalent']
        bounds = []
        for field in ('launch_minus_capture_effective_ns','input_data_delay_ns'):
            values = equivalent[field]
            if any(type(values[k]) not in (int,Decimal) for k in ('min','max')):
                raise ValueError(f'nonnumeric fit interval: {name}/{field}')
            low, high = (Decimal(values[k]) for k in ('min','max'))
            if not low.is_finite() or not high.is_finite() or low > high:
                raise ValueError(f'invalid fit interval: {name}/{field}')
            if field == 'input_data_delay_ns' and low < 0:
                raise ValueError(f'negative input path delay: {name}')
            bounds.append((int((low*1000).to_integral_value(rounding=ROUND_FLOOR)),
                           int((high*1000).to_integral_value(rounding=ROUND_CEILING))))
        ranges[name] = tuple(bounds)
    if set(ranges) != set(HISTORICAL_RANGES):
        raise ValueError('fit ranges must contain all four slow/fast 0/85C corners')
    # Use the historical corner order to keep case labels/order comparable.
    ranges = {name:ranges[name] for name in HISTORICAL_RANGES}
    context = {'path':str(path.resolve()),'sha256':hashlib.sha256(body).hexdigest(),
        'scope':extracted['scope'],'schema':extracted['schema'],'path_count':128,
        'extractor':extracted['extractor'],'provenance':provenance,
        'paths_tsv':extracted['paths_tsv'],
        'reported_dq_setup_hold_nonnegative':extracted['reported_dq_setup_hold_nonnegative'],
        'interval_source':'corner_intervals_ns/checks/combined/sta_equivalent',
        'rounding':'min floor(ns*1000), max ceil(ns*1000), Decimal arithmetic',
        'representation':'STA-equivalent envelope includes capture-cell endpoint and CPPR; not unique physical clock/wire propagation',
        'scope_limit':'Independent min/max combinations bound reported scalar values only; no full-fit, physical pulse aperture, command/write or Pocket qualification'}
    return ranges, context, body

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--label', default='original')
    ap.add_argument('--phase', type=int, default=6116)
    ap.add_argument('--iverilog',default='iverilog')
    ap.add_argument('--vvp',default='vvp')
    ap.add_argument('--reviewer', default='verification agent',
                    help='Actual operator/reviewer; lead-run checks must say lead')
    ap.add_argument('--fit-ranges-json', type=Path,
                    help='read_sdram_fit.py JSON; combined setup/hold STA-equivalent bounds')
    args = ap.parse_args()
    datasheet = verified_datasheet() # Fail before creating an archive or compiling.
    corner_ranges, fit_context, fit_body = HISTORICAL_RANGES, None, None
    if args.fit_ranges_json:
        corner_ranges, fit_context, fit_body = load_fit_ranges(args.fit_ranges_json)
        if any(args.phase+skew[0] < 0 for skew,pad in corner_ranges.values()):
            raise ValueError('fit ranges produce a negative simulated clock phase')
    if not args.label.replace('-','').isalnum():
        raise SystemExit('label must be alphanumeric')
    dest = OUT/f'archive-{args.label}'
    if dest.exists():
        raise SystemExit(f'archive exists: {dest}; never overwrite source-bound evidence')
    dest.mkdir(parents=True)
    if fit_body is not None:
        (dest/'fit-ranges.json').write_bytes(fit_body)
    bench = ROOT/'sim/tb_sdram_phase.sv'
    source = ROOT/'target/pocket/sdram_ctrl.sv'
    copied_source = dest/'sdram_ctrl-source.sv'
    copied_bench = dest/'tb_sdram_phase.sv'
    shutil.copy2(source,copied_source); shutil.copy2(bench,copied_bench)
    copied_runner = dest/'run_sdram_phase.py'
    shutil.copy2(Path(__file__),copied_runner)
    compiler_source = dest/'sdram_ctrl-iverilog.sv'
    compiler_source.write_text(source.read_text())
    rom = ROOT/'private/gaiapols.rom'
    image = rom.read_bytes()
    if len(image)!=20316288 or hashlib.md5(image).hexdigest()!='7ed05d08287ecc2be8592b0ef0158aad':
        raise SystemExit('original ROM image identity mismatch')
    # SD_TILE physical word0x8000 maps IMG_TILE byte0x340000 +0x10000.
    offset, count = 0x350000, 8192
    data = image[offset:offset+count]
    seed = dest/'seed.hex'
    seed.write_text(''.join(f'{int.from_bytes(data[i:i+2],"big"):04x}\n' for i in range(0,count,2)))
    cmd = [args.iverilog,'-g2012','-DVERILATOR','-s','tb_sdram_phase',
           '-o',str(dest/'sdram-phase.vvp'),str(copied_bench),str(compiler_source)]
    with (dest/'compile.log').open('w') as out:
        cp = subprocess.run(cmd,stdout=out,stderr=subprocess.STDOUT)
    (dest/'compile.exit').write_text(f'{cp.returncode}\n')
    toolchain = {}
    for name, executable in [('iverilog',args.iverilog),('vvp',args.vvp)]:
        resolved = Path(shutil.which(executable) or executable).resolve()
        version = subprocess.run([str(resolved),'-V'],capture_output=True,text=True)
        toolchain[name] = {'path':str(resolved),'sha256':sha(resolved),
            'version':(version.stdout+version.stderr).splitlines()[0]}
    record = {'reviewer':args.reviewer,'label':args.label,'chip':'AS4C32M16MSA-6BIN',
        'scope':'Actual sdram_ctrl, public single/burst consumers, four-state MR-selected CL2/CL3 BL1 pin response; original ROM bytes, no physical board or full memory loader qualification',
        'toolchain':toolchain,
        'sources_sha256': {'target/pocket/sdram_ctrl.sv':sha(copied_source),'sim/tb_sdram_phase.sv':sha(copied_bench),'sim/run_sdram_phase.py':sha(copied_runner)},
        'generated_source': {'sha256':sha(compiler_source),'transformation':'byte-identical actual controller source; VERILATOR macro only selects equivalent positive DDR clock carrier'},
        'compile_command':cmd,'compile_exit':cp.returncode,'compile_log_sha256':sha(dest/'compile.log'),
        'rom_sha256':hashlib.sha256(image).hexdigest(),'rom_slice_offset':offset,'rom_slice_bytes':count,
        'rom_slice_sha256':hashlib.sha256(data).hexdigest(),'seed_sha256':sha(seed),
        'datasheet':{'path':str(datasheet),'sha256':sha(datasheet),
                     'chip_identity_source':'https://www.analogue.co/developer/docs/openfpga/external-hardware'},
        'timing_ps':{'system_period':10410,'phase':args.phase,'tAC2_max':6000,'tAC3_max':5500,'tCK2_min':12000,'tCK3_min':6000,'tOH_min':2500,'tHZ_max':6000,'input_setup':2000,'input_hold':1000},
        'cases':{},'hardware_verified':False,'public_ack_observation':'Actual unpacked c_ack ports with modern Icarus; no internal state access','qualification_cases':'Four reported old-fit corners, minimum/maximum clock/pad bounds; nominal ideal cases diagnostic only'}
    if fit_context is not None:
        record['fit_ranges_input'] = fit_context
        record['full_fit_qualified'] = False
        record['fit_ranges_input']['archive_copy'] = str((dest/'fit-ranges.json').relative_to(ROOT))
        record['qualification_cases'] = ('Four combined setup/hold corner STA-equivalent envelopes, '
            'including capture-cell/CPPR; not unique physical propagation. Nominal cases diagnostic only; '
            'simulation PASS does not qualify the full fit or physical SDRAM aperture.')
    if cp.returncode==0:
        record['executable_sha256']=sha(dest/'sdram-phase.vvp')
        import itertools
        timings = [('nominal',args.phase,0,0,0), ('nominal-out1ns',args.phase,1000,0,0)]
        # Every reported corner: earliest validity loss (min clock/pad) and
        # latest data arrival (max clock/pad). They bound intermediate combinations.
        for corner,(skews,pads) in corner_ranges.items():
            for edge in (0,1):
                timings.append((f'fitted-{corner}-'+('min' if edge==0 else 'max'),
                                args.phase+skews[edge],2000,pads[edge],1000))
        record['fitted_clock_pad_ranges_ps']=corner_ranges
        for timing, late_release, late, slow in itertools.product(timings,(0,1),(0,1),(0,1)):
            name,phase,output_delay,input_delay,board_delay=timing
            label=f'{name}-release{late_release}-late{late}-slow{slow}'
            log=dest/f'{label}.log'
            run_cmd=[args.vvp,str(dest/'sdram-phase.vvp'),f'+PHASE={phase}',
                f'+OUT_PS={output_delay}',f'+INPUT_PS={input_delay}',f'+BOARD_PS={board_delay}',
                f'+RELEASE_LATE={late_release}',f'+RD_LATE={late}',f'+SLOW={slow}']
            try:
                with log.open('w') as out:
                    rp=subprocess.run(run_cmd,cwd=dest,stdout=out,stderr=subprocess.STDOUT,timeout=15)
                rc=rp.returncode
            except subprocess.TimeoutExpired:
                rc=124
            (dest/f'{label}.exit').write_text(f'{rc}\n')
            body=log.read_text()
            marks=[v[len('RESULT_JSON '):] for v in body.splitlines() if v.startswith('RESULT_JSON ')]
            result=json.loads(marks[-1]) if marks else {'passed':False,'no_result':True}
            result['passed']=result.get('data_passed',False) and result.get('initialization_passed',False) and result.get('clock_passed',False)
            result.update(exit_code=rc,log_sha256=sha(log),command=run_cmd,timing_case=name)
            record['cases'][label]=result
            print(label,json.dumps(result),flush=True)
            if not marks:
                break # fixture/watchdog errors must be diagnosed before the matrix
    record['sources_unchanged']=sha(source)==sha(copied_source) and sha(bench)==sha(copied_bench)
    if fit_context is not None:
        record['fit_ranges_unchanged'] = sha(args.fit_ranges_json)==fit_context['sha256']
        record['sources_unchanged'] &= record['fit_ranges_unchanged']
    fitted=[v for v in record['cases'].values() if v['timing_case'].startswith('fitted-')]
    record['passed']=cp.returncode==0 and len(fitted)==64 and all(x['passed'] and x['exit_code']==0 for x in fitted) and record['sources_unchanged']
    record['negative_reproduced']=len(fitted)==64 and all((not x['passed'] and x.get('mismatches',0)>0 if x['rd_late']==1 else x['data_passed']) and x.get('protocol_errors',1)==0 and x.get('input_setup_errors',1)==0 and x.get('input_hold_errors',1)==0 for x in fitted)
    (dest/'manifest.json').write_text(json.dumps(record,indent=2)+'\n')
    evidence_path=ROOT/'evidence/sdram-phase.json'
    evidence=json.loads(evidence_path.read_text()) if evidence_path.exists() else {'runs':{}}
    evidence['runs'][args.label]={'manifest_path':str((dest/'manifest.json').relative_to(ROOT)),'manifest_sha256':sha(dest/'manifest.json'),'passed':record['passed'],'negative_reproduced':record['negative_reproduced'],'source_sha256':sha(copied_source)}
    evidence['latest_label']=args.label
    evidence_path.write_text(json.dumps(evidence,indent=2)+'\n')
    print('RESULT',json.dumps({'passed':record['passed'],'negative_reproduced':record['negative_reproduced'],'compile_exit':cp.returncode}))
    if cp.returncode:
        print((dest/'compile.log').read_text())
    return 0 if record['passed'] else 1
if __name__=='__main__':
    raise SystemExit(main())
