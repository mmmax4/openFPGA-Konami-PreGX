#!/usr/bin/env python3
"""Compare two per-layer palette-index dumps (4 x 224 x 376 uint16).

Used to gate the tilemap RTL against tools/render_model.py, which is itself
pixel-exact against MAME. 0xffff means transparent.

Usage: diff_layers.py <a.layers> <b.layers>
"""
import sys, struct

VIS_W, VIS_H = 376, 224
N = VIS_W * VIS_H


def load(path):
    d = open(path, 'rb').read()
    want = 4 * N * 2
    if len(d) != want:
        sys.exit(f'{path}: {len(d)} bytes, expected {want}')
    return struct.unpack('<%dH' % (4 * N), d)


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    total = 0
    for l in range(4):
        bad = [i for i in range(N) if a[l * N + i] != b[l * N + i]]
        total += len(bad)
        if bad:
            i = bad[0]
            print(f'  layer {"ABCD"[l]}: {len(bad):6d} differing, first at '
                  f'x={i % VIS_W} y={i // VIS_W} '
                  f'rtl={a[l*N+i]:#06x} model={b[l*N+i]:#06x}')
        else:
            drawn = sum(1 for i in range(N) if b[l * N + i] != 0xffff)
            print(f'  layer {"ABCD"[l]}: match (coverage {100.0*drawn/N:.1f}%)')
    print(f'total differing: {total}')
    sys.exit(1 if total else 0)


if __name__ == '__main__':
    main()
