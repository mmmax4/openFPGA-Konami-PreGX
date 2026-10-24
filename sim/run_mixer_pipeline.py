#!/usr/bin/env python3
"""Independent bounded mixer gate. Build one job, then latency1 and negative2.

No game data are modified. Original comparison module is an exact generated
copy with only its module declaration renamed. Original stable cases must
remain unchanged; late-MMIO differences exercise the new snapshot contract.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import re
import time
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/verification/mixer-pipeline'
OUT.mkdir(parents=True, exist_ok=True)
reference = os.environ.get('GAIAPOLIS_REFERENCE_MIXER')
if not reference:
    raise SystemExit('Set GAIAPOLIS_REFERENCE_MIXER to the original upstream mixer source (commit3cc3ab372331fc5659f81e7c53a5aafff3049e08)')
tool = os.environ.get('VERILATOR') or shutil.which('verilator')
if not tool:
    raise SystemExit('A timing-capable Verilator is required; set VERILATOR or PATH')
VERILATOR = Path(tool).resolve()
ORIGINAL = Path(reference).resolve()
CPP = os.environ.get('CXX', 'g++')
def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
inputs = [ROOT/'rtl/k055555_mixer.sv', ROOT/'sim/tb_mixer_pipeline.sv',
          ROOT/'sim/run_mixer_pipeline.py', ROOT/'rtl/gaia_main.sv',
          ROOT/'projects/gaia_pocket.sdc', ORIGINAL]
frozen = {str(p): digest(p) for p in inputs}
original_copy = OUT/'k055555_mixer_original.sv'
text = ORIGINAL.read_text()
if text.count('module k055555_mixer (') != 1:
    raise SystemExit('original declaration unexpected')
original_copy.write_text(text.replace('module k055555_mixer (',
                                    'module k055555_mixer_original (', 1))
cmd = [str(VERILATOR), '--binary', '--timing', '--output-split', '0',
       '-j', '1', '-O2', '-Wno-fatal', '--top-module', 'tb_mixer_pipeline',
       '-Mdir', str(OUT/'obj'), str(ROOT/'rtl/k055555_mixer.sv'),
       str(original_copy), str(ROOT/'sim/tb_mixer_pipeline.sv')]
env = os.environ.copy()
env['MAKEFLAGS'] = f'CXX={CPP}'
start = time.monotonic()
with (OUT/'compile.log').open('w') as log:
    cp = subprocess.run(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT)
(OUT/'compile.exit').write_text(f'{cp.returncode}\n')
record = {'reviewer': 'verification agent', 'sources_sha256': frozen,
    'scope': 'public mixer interface; synchronous palette read-before-write model matching gaia_main, not complete CPU/ROM/renderer or physical timing',
    'original_copy_transformation': 'module identifier only',
    'original_copy_sha256': digest(original_copy), 'compile_command': cmd,
    'makeflags': env['MAKEFLAGS'], 'compile_exit': cp.returncode,
    'compile_log_sha256': digest(OUT/'compile.log'), 'cases': {}}
if cp.returncode == 0:
    for latency in (1, 2):
        path = OUT/f'latency{latency}.log'
        run_cmd = [str(OUT/'obj/Vtb_mixer_pipeline'), f'+LATENCY={latency}']
        with path.open('w') as log:
            run = subprocess.run(run_cmd, cwd=ROOT, env=env,
                stdout=log, stderr=subprocess.STDOUT, timeout=30)
        (OUT/f'latency{latency}.exit').write_text(f'{run.returncode}\n')
        body = path.read_text()
        summary = re.search(r'^SUMMARY (.*)$', body, re.M)
        record['cases'][f'latency{latency}'] = {
            'command': run_cmd, 'exit': run.returncode,
            'explicit_pass': bool(re.search(r'^PASS mixer pipeline', body, re.M)),
            'log_sha256': digest(path), 'summary': summary.group(1) if summary else None}
record['elapsed_seconds'] = round(time.monotonic()-start, 3)
record['sources_unchanged'] = all(digest(p) == frozen[str(p)] for p in inputs)
positive = record['cases'].get('latency1', {})
negative = record['cases'].get('latency2', {})
record['passed'] = (cp.returncode == 0 and positive.get('exit') == 0
    and positive.get('explicit_pass') and negative.get('exit', 0) != 0
    and not negative.get('explicit_pass') and record['sources_unchanged'])
record['negative_scope'] = 'extra palette read register violates current phase7 operand deadline; deliberately incompatible consumer, not original stable-pixel bug'
(ROOT/'evidence/mixer-pipeline.json').write_text(json.dumps(record, indent=2)+'\n')
print(json.dumps({'passed': record['passed'], 'cases': record['cases']}, indent=2))
raise SystemExit(0 if record['passed'] else 1)
