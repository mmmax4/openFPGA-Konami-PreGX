#!/usr/bin/env python3
"""Independent record-oriented verification of original Mystic ROM regions.

No import from build_mystic_regions/audit_roms and no writes to game artifacts.
Checks pre-endian-normalization ROM directive layout, not an FPGA loader image.
"""
import hashlib
import json
import re
import struct
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PIN = '76af2d6d907f0df822dca1d5146454cc5ee18294'
SOURCES = {
    'mystwarr.cpp': 'ece43729edea2dc86615fb96f19d0c3cc8fc93a8776fc38353e31a48235fec9a',
    'romload.cpp': '854873d6f1b33d1dd3614a219b4b744f8fefb11708c8389141157825599f275f',
    'romentry.h': '572a2d095ee86abafcc30e4df876e76d5a03d56d2add9d4b80dfb31835580a08',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pairs(even, odd):
    assert len(even) == len(odd)
    return b''.join(bytes((a, b)) for a, b in zip(even, odd))


def tiles(a, b, fifth):
    assert len(a) == len(b) == 2 * len(fifth)
    return b''.join(bytes((a1, a0, b1, b0, f))
                    for (a0, a1), (b0, b1), f in
                    zip(struct.iter_unpack('BB', a), struct.iter_unpack('BB', b), fifth))


def sprites(a, b, c, d):
    assert len(a) == len(b) == len(c) == len(d)
    return b''.join(a0 + b0 + c0 + d0 for (a0,), (b0,), (c0,), (d0,) in
                    zip(*(struct.iter_unpack('2s', data) for data in (a, b, c, d))))


def records_split(data, record_size, field_indices):
    """Transpose complete records, then reconstruct member order explicitly."""
    result = bytearray()
    for record in struct.iter_unpack(f'{record_size}B', data):
        result.extend(record[i] for i in field_indices)
    return bytes(result)


def expected_regions(payload):
    main = pairs(payload['128eaa01.20f'], payload['128eaa02.20g'])
    main += bytes(0x80000) + pairs(payload['128a03.19f'], payload['128a04.19g'])
    tile = tiles(payload['128a08.1h'], payload['128a09.1k'], payload['128a10.3h'])
    sprite = sprites(*(payload[name] for name in ('128a16.22k', '128a15.20k', '128a14.19k', '128a13.17k')))
    sprite += pairs(payload['128a12.12k'], payload['128a11.10k'])
    return {'maincpu': main, 'soundcpu': payload['128a05.6b'] * 2,
            'k056832': tile + bytes(0x280000), 'k055673': sprite,
            'gfx3': bytes(0x40000), 'k054539': payload['128a06.2d'] + payload['128a07.1d'],
            'eeprom': payload['mystwarr.nv']}


def roundtrip(region):
    out = {}
    out['128eaa01.20f'] = records_split(region['maincpu'][:0x80000], 2, (0,))
    out['128eaa02.20g'] = records_split(region['maincpu'][:0x80000], 2, (1,))
    out['128a03.19f'] = records_split(region['maincpu'][0x100000:], 2, (0,))
    out['128a04.19g'] = records_split(region['maincpu'][0x100000:], 2, (1,))
    out['128a05.6b'] = region['soundcpu'][:0x20000]
    for name, fields in (('128a08.1h', (1, 0)), ('128a09.1k', (3, 2)), ('128a10.3h', (4,))):
        out[name] = records_split(region['k056832'][:0x280000], 5, fields)
    for name, fields in zip(('128a16.22k', '128a15.20k', '128a14.19k', '128a13.17k'),
                            ((0, 1), (2, 3), (4, 5), (6, 7))):
        out[name] = records_split(region['k055673'][:0x400000], 8, fields)
    out['128a12.12k'] = records_split(region['k055673'][0x400000:], 2, (0,))
    out['128a11.10k'] = records_split(region['k055673'][0x400000:], 2, (1,))
    out['128a06.2d'] = region['k054539'][:0x200000]
    out['128a07.1d'] = region['k054539'][0x200000:]
    out['mystwarr.nv'] = region['eeprom']
    return out


def main():
    source_hashes = {name: digest((ROOT / 'ref/mame' / name).read_bytes()) for name in SOURCES}
    assert source_hashes == SOURCES, 'pinned reference changed'
    source = (ROOT / 'ref/mame/mystwarr.cpp').read_text()
    body = source.split('ROM_START( mystwarr )', 1)[1].split('ROM_END', 1)[0]
    declarations = re.findall(r'ROM_LOAD\w*\(\s*"([^"]+)"\s*,\s*0x[\da-fA-F]+\s*,\s*(0x[\da-fA-F]+)\s*,\s*CRC\(([\da-f]{8})\)\s*SHA1\(([\da-f]{40})\)', body)
    assert len(declarations) == 17
    archive_path = ROOT / 'roms/mystwarr.zip'
    with zipfile.ZipFile(archive_path) as archive:
        assert set(archive.namelist()) == {name for name, *_ in declarations}
        payload = {name: archive.read(name) for name, *_ in declarations}
    source_audit = {}
    for name, size, crc, sha1 in declarations:
        raw = payload[name]
        source_audit[name] = len(raw) == int(size, 16) and f'{zlib.crc32(raw) & 0xffffffff:08x}' == crc and hashlib.sha1(raw).hexdigest() == sha1
    assert all(source_audit.values()), 'original ZIP changed'

    literals = {
        'cpu_byte_lane': pairs(bytes.fromhex('10 20'), bytes.fromhex('11 21')) == bytes.fromhex('10 11 20 21'),
        'tile_word_reverse_and_plane5': tiles(bytes.fromhex('10 20 30 40'), bytes.fromhex('50 60 70 80'), bytes.fromhex('90 a0')) == bytes.fromhex('20 10 60 50 90 40 30 80 70 a0'),
        'sprite_group2_skip6_no_reverse': sprites(bytes.fromhex('01 02 03 04'), bytes.fromhex('05 06 07 08'), bytes.fromhex('09 0a 0b 0c'), bytes.fromhex('0d 0e 0f 10')) == bytes.fromhex('01 02 05 06 09 0a 0d 0e 03 04 07 08 0b 0c 0f 10'),
        'record_inverse_literal': records_split(bytes.fromhex('20 10 60 50 90 40 30 80 70 a0'), 5, (1, 0)) == bytes.fromhex('10 20 30 40'),
    }
    assert all(literals.values())
    expected = expected_regions(payload)
    actual = {name: (ROOT / 'private/mystwarr-regions' / f'{name}.bin').read_bytes() for name in expected}
    before = {name: digest(raw) for name, raw in actual.items()}
    manifest_path = ROOT / 'evidence/mystwarr-regions.json'
    manifest = json.loads(manifest_path.read_text())
    manifest_checks = {name: len(raw) == manifest['regions'][name]['bytes'] and digest(raw) == manifest['regions'][name]['sha256'] for name, raw in actual.items()}
    region_checks = {name: actual[name] == expected[name] for name in expected}
    reconstructed = roundtrip(actual)
    member_checks = {name: reconstructed[name] == payload[name] for name in payload}
    reload_ok = actual['soundcpu'][0x20000:] == payload['128a05.6b']
    eof_checks = {name: actual[name][-16:] == raw[-16:] for name, raw in expected.items()}
    negative = {}
    # Known-wrong transformations exist only in RAM, never overwrite artifacts.
    def reject(label, region, mutated):
        negative[label] = bytes(mutated) != expected[region]
    mutated = bytearray(actual['k056832']);mutated[4:0x280000:5] = bytes(0x80000)
    reject('tile_fifth_plane_omitted', 'k056832', mutated)
    mutated = bytearray(actual['k055673']);mutated[0x400000:] = bytes(0x100000)
    reject('sprite_fifth_plane_omitted', 'k055673', mutated)
    mutated = bytearray(actual['k056832'])
    for at in range(0, 0x280000, 5):
        mutated[at], mutated[at+1] = mutated[at+1], mutated[at]
        mutated[at+2], mutated[at+3] = mutated[at+3], mutated[at+2]
    reject('tile_groupword_reverse_missing', 'k056832', mutated)
    mutated = bytearray(actual['soundcpu']);mutated[0x20000:] = bytes(0x20000)
    reject('sound_reload_missing', 'soundcpu', mutated)
    mutated = bytearray(actual['maincpu']);mutated[0x80000:0x100000] = bytes([255]) * 0x80000
    reject('main_hole_filled_ff', 'maincpu', mutated)
    mutated = bytearray(actual['k056832']);mutated[0x280000:] = bytes([255]) * 0x280000
    reject('tile_erased_tail_filled_ff', 'k056832', mutated)
    mutated = bytearray(actual['k055673'])
    # Leading graphic words may be equal bytes. Select a demonstrably distinct
    # original word so swapping is a real negative fixture, not a no-op.
    at = next(i for i in range(0, 0x400000, 2) if mutated[i] != mutated[i+1])
    mutated[at],mutated[at+1] = mutated[at+1],mutated[at]
    reject('sprite_groupword_wrong_reverse', 'k055673', mutated)
    # Region mutation controls must be detectable by the exact independent
    # expected-region comparator; originals are still byte-identical afterward.
    unchanged = all(digest((ROOT / 'private/mystwarr-regions' / f'{name}.bin').read_bytes()) == value for name, value in before.items())
    checks = {'original_zip_crc_sha1': all(source_audit.values()), 'literal_vectors': all(literals.values()),
              'whole_regions_match': all(region_checks.values()), 'all_17_members_roundtrip': all(member_checks.values()),
              'sound_rom_reload': reload_ok, 'all_region_eof_bytes': all(eof_checks.values()),
              'manifest_hashes_sizes': all(manifest_checks.values()), 'all_negative_controls_rejected': all(negative.values()),
              'private_artifacts_unchanged': unchanged}
    report = {'passed': all(checks.values()), 'reviewer': 'research agent', 'set': 'mystwarr', 'mame_commit': PIN,
              'scope': 'Full-byte independent record-oriented assembly and reverse extraction of all 17 original ZIP members; ROM directive byte order before device/native endian normalization and graphics decoding. No MAME executable, FPGA loader, RTL, fit or Pocket verification.',
              'sources_sha256': source_hashes, 'builder_sha256': digest((ROOT / 'scripts/build_mystic_regions.py').read_bytes()),
              'reviewer_script_sha256': digest(Path(__file__).read_bytes()), 'builder_manifest_sha256': digest(manifest_path.read_bytes()),
              'zip_sha256': digest(archive_path.read_bytes()), 'checks': checks, 'regions_sha256': before,
              'original_member_roundtrip': member_checks, 'literal_vectors': literals, 'negative_controls': negative,
              'fpga_loader_compatible': False, 'hardware_verified': False}
    (ROOT / 'evidence/mystwarr-regions-review.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'passed': report['passed'], 'checks': checks, 'negative_controls': negative}, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
