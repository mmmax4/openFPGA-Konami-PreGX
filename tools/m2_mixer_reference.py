#!/usr/bin/env python3
"""Full static Mystic RGB: primary-source global paint order, not front sprite LB.

Geometry/decode are imported from frozen independent oracles. No RTL, MAME RGB
capture, compiler, ROM patch or hardware behaviour is consumed/inferred.
"""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import struct

WORKTREE = Path(__file__).resolve().parents[1]
PIN = "76af2d6d907f0df822dca1d5146454cc5ee18294"
W, H, X0, Y0 = 288, 224, 24, 16
MODULE_HASHES = {
    "m2_tile_reference.py": "fb260491fc6b95e5c8dcaaf392bc00a20c8ac2d7146a8e89adbb067b38715ef3",
    "m2_sprite_reference.py": "3541fd51952b7e28f6563cf014d902ab120b54a267011e6b5594ff860ead83d9",
    "m2_rgb_reference.py": "0ca0ed4be567f0a54fbbb20226dab579363119535e6975fd1f5949ee6df12ac5",
}
LIMITS = ["Tile configurations rejected by frozen tile oracle (including actual row/linescroll0/2)",
          "Non255 selected brightness/contrast", "MIXPRI flag (physical meaning unknown, MAME unimplemented)",
          "GX WRPORT gradient/background-mode selection (Mystic fixed solid K338 backdrop here)",
          "Palette index outside original2048-entry region (no invented wrap)",
          "Non-Mystic callbacks/primode/ROZ layers", "Live midframe registers/palette writes",
          "Hardware memory/clock timing, streaming backpressure/deadlines and Pocket"]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(ok, msg):
    if not ok:
        raise ValueError(msg)


