#!/usr/bin/env python3
"""Independent, current-MAME Mystic GX5 sprite candidates; no RTL/RGB input.

Solid z selection and shadow-candidate z selection are independent. This is
not the layer-dependent GX mixer or a golden bitmap from historical MAME.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct

WORKTREE = Path(__file__).resolve().parents[1]
PIN = "76af2d6d907f0df822dca1d5146454cc5ee18294"
ROM_SHA = "0911773903b0b04df4272abddc02041b526e7218a582c308da3fa68c022c3547"
SOURCES = {
    "ref/mame/mystwarr.cpp": "ece43729edea2dc86615fb96f19d0c3cc8fc93a8776fc38353e31a48235fec9a",
    "ref/mame/mystwarr_v.cpp": "960e935ad8cf16e3e37d019f2a04a31942041a107a907023aa89434d386bc257",
    "ref/mame/k053246_k053247_k055673.cpp": "fc534b7b0e250b80a9706a99622a339f681fa49e5ad207bc027e410c6f9f1f27",
    "private/mystic-sprite-oracle-k053247.h": "1d4d33ac0a556c92a32e54289b3dabce14ac785913c73b5a1cc58d6c2b8fe08d",
    "private/mystic-sprite-oracle-konami-helper.cpp": "90f1b0de9315ba813b049e67dc0917251f3f7e3100c1c7d49cc11815c76ff7a5",
    "private/mystic-sprite-oracle-k055555.h": "8636aac1def0abbfe84c7d64f7a262ac15e02bf6c5a4b7e09873351f3a03e052",
    "private/mame0220/current_konamigx_v.cpp": "a56e198c8b5747f2c1553fbce72ed7f223398bf710d2da091fcae6c9dc346354",
    "private/mame0220/current_k054338.cpp": "e04cb7a42b767f6bd516f1fbc127aa72a3eb6ceb1bece5faaa43ca65aca44064",
}
W, H, X0, Y0, DX, DY = 288, 224, 24, 16, -48, -24
XO = (0, 1, 4, 5, 16, 17, 20, 21)
YO = (0, 2, 8, 10, 32, 34, 40, 42)
BITS = {"palette": [0, 11], "opaque": 12, "solid_priority": [13, 20],
        "effect": [21, 22], "solid_z": [23, 30], "shadow_valid": 31,
        "shadow_table": [32, 33], "shadow_priority": [34, 41],
        "shadow_z": [42, 49], "solid_pen": [50, 54],
        "solid_drawmode_effective": [55, 56], "shadow_drawmode": [57, 59], "zero": [60, 63]}
LIMITS = ["RGB/alpha blending and additive RGB arithmetic",
          "layer-dependent SHD_ON/SHD_PRI_SEL/topmost shadow visibility",
          "interaction with tile/ROZ priorities; final composite pixel",
          "non-Mystic callback/primode and Escape Kids half-width mode",
          "hardware memory latency, scheduling, deadlines and cancellation"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(ok, msg):
    if not ok:
        raise ValueError(msg)


def s16(value):
    return value - 65536 if value & 32768 else value


def pen5(rom, code, row, x):
    r = ((code & 0x7fff) * 16 + row)
    bit = 7 - (x & 7)
    at = r * 8 + (x // 8) * 4
    return sum(((rom[at+j] >> bit) & 1) << j for j in range(4)) | (((rom[0x400000+r*2+x//8] >> bit) & 1) << 4)


def mame_layout_pen(rom, code, row, x):
    """Actual combined-ROM byte layout + primary gfx_layout bit offsets."""
    row = (code & 0x7fff) * 16 + row
    combined = []
    for half in range(2):
        combined.extend(rom[row*8+half*4:row*8+half*4+4])
        combined.append(rom[0x400000+row*2+half])
    xoff = x if x < 8 else x+32
    return sum(((combined[(plane+xoff)//8] >> (7-(plane+xoff)%8)) & 1) << (4-i)
               for i, plane in enumerate((32, 24, 16, 8, 0)))


def alpha_level(regs, effect):
    if not effect:
        return 255
    mixset = (regs[13+((effect >> 1) & 1)] >> ((~effect << 3) & 8)) & 255
    level = mixset & 31
    if not mixset & 32:  # Mystic GX mixer init invert_alpha(1)
        level = 31-level
    return ((level << 3) | (level >> 2)) | ((bool(mixset & 32)) << 8) | ((bool(regs[15] & 2)) << 9)


def objects(st, old_priority=False, one_effect_bit=False):
    ram, k46, k47, k55, k38 = (st[k] for k in ("SPRITERAM", "K46REGS", "K47REGS", "K55REGS", "K38REGS"))
    shadowon = []
    for table in range(3):
        delta = [v-512 if v & 256 else v for v in [r & 511 for r in k38[2+table*3:5+table*3]]]
        shadowon.append(any(abs(v) > 7 for v in delta))
    result = []
    for off in range(0, 2048, 8):
        if not ram[off] & 0x8000:
            continue
        raw = ram[off+6]; z = ram[off] & 255
        if k47[6] & 16:
            z = 255-z
        pri = raw & (0xf0 if old_priority else 0xe0)
        effect = (raw >> 8) & (1 if one_effect_bit else 3)
        group = ((k55[27] << 5) | (raw & 31)) % 64
        shadow = (raw >> 10) & 3
        modes = []
        if not shadow:
            modes.append((2 if effect else 0, pri, 0))
        elif shadow != 1 or k46[5] & 32:
            table = shadow-1
            modes.append((3 if effect else 1, pri, 0))
            if shadowon[table]:
                modes.append((4, pri if k47[6] & 32 else k55[37+table], table))
        elif shadowon[0]:
            modes.append((5, pri if k47[6] & 32 else k55[37], 0))
        for mode, priority, table in modes:
            order = (priority << 24) | (z << 16) | (off << 5) | (mode << 4) | table
            result.append({"order": order, "offset_words": off, "object_index": off//8,
                           "code": ram[off+1], "raw_attr": raw, "group": group,
                           "effect": effect, "callback_priority": pri, "priority": priority,
                           "z": z, "drawmode": mode, "shadow_table": table,
                           "shadow_condition": (k55[41] >> (2*table)) & 3 if mode >= 4 else 0,
                           "alpha": alpha_level(k38, effect) if mode & 2 else 255})
    # Same reverse+stable-descending ordering as current GX pool, excluding layers.
    return sorted(reversed(result), key=lambda o: -o["order"])


def tiles(st, obj):
    ram, k46, k47 = st["SPRITERAM"], st["K46REGS"], st["K47REGS"]
    require(not k46[5] & 8, "Escape Kids half-width mode is outside Mystic scope")
    off = obj["offset_words"]; w0 = ram[off]; attr = ram[off+6]; code = obj["code"]
    xa = (code & 1) | ((code >> 1) & 2) | ((code >> 2) & 4)
    ya = ((code >> 1) & 1) | ((code >> 2) & 2) | ((code >> 3) & 4)
    code &= ~63
    oy, ox = ram[off+2] & 1023, ram[off+3] & 1023
    scale_y = ram[off+4] & 1023
    scale_x = scale_y if w0 & 0x4000 else ram[off+5] & 1023
    zy = (0x400000 + (scale_y >> 1)) // scale_y if scale_y else 0x800000
    zx = (0x400000 + (scale_x >> 1)) // scale_x if scale_x else 0x800000
    fx, fy = bool(w0 & 0x1000), bool(w0 & 0x2000)
    mx, my = bool(attr & 0x4000), bool(attr & 0x8000)
    if mx:
        fx = False
    if k46[5] & 1:
        ox = -ox
        if not mx:
            fx = not fx
    if k46[5] & 2:
        oy = -oy
        if not my:
            fy = not fy
    wrap, xlim, ylim = (512, 448, 384) if k47[6] & 64 else (1024, 640, 512)
    ox = (ox+DX-s16(k46[0]*256+k46[1])) & (wrap-1)
    oy = (-oy+DY-s16(k46[2]*256+k46[3])) & (wrap-1)
    if ox >= xlim:
        ox -= wrap
    if oy >= ylim:
        oy -= wrap
    size = (w0 >> 8) & 15; width, height = 1 << (size & 3), 1 << ((size >> 2) & 3)
    ox -= (zx*width) >> 13; oy -= (zy*height) >> 13
    for y in range(height):
        sy = oy+((zy*y+2048) >> 12)
        zh = oy+((zy*(y+1)+2048) >> 12)-sy
        for x in range(width):
            sx = ox+((zx*x+2048) >> 12)
            zw = ox+((zx*(x+1)+2048) >> 12)-sx
            flip_x = ((not fx) ^ ((x*2) < width)) if mx else fx
            flip_y = ((not fy) ^ ((y*2) >= height)) if my else fy
            column = width-1-x if flip_x else x
            row = height-1-y if flip_y else y
            tile = code + XO[(column+xa) & 7] + YO[(row+ya) & 7]
            if scale_x == scale_y == 64:
                zw = zh = 16
            yield tile, sx, sy, zw, zh, bool(flip_x), bool(flip_y)


def render(st, rom, decoder=pen5, old_priority=False, one_effect_bit=False):
    pool = objects(st, old_priority, one_effect_bit)
    n = W*H; pixels = [0]*n; orders = [[0, 0] for _ in range(n)]
    oz, sz, sp = [255]*n, [255]*n, [255]*n
    counts = Counter(); coverage = Counter(); cache = {}
    if not st["K55REGS"][45] & 16:
        return struct.pack("<"+str(n)+"Q", *pixels), b"\0"*(n*8), pool, {}
    for obj in pool:
        mode = obj["drawmode"]; z = obj["z"]; pri = obj["priority"]; alpha = obj["alpha"]
        if mode & 2:
            if alpha == 0:
                continue
            if alpha == 255:
                mode &= ~2
        for code, sx, sy, dw, dh, fx, fy in tiles(st, obj):
            coverage["tiles"] += 1
            if not dw or not dh or sx >= X0+W or sy >= Y0+H or sx+dw <= X0 or sy+dh <= Y0:
                continue
            coverage["visible_tiles"] += 1
            coverage["flip_x_tiles"] += fx; coverage["flip_y_tiles"] += fy
            coverage["zoomed_tiles"] += (dw, dh) != (16, 16)
            coverage["clipped_tiles"] += sx < X0 or sy < Y0 or sx+dw > X0+W or sy+dh > Y0+H
            code &= 0x7fff
            if code not in cache:
                cache[code] = [decoder(rom, code, y, x) for y in range(16) for x in range(16)]
            dx, dy = (16 << 19)//dw, (16 << 19)//dh
            mask = (15 if fx else 0) | (240 if fy else 0)
            for y in range(max(Y0, sy), min(Y0+H, sy+dh)):
                ry = ((y-sy)*dy) >> 19
                for x in range(max(X0, sx), min(X0+W, sx+dw)):
                    rx = ((x-sx)*dx) >> 19
                    pen = cache[code][(ry*16+rx) ^ mask]
                    at = (y-Y0)*W+x-X0
                    if mode < 4:
                        if not pen or (mode & 3 and pen >= 31) or oz[at] < z:
                            continue
                        oz[at] = z
                        value = ((obj["group"]*32+pen) | (1 << 12) | (pri << 13) |
                                 (obj["effect"] << 21) | (z << 23) | (pen << 50) | (mode << 55))
                        # Preserve the independent shadow candidate; no RGB/topmost composition here.
                        pixels[at] = (pixels[at] & (((1 << 50)-1) ^ ((1 << 31)-1) | (7 << 57))) | value
                        orders[at][0] = obj["order"]
                        counts["solid_writes"] += 1
                    else:
                        if pen < (1 if mode == 5 else 31) or sz[at] < z or sp[at] <= pri:
                            continue
                        sz[at], sp[at] = z, pri
                        value = ((1 << 31) | (obj["shadow_table"] << 32) | (pri << 34) | (z << 42) | (mode << 57))
                        shadowmask = (((1 << 50)-1) ^ ((1 << 31)-1)) | (7 << 57)
                        pixels[at] = (pixels[at] & ~shadowmask) | value
                        orders[at][1] = obj["order"]
                        counts["shadow_writes"] += 1
    for value in pixels:
        if value & (1 << 12):
            counts["opaque_pixels"] += 1
            counts[f"effect{(value >> 21) & 3}_pixels"] += 1
            counts[f"pen{(value >> 50) & 31}_pixels"] += 1
        if value & (1 << 31):
            counts["shadow_pixels"] += 1
            counts[f"table{(value >> 32) & 3}_pixels"] += 1
    return (struct.pack("<"+str(n)+"Q", *pixels),
            struct.pack("<"+str(n*2)+"I", *(v for pair in orders for v in pair)), pool,
            {"counts": dict(counts), "geometry": dict(coverage)})


def state_text(st, frame):
    return "FRAME " + str(frame) + "\n" + "\n".join(key+" "+" ".join(f"{v:04x}" for v in value) for key, value in st.items())+"\n"


def constructed(parent, full_shadow=False):
    st = {k: list(v) for k, v in parent.items()}; st["SPRITERAM"] = [0]*2048
    st["K46REGS"][5] = 0 if full_shadow else 32
    st["K47REGS"][6] = 0x81
    st["K55REGS"][41] = 0x3f  # immediate candidate semantics; no deferred layer filter
    st["K55REGS"][37:40] = [0x13, 0x4d, 0x85]  # Shadows retain arbitrary eight-bit priority.
    # Actual board fields, original ROM unchanged. Invert-alpha levels are 140.
    st["K38REGS"][13] = 14; st["K38REGS"][14] = 0x0e0e
    if full_shadow:
        st["K38REGS"][13] = 31  # effect1 -> alpha0, cull before pixel/Z writes
        st["K38REGS"][14] = 14  # effect2 -> alpha255, mode2 becomes mode0; pen31 solid
    def add(index, cx, cy, code, attr, flags=0, size=0, sx=64, sy=64, z=None):
        off = index*8
        offx = s16(st["K46REGS"][0]*256+st["K46REGS"][1])
        offy = s16(st["K46REGS"][2]*256+st["K46REGS"][3])
        st["SPRITERAM"][off:off+8] = [0x8000 | flags | (size << 8) | (index if z is None else z), code,
            (-cy+DY-offy) & 1023, (cx-DX+offx) & 1023, sy, sx, attr, 0]
    # First output pixel samples original pen16. Each effect code and flip present.
    add(0, 32, 24, 0x1f, 0x10)
    add(1, 64, 24, 0x38, 0x0200 | 0x21)
    for i in range(4):
        add(2+i, 100+i*48, 48, 0x1f, (i << 8) | (i << 5) | i, flags=i << 12)
    add(6, 48, 104, 0x1f if full_shadow else 0x38, 0x0400 | 0x40)
    add(7, 96, 104, 0x38, 0x0800 | 0x80)
    add(8, 144, 104, 0x38, 0x0c00 | 0xc0)
    add(9, 204, 112, 0x0140, 0x4020, size=5, sx=0x60, sy=0x30)
    add(10, 272, 112, 0x0140, 0x8040, size=5, flags=0x2000, sx=0x30, sy=0x60)
    add(11, 20, 172, 0x1f, 0x60, flags=0x1000)
    add(12, 316, 172, 0x1f, 0x80, flags=0x2000)
    add(13, 156, 244, 0x7fff, 0xa0)
    # Overlap: later equal-priority lower Z wins; distinct priority/Z exposed.
    add(14, 216, 192, 0x38, 0xe3, z=90)
    add(15, 216, 192, 0x1f, 0xe4, z=10)
    add(16, 264, 192, 0x1f, 0x00, flags=0x4000, sx=0x90, sy=0x50)
    return st


def edges(rom):
    comparisons = 0
    for code in (0x1f, 0x38, 0x140, 0x7fff):
        for y in range(16):
            for x in range(16):
                require(pen5(rom, code, y, x) == mame_layout_pen(rom, code, y, x), "GX layout decoder mismatch")
                comparisons += 1
    require(pen5(rom, 0x1f, 0, 0) == 16, "original pen16 fixture")
    require(pen5(rom, 0x38, 0, 1) == 31, "original pen31 fixture")
    require(0x400000+(0x7fff*16+15)*2+1 == len(rom)-1, "fifth plane EOF")
    a = [0]*32
    a[13] = 31; require(alpha_level(a, 1) == 0, "inverted alpha0")
    a[13] = 0; require(alpha_level(a, 1) == 255, "inverted alpha255")
    a[13] = 14; require(alpha_level(a, 1) == 140, "inverted alpha140")
    return {"separate_MAME_layout_comparisons": comparisons, "original_pen16": [31, 0, 0, 16],
            "original_pen31": [56, 0, 1, 31], "last_fifth_address": len(rom)-1,
            "last_fifth_byte": rom[-1], "inverted_alpha_values_checked": [0, 255, 140],
            "scope": "Original ROM; no RTL execution"}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--project-root", type=Path, required=True)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args(); root = args.project_root.resolve()
    out = args.output or root / "private/mystic-sprite-oracle"
    require(not out.exists(), "Preserve existing oracle: output directory already exists")
    for path, value in SOURCES.items():
        require(sha((root/path).read_bytes()) == value, "Pinned source changed: "+path)
    rp = root / "private/mystwarr-regions/k055673.bin"; rom = rp.read_bytes()
    require(len(rom) == 0x500000 and sha(rom) == ROM_SHA, "Original canonical sprite ROM changed")
    captures = [("scene-play1800", "play-01", 1800), ("scene-attract900", "scene-03", 900)]
    field_files = {"K46REGS": ("k46_regs", "<8B"), "K47REGS": ("k47_regs", "<16H"),
                   "K55REGS": ("k55_regs", "<128B"), "K38REGS": ("k38_regs", "<32H"),
                   "SPRITERAM": ("k47_list", "<2048H")}
    paths = [Path(__file__), rp, *(root/p for p in SOURCES)]
    for _, directory, frame in captures:
        paths += [root/"private/mystic-capture"/directory/f"f{frame:05d}-{name}.bin" for name, _ in field_files.values()]
    inputs = {str(p): sha(p.read_bytes()) for p in paths}
    scenes = []
    for label, directory, frame in captures:
        base = root/"private/mystic-capture"/directory
        st = {key: list(struct.unpack(fmt, (base/f"f{frame:05d}-{name}.bin").read_bytes())) for key, (name, fmt) in field_files.items()}
        scenes.append((label, st, frame, "original_capture", directory, []))
    parent = scenes[0][1]
    for full in (False, True):
        st = constructed(parent, full)
        delta = [{"field": k, "index": i, "before": a, "after": b}
                 for k in parent for i, (a, b) in enumerate(zip(parent[k], st[k])) if a != b]
        scenes.append(("scene-constructed-"+("full-shadow" if full else "effects"), st, 1800,
                       "constructed_legal_registers_original_ROM", "play-01", delta))
    out.mkdir(parents=True)
    report = {"schema": 1, "passed": False, "reviewer": "/root/research_mystic", "mame_commit": PIN,
              "scope": "Independent current-source sprite candidate model, not old RGB, final mixer or hardware qualification",
              "inputs_sha256": inputs, "edge_checks": edges(rom), "scenes": [], "limitations": LIMITS}
    for label, st, frame, kind, capture, delta in scenes:
        pix, orders, pool, summary = render(st, rom)
        scene = out/label; scene.mkdir()
        pp = scene/"pixels.bin"; pp.write_bytes(pix)
        op = scene/"orders.bin"; op.write_bytes(orders)
        sp = scene/"state.txt"; sp.write_text(state_text(st, frame))
        hp = scene/"header.json"
        header = {"schema": 1, "set": "mystwarr", "title": "Mystic Warriors (ver EAA)", "frame": frame,
                  "mame_commit": PIN, "profile_mystic": True, "source_kind": kind, "capture": capture,
                  "constructed_parent": "scene-play1800" if delta else None, "constructed_deltas": delta,
                  "width": W, "height": H, "visible_origin": [X0, Y0], "sprite_offsets": [DX, DY],
                  "dtype": "u64LE", "order": "row-major, x increasing", "bits": BITS,
                  "inactive_semantics": "All fields of absent solid/shadow are zero; independent candidates coexist",
                  "shadow_semantics": "Separate geometry/z candidate, no solid or tile/topmost occlusion or RGB application",
                  "alpha_semantics": "Current K338 invert_alpha(1) gating and drawmode normalization; raw 2-bit effect retained; RGB excluded",
                  "ordered_objects": pool, "summary": summary, "limitations": LIMITS,
                  "K55_mix_registers_33_36": st["K55REGS"][33:37],
                  "K38_blend_control_13_15": st["K38REGS"][13:16],
                  "effective_alpha_selectors_1_3": [alpha_level(st["K38REGS"], e) for e in (1, 2, 3)],
                  "orders_semantics": "Two u32LE per pixel: full solid order then shadow candidate order; absent=0",
                  "pixels_path": str(pp), "pixels_sha256": sha(pix), "orders_path": str(op), "orders_sha256": sha(orders),
                  "state_path": str(sp), "state_sha256": sha(sp.read_bytes()), "inputs_sha256": inputs}
        hp.write_text(json.dumps(header, indent=2)+"\n")
        report["scenes"].append({"scene": label, "source_kind": kind, "header_path": str(hp), "header_sha256": sha(hp.read_bytes()),
                                 "pixels_sha256": sha(pix), "orders_sha256": sha(orders), "objects": len(pool), **summary})
    original = scenes[0][1]; baseline = (out/scenes[0][0]/"pixels.bin").read_bytes()
    old4 = render(original, rom, decoder=lambda r, c, y, x: pen5(r, c, y, x) & 15)[0]
    oldpri = render(original, rom, old_priority=True)[0]
    cst = scenes[2][1]; candidate = (out/scenes[2][0]/"pixels.bin").read_bytes()
    effect1 = render(cst, rom, one_effect_bit=True)[0]
    differ = lambda a, b: sum(a[i:i+8] != b[i:i+8] for i in range(0, len(a), 8))
    mutations = {"old_4bpp_original_pixel_mismatches": differ(old4, baseline),
                 "old_0_220_priority_f0_original_pixel_mismatches": differ(oldpri, baseline),
                 "one_effect_bit_constructed_pixel_mismatches": differ(effect1, candidate)}
    require(all(mutations.values()), "Known-old mutation produced no mismatches")
    first = struct.unpack_from("<Q", candidate)[0]
    require(first & 4096 and (first >> 50) & 31 == 16, "First visible original pen16 opaque fixture")
    pixel = lambda data, x, y: struct.unpack_from("<Q", data, ((y-Y0)*W+x-X0)*8)[0]
    require(not pixel(candidate, 57, 16) & 4096, "partial alpha mode2 excludes original pen31")
    full = (out/scenes[3][0]/"pixels.bin").read_bytes()
    require(pixel(full, 57, 16) & 4096 and (pixel(full, 57, 16) >> 50) & 31 == 31,
            "alpha255 mode2 normalization must allow pen31")
    require(not pixel(full, 140, 40) & 4096, "alpha0 must cull effect1")
    require(pixel(full, 40, 96) & (1 << 31) and (pixel(full, 40, 96) >> 34) & 255 == 0x13,
            "full shadow must retain arbitrary priority for original pen16")
    report["constructed_pixel_assertions"] = ["first pen16 opaque", "alpha140 mode2 pen31 culled",
        "alpha255 mode2 pen31 opaque", "alpha0 effect1 culled", "full-shadow pen16 priority19"]
    report["negative_mutations"] = mutations
    report["inputs_unchanged"] = all(sha(Path(p).read_bytes()) == value for p, value in inputs.items())
    report["passed"] = report["inputs_unchanged"]
    report["hardware_verified"] = False; report["game_playable"] = False
    (WORKTREE/"evidence/m2-sprite-oracle.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps({"passed": report["passed"], "scenes": len(scenes), "pixels_per_scene": W*H, "negative_mutations": mutations}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
