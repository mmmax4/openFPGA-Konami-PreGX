#!/usr/bin/env python3
"""Build reversible, private Violent Storm EAC canonical regions and M3 image.

Frozen MAME 0.289 declarations; no ROM/program/EEPROM patches. Refuse to
overwrite artifacts. Historical M2 builders and source pins are untouched.
"""
import argparse
import hashlib
import json
import re
import zipfile
import zlib
from pathlib import Path

DEV = Path(__file__).resolve().parents[1]
ROOT = DEV
MAME_COMMIT = 'f34f02505e32c1993c6a782b6814232cbfc74e36'
DRIVER_SHA256 = 'f6c1ba57e7522803c48b3437e51744ecae3183d4be725d7a7b93c20e2d49199a'
LAYOUT = {'ROM_LOAD': (1, 1, False), 'ROM_LOAD16_BYTE': (1, 2, False),
          'ROM_LOAD64_WORD': (2, 8, False), 'ROM_LOADTILE_WORD': (2, 5, True)}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def place(region, coverage, payload, offset, method):
    group, stride, reverse = LAYOUT[method]
    assert len(payload) % group == 0
    count = len(payload) // group
    assert offset + (count - 1) * stride + group <= len(region)
    for lane in range(group):
        selection = slice(offset + lane, offset + lane + count * stride, stride)
        assert not any(coverage[selection]), 'overlapping original ROM loads'
        region[selection] = payload[(group - lane - 1 if reverse else lane)::group]
        coverage[selection] = bytes([1]) * count
    # Inverse every placement immediately, including word reversal/byte lanes.
    recovered = bytearray(len(payload))
    for lane in range(group):
        source_lane = group - lane - 1 if reverse else lane
        recovered[source_lane::group] = region[offset + lane:offset + lane + count * stride:stride]
    assert recovered == payload, 'original ROM round trip failed'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom-zip', type=Path, default=ROOT/'roms/viostorm.zip')
    parser.add_argument('--driver', type=Path, default=ROOT/'ref/mame0289/mystwarr.cpp')
    parser.add_argument('--destination', type=Path, default=ROOT/'private/viostorm-m3')
    parser.add_argument('--evidence', type=Path, default=ROOT/'evidence/viostorm-memory-image.json')
    args = parser.parse_args()
    if args.destination.exists() or args.evidence.exists():
        raise SystemExit('Artifact/evidence exists; preserve it and choose a fresh path')
    source_bytes = args.driver.read_bytes()
    assert sha(source_bytes) == DRIVER_SHA256, 'frozen MAME driver changed'
    source = source_bytes.decode()
    assert '#define ROM_LOADTILE_WORD(name,offset,length,crc) ROMX_LOAD(name, offset, length, crc, ROM_GROUPWORD | ROM_SKIP(3) | ROM_REVERSE)' in source
    assert '"Violent Storm (ver EAC)"' in source
    body = re.search(r'ROM_START\(\s*viostorm\s*\)(.*?)ROM_END', source, re.S).group(1)
    regions, coverage, checks, parts = {}, {}, [], []
    current = previous = None
    archive_bytes = args.rom_zip.read_bytes()
    with zipfile.ZipFile(args.rom_zip) as archive:
        required = set()
        for raw in body.splitlines():
            line = raw.split('//', 1)[0].strip()
            if not line:
                continue
            match = re.fullmatch(r'ROM_REGION\(\s*(0x[\da-f]+)\s*,\s*"([^"]+)"\s*,\s*(0|ROMREGION_ERASE00)\s*\)', line)
            if match:
                length, current, flags = match.groups()
                assert current not in regions
                regions[current] = bytearray(int(length, 16))
                coverage[current] = bytearray(int(length, 16))
                previous = None
                continue
            match = re.fullmatch(r'(ROM_LOAD\w*)\(\s*"([^"]+)"\s*,\s*(0x[\da-f]+)\s*,\s*(0x[\da-f]+)\s*,\s*CRC\(([\da-f]+)\) SHA1\(([\da-f]+)\)\s*\)', line)
            if match:
                method, name, offset, length, crc, s1 = match.groups()
                assert method in LAYOUT and current is not None
                payload = archive.read(name)
                assert len(payload) == int(length, 16)
                assert f'{zlib.crc32(payload):08x}' == crc and hashlib.sha1(payload).hexdigest() == s1, name
                place(regions[current], coverage[current], payload, int(offset, 16), method)
                checks.append(dict(name=name, bytes=len(payload), crc32=crc, sha1=s1, sha256=sha(payload), status='pass', roundtrip=True))
                parts.append(dict(region=current, file=name, offset=int(offset, 16), method=method))
                required.add(name)
                previous = payload, method
                continue
            match = re.fullmatch(r'ROM_RELOAD\(\s*(0x[\da-f]+)\s*,\s*(0x[\da-f]+)\s*\)', line)
            if match and previous:
                offset, length = (int(v, 16) for v in match.groups())
                payload, method = previous
                assert len(payload) == length
                place(regions[current], coverage[current], payload, offset, method)
                parts.append(dict(region=current, offset=offset, method='ROM_RELOAD'))
                continue
            raise AssertionError(f'unparsed frozen declaration: {line}')
        assert set(archive.namelist()) == required, 'unexpected archive members'
    assert {k: len(v) for k, v in regions.items()} == dict(maincpu=0x200000, soundcpu=0x40000, k056832=0x600000, k055673=0x800000, gfx3=0x40000, k054539=0x400000, eeprom=0x80)
    assert all(not any(d for d, loaded in zip(data, coverage[name]) if not loaded) for name, data in regions.items()), 'nonzero unloaded padding'
    rawtile = regions['k056832']
    assert not any(rawtile[4:0x500000:5]) and not any(rawtile[0x500000:])
    tiles = bytearray(0x400000)
    for lane in range(4):
        tiles[lane::4] = rawtile[lane:0x500000:5]
    tile_inverse = bytearray(0x600000)
    for lane in range(4):
        tile_inverse[lane:0x500000:5] = tiles[lane::4]
    assert tile_inverse == rawtile, 'tile packing is not reversible'
    # RNG layout is already eight native plane bytes per16pixel row. No
    # sprite conversion, reordering, fifth plane or ROM content substitution.
    image = bytearray()
    segments = []
    for name, data, offset in [('maincpu', regions['maincpu'], 0),
                               ('soundcpu', regions['soundcpu'], 0x200000),
                               ('tile_rows4', tiles, 0x240000),
                               ('k054539', regions['k054539'], 0x640000),
                               ('sprite_rows8', regions['k055673'], 0xa40000),
                               ('eeprom', regions['eeprom'], 0x1240000)]:
        assert len(image) == offset
        image.extend(data)
        assert image[offset:offset + len(data)] == data
        segments.append(dict(name=name, offset=offset, bytes=len(data), sha256=sha(data)))
    assert len(image) == 0x1240080
    args.destination.mkdir(parents=True)
    region_records = {}
    for name, data in regions.items():
        path = args.destination/(name + '.bin')
        with path.open('xb') as handle:
            handle.write(data)
        assert sha(path.read_bytes()) == sha(data)
        region_records[name] = dict(path=str(path.resolve()), bytes=len(data), loaded_bytes=sum(coverage[name]), sha256=sha(data))
    image_path = args.destination/'viostorm.rom'
    with image_path.open('xb') as handle:
        handle.write(image)
    assert sha(image_path.read_bytes()) == sha(image)
    assert sha(args.rom_zip.read_bytes()) == sha(archive_bytes)
    record = dict(schema=1, reviewer='builder self-check', status='verified_original_image', set='viostorm', title='Violent Storm (ver EAC)',
                  mame_tag='mame0289', mame_commit=MAME_COMMIT, driver_sha256=DRIVER_SHA256, builder_sha256=sha(Path(__file__).read_bytes()),
                  source_zip_sha256=sha(archive_bytes), original_rom_audit=checks, original_rom_roundtrip=True, tile_packing_roundtrip=True,
                  unloaded_padding_zero=True, regions=region_records, parts=parts, segments=segments,
                  image_path=str(image_path.resolve()), image_bytes=len(image), image_sha256=sha(image),
                  prefix_crc32=f'{zlib.crc32(image[:256]):08x}', image_crc32=f'{zlib.crc32(image):08x}', last_byte_address=len(image)-1,
                  sdram_word_bases=dict(tile=0, pcm=0x200000, sprite=0x400000), omitted_erased_region='gfx3',
                  rom_program_graphics_eeprom_patched=False, hardware_verified=False, native_exit=0)
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    with args.evidence.open('x') as handle:
        handle.write(json.dumps(record, indent=2) + '\n')
    print(json.dumps({k: record[k] for k in ['image_path', 'image_bytes', 'image_sha256', 'prefix_crc32', 'image_crc32', 'last_byte_address']}))


if __name__ == '__main__':
    main()
