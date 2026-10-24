#!/usr/bin/env python3
"""Reversible Mystic Warriors memory image for the M2 loader, private only.

Tile records retain original five-byte rows. Sprite records contain the eight
original four-plane bytes followed by the two original fifth-plane bytes.
No program, EEPROM, graphics or sample bytes are patched.
"""
import argparse
import hashlib
import json
from pathlib import Path

from audit_roms import MAME_COMMIT, SOURCE_HASHES

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--regions', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--source-manifest', type=Path, required=True)
    ap.add_argument('--rom-zip', type=Path, required=True)
    ap.add_argument('--driver', type=Path, default=ROOT/'ref/mame/mystwarr.cpp')
    ap.add_argument('--evidence', type=Path, default=ROOT/'evidence/m2-memory-image.json')
    args = ap.parse_args()
    if args.output.exists() or args.evidence.exists():
        raise SystemExit('Output/evidence exists; retain it and use a fresh artifact')
    source_bytes = args.source_manifest.read_bytes()
    source = json.loads(source_bytes)
    assert source['status'] == 'original_regions_built' and source['set'] == 'mystwarr'
    assert source['mame_commit'] == MAME_COMMIT
    driver = args.driver
    assert sha(driver.read_bytes()) == source['driver_sha256'] == SOURCE_HASHES['mystwarr.cpp']
    assert sha(args.rom_zip.read_bytes()) == source['zip_sha256']
    lengths = {'maincpu':0x200000, 'soundcpu':0x40000, 'k056832':0x500000,
               'k055673':0x500000, 'k054539':0x400000, 'gfx3':0x40000, 'eeprom':128}
    regions = {}
    for name, length in lengths.items():
        data = (args.regions/(name+'.bin')).read_bytes()
        assert len(data) == length == source['regions'][name]['bytes']
        assert sha(data) == source['regions'][name]['sha256'], name
        regions[name] = data
    # Both omitted parts are explicitly ERASE00 in the pinned original source.
    assert not any(regions['k056832'][0x280000:])
    assert not any(regions['gfx3'])
    rows = bytearray(0x500000)
    raw = regions['k055673']
    for lane in range(8):
        rows[lane::10] = raw[lane:0x400000:8]
    rows[8::10] = raw[0x400000::2]
    rows[9::10] = raw[0x400001::2]
    image = bytearray()
    segments = []
    for name, data, offset in [
        ('maincpu',regions['maincpu'],0), ('soundcpu',regions['soundcpu'],0x200000),
        ('tile_rows5',regions['k056832'][:0x280000],0x240000),
        ('k054539',regions['k054539'],0x4c0000), ('sprite_rows10',rows,0x8c0000),
        ('eeprom',regions['eeprom'],0xdc0000)]:
        assert len(image) == offset
        image.extend(data)
        segments.append({'name':name,'offset':offset,'bytes':len(data),'sha256':sha(data)})
    assert len(image) == 0xdc0080
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('xb') as handle:
        handle.write(image)
    record = {'schema':1,'reviewer':'lead','status':'built_for_m2_memory_component',
              'set':'mystwarr','title':source['title'],'mame_commit':MAME_COMMIT,
              'driver_sha256':sha(driver.read_bytes()), 'source_manifest_sha256':sha(source_bytes),
              'source_zip_sha256':source['zip_sha256'],
              'source_regions_sha256':{n:sha(d) for n,d in regions.items()},
              'image_path':str(args.output.resolve()),'image_bytes':len(image),
              'image_sha256':sha(image),'segments':segments,
              'sdram_word_bases':{'tile':0,'pcm':0x140000,'sprite':0x340000},
              'omitted_erased_regions':{'tile_tail':[0x280000,0x500000],'gfx3':[0,0x40000]},
              'hardware_verified':False,'game_playable':False,
              'builder_sha256':sha(Path(__file__).read_bytes())}
    args.evidence.parent.mkdir(parents=True,exist_ok=True)
    args.evidence.write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps({'image':str(args.output),'bytes':len(image),'sha256':sha(image)}))


if __name__ == '__main__':
    main()