def load_module(name):
    path = WORKTREE/"tools"/name
    require(sha(path.read_bytes()) == MODULE_HASHES[name], "Frozen independent model changed: "+name)
    spec = importlib.util.spec_from_file_location(name[:-3], path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def verify_configuration(st):
    k55, k38 = st["K55REGS"], st["K38REGS"]
    require(not k38[15] & 2, "MIXPRI rejected: physical semantics unknown, not modeled")
    brightness = [k38[11] & 255, k38[12] >> 8, k38[12] & 255]
    for layer in range(4):
        selector = (k55[42] >> (layer*2)) & 3
        require(not selector or brightness[selector-1] == 255, "Unsupported non255 brightness")
    require(not k55[45] & 0xe0, "Unsupported non-Mystic extra layers")


def palette_rgb(st):
    words = st["PALETTE"]
    return [((words[i*2] & 255) << 16) | words[i*2+1] for i in range(2048)]


def shadow_rgb(value, table, st):
    result = 0
    for channel, shift in enumerate((16, 8, 0)):
        raw = st["K38REGS"][2+table*3+channel] & 511 if table != 3 else 432
        delta = raw-512 if raw & 256 else raw
        # Exact current dipalette.cpp299..345 clamps the delta first, even
        # when subsequent colour arithmetic uses wrap/noclip.
        delta = min(255, max(-255, delta))
        five = (value >> (shift+3)) & 31
        out = (five << 3) | (five >> 2)
        out += delta
        out = out & 255 if st["K38REGS"][15] & 32 else min(255, max(0, out))
        result |= out << shift
    return result


def sprite_pixels(st, obj, rom, sprite, cache):
    for code, sx, sy, width, height, fx, fy in sprite.tiles(st, obj):
        if not width or not height:
            continue
        if sx >= X0+W or sy >= Y0+H or sx+width <= X0 or sy+height <= Y0:
            continue
        code &= 32767
        if code not in cache:
            cache[code] = [sprite.pen5(rom, code, y, x) for y in range(16) for x in range(16)]
        dx, dy = (16 << 19)//width, (16 << 19)//height
        mask = (15 if fx else 0) | (240 if fy else 0)
        for y in range(max(Y0, sy), min(Y0+H, sy+height)):
            row = ((y-sy)*dy) >> 19
            for x in range(max(X0, sx), min(X0+W, sx+width)):
                column = ((x-sx)*dx) >> 19
                yield (y-Y0)*W+x-X0, cache[code][(row*16+column) ^ mask]


def tile_order(k55):
    # Exact six-layer <= sorting then reverse-insertion/pool-reversal. Mystic
    # omits SUB1/SUB2 later, but their priorities still participate in sorting.
    pri = [k55[i] for i in (7, 10, 13, 14, 16, 17)]; ids = list(range(6))
    for j in range(5):
        for i in range(j+1, 6):
            if pri[j] <= pri[i]:
                pri[j], pri[i] = pri[i], pri[j]; ids[j], ids[i] = ids[i], ids[j]
    return ids


def render(st, tile_planes, spr_rom, sprite, rgb, omit=(), defer=True):
    verify_configuration(st)
    k55, k38 = st["K55REGS"], st["K38REGS"]
    n = W*H; colors = [((k38[0] & 255) << 16) | k38[1]]*n
    top, zbuf, shdz, shdpri = [255]*n, [255]*n, [255]*n, [255]*n
    palette = palette_rgb(st); counts = Counter(); alpha_objects = [set() for _ in range(n)]
    objects = [o for o in sprite.objects(st) if o["object_index"] not in omit]
    normal, deferred = [], []
    # Sprite objects arrive already in the independent primary-order sort.
    # Tie key ensures normal sprites paint before tiles, including order0.
    for rank, obj in enumerate(objects):
        item = (obj["order"], 0, rank, "sprite", obj)
        if defer and obj["drawmode"] >= 4 and obj["shadow_condition"] in (1, 2):
            deferred.append(item)
        else:
            normal.append(item)
    layerpri = [k55[i] for i in (7, 10, 13, 14)]
    for rank, layer in enumerate(tile_order(k55)):
        if layer < 4:
            normal.append((layerpri[layer] << 24, 1, rank, "tile", layer))
    normal.sort(key=lambda event: (-event[0], event[1], event[2]))
    deferred.sort(key=lambda event: (-event[0], event[1], event[2]))
    public_order = [{"kind": e[3], "order": e[0], "layer": e[4] if e[3] == "tile" else None,
                     "object_index": e[4]["object_index"] if e[3] == "sprite" else None,
                     "deferred": e in deferred} for e in normal+deferred]
    if not k55[45] or not k38[15] & 1:
        return colors, {"counts": {}, "max_contributing_alpha_objects": 0}, objects, public_order, alpha_objects
    cache = {}
    for _, _, _, kind, value in normal+deferred:
        if kind == "tile":
            layer = value
            if not k55[45] & (1 << layer):
                continue
            mask = (k55[34] >> (2*layer)) & 3; internal = (k55[33] >> (2*layer)) & mask
            for at, packed in enumerate(tile_planes[layer]):
                if not packed & 4096:
                    continue
                category = (packed >> 13) & 3
                mix = (category & (~mask & 3)) | internal
                level = sprite.alpha_level(k38, mix)
                if not level & 256 and level & 255 == 0:
                    continue
                index = packed & 4095
                require(index < len(palette), "Tile palette outside original region")
                source = palette[index]
                colors[at] = source if level == 255 else rgb.evaluate(source, colors[at], level, 1)
                top[at] = layerpri[layer] if k55[40] & (1 << layer) else 255
                counts["tile_writes"] += 1; counts[f"tile_category{category}_writes"] += 1
            continue
        obj = value
        if not k55[45] & 16:
            continue
        mode, alpha = obj["drawmode"], obj["alpha"]
        if mode & 2:
            if alpha == 0:
                continue
            if alpha == 255:
                mode &= ~2
        for at, pen in sprite_pixels(st, obj, spr_rom, sprite, cache):
            if mode < 4:
                if not pen or (mode & 3 and pen >= 31) or zbuf[at] < obj["z"]:
                    continue
                zbuf[at] = obj["z"]; top[at] = obj["priority"]
                source = palette[obj["group"]*32+pen]
                colors[at] = rgb.evaluate(source, colors[at], alpha, 0) if mode & 2 else source
                if mode & 2:
                    alpha_objects[at].add(obj["object_index"])
                counts["sprite_writes"] += 1
                counts[f"effect{obj['effect']}_writes"] += 1
            else:
                threshold = 1 if mode == 5 else 31
                if pen < threshold or shdz[at] < obj["z"] or shdpri[at] <= obj["priority"]:
                    continue
                condition = obj["shadow_condition"]
                if defer and condition in (1, 2):
                    allowed = obj["priority"] == top[at] if condition == 2 else obj["priority"] > top[at]
                    if top[at] == 255 or not allowed:
                        counts["deferred_rejects"] += 1
                        continue
                shdz[at], shdpri[at] = obj["z"], obj["priority"]
                colors[at] = shadow_rgb(colors[at], obj["shadow_table"], st)
                counts["shadow_writes"] += 1; counts[f"shadow_condition{condition}_writes"] += 1
    return colors, {"counts": dict(counts), "max_contributing_alpha_objects": max(map(len, alpha_objects))}, objects, public_order, alpha_objects


def constructed(parent):
    st = {key: list(value) for key, value in parent.items()}
    st["SPRITERAM"] = [0]*2048
    st["K46REGS"][5] = 32; st["K47REGS"][6] = 0x81
    st["K55REGS"][7], st["K55REGS"][10], st["K55REGS"][13], st["K55REGS"][14] = 224, 160, 96, 32
    st["K55REGS"][33:35] = [0, 0]; st["K55REGS"][37:42] = [80, 32, 16, 15, 9]
    st["K55REGS"][45] = 31
    st["K38REGS"][13:16] = [14, 0x0e0e, 1]
    st["K38REGS"][2:11] = [v & 511 for v in (-16, -32, -48)*3]
    st["K56REGS"][3] = (st["K56REGS"][3] & ~192) | 192
    for at in range(0, 16*4096, 2):
        st["VRAM"][at:at+2] = [8, 0x40]  # legal category2/groupodd, original ROM
    offx = (st["K46REGS"][0] << 8) | st["K46REGS"][1]
    offy = (st["K46REGS"][2] << 8) | st["K46REGS"][3]
    def add(index, code, attr, z):
        st["SPRITERAM"][index*8:index*8+8] = [0x8000 | z, code,
            (-104-24-offy) & 1023, (120+48+offx) & 1023, 64, 64, attr, 0]
    add(0, 0x1f, 0x100 | 0xc0 | 1, 90)
    add(1, 0x1f, 0x200 | 0x80 | 2, 60)
    add(2, 0x1f, 0x300 | 0x40 | 3, 30)
    add(3, 0x38, 0x400 | 0xe0 | 4, 20)
    add(4, 0x38, 0x800 | 0xe0 | 5, 10)
    return st


def state_text(st, frame):
    lines = ["FRAME "+str(frame)]
    for key, values in st.items():
        if key != "VRAM":
            lines.append(key+" "+" ".join(f"{v:04x}" for v in values))
    for page in range(17):
        lines.append("VRAM "+str(page)+" "+" ".join(f"{v:04x}" for v in st["VRAM"][page*4096:(page+1)*4096]))
    return "\n".join(lines)+"\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(); root = args.project_root.resolve()
    out = args.output or root/"private/mystic-mixer-oracle"
    require(not out.exists(), "Preserve existing oracle; choose fresh output")
    tile, sprite, rgb = [load_module(name) for name in MODULE_HASHES]
    source_hashes = dict(sprite.SOURCES)
    source_hashes.update({"ref/mame/"+name: value for name, value in tile.SOURCES.items()})
    source_hashes.update({"private/mame0220/current_drawgfx.h": rgb.SOURCES["private/mame0220/current_drawgfx.h"],
                         "private/mame0220/current_dipalette.cpp": "58343b1dc046faf0d3d28ec0b760ea0850bf74a28a7044bff2dc4ef4d923d248"})
    for path, expected in source_hashes.items():
        require(sha((root/path).read_bytes()) == expected, "Pinned primary source changed: "+path)
    tp, sp = root/"private/mystwarr-regions/k056832.bin", root/"private/mystwarr-regions/k055673.bin"
    tr, sr = tp.read_bytes(), sp.read_bytes()
    require(sha(tr) == tile.ROM_SHA and sha(sr) == sprite.ROM_SHA, "Original canonical graphics changed")
    vector = root/"private/m2-rgb-oracle/vectors.txt"
    require(sha(vector.read_bytes()) == "c9a2458fc7dad0e2edd49f69bbc85635f5acda3cf55bdff016ecf96b6c977efd", "Frozen RGB vectors changed")
    cross = 0
    for line in vector.read_text().splitlines():
        src, dst, level, is_tile, expected = [int(v, 16) for v in line.split()]
        require(rgb.evaluate(src, dst, level, is_tile) == expected, "RGB scalar mismatch")
        cross += 1
    require(cross == 6726, "Missing RGB comparisons")
    fields = {"K46REGS": ("k46_regs", "<8B"), "K47REGS": ("k47_regs", "<16H"),
              "K55REGS": ("k55_regs", "<128B"), "K38REGS": ("k38_regs", "<32H"),
              "SPRITERAM": ("k47_list", "<2048H"), "K56REGS": ("k56_regs", "<32H"),
              "K56REGSB": ("k56_regsb", "<4H"), "VRAM": ("k56_vram", "<69632H"),
              "PALETTE": ("palette", "<4096H")}
    paths = [Path(__file__), tp, sp, vector, *(root/p for p in source_hashes),
             *(WORKTREE/"tools"/name for name in MODULE_HASHES)]
    scenes = []
    for name, directory, frame in (("scene-play1800", "play-01", 1800), ("scene-attract900", "scene-03", 900)):
        base = root/"private/mystic-capture"/directory; st = {}
        for key, (field, fmt) in fields.items():
            path = base/f"f{frame:05d}-{field}.bin"; paths.append(path)
            st[key] = list(struct.unpack(fmt, path.read_bytes()))
        scenes.append((name, directory, frame, "original_capture", st))
    scenes.append(("scene-constructed-alpha-shadow", "play-01", 1800,
                   "constructed_legal_registers_VRAM_objectRAM_original_ROM_palette", constructed(scenes[0][4])))
    inputs = {str(path): sha(path.read_bytes()) for path in paths}
    report = {"schema": 1, "reviewer": "/root/research_mystic", "mame_commit": PIN, "inputs_sha256": inputs,
              "scope": "Static full-frame current-source Mystic RGB model; procedural global pool, all original objects, not front-LB synthesis or historical MAME RGB golden",
              "passed": False, "RGB_scalar_crosschecks": cross, "scenes": [], "unsupported": LIMITS}
    out.mkdir(parents=True)
    for name, directory, frame, kind, st in scenes:
        packed, summaries, owners = tile.render(st["K56REGS"], st["K55REGS"], st["VRAM"], tr)
        values = struct.unpack("<"+str(4*W*H)+"H", packed)
        planes = [values[l*W*H:(l+1)*W*H] for l in range(4)]
        colors, stats, objects, draworder, contributors = render(st, planes, sr, sprite, rgb)
        checks = {}
        if kind != "original_capture":
            require(stats["max_contributing_alpha_objects"] >= 3, "Missing three accepted alpha objects")
            without = [render(st, planes, sr, sprite, rgb, omit=(index,))[0] for index in range(3)]
            witnesses = [i for i in range(W*H) if len(contributors[i]) >= 3 and all(v[i] != colors[i] for v in without)]
            require(witnesses, "All three alpha colours must affect the same final pixel")
            at = witnesses[0]
            immediate = render(st, planes, sr, sprite, rgb, defer=False)[0]
            bad_deferred = sum(a != b for a, b in zip(colors, immediate))
            require(bad_deferred and stats["counts"].get("shadow_condition1_writes", 0) and stats["counts"].get("shadow_condition2_writes", 0),
                    "Deferred shadow conditions must be observable")
            checks = {"three_alpha_final_pixel_witness": {"x": X0+at%W, "y": Y0+at//W, "RGB": colors[at],
                       "without_objects_0_1_2": [v[at] for v in without]},
                      "wrong_immediate_shadow_pixel_mismatches": bad_deferred,
                      "omit_each_alpha_object_pixel_mismatches": [sum(a != b for a, b in zip(colors, v)) for v in without]}
        scene = out/name; scene.mkdir()
        state = scene/"state.txt"; state.write_text(state_text(st, frame))
        pixels = scene/"rgb.bin"; pixels.write_bytes(struct.pack("<"+str(W*H)+"I", *colors))
        pp = scene/"tile-planes.bin"; pp.write_bytes(packed)
        deltas = None
        if kind != "original_capture":
            parent = scenes[0][4]
            deltas = {key: [{"index": i, "before": a, "after": b} for i, (a, b) in enumerate(zip(parent[key], st[key])) if a != b]
                      for key in st if key != "VRAM" and st[key] != parent[key]}
            deltas["VRAM"] = {"range_words": [0, 65536], "step_words": 2, "write_attr": 8, "write_code": 64,
                              "scroll_page16_unchanged": True}
        header = {"schema": 1, "set": "mystwarr", "title": "Mystic Warriors (ver EAA)", "frame": frame,
                  "capture": directory, "source_kind": kind, "mame_commit": PIN, "profile_mystic": True,
                  "width": W, "height": H, "visible_origin": [X0, Y0], "sprite_offsets": [-48, -24],
                  "dtype": "u32LE 0x00RRGGBB", "order": "row-major, x increasing", "pixels": W*H,
                  "pixels_path": str(pixels), "pixels_sha256": sha(pixels.read_bytes()),
                  "state_path": str(state), "state_sha256": sha(state.read_bytes()),
                  "tile_planes_path": str(pp), "tile_planes_sha256": sha(packed),
                  "tile_planes_format": "four layer-major u16LE planes, palette11:0,opaque12,category14:13",
                  "canonical_tile_ROM": str(tp), "canonical_sprite_ROM": str(sp),
                  "state_semantics": "u16LE captures expressed as hex words; SPRITERAM is internal2048word K47list; VRAM17pages; PALETTE4096words00RR/GGBB",
                  "backdrop_mode": "Mystic solid K338 background; no GX WRPORT override",
                  "constructed_parent": "scene-play1800" if deltas else None, "constructed_deltas": deltas,
                  "registers": {key: st[key] for key in ("K46REGS", "K47REGS", "K55REGS", "K38REGS", "K56REGS", "K56REGSB")},
                  "objects": objects, "global_paint_order": draworder, "tile_summaries": summaries, "page_owners": owners,
                  "statistics": stats, "constructed_checks": checks, "unsupported": LIMITS, "inputs_sha256": inputs,
                  "hardware_verified": False, "game_playable": False}
        hp = scene/"header.json"; hp.write_text(json.dumps(header, indent=2)+"\n")
        report["scenes"].append({"scene": name, "source_kind": kind, "header_path": str(hp), "header_sha256": sha(hp.read_bytes()),
                                  "pixels_sha256": sha(pixels.read_bytes()), "objects": len(objects), "statistics": stats,
                                  "constructed_checks": checks})
        print(json.dumps({"scene": name, "objects": len(objects), "RGB_sha256": sha(pixels.read_bytes()), "statistics": stats}), flush=True)
    report["inputs_unchanged"] = all(sha(Path(path).read_bytes()) == value for path, value in inputs.items())
    require(report["inputs_unchanged"], "Frozen original input changed")
    report["passed"] = True; report["hardware_verified"] = False; report["game_playable"] = False
    (WORKTREE/"evidence/m2-mixer-oracle.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps({"passed": True, "scenes": len(scenes), "pixels_per_scene": W*H, "RGB_scalar_crosschecks": cross}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
