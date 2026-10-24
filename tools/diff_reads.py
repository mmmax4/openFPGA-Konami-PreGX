#!/usr/bin/env python3
"""Diff the 68000's device-window reads between MAME and the RTL.

Both logs are the ordered sequence of reads the self-test makes ("frame addr
data ..."); the code is deterministic and interrupts are masked, so the two
sequences should line up one for one. Reports the first mismatches.

The two machines pace differently, so the logs are aligned on the first read
of an anchor address (default 400000, the start of the sprite-window test)
rather than by frame.

Usage: diff_reads.py <mame_reads.txt> <rtl_reads.txt> [anchor_hex]
"""
import sys

def load(path, lo, hi):
    out = []
    for l in open(path):
        p = l.split()
        if len(p) < 3: continue
        f = int(p[0])
        if lo <= f <= hi: out.append((f, int(p[1], 16), int(p[2], 16)))
    return out

anchor = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x400000
a = load(sys.argv[1], 0, 10**9); b = load(sys.argv[2], 0, 10**9)
def anchor_at(seq):
    for i, (f, ad, d) in enumerate(seq):
        if ad == anchor: return i
    return None
ia, ib = anchor_at(a), anchor_at(b)
if ia is None or ib is None:
    sys.exit(f'anchor {anchor:06x} not found (mame {ia}, rtl {ib})')
print(f'mame: {len(a)} reads (anchor at #{ia}, frame {a[ia][0]}); rtl: {len(b)} reads (anchor at #{ib}, frame {b[ib][0]})')
a = a[ia:]; b = b[ib:]
n = min(len(a), len(b)); bad = 0; shown = 0
for i in range(n):
    fa, aa, da = a[i]; fb, ab, db = b[i]
    if aa != ab:
        print(f'  sequence diverges at read #{i}: mame f{fa} {aa:06x}={da:04x}  rtl f{fb} {ab:06x}={db:04x}')
        break
    if da != db:
        bad += 1
        if shown < 12:
            print(f'  #{i} f{fa} addr {aa:06x}: mame {da:04x} rtl {db:04x}'); shown += 1
print(f'{bad} value mismatches over {n} aligned reads')
