#!/usr/bin/env python3
"""Fetch pinned source dependencies only; never download ROMs or saves."""
from pathlib import Path
import hashlib, json, urllib.request
ROOT = Path(__file__).resolve().parents[1]
for entry in json.loads((ROOT/'config/dependencies.json').read_text()):
    target = ROOT/entry['path']
    assert ROOT in target.resolve().parents
    if target.exists():
        if hashlib.sha256(target.read_bytes()).hexdigest() != entry['sha256']:
            raise SystemExit('Existing dependency changed: '+entry['path'])
        print('Verified '+entry['path']); continue
    with urllib.request.urlopen(entry['url'], timeout=30) as response:
        data = response.read(2_000_001)
    if len(data)>2_000_000 or hashlib.sha256(data).hexdigest()!=entry['sha256']:
        raise SystemExit('Dependency size/hash mismatch: '+entry['path'])
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('xb') as output: output.write(data)
    print('Fetched '+entry['path'])
