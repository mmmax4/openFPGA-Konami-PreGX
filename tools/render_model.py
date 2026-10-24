#!/usr/bin/env python3
"""Reference renderer for Gaiapolis video hardware (Konami pre-GX / GX123).

This is the executable spec the RTL is written against: it consumes a frozen
machine state dumped by tools/dump_state.lua plus the built ROM image, and
reproduces the frame MAME produced. Semantics are taken from MAME 0.288
(k054156_k054157_k056832.cpp, k053246_k053247_k055673.cpp, k053936.cpp,
konamigx_v.cpp) -- see docs/hardware.md.

Raster space is 376 x 224 with the visible origin at (40, 16); the cabinet is
ROT90 so MAME's snapshot is 224 wide by 376 tall.

Usage:
    render_model.py <state.txt> <rom> [--layers=A,B,C,D,OBJ,SUB1] [--out out.png]
                    [--ref mame.png] [--diff diff.png]
"""
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio

# ---------------------------------------------------------------- geometry
VIS_W, VIS_H = 376, 224          # raster: X is the 376 axis, Y the 224 axis
VIS_X0, VIS_Y0 = 40, 16          # visible origin inside the 512x264 raster

# ---------------------------------------------------------- ROM image map
ROM_MAINCPU   = 0x0000000
ROM_SOUNDCPU  = 0x0300000
ROM_TILES     = 0x0340000        # 2 MB, 4bpp chunky, 4 bytes per 8-pixel row
ROM_ROZCHAR   = 0x0540000        # gfx3, 1.5 MB, 4bpp 16x16 packed MSB
ROM_ROZMAP    = 0x06C0000        # gfx4, 640 KB
ROM_PCM       = 0x0760000
ROM_SPRITES   = 0x0B60000        # 8 MB, 4bpp, 64-bit word = one 16-pixel row
ROM_EEPROM    = 0x1360000

# gaiapolis constants from mystwarr.cpp / mystwarr_v.cpp
LAYER_OFFS   = [(-2 + 2 - 1, 0 - 1), (0 + 2, 0), (2 + 2, 0), (3 + 2, 0)]  # set_layer_offs
SPR_DX, SPR_DY = -61, -22        # k055673 set_config(K055673_LAYOUT_RNG, -61, -22)
ROZ_OFFS     = (-10, 0)          # K053936GP_set_offset(0, -10, 0)
LSRAM_PAGE   = [(i, i << 11) for i in range(8)]   # k056832 defaults

# MAME paints ROZ raster row N with the transform for row N-1 and never writes
# the first visible row (docs/hardware.md section 10). The model reproduces
# that by default so it can be gated against MAME; the RTL does not, so its
# full-frame gate renders with this off (--roz-exact).
ROZ_MAME_SHIFT = True

K056832_PAGE_W, K056832_PAGE_H = 64, 32          # tiles
SHIFTMASKS = [(6, 0x3f, 0, 0x00), (4, 0x0f, 2, 0x30),
              (2, 0x03, 2, 0x3c), (0, 0x00, 2, 0x3f)]

# K055555 register indices (k055555.h)
K55_PALBASE_A, K55_PALBASE_OBJ, K55_PALBASE_SUB1 = 23, 27, 28
K55_PRIINP = {'A': 7, 'B': 10, 'C': 13, 'D': 14, 'OBJ': 15, 'SUB1': 16}
K55_SHAD1_PRI, K55_SHAD2_PRI, K55_SHAD3_PRI = 37, 38, 39
K55_INPUT_ENABLES = 45
K55_INP_BIT = {'A': 0x01, 'B': 0x02, 'C': 0x04, 'D': 0x08, 'OBJ': 0x10, 'SUB1': 0x20}


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


