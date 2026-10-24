#!/usr/bin/env python3
"""Compare two VIS_H x VIS_W uint32 RGB frames.

Used to gate the sprite RTL against the reference renderer's sprite-only
composite.

The backdrop colour is passed in rather than guessed: on a busy frame neither
the corner pixel nor the most common colour is the backdrop.

Usage: diff_rgb.py <a.rgb> <b.rgb> [backdrop_hex]
"""
import sys, struct

VIS_W, VIS_H = 376, 224
N = VIS_W * VIS_H


def load(path):
    d = open(path, 'rb').read()
    if len(d) != N * 4:
        sys.exit(f'{path}: {len(d)} bytes, expected {N*4}')
    return struct.unpack('<%dI' % N, d)


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    bad = [i for i in range(N) if a[i] != b[i]]
    backdrop = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0
    drawn = sum(1 for v in b if v != backdrop)
    if bad:
        i = bad[0]
        print(f'  {len(bad)} differing of {N}, first at x={i % VIS_W} y={i // VIS_W} '
              f'rtl={a[i]:#08x} model={b[i]:#08x}')
        sys.exit(1)
    print(f'  match (coverage {100.0*drawn/N:.1f}%)')


if __name__ == '__main__':
    main()
