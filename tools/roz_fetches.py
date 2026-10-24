#!/usr/bin/env python3
"""What a line of the ROZ plane costs the core's renderer, per frozen state,
under its tile cache: a 16x16 tile is one 64-word burst into a 128-entry
fully associative cache with round-robin replacement, a hit is free and a
miss costs the burst plus the tile's three map reads; three clocks a pixel.
Reports the average and worst line, and the lead (lines rendered ahead of
the display) the scene needs so that no line is late, at the line budget and
at a contended one.
    tools/roz_fetches.py <state.txt> [...] [--sweep]
--sweep also rotates each state's transform through 0..345 degrees (the
character-select water turns) and reports the worst angle."""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
import render_model as rm

ENTRIES, MISS, BASE, BUDGET, CONTENDED = 128, 182, 3, 6144, 4500

def walk(startx, starty, xx, xy, yx, yy):
    """per line, the (tile column, tile row) sequence, consecutive repeats removed"""
    lines = []
    for y in range(rm.VIS_H):
        cx = (startx + y * yx) & 0xffffffff; cy = (starty + y * yy) & 0xffffffff
        ev = []; last = None
        for x in range(rm.VIS_W):
            k = ((cx >> 20) & 0x1ff, (cy >> 20) & 0x1ff)
            cx = (cx + xx) & 0xffffffff; cy = (cy + xy) & 0xffffffff
            if k != last: ev.append(k); last = k
        lines.append(ev)
    return lines

def transform(st, rotate=None):
    c = st.rozct16; s16 = rm.s16
    startx = s16(c[0]) << 8; starty = s16(c[1]) << 8
    incyx, incyy = s16(c[2]), s16(c[3]); incxx, incxy = s16(c[4]), s16(c[5])
    if c[6] & 0x4000: incyx <<= 8; incyy <<= 8
    if c[6] & 0x0040: incxx <<= 8; incxy <<= 8
    if rotate is not None:                       # the same scale, another angle
        s = math.hypot(incxx, incxy); t = math.radians(rotate)
        incxx = int(round(s * math.cos(t))); incxy = int(round(s * math.sin(t)))
        incyx, incyy = -incxy, incxx
    ox, oy = rm.ROZ_OFFS
    startx -= oy * incyx; starty -= oy * incyy; startx -= ox * incxx; starty -= ox * incxy
    startx <<= 5; starty <<= 5; incxx <<= 5; incxy <<= 5; incyx <<= 5; incyy <<= 5
    startx = (startx + rm.VIS_X0 * incxx + rm.VIS_Y0 * incyx) & 0xffffffff
    starty = (starty + rm.VIS_X0 * incxy + rm.VIS_Y0 * incyy) & 0xffffffff
    return startx, starty, incxx & 0xffffffff, incxy & 0xffffffff, incyx & 0xffffffff, incyy & 0xffffffff

def costs(lines):
    cache = {}; order = []; ptr = 0; out = []
    for ev in lines:
        c = BASE * rm.VIS_W
        for k in ev:
            if k in cache: continue
            c += MISS
            if len(order) < ENTRIES: order.append(k)
            else:
                victim = order[ptr]; del cache[victim]; order[ptr] = k; ptr = (ptr + 1) % ENTRIES
            cache[k] = True
        out.append(c)
    return out

def lead_needed(cs, budget):
    cum = 0; d = 0
    for j, c in enumerate(cs):
        cum += c
        d = max(d, -(-cum // budget) - (j + 1))
    return d

def analyse(st, rotate=None):
    cs = costs(walk(*transform(st, rotate)))
    return sum(cs) // len(cs), max(cs), lead_needed(cs, BUDGET), lead_needed(cs, CONTENDED)

sweep = '--sweep' in sys.argv
for p in [a for a in sys.argv[1:] if not a.startswith('--')]:
    st = rm.State(p); name = os.path.basename(p).replace('.txt', '')
    if not (st.rozctrl[0] & 0x0100): print("%-14s ROZ off" % name); continue
    avg, worst, l1, l2 = analyse(st)
    print("%-14s avg %5d  worst line %5d  lead needed %d (%d at %d)" % (name, avg, worst, l1, l2, CONTENDED))
    if sweep:
        rows = [(analyse(st, d), d) for d in range(0, 360, 15)]
        (avg, worst, l1, l2), d = max(rows, key=lambda r: r[0][0])
        print("%-14s   worst angle %3d: avg %5d  worst line %5d  lead needed %d (%d at %d)" % ('', d, avg, worst, l1, l2, CONTENDED))
