#!/usr/bin/env python3
"""Does a per-pixel priority encoder reproduce MAME's ordered composite?

The real K055555 compares every input per pixel. konamigx_mixer -- and so the
reference renderer -- instead sorts everything into one list and paints back to
front. For opaque pixels the two should agree; shadows depend on draw order
and might not. This renders each full-frame state both ways and diffs them,
so the RTL mixer can be built the hardware way with evidence rather than hope.

Per-pixel rule derived from the ordered composite:
  * candidates are each opaque layer pixel (order = pri<<24) and the sprite
    line buffer's solid winner (its own order word);
  * the visible pixel is the candidate with the SMALLEST order, since the
    ordered composite paints descending and the last painted wins;
  * a shadow darkens the visible pixel iff the shadow's order is smaller than
    the winner's (the shadow was painted after it and nothing later covered
    it).

Usage: mixer_experiment.py <rom> [state ...]
"""
import sys, os, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_model as M

N = M.VIS_W * M.VIS_H


def sprite_planes(st, roms):
    """Run the sprite pass alone, recording per-pixel the solid winner's order
    and the applied shadow's order/table."""
    sol_order = [None] * N
    sol_pen = [-1] * N
    shd_order = [None] * N
    shd_tab = [0] * N

    orig = M.draw_sprite_tile

    def hooked(st_, roms_, pix, fb, zbuf, szbuf, tile, color, flipx, flipy,
               sx, sy, zw, zh, zcode, drawmode, pri, shd, cache):
        # snapshot buffers, draw, then attribute every change to this object
        zb0 = bytes(zbuf); sz0 = bytes(szbuf); pix0 = list(pix)
        orig(st_, roms_, pix, fb, zbuf, szbuf, tile, color, flipx, flipy,
             sx, sy, zw, zh, zcode, drawmode, pri, shd, cache)
        order = hooked.cur_order
        if drawmode < 4:
            for i in range(N):
                if pix[i] != pix0[i] or (zbuf[i] != zb0[i]):
                    sol_order[i] = order; sol_pen[i] = pix[i]
                    shd_order[i] = None          # a later solid clears it
        else:
            for i in range(N):
                if szbuf[2*i] != sz0[2*i] or szbuf[2*i+1] != sz0[2*i+1]:
                    shd_order[i] = order; shd_tab[i] = order & 3
    hooked.cur_order = None
    M.draw_sprite_tile = hooked

    # replicate render()'s sprite dispatch so we know each object's order
    ctx = M.SpriteCtx(st)
    pix = [-1] * N; fb = [st.bgcolor()] * N
    for obj in M.sprite_objects(st):
        hooked.cur_order = obj[0]
        M.draw_sprite_object(st, roms, pix, fb, ctx, obj)
    M.draw_sprite_tile = orig
    return sol_order, sol_pen, shd_order, shd_tab


def per_pixel(st, roms):
    disp = st.k55regs[M.K55_INPUT_ENABLES]
    layers = []
    for name in 'ABCD':
        if not (disp & M.K55_INP_BIT[name]):
            continue
        pix = [-1] * N; fb = [0] * N; pri = [0] * N
        M.render_tilemap(st, roms, 'ABCD'.index(name), pix, fb, pri, 0)
        layers.append((st.k55regs[M.K55_PRIINP[name]] << 24, pix, 'ABCD'.index(name)))
    if (disp & M.K55_INP_BIT['SUB1']) and (st.rozctrl[0] & 0x100):
        pix = [-1] * N; fb = [0] * N; pri = [0] * N
        M.render_roz(st, roms, pix, fb, pri, 0)
        layers.append((st.k55regs[16] << 24, pix, 4))

    # the ordered composite's tie-break among equal-order layers comes from its
    # sort; reproduce it by asking mixer_pool for the layer order it would paint
    pool = M.mixer_pool(st, {'A', 'B', 'C', 'D', 'SUB1'})
    pool.reverse(); pool.sort(key=lambda o: -o[0])
    paint_rank = {}
    for r, obj in enumerate(pool):
        code = obj[2] if obj[1] == -1 else 4
        paint_rank[code] = r                  # later rank = painted later = on top

    have_obj = bool(disp & M.K55_INP_BIT['OBJ'])
    sol_order, sol_pen, shd_order, shd_tab = sprite_planes(st, roms) if have_obj \
        else ([None]*N, [-1]*N, [None]*N, [0]*N)

    out = [st.bgcolor()] * N
    noclip = st.noclip()
    for i in range(N):
        best = None                        # (order, -paint_rank, pen)
        for order, pix, code in layers:
            if pix[i] >= 0:
                key = (order, -paint_rank[code])
                if best is None or key < best[0]:
                    best = (key, pix[i])
        if sol_order[i] is not None:
            # sprites lose ties to layers: a layer's order is exactly pri<<24
            # while a sprite's is strictly larger for the same priority
            key = (sol_order[i], 1)
            if best is None or key < best[0]:
                best = (key, sol_pen[i])
        if best is not None:
            rgb = st.rgb(best[1])
            win_order = best[0][0]
        else:
            rgb = st.bgcolor()
            win_order = None
        if shd_order[i] is not None and (win_order is None or shd_order[i] < win_order):
            rgb = M.apply_shadow(rgb, st.shadow_deltas(shd_tab[i]), noclip)
        out[i] = rgb
    return out


def main():
    roms = M.Roms(sys.argv[1])
    names = sys.argv[2:] or [os.path.basename(f)[:-4] for f in sorted(glob.glob('artifacts/states/*.txt'))
                             if not any(f.endswith(s) for s in ('_tm.txt','_obj.txt','_roz.txt','_A.txt','_B.txt','_C.txt','_D.txt'))]
    total_bad = 0
    for n in names:
        st = M.State(f'artifacts/states/{n}.txt')
        _, ordered = M.render(st, roms, {'A','B','C','D','OBJ','SUB1'})
        pp = per_pixel(st, roms)
        bad = [i for i in range(N) if ordered[i] != pp[i]]
        total_bad += len(bad)
        if bad:
            i = bad[0]
            print(f'{n:10s} DIFFER {len(bad):6d} px, first x={i % M.VIS_W} y={i // M.VIS_W} '
                  f'ordered={ordered[i]:#08x} perpixel={pp[i]:#08x}')
        else:
            print(f'{n:10s} identical')
    print('per-pixel encoder matches the ordered composite' if not total_bad
          else f'{total_bad} differing pixels in total')
    sys.exit(1 if total_bad else 0)


if __name__ == '__main__':
    main()
