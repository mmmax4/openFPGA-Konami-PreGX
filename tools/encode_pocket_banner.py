#!/usr/bin/env python3
"""Encode an existing521x165 PNG as Pocket native grayscale; no artwork edits."""
import argparse
import hashlib
import json
from pathlib import Path
from pngio import read, write


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('source', type=Path)
    ap.add_argument('output', type=Path)
    ap.add_argument('--preview', type=Path)
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    width, height, rgb = read(args.source)
    if (width, height) != (521, 165):
        raise SystemExit('Pocket banner must be521x165; normalize the source first')
    for path in (args.output, args.preview, args.report):
        if path is not None and path.exists():
            raise SystemExit('Refusing to overwrite '+str(path))
    gray = bytes((299*rgb[i]+587*rgb[i+1]+114*rgb[i+2]+500)//1000
                 for i in range(0, len(rgb), 3))
    native = bytearray(width*height*2)
    for y in range(height):
        for x in range(width):
            native[2*((width-1-x)*height+y)] = 255-gray[y*width+x]
    decoded = bytes(255-native[2*((width-1-x)*height+y)]
                    for y in range(height) for x in range(width))
    assert decoded == gray and len(native) == 171930 and not any(native[1::2])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('xb') as output:
        output.write(native)
    if args.preview:
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        write(args.preview, width, height, bytes(v for value in decoded for v in (value,)*3))
    record = {'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
              'native_sha256': hashlib.sha256(native).hexdigest(),
              'size': [width, height], 'native_bytes': len(native),
              'roundtrip_pixels': width*height, 'all_padding_bytes_zero': True,
              'format': 'Inverted grayscale brightness/zero pairs,90degreesCCW storage',
              'artwork_edit_by_encoder': False}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record))


if __name__ == '__main__':
    main()