class State:
    """A frozen frame, as written by tools/dump_state.lua."""

    def __init__(self, path):
        self.vram = [None] * 17
        for line in open(path):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            key = parts[0]
            if key == 'FRAME':
                self.frame = int(parts[1])
                continue
            if key == 'VRAM':
                self.vram[int(parts[1])] = [int(x, 16) for x in parts[2:]]
                continue
            vals = [int(x, 16) for x in parts[1:]]
            setattr(self, key.lower(), vals)

    # --- K056832 ------------------------------------------------------
    def layer_pages(self, layer):
        r0 = (self.k56regs[8 + layer] & 0x18) >> 3
        h = self.k56regs[8 + layer] & 3
        c0 = (self.k56regs[12 + layer] & 0x18) >> 3
        w = self.k56regs[12 + layer] & 3
        return r0, h + 1, c0, w + 1

    def layer_scroll(self, layer):
        dy = s16(self.k56regs[16 + layer])
        dx = s16(self.k56regs[20 + layer])
        return dx, dy

    def scrollmode(self, layer):
        return (self.k56regs[5] >> (LSRAM_PAGE[layer][0] << 1)) & 3

    def colorbase(self, layer):
        return self.k55regs[K55_PALBASE_A + layer] << 4

    # --- K054338 ------------------------------------------------------
    def bgcolor(self):
        """fill_solid_bg: (BGC_R & 0xff) << 16 | BGC_GB"""
        return ((self.k38regs[0] & 0xff) << 16) | self.k38regs[1]

    def shd_rgb(self):
        """9 signed deltas, three per shadow table (update_all_shadows)."""
        out = []
        for i in range(9):
            d = self.k38regs[2 + i] & 0x1ff
            out.append(d - 0x200 if d >= 0x100 else d)
        return out

    def shadowon(self):
        """A shadow table is live only if some delta exceeds +/-7."""
        v = self.shd_rgb()
        return [1 if any(k < -7 or k > 7 for k in v[i * 3:i * 3 + 3]) else 0
                for i in range(3)]

    def shadow_deltas(self, mode):
        if mode == 3:
            return (-80, -80, -80)          # konamigx_mixer_init preset
        v = self.shd_rgb()
        return tuple(v[mode * 3:mode * 3 + 3])

    def noclip(self):
        return bool(self.k38regs[15] & 0x20)   # K338_CTL_CLIPSL

    # --- palette ------------------------------------------------------
    def color(self, idx):
        """xRGB_888: word 2i = 0x00RR, word 2i+1 = 0xGGBB (big-endian 68k)."""
        w0 = self.palette[idx * 2]
        w1 = self.palette[idx * 2 + 1]
        return (w0 & 0xff, (w1 >> 8) & 0xff, w1 & 0xff)

    def rgb(self, idx):
        """Same entry packed as 0xRRGGBB."""
        return ((self.palette[idx * 2] & 0xff) << 16) | self.palette[idx * 2 + 1]


class Roms:
    def __init__(self, path):
        self.d = open(path, 'rb').read()
        if len(self.d) < ROM_EEPROM:
            raise ValueError(f'{path}: too small ({len(self.d)} bytes)')

    def tile_row(self, code, row):
        """4 bytes = one 8-pixel row of an 8x8 tile."""
        o = ROM_TILES + ((code * 32 + row * 4) % 0x200000)
        return self.d[o:o + 4]

    def roz_char_row(self, code, row):
        """8 bytes = one 16-pixel row of a 16x16 4bpp tile."""
        o = ROM_ROZCHAR + ((code * 128 + row * 8) % 0x180000)
        return self.d[o:o + 8]

    def roz_map(self, i):
        """gfx4 layout: colour nibbles (two tiles per byte) at 0, attribute
        bytes at 0x20000, tile low bytes at 0x60000."""
        b = ROM_ROZMAP
        return self.d[b + (i >> 1)], self.d[b + 0x20000 + i], self.d[b + 0x60000 + i]

    def sprite_row(self, code, row):
        """8 bytes = one 16-pixel row of a 16x16 4bpp sprite tile."""
        o = ROM_SPRITES + ((code * 128 + row * 8) % 0x800000)
        return self.d[o:o + 8]


def pal5bit(v):
    v &= 0x1f
    return (v << 3) | (v >> 2)


def apply_shadow(rgb, deltas, noclip):
    """MAME's 15-bit shadow lookup: quantise to RGB15, add the deltas, clamp.

    Lossy by construction -- even zero deltas darken slightly, which is why
    MAME's own comment calls it "lossy, nasty, yuck!".
    """
    r5, g5, b5 = (rgb >> 19) & 0x1f, (rgb >> 11) & 0x1f, (rgb >> 3) & 0x1f
    r = pal5bit(r5) + deltas[0]
    g = pal5bit(g5) + deltas[1]
    b = pal5bit(b5) + deltas[2]
    if not noclip:
        r = 0 if r < 0 else (255 if r > 255 else r)
        g = 0 if g < 0 else (255 if g > 255 else g)
        b = 0 if b < 0 else (255 if b > 255 else b)
    else:
        r &= 0xff; g &= 0xff; b &= 0xff
    return (r << 16) | (g << 8) | b


def nib(b, i):
    """pixel i of a packed-MSB 4bpp byte run"""
    return (b[i >> 1] >> 4) if not (i & 1) else (b[i >> 1] & 0x0f)


