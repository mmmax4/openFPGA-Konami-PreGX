#!/usr/bin/env python3
"""Compare the ROZ RTL output against the reference renderer.

Both files are VIS_H x VIS_W uint16 palette indices, 0xffff transparent.

The comparison is offset by one line on purpose. MAME's
K053936GP_copyroz32clip advances its destination row before the loop body, so
it paints raster row N with the transform for row N-1 and never writes the
first visible row; the reference renderer reproduces that so it can be gated
against MAME. The RTL does not, because it reads as a porting artefact rather
than silicon behaviour (docs/hardware.md section 10). So RTL row N is checked
against model row N+1, and the model's blank first row is skipped.

Usage: diff_roz.py <rtl.roz> <model.roz>
"""
import sys, struct

VIS_W, VIS_H = 376, 224
N = VIS_W * VIS_H


def load(path):
    d = open(path, 'rb').read()
    if len(d) != N * 2:
        sys.exit(f'{path}: {len(d)} bytes, expected {N*2}')
    return struct.unpack('<%dH' % N, d)


def main():
    rtl, model = load(sys.argv[1]), load(sys.argv[2])
    bad = []
    for y in range(VIS_H - 1):
        for x in range(VIS_W):
            a = rtl[y * VIS_W + x]
            b = model[(y + 1) * VIS_W + x]
            if a != b:
                bad.append((x, y, a, b))
    drawn = sum(1 for v in model if v != 0xffff)
    cmp_px = (VIS_H - 1) * VIS_W
    if bad:
        x, y, a, b = bad[0]
        print(f'  {len(bad)} differing of {cmp_px}, first at x={x} y={y} '
              f'rtl={a:#06x} model={b:#06x}')
        sys.exit(1)
    print(f'  match ({cmp_px} pixels compared, coverage {100.0*drawn/N:.1f}%)')


if __name__ == '__main__':
    main()
