#!/usr/bin/env python3
"""Preserve original Mystic ROMs in canonical MAME regions for the new profile.

This is not a ROM image accepted by the Gaiapolis-only baseline loader.
No game patches, graphics conversions or missing-plane substitutions.
"""
import hashlib
import json
import re
import zipfile
from pathlib import Path
from audit_roms import MAME_COMMIT, SOURCE_HASHES, audit_zip, declarations

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = {
    'ROM_LOAD': (1, 1, False),
    'ROM_LOAD16_BYTE': (1, 2, False),
    'ROM_LOAD64_WORD': (2, 8, False),
    # Definitions immediately preceding ROM_START in the pinned driver:
    # GROUPWORD | SKIP(3) | REVERSE and GROUPBYTE | SKIP(4).
    'ROM_LOADTILE_WORD': (2, 5, True),
    'ROM_LOADTILE_BYTE': (1, 5, False),
}

def place(region, coverage, payload, offset, method):
    if method not in LAYOUT:
        raise ValueError(f'unsupported ROM directive: {method}')
    group, stride, reverse = LAYOUT[method]
    if len(payload) % group:
        raise ValueError('partial word in original ROM')
    count = len(payload) // group
    if count and offset + (count - 1) * stride + group > len(region):
        raise ValueError('ROM placement exceeds declared region')
    for lane in range(group):
        begin = offset + lane
        end = begin + count * stride
        if any(coverage[begin:end:stride]):
            raise ValueError('overlapping ROM declarations')
        source_lane = group - lane - 1 if reverse else lane
        region[begin:end:stride] = payload[source_lane::group]
        coverage[begin:end:stride] = bytes([1]) * count

def main():
    driver = ROOT / 'ref/mame/mystwarr.cpp'
    source_bytes = driver.read_bytes()
    if hashlib.sha256(source_bytes).hexdigest() != SOURCE_HASHES['mystwarr.cpp']:
        raise SystemExit('pinned MAME driver changed')
    source = source_bytes.decode()
    title, rotation, declared_regions, entries = declarations(source, 'mystwarr')
    archive_path = ROOT / 'roms/mystwarr.zip'
    checks, extra = audit_zip(archive_path, entries)
    if extra or any(c['status'] != 'pass' for c in checks):
        raise SystemExit('Mystic original ZIP failed size/CRC32/SHA1 audit')
    destination = ROOT / 'private/mystwarr-regions'
    if destination.exists():
        raise SystemExit('region artifact already exists; do not overwrite')
    body = re.search(r'ROM_START\(\s*mystwarr\s*\)(.*?)ROM_END', source, re.S).group(1)
    regions = {r['name']: bytearray(r['bytes']) for r in declared_regions}
    coverage = {name: bytearray(len(data)) for name, data in regions.items()}
    current = None
    previous = None
    parts = []
    with zipfile.ZipFile(archive_path) as archive:
        for raw in body.splitlines():
            line = raw.split('//', 1)[0].strip()
            if not line:
                continue
            match = re.match(r'ROM_REGION\(\s*0x[0-9a-fA-F]+\s*,\s*"([^"]+)"\s*,\s*(0|ROMREGION_ERASE00)\s*\)', line)
            if match:
                current = match.group(1)
                previous = None
                continue
            match = re.match(r'(ROM_LOAD\w*)\(\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)', line)
            if match:
                method, name, offset, length = match.groups()
                payload = archive.read(name)
                if len(payload) != int(length, 16):
                    raise SystemExit(f'original length changed: {name}')
                offset = int(offset, 16)
                place(regions[current], coverage[current], payload, offset, method)
                previous = (payload, method)
                parts.append({'region': current, 'file': name, 'method': method, 'offset': offset,
                              'sha256': hashlib.sha256(payload).hexdigest()})
                continue
            match = re.match(r'ROM_RELOAD\(\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*\)', line)
            if match and previous:
                offset, length = (int(v, 16) for v in match.groups())
                payload, method = previous
                if length != len(payload):
                    raise SystemExit('unsupported partial ROM reload')
                place(regions[current], coverage[current], payload, offset, method)
                parts.append({'region': current, 'method': 'ROM_RELOAD', 'offset': offset,
                              'sha256': hashlib.sha256(payload).hexdigest()})
                continue
            raise SystemExit(f'unparsed directive: {line}')
    destination.mkdir(parents=True)
    outputs = {}
    for name, data in regions.items():
        path = destination / f'{name}.bin'
        path.write_bytes(data)
        outputs[name] = {'path': str(path.relative_to(ROOT)), 'bytes': len(data),
                         'loaded_bytes': sum(coverage[name]),
                         'sha256': hashlib.sha256(data).hexdigest()}
    record = {'status': 'original_regions_built', 'set': 'mystwarr', 'title': title,
        'mame_commit': MAME_COMMIT, 'driver_sha256': SOURCE_HASHES['mystwarr.cpp'],
        'zip_sha256': hashlib.sha256(archive_path.read_bytes()).hexdigest(),
        'rotation': rotation, 'unloaded_byte_fill': 0, 'parts': parts, 'regions': outputs,
        'fpga_loader_compatible': False, 'hardware_verified': False}
    (ROOT / 'evidence/mystwarr-regions.json').write_text(json.dumps(record, indent=2) + '\n')
    print(f'{title}: {len(outputs)} canonical regions; FPGA layout not yet implemented')

if __name__ == '__main__':
    main()