# ------------------------------------------------------------ tile layers
def render_tilemap(st, roms, layer, pix, fb, pri, layer_pri):
    """Paint one K056832 layer into pix[] (palette index, -1 = transparent)."""
    r0, rowspan, c0, colspan = st.layer_pages(layer)
    dx, dy = st.layer_scroll(layer)
    mode = st.scrollmode(layer)
    cb = st.colorbase(layer)
    fbits = (st.k56regs[3] >> 6) & 3
    flips_sh, palm1, pals2, palm2 = SHIFTMASKS[fbits]
    flip_override = (st.k56regs[1] >> (layer << 1)) & 3
    ox, oy = LAYER_OFFS[layer]

    width = colspan * K056832_PAGE_W * 8
    height = rowspan * K056832_PAGE_H * 8

    scrollbank = ((st.k56regs[0x18] >> 1) & 0xc) | (st.k56regs[0x18] & 3)
    ls_base = LSRAM_PAGE[layer][1] >> 1

    # MAME draws the tilemap into the full 512x264 raster bitmap and clips to
    # the visible area, so tilemap coordinates are absolute raster coordinates:
    # visible (0,0) is raster (VIS_X0, VIS_Y0).
    for y in range(VIS_H):
        ry = y + VIS_Y0
        if mode == 3:                       # xy scroll
            sx = dx
        elif mode == 0:                     # linescroll
            sx = st.vram[scrollbank][(ls_base + ry * 2 + 1) & 0xfff]
        else:                               # rowscroll
            sx = st.vram[scrollbank][(ls_base + (ry >> 3) * 16 + 1) & 0xfff]
        # MAME: set_scrolly(0, ay) with ay = (dy - layer_offs_y) % height, and
        # a tilemap scroll of v shows source pixel (screen + v).
        vy = (ry + dy - oy) % height
        py = (vy >> 8) % rowspan
        ty = (vy >> 3) & (K056832_PAGE_H - 1)
        fy = vy & 7
        row_base = ((r0 + py) & 3) << 2

        for x in range(VIS_W):
            vx = (x + VIS_X0 + sx - ox) % width
            px_ = (vx >> 9) % colspan
            tx = (vx >> 3) & (K056832_PAGE_W - 1)
            fx = vx & 7
            page = row_base | ((c0 + px_) & 3)
            vram = st.vram[page]
            i = ((ty * K056832_PAGE_W) + tx) << 1
            attr, code = vram[i], vram[i + 1]

            flip = flip_override & ((attr >> flips_sh) & 3)
            color = (attr & palm1) | ((attr >> pals2) & palm2)
            color = cb | ((color >> 2) & 0x0f)      # game4bpp_tile_callback

            rr = 7 - fy if (flip & 2) else fy
            cc = 7 - fx if (flip & 1) else fx
            pv = nib(roms.tile_row(code, rr), cc)
            if pv:
                o = y * VIS_W + x
                pen = (color << 4) | pv
                pix[o] = pen
                fb[o] = st.rgb(pen)
                pri[o] = layer_pri


# ------------------------------------------------------------------ ROZ
# K053936-class PSAC2 plane, driven through the K053936GP_* helpers in
# MAME's k053936.cpp. Virtual plane is 512x512 tiles of 16x16 = 8192x8192.
def roz_tile(st, roms, ti):
    """-> (tile number, colour) for tilemap index ti, per get_gai_936_tile_info"""
    d1, d2, d3 = roms.roz_map(ti)
    tileno = d3 | ((d2 & 0x3f) << 8)
    colour = (d1 & 0x0f) if (ti & 1) else ((d1 >> 4) & 0x0f)
    if d2 & 0x80:
        colour |= 0x10
    colour |= st.k55regs[K55_PALBASE_SUB1] << 4
    return tileno, colour


