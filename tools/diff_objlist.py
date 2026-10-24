#!/usr/bin/env python3
"""Compare the RTL object list against the reference renderer's.

The RTL file is a count followed by that many 32-bit order words; the model
file is a count followed by 12-byte records whose first field is the order.
Only the order words are compared -- everything else (code, colour, geometry)
is re-read from sprite RAM by the rasterizer.

Usage: diff_objlist.py <rtl.obj> <model.obj>
"""
import sys, struct


def load_rtl(path):
    d = open(path, 'rb').read()
    n = struct.unpack('<I', d[:4])[0]
    return list(struct.unpack('<%dI' % n, d[4:4 + n * 4]))


def load_model(path):
    d = open(path, 'rb').read()
    n = struct.unpack('<I', d[:4])[0]
    return [struct.unpack('<IHHHBB', d[4 + i * 12:16 + i * 12])[0] for i in range(n)]


def main():
    a, b = load_rtl(sys.argv[1]), load_model(sys.argv[2])
    if len(a) != len(b):
        print(f'  count differs: rtl {len(a)}, model {len(b)}')
        sys.exit(1)
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            print(f'  order differs at {i}: rtl {x:#010x} model {y:#010x}')
            ctx = [f'{j}:{a[j]:08x}/{b[j]:08x}' for j in range(max(0, i - 2), min(len(a), i + 3))]
            print('   ' + '  '.join(ctx))
            sys.exit(1)
    print(f'  match ({len(a)} objects)')


if __name__ == '__main__':
    main()
