#!/usr/bin/env python3
"""Prepare a local ROM/save-free SD folder; never upload or overwrite one."""
from pathlib import Path
import argparse, json, shutil
ROOT = Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--rbf', type=Path, required=True)
ap.add_argument('--output', type=Path, default=ROOT/'private/pocket-local')
a = ap.parse_args()
raw = a.rbf.read_bytes()
if not raw: raise SystemExit('Empty raw bitstream')
names = json.loads((ROOT/'config/package-files.json').read_text())
assert len(names)==len(set(names))
for name in names:
    p=Path(name)
    assert not p.is_absolute() and '..' not in p.parts
    assert p.suffix.lower() in ('.json','.txt','.bin')
    assert (ROOT/'pkg/pocket'/p).is_file()
a.output.mkdir(parents=True, exist_ok=False)
for name in names:
    dst=a.output/name;dst.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(ROOT/'pkg/pocket'/name,dst)
reverse=bytes(int(f'{n:08b}'[::-1],2) for n in range(256))
(a.output/'Cores/mmmax4.pregx/bitstream.rbf_r').write_bytes(raw.translate(reverse))
print(a.output)