def render_roz(st, roms, pix, fb, pri, layer_pri):
    if not (st.rozctrl[0] & 0x0100):        # ddd_053936_enable_w bit 8
        return
    c = st.rozct16
    startx = s16(c[0]) << 8
    starty = s16(c[1]) << 8
    incyx, incyy = s16(c[2]), s16(c[3])
    incxx, incxy = s16(c[4]), s16(c[5])
    if c[6] & 0x4000:
        incyx <<= 8; incyy <<= 8
    if c[6] & 0x0040:
        incxx <<= 8; incxy <<= 8

    if c[7] & 0x0040:
        raise NotImplementedError('K053936 "super" (per-line) mode not modelled yet')

    ox, oy = ROZ_OFFS
    startx -= oy * incyx; starty -= oy * incyy
    startx -= ox * incxx; starty -= ox * incxy
    startx <<= 5; starty <<= 5
    incxx <<= 5; incxy <<= 5; incyx <<= 5; incyy <<= 5

    # copyroz32clip: the caller's cliprect is the visible area, and the walk
    # starts from its top-left corner in raster coordinates. MAME carries the
    # accumulators as uint32_t, so the >>16 is an unsigned shift -- Python's
    # unbounded ints have to be masked to match.
    startx = (startx + VIS_X0 * incxx + VIS_Y0 * incyx) & 0xffffffff
    starty = (starty + VIS_X0 * incxy + VIS_Y0 * incyy) & 0xffffffff
    incxx &= 0xffffffff; incxy &= 0xffffffff
    incyx &= 0xffffffff; incyy &= 0xffffffff

    # source clip window (ddd_053936_clip_w)
    clip = st.rozclip[1] & 0x0100
    if clip:
        m = st.rozclip[0]
        cx, cy = m & 0x3f, (m & 0x0fc0) >> 6
        sxs, sys = (m & 0x3000) >> 12, (m & 0xc000) >> 14
        sxs = {3: 1, 2: 2}.get(sxs, 4)
        sys = {3: 1, 2: 2}.get(sys, 4)
        minx, maxx = cx << 7, ((cx + sxs) << 7) - 1
        miny, maxy = cy << 7, ((cy + sys) << 7) - 1
    else:
        minx = miny = -0x10000
        maxx = maxy = 0x10000

    tile_cache = {}
    # MAME's K053936GP_copyroz32clip advances its destination pointer by one
    # row before the loop body while leaving the accumulators at their initial
    # value, so raster row N is painted with the transform for row N-1 and the
    # first visible row is never written. Reproduced here so the frozen-state
    # gate can be exact; flagged because it looks like a MAME artefact rather
    # than hardware behaviour (docs/hardware.md section 10) and the RTL should
    # probably not copy it.
    for ti in range(VIS_H):
        y = ti + 1 if ROZ_MAME_SHIFT else ti
        cx, cy = startx, starty
        startx = (startx + incyx) & 0xffffffff
        starty = (starty + incyy) & 0xffffffff
        if y >= VIS_H:
            break
        for x in range(VIS_W):
            srcx = (cx >> 16) & 0x1fff
            srcy = (cy >> 16) & 0x1fff
            cx = (cx + incxx) & 0xffffffff
            cy = (cy + incxy) & 0xffffffff
            if srcx < minx or srcx > maxx or srcy < miny or srcy > maxy:
                continue
            ti = ((srcy >> 4) << 9) | (srcx >> 4)
            ent = tile_cache.get(ti)
            if ent is None:
                ent = roz_tile(st, roms, ti)
                tile_cache[ti] = ent
            tileno, colour = ent
            pv = nib(roms.roz_char_row(tileno, srcy & 15), srcx & 15)
            if not pv:                       # cmask 0xf for 4bpp: pen 0 is clear
                continue
            o = y * VIS_W + x
            pen = (colour << 4) | pv
            pix[o] = pen
            fb[o] = st.rgb(pen)
            pri[o] = layer_pri


# -------------------------------------------------------------- sprites
# K055673 (K053246/K053247 family) in K055673_LAYOUT_RNG: 16x16 4bpp tiles,
# planes at bit offsets {24,16,8,0}, x offsets 0..7 then 32..39, row stride
# 64 bits. One 64-bit word is one complete 16-pixel row, 128 bytes per tile.
SPR_XOFFSET = (0, 1, 4, 5, 16, 17, 20, 21)
SPR_YOFFSET = (0, 2, 8, 10, 32, 34, 40, 42)
SPR_PLANEOFS = (24, 16, 8, 0)          # planeoffset[0] is the MSB
FP = 19                                 # 13.19 fixed point in zdrawgfxzoom32GP
GRANULARITY = 16                        # 4bpp
SHDPEN = GRANULARITY - 1


def decode_sprite_tile(roms, code):
    """-> bytes(256), one pixel value per byte, row-major."""
    base = ROM_SPRITES + ((code & 0xffff) * 128)
    d = roms.d
    out = bytearray(256)
    for r in range(16):
        rb = base + r * 8
        for c in range(16):
            xo = c if c < 8 else 32 + (c - 8)
            v = 0
            for pi, po in enumerate(SPR_PLANEOFS):
                bit = po + xo
                byte = d[rb + (bit >> 3)]
                v |= ((byte >> (7 - (bit & 7))) & 1) << (3 - pi)
            out[r * 16 + c] = v
    return out


def sprite_colorbase(st):
    # screen_update_dadandrn, m_gametype == 0
    return (st.k55regs[K55_PALBASE_OBJ] << 4) & 0x7f


