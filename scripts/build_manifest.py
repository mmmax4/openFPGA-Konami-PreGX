#!/usr/bin/env python3
"""Record actual build inputs, exit status, and prohibit changed active inputs."""
from pathlib import Path
import hashlib
import json
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/verification/quartus-inputs.json'

def inputs():
    paths = []
    for directory in ('rtl', 'modules', 'target', 'platform', 'projects'):
        for p in (ROOT / directory).rglob('*'):
            if not p.is_file() or any(d in p.parts for d in ('db', 'incremental_db', 'output_files')):
                continue
            if p.suffix not in ('.sv', '.v', '.vhd', '.hex', '.mif', '.qip', '.qsf', '.qpf', '.sdc', '.tcl'):
                continue
            if p.name in ('build_id.mif', 'build_id.vh'):
                continue  # framework writes these during pre-flow
            paths.append(p)
    paths.extend(ROOT / name for name in ('scripts/build.sh', 'scripts/build_manifest.py',
                                         'scripts/report_sdram_timing.tcl', 'scripts/run_fit_gate.py',
                                         'scripts/read_sdram_fit.py', 'scripts/qualify_fit.py',
                                         'scripts/timing_summary.py'))
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}

now = datetime.now(timezone.utc).isoformat()
if sys.argv[1] == 'begin':
    mode = sys.argv[2]
    if mode not in ('compile', 'map', 'sta', 'audit-sdram'):
        raise SystemExit('unknown Quartus stage')
    data = {'started_utc': now, 'build_mode': mode,
            'command': ['bash', 'scripts/build.sh', mode],
            'inputs': inputs(), 'status': 'running'}
elif sys.argv[1] == 'end':
    data = json.loads(OUT.read_text())
    data.update(finished_utc=now, exit_code=int(sys.argv[2]), inputs_unchanged=inputs() == data['inputs'])
    data['generated_inputs_after'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in (ROOT / 'target').rglob('build_id.*') if p.is_file()}
    data['artifacts_after'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((ROOT / 'projects/output_files').glob('gaia_pocket.*'))
        if p.suffix in ('.rbf', '.sof', '.summary', '.rpt')}
    if data['build_mode'] == 'audit-sdram':
        data['review_outputs_after'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted((ROOT / 'build/verification/sdram-timing').glob('*')) if p.is_file()}
    data['status'] = 'passed' if data['exit_code'] == 0 and data['inputs_unchanged'] else 'failed'
else:
    raise SystemExit('usage: build_manifest.py begin MODE | end EXIT_CODE')
OUT.write_text(json.dumps(data, indent=2) + '\n')
if sys.argv[1] == 'end':
    (OUT.parent / f"quartus-{data['build_mode']}-inputs.json").write_text(
        json.dumps(data, indent=2) + '\n')
if data['status'] == 'failed':
    raise SystemExit(1)
