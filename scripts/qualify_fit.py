#!/usr/bin/env python3
"""Fail closed on missing/negative corner timing; record the fitted artifact."""
import hashlib
import json
from pathlib import Path
from timing_summary import check, REQUIRED

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / 'projects/output_files'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

manifest_path = ROOT / 'build/verification/quartus-compile-inputs.json'
manifest = json.loads(manifest_path.read_text())
if manifest['status'] != 'passed' or manifest.get('build_mode') != 'compile':
    raise SystemExit('a successful source-frozen full compile is required; map/STA cannot qualify an RBF')
for name in ('gaia_pocket.rbf', 'gaia_pocket.fit.rpt', 'gaia_pocket.sta.rpt', 'gaia_pocket.sta.summary'):
    if sha(DIR / name) != manifest.get('artifacts_after', {}).get(f'projects/output_files/{name}'):
        raise SystemExit(f'artifact does not belong to recorded full compile: {name}')
for name, digest in manifest['inputs'].items():
    if sha(ROOT / name) != digest:
        raise SystemExit(f'current source differs from fitted source: {name}')

records, corners = check(DIR / 'gaia_pocket.sta.summary')

# A positive summary is only one gate. Review all warnings and exceptions
# explicitly before using the package builder.
output = {'status': 'timing_summary_pass', 'reviewer': 'lead',
          'constraints_warning_review': 'pending', 'corners': sorted(corners),
          'minimum_slack_ns': {k: min(r['slack_ns'] for r in records if f'Model {k} ' in r['type']) for k in REQUIRED},
          'records': records, 'fit_summary': (DIR / 'gaia_pocket.fit.summary').read_text(),
          'artifacts': {p.name: sha(p) for p in sorted(DIR.glob('gaia_pocket.*')) if p.suffix in ('.rbf', '.sof', '.summary', '.rpt')},
          'source_manifest_sha256': sha(manifest_path)}
path = ROOT / 'evidence/gaiapolis-fit.json'
path.write_text(json.dumps(output, indent=2) + '\n')
print(json.dumps({k: output[k] for k in ('status', 'corners', 'minimum_slack_ns')}, indent=2))