def sprite_objects(st):
    """The K053247 object list, ordered exactly as konamigx_mixer sorts it.

    order = pri<<24 | zcode<<16 | offs<<5 | drawmode<<4 | shadow, sorted
    descending with ties keeping reverse insertion order, so the list is
    back-to-front.
    """
    opset = st.k47regs[6]                       # k053247_read_register(0xc/2)
    objset1 = st.k46regs[5]                     # k053246_read_register(5)
    shadowon = st.shadowon()
    shdpri = [st.k55regs[K55_SHAD1_PRI], st.k55regs[K55_SHAD2_PRI],
              st.k55regs[K55_SHAD3_PRI]]
    cb = sprite_colorbase(st)
    objs = []
    for n in range(256):
        offs = n * 8
        w0 = st.spriteram[offs]
        if not (w0 & 0x8000):
            continue
        zcode = w0 & 0xff
        if opset & 0x10:                        # OPSET PRI inverts z order
            zcode = 0xff - zcode
        code = st.spriteram[offs + 1]
        raw = st.spriteram[offs + 6]
        # gaiapols_sprite_callback
        pri = raw & 0xe0
        color = cb | ((raw >> 4) & 0x20) | (raw & 0x1f)

        # konamigx_mixer: a sprite can contribute a solid object, a shadow
        # object, or both.
        shadow = (raw >> 10) & 3
        add_solid = add_shadow = False
        solid_mode = shadow_mode = 0
        if shadow:
            if shadow != 1 or (objset1 & 0x20):
                shadow -= 1
                add_solid, solid_mode = True, 1     # partial solid
                if shadowon[shadow]:
                    add_shadow, shadow_mode = True, 4   # partial shadow
            else:
                # shadow code 1 with SD0EN off drops the whole sprite to shadow
                shadow = 0
                if not shadowon[0]:
                    continue
                add_shadow, shadow_mode = True, 5       # full shadow
        else:
            add_solid, solid_mode = True, 0             # full solid

        if add_solid:
            order = (pri << 24) | (zcode << 16) | (offs << 5) | (solid_mode << 4)
            objs.append((order, offs, code, color, solid_mode, pri))
        if add_shadow:
            spri = pri if (opset & 0x20) else shdpri[shadow]
            order = ((spri << 24) | (zcode << 16) | (offs << 5)
                     | (shadow_mode << 4) | shadow)
            objs.append((order, offs, code, color, shadow_mode, spri))

    objs.reverse()
    objs.sort(key=lambda o: -o[0])               # stable: ties keep order
    return objs


def draw_sprite_tile(st, roms, pix, fb, zbuf, szbuf, tile, color, flipx, flipy,
                     sx, sy, zw, zh, zcode, drawmode, pri, shd, cache):
    """zdrawgfxzoom32GP: drawmode 0-3 solid/alpha, 4-5 shadow. Alpha is not
    reached by gaiapolis (its sprite callback sets no mix bits)."""
    scalex, scaley = zw << 12, zh << 12
    if not scalex or not scaley:
        return
    dw = ((scalex << 4) + 0x8000) >> 16
    dh = ((scaley << 4) + 0x8000) >> 16
    if dw <= 0 or dh <= 0:
        return
    left, top = sx, sy
    right, bottom = sx + dw - 1, sy + dh - 1
    # cliprect is the visible area in raster coordinates
    cl, cr, ct, cb_ = VIS_X0, VIS_X0 + VIS_W - 1, VIS_Y0, VIS_Y0 + VIS_H - 1
    if left > cr or right < cl or top > cb_ or bottom < ct:
        return

    src_stride_x = (16 << FP) // dw
    src_stride_y = (16 << FP) // dh
    src_base_x = max(cl - left, 0) * src_stride_x
    src_base_y = max(ct - top, 0) * src_stride_y

    left, right = max(left, cl), min(right, cr)
    top, bottom = max(top, ct), min(bottom, cb_)

    flip_mask = (15 if flipx else 0) | ((15 << 4) if flipy else 0)

    src = cache.get(tile)
    if src is None:
        src = decode_sprite_tile(roms, tile)
        cache[tile] = src

    pal_base = (color % 128) * GRANULARITY
    z8 = zcode & 0xff
    shdpen = SHDPEN
    if drawmode == 5:
        drawmode, shdpen = 4, 1

    if drawmode < 4:
        test_shd = bool(drawmode & 3)
        for y in range(bottom - top + 1):
            y_off = (src_base_y + y * src_stride_y) >> FP
            row = y_off * 16
            base = (top - VIS_Y0 + y) * VIS_W + (left - VIS_X0)
            for x in range(right - left + 1):
                x_off = (src_base_x + x * src_stride_x) >> FP
                pal_idx = src[(x_off + row) ^ flip_mask]
                if not pal_idx:
                    continue
                if test_shd and pal_idx >= shdpen:
                    continue
                o = base + x
                if zbuf[o] < z8:
                    continue
                zbuf[o] = z8
                pen = pal_base + pal_idx
                pix[o] = pen
                fb[o] = st.rgb(pen)
    else:
        deltas, noclip = shd
        for y in range(bottom - top + 1):
            y_off = (src_base_y + y * src_stride_y) >> FP
            row = y_off * 16
            base = (top - VIS_Y0 + y) * VIS_W + (left - VIS_X0)
            for x in range(right - left + 1):
                x_off = (src_base_x + x * src_stride_x) >> FP
                pal_idx = src[(x_off + row) ^ flip_mask]
                if pal_idx < shdpen:
                    continue
                o = base + x
                if szbuf[o * 2] < z8 or szbuf[o * 2 + 1] <= pri:
                    continue
                szbuf[o * 2] = z8
                szbuf[o * 2 + 1] = pri
                fb[o] = apply_shadow(fb[o], deltas, noclip)


class SpriteCtx:
    """Per-frame sprite state shared by every object draw."""

    def __init__(self, st):
        k46 = st.k46regs
        opset = st.k47regs[6]
        self.flipscreenx = k46[5] & 1
        self.flipscreeny = (k46[5] >> 1) & 1
        self.offx = s16((k46[0] << 8) | k46[1])
        self.offy = s16((k46[2] << 8) | k46[3])
        if opset & 0x40:
            self.wrap = (512, 512 - 64, 512 - 128)
        else:
            self.wrap = (1024, 1024 - 384, 1024 - 512)
        self.zbuf = bytearray(b'\xff' * (VIS_W * VIS_H))       # wipezbuf: memset -1
        self.szbuf = bytearray(b'\xff' * (VIS_W * VIS_H * 2))  # shadow z + priority
        self.cache = {}
        self.noclip = st.noclip()


def draw_sprite_object(st, roms, pix, fb, ctx, obj):
    """One entry of the mixer's object pool."""
    ram = st.spriteram
    order, offs, code, color, drawmode, pri = obj
    flipscreenx, flipscreeny = ctx.flipscreenx, ctx.flipscreeny
    offx, offy = ctx.offx, ctx.offy
    wrapsize, xwraplim, ywraplim = ctx.wrap
    zbuf, szbuf, cache = ctx.zbuf, ctx.szbuf, ctx.cache

    zcode = (order >> 16) & 0xff
    shd = (st.shadow_deltas(order & 3), ctx.noclip) if drawmode >= 4 else None
    temp4 = ram[offs]

    xa = ya = 0
    if code & 0x01: xa += 1
    if code & 0x02: ya += 1
    if code & 0x04: xa += 2
    if code & 0x08: ya += 2
    if code & 0x10: xa += 4
    if code & 0x20: ya += 4
    code &= ~0x3f

    oy = ram[offs + 2] & 0x3ff
    ox = ram[offs + 3] & 0x3ff

    scaley = ram[offs + 4] & 0x3ff
    zoomy = ((0x400000 + (scaley >> 1)) // scaley) if scaley else 0x800000
    if temp4 & 0x4000:
        zoomx, scalex = zoomy, scaley
    else:
        scalex = ram[offs + 5] & 0x3ff
        zoomx = ((0x400000 + (scalex >> 1)) // scalex) if scalex else 0x800000
    nozoom = (scalex == 0x40 and scaley == 0x40)

    flipx = temp4 & 0x1000
    flipy = temp4 & 0x2000
    attr = ram[offs + 6]
    mirrorx = attr & 0x4000
    if mirrorx:
        flipx = 0
    mirrory = attr & 0x8000

    if flipscreenx:
        ox = -ox
        if not mirrorx:
            flipx = not flipx
    if flipscreeny:
        oy = -oy
        if not mirrory:
            flipy = not flipy

    # GX path applies the global offsets before wrapping
    ox += SPR_DX
    oy -= SPR_DY
    ox = (ox - offx) & (wrapsize - 1)
    oy = ((-oy) - offy) & (wrapsize - 1)
    if ox >= xwraplim: ox -= wrapsize
    if oy >= ywraplim: oy -= wrapsize

    sz = (temp4 >> 8) & 0x0f
    width = 1 << (sz & 3)
    height = 1 << ((sz >> 2) & 3)

    ox -= (zoomx * width) >> 13
    oy -= (zoomy * height) >> 13

    for y in range(height):
        sy = oy + ((zoomy * y + (1 << 11)) >> 12)
        zh = (oy + ((zoomy * (y + 1) + (1 << 11)) >> 12)) - sy
        for x in range(width):
            sx = ox + ((zoomx * x + (1 << 11)) >> 12)
            zw = (ox + ((zoomx * (x + 1) + (1 << 11)) >> 12)) - sx
            tempcode = code

            if mirrorx:
                if (not flipx) ^ ((x << 1) < width):
                    tempcode += SPR_XOFFSET[(width - 1 - x + xa) & 7]
                    fx = 1
                else:
                    tempcode += SPR_XOFFSET[(x + xa) & 7]
                    fx = 0
            else:
                if flipx:
                    tempcode += SPR_XOFFSET[(width - 1 - x + xa) & 7]
                else:
                    tempcode += SPR_XOFFSET[(x + xa) & 7]
                fx = bool(flipx)

            if mirrory:
                if (not flipy) ^ ((y << 1) >= height):
                    tempcode += SPR_YOFFSET[(height - 1 - y + ya) & 7]
                    fy = 1
                else:
                    tempcode += SPR_YOFFSET[(y + ya) & 7]
                    fy = 0
            else:
                if flipy:
                    tempcode += SPR_YOFFSET[(height - 1 - y + ya) & 7]
                else:
                    tempcode += SPR_YOFFSET[(y + ya) & 7]
                fy = bool(flipy)

            w, h = (0x10, 0x10) if nozoom else (zw, zh)
            draw_sprite_tile(st, roms, pix, fb, zbuf, szbuf, tempcode, color,
                             fx, fy, sx, sy, w, h, zcode, drawmode, pri,
                             shd, cache)


# ------------------------------------------------------------------ main
# ---------------------------------------------------------------- mixer
# K055555 priority encoder. MAME models it as konamigx_mixer: every input --
# the four tilemaps, the ROZ sub-layer and all 256 sprites -- goes into one
# object pool keyed by a 32-bit `order`, sorted descending, and drawn
# back-to-front. Real silicon compares per pixel instead, which is what the
# RTL should do; the draw order is the observable part and that is what this
# reproduces.
#
# Not modelled, because nothing in the state corpus exercises it (see
# docs/hardware.md): tilemap and object alpha (V_INMIX and OS_INMIX are 0 in
# every captured frame) and layer brightness (V_BRI only ever selects a
# 0xff level). MAME also applies brightness as a global palette contrast
# whose last value leaks into the sprite draw, which this does not copy.

def mixer_pool(st, layers):
    """The layer half of the object pool, in MAME's order."""
    layerid = [0, 1, 2, 3, 4, 5]
    layerpri = [
        st.k55regs[K55_PRIINP['A']],
        st.k55regs[K55_PRIINP['B']],
        st.k55regs[K55_PRIINP['C']],
        st.k55regs[K55_PRIINP['D']],
        st.k55regs[16],                       # K55_PRIINP_9  = SUB1
        st.k55regs[17],                       # K55_PRIINP_10 = SUB2
    ]
    for j in range(5):                        # selection sort, descending
        for i in range(j + 1, 6):
            if layerpri[j] <= layerpri[i]:
                layerpri[j], layerpri[i] = layerpri[i], layerpri[j]
                layerid[j], layerid[i] = layerid[i], layerid[j]

    pool = []
    for i in range(5, -1, -1):
        code = layerid[i]
        if code == 4:
            # sub1 is the ROZ tilemap, present only while it is enabled
            offs = -2 if (st.rozctrl[0] & 0x0100) else -128
        elif code == 5:
            offs = -128                        # no sub2 on this board
        else:
            offs = -1
        if offs != -128:
            pool.append((layerpri[i] << 24, offs, code, 0, 0, 0))
    return pool


def dump_objlist(st, path):
    """The mixer's sprite object list in draw order, for the RTL bench.

    One record per object: order(u32), offs(u16), code(u16), color(u16),
    drawmode(u8), pri(u8). Little-endian, packed.
    """
    import struct
    objs = sprite_objects(st)
    with open(path, 'wb') as f:
        f.write(struct.pack('<I', len(objs)))
        for order, offs, code, color, drawmode, pri in objs:
            f.write(struct.pack('<IHHHBB', order, offs, code, color & 0xffff,
                                drawmode, pri))
    return len(objs)


def render_roz_only(st, roms):
    """The ROZ layer's palette indices for the RTL bench, 0xffff transparent."""
    pix = [-1] * (VIS_W * VIS_H)
    fb = [0] * (VIS_W * VIS_H)
    pri = [0] * (VIS_W * VIS_H)
    render_roz(st, roms, pix, fb, pri, 0)
    return pix


def render_layers_only(st, roms):
    """Per-layer palette indices for the RTL bench: 4 x VIS_H x VIS_W uint16,
    0xffff where the layer is transparent. Bypasses the mixer so the tilemap
    RTL can be gated on its own."""
    out = []
    for li in range(4):
        pix = [-1] * (VIS_W * VIS_H)
        fb = [0] * (VIS_W * VIS_H)
        pri = [0] * (VIS_W * VIS_H)
        render_tilemap(st, roms, li, pix, fb, pri, 0)
        out.append(pix)
    return out


def render(st, roms, layers):
    n = VIS_W * VIS_H
    pix = [-1] * n
    pri = [0] * n
    fb = [st.bgcolor()] * n

    disp = st.k55regs[K55_INPUT_ENABLES]
    pool = mixer_pool(st, layers)
    ctx = None
    if 'OBJ' in layers and (disp & K55_INP_BIT['OBJ']):
        ctx = SpriteCtx(st)
        pool += sprite_objects(st)

    pool.reverse()
    pool.sort(key=lambda o: -o[0])             # stable: ties keep order

    for obj in pool:
        offs = obj[1]
        if offs >= 0:
            draw_sprite_object(st, roms, pix, fb, ctx, obj)
        elif offs == -1:
            name = 'ABCD'[obj[2]]
            if name in layers and (disp & K55_INP_BIT[name]):
                render_tilemap(st, roms, obj[2], pix, fb, pri,
                               st.k55regs[K55_PRIINP[name]])
        elif offs == -2:
            if 'SUB1' in layers and (disp & K55_INP_BIT['SUB1']):
                render_roz(st, roms, pix, fb, pri, st.k55regs[16])
    return pix, fb


def to_rgb_rot90(fb):
    """raster (x,y) -> ROT90 snapshot (223-y, x); returns (w,h,rgb)."""
    w, h = VIS_H, VIS_W
    out = bytearray(w * h * 3)
    for y in range(VIS_H):
        row = y * VIS_W
        for x in range(VIS_W):
            v = fb[row + x]
            o = (x * w + (VIS_H - 1 - y)) * 3
            out[o] = (v >> 16) & 0xff
            out[o + 1] = (v >> 8) & 0xff
            out[o + 2] = v & 0xff
    return w, h, out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--') and '=' in a)
    if len(args) < 2:
        sys.exit(__doc__)
    st = State(args[0])
    roms = Roms(args[1])
    if 'roz-exact' in [a[2:] for a in sys.argv[1:] if a.startswith('--')]:
        global ROZ_MAME_SHIFT
        ROZ_MAME_SHIFT = False
    layers = set((opts.get('layers') or 'A,B,C,D,OBJ,SUB1').split(','))

    dumprgb = opts.get('dump-rgb')
    if dumprgb:
        import struct
        _, fb = render(st, roms, layers)
        with open(dumprgb, 'wb') as f:
            f.write(struct.pack('<%dI' % len(fb), *fb))
        print(f'wrote {dumprgb} ({VIS_H} x {VIS_W} uint32 RGB, layers {",".join(sorted(layers))})')
        return

    dumpobjrgb = opts.get('dump-obj-rgb')
    if dumpobjrgb:
        import struct
        _, fb = render(st, roms, {'OBJ'})
        with open(dumpobjrgb, 'wb') as f:
            f.write(struct.pack('<%dI' % len(fb), *fb))
        print(f'wrote {dumpobjrgb} ({VIS_H} x {VIS_W} uint32 RGB)')
        return

    dumpobj = opts.get('dump-objlist')
    if dumpobj:
        n = dump_objlist(st, dumpobj)
        print(f'wrote {dumpobj} ({n} objects)')
        return

    dumproz = opts.get('dump-roz')
    if dumproz:
        import struct
        layer = render_roz_only(st, roms)
        with open(dumproz, 'wb') as f:
            f.write(struct.pack('<%dH' % len(layer),
                                *[(v & 0xffff) if v >= 0 else 0xffff for v in layer]))
        print(f'wrote {dumproz} ({VIS_H} x {VIS_W} uint16)')
        return

    dump = opts.get('dump-layers')
    if dump:
        import struct
        data = render_layers_only(st, roms)
        with open(dump, 'wb') as f:
            for layer in data:
                f.write(struct.pack('<%dH' % len(layer),
                                    *[(v & 0xffff) if v >= 0 else 0xffff for v in layer]))
        print(f'wrote {dump} (4 x {VIS_H} x {VIS_W} uint16)')
        return

    pix, fb = render(st, roms, layers)
    w, h, rgb = to_rgb_rot90(fb)

    out = opts.get('out')
    if out:
        pngio.write(out, w, h, rgb)
        print(f'wrote {out} ({w}x{h})')

    ref = opts.get('ref')
    if ref:
        rw, rh, rpx = pngio.read(ref)
        if (rw, rh) != (w, h):
            sys.exit(f'reference is {rw}x{rh}, model is {w}x{h}')
        diff = sum(1 for i in range(0, len(rgb), 3)
                   if rgb[i:i + 3] != rpx[i:i + 3])
        # coverage: how much of the frame the model actually painted. A state
        # where the layer is blank passes trivially, so report it alongside.
        drawn = sum(1 for v in pix if v >= 0)
        print(f'differing pixels: {diff} / {w*h} ({100.0*diff/(w*h):.2f}%) '
              f'coverage {100.0*drawn/(VIS_W*VIS_H):.1f}%')
        dimg = opts.get('diff')
        if dimg:
            dd = bytearray(w * h * 3)
            for i in range(0, len(rgb), 3):
                if rgb[i:i + 3] != rpx[i:i + 3]:
                    dd[i] = 0xff
                else:
                    g = (rgb[i] + rgb[i + 1] + rgb[i + 2]) // 6
                    dd[i] = dd[i + 1] = dd[i + 2] = g
            pngio.write(dimg, w, h, dd)
            print(f'wrote {dimg}')


if __name__ == '__main__':
    main()
