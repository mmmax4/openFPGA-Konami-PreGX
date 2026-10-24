#!/usr/bin/env python3
"""Mystic per-layer tile oracle from original captures and pinned MAME source.

No RTL is imported/read, no historical MAME RGB bitmap is consumed. Supports
the actual captured XY configurations, retaining palette/category on pen0.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct

WORKTREE = Path(__file__).resolve().parents[1]
PIN = "76af2d6d907f0df822dca1d5146454cc5ee18294"
SOURCES = {"mystwarr.cpp": "ece43729edea2dc86615fb96f19d0c3cc8fc93a8776fc38353e31a48235fec9a",
           "mystwarr_v.cpp": "960e935ad8cf16e3e37d019f2a04a31942041a107a907023aa89434d386bc257",
           "k054156_k054157_k056832.cpp": "39ed73342c569faa276d48561189d7900a88354b5a8261de3a78d06156b52091"}
ROM_SHA = "8ec06bff6f73cb5bb03b1fd7f34ee477f28ddc5b9dabe288e5e456d7daf09977"
WIDTH, HEIGHT, ORIGIN_X, ORIGIN_Y = 288, 224, 24, 16
OFFSETS = (-5, -3, -1, 0)
SHIFT = ((6, 0x3f, 0, 0), (4, 0x0f, 2, 0x30), (2, 3, 2, 0x3c), (0, 0, 2, 0x3f))
UNSUPPORTED = ["line/rowscroll modes0/2", "global screen flip", "512x1 linemap tilemode",
               "three-page non-power-of-two spans", "disabled layer association/full4x4 map",
               "external/synchronous scroll timing", "forced-XY/mirror draw flags", "mixer/alpha/RGB composition"]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(ok, message):
    if not ok:
        raise ValueError(message)


def signed16(value):
    return value - 0x10000 if value & 0x8000 else value


def descriptor(regs, palettes, layer, attr):
    shift, mask1, shift2, mask2 = SHIFT[(regs[3] >> 6) & 3]
    flip = ((regs[1] >> (layer * 2)) & 3) & ((attr >> shift) & 3)
    normalized = (attr & mask1) | ((attr >> shift2) & mask2)
    # get_tile_info -> Mystic callback -> tileinfo.set/gfx colors128.
    group = ((palettes[23 + layer] << 4) | ((normalized >> 1) & 15)) % 128
    return group, (attr >> 2) & 3, flip


def pen5(rom, code, row, column):
    at = (code * 8 + row) * 5
    lower = (rom[at + column // 2] >> (4 if column % 2 == 0 else 0)) & 15
    return lower | (((rom[at + 4] >> (7-column)) & 1) << 4)


def planar_mame_pen(rom, code, row, column):
    """Separate byte-to-plane transpose + charlayout5, not the direct decoder."""
    at = (code * 8 + row) * 5
    planes = [0, 0, 0, 0]
    for x in range(8):
        nibble = (rom[at + x // 2] >> (4 * (1 - x % 2))) & 15
        for bit in range(4):
            planes[bit] |= ((nibble >> bit) & 1) << (7-x)
    # decode_tiles writes d3,d1,d2,d0,fifth; charlayout5 offsets32,24,8,16,0.
    converted = (planes[0], planes[2], planes[1], planes[3], rom[at+4])
    return sum(((converted[offset // 8] >> (7-column)) & 1) << (4-plane)
               for plane, offset in enumerate((32, 24, 8, 16, 0)))


def sample(rom, regs, palettes, layer, attr, code, x, y, decoder=pen5, palette_or=False):
    group, category, flip = descriptor(regs, palettes, layer, attr)
    sx, sy = (7-x if flip & 1 else x), (7-y if flip & 2 else y)
    pen = decoder(rom, code, sy, sx)
    palette = (group * 16) | pen if palette_or else group * 16 + pen
    require(palette <= 0xfff, "palette12 overflow")
    return palette | ((pen != 0) << 12) | (category << 13), pen, group, flip


def layout(regs):
    require(not (regs[0] & 0x30), "unsupported global screen flip")
    require(regs[4] & 15 == 15, "unsupported non-8x8 layer tilemode")
    layers, owners = [], [-1] * 16
    for layer in range(4):
        ry, cx = regs[8+layer], regs[12+layer]
        entry = {"rowstart": (ry >> 3) & 3, "rows": (ry & 3) + 1,
                 "colstart": (cx >> 3) & 3, "cols": (cx & 3) + 1,
                 "scrollmode": (regs[5] >> (2*layer)) & 3,
                 "dx": signed16(regs[20+layer]), "dy": signed16(regs[16+layer]),
                 "offset_x": OFFSETS[layer], "offset_y": 0}
        require(entry["scrollmode"] in (1, 3), "unsupported line/rowscroll mode")
        require(entry["rows"] in (1, 2, 4) and entry["cols"] in (1, 2, 4), "unsupported three-page span")
        require(not (entry["rowstart"] == entry["colstart"] == 0 and entry["rows"] == entry["cols"] == 4), "unsupported association disabled")
        layers.append(entry)
        for row in range(entry["rows"]):
            for col in range(entry["cols"]):
                owners[(((entry["rowstart"]+row) & 3) << 2) | ((entry["colstart"]+col) & 3)] = layer
    return layers, owners


def render(regs, palettes, vram, rom):
    layers, owners = layout(regs)
    packed, summaries = [], []
    for layer, cfg in enumerate(layers):
        categories, flips, pages = Counter(), Counter(), set()
        opaque = upper = old4 = old_or = 0
        plane = []
        for y in range(HEIGHT):
            # Power-of-two spans: this equals MAME's unsigned ay and page clip.
            sy = (ORIGIN_Y + y + cfg["dy"]) % (cfg["rows"] * 256)
            page_row = (cfg["rowstart"] + sy // 256) & 3
            for x in range(WIDTH):
                sx = (ORIGIN_X + x + cfg["dx"] - cfg["offset_x"]) % (cfg["cols"] * 512)
                page = (page_row << 2) | ((cfg["colstart"] + sx // 512) & 3)
                if owners[page] != layer:
                    plane.append(0)
                    continue
                index = page * 4096 + (((sy % 256) // 8) * 64 + ((sx % 512) // 8)) * 2
                attr, code = vram[index:index+2]
                value, pen, group, flip = sample(rom, regs, palettes, layer, attr, code, sx % 8, sy % 8)
                plane.append(value)
                opaque += pen != 0
                upper += pen >= 16
                old4 += pen >= 16
                old_or += (group * 16 + pen) != ((group * 16) | pen)
                categories[(attr >> 2) & 3] += 1
                flips[flip] += 1
                pages.add(page)
        packed.extend(plane)
        summaries.append({**cfg, "layer": layer, "opaque_pixels": opaque,
                          "pen5_high_pixels": upper, "known_old_4bpp_mismatches": old4,
                          "known_old_or_palette_mismatches": old_or,
                          "categories": dict(categories), "flips": dict(flips), "pages_used": sorted(pages)})
    return struct.pack("<" + str(len(packed)) + "H", *packed), summaries, owners


def edge_checks(rom, original_regs, palettes):
    generic = 0
    for code in (0, 0x40, 0x140, 0xffff):
        for y in range(8):
            for x in range(8):
                require(pen5(rom, code, y, x) == planar_mame_pen(rom, code, y, x), "MAME planar layout mismatch")
                generic += 1
    require(pen5(rom, 0x40, 0, 0) == 26, "original pen26 fixture")
    require(pen5(rom, 0x140, 1, 7) == 16, "original pen16 odd-row fixture")
    require((0xffff*8+7)*5+4 == 0x27ffff, "populated tile fifth EOF address")
    regs = list(original_regs); regs[3] = (regs[3] & ~0xc0) | 0xc0; regs[1] |= 3
    # Legal attr8 with fbits3: group is odd, category2; all source ROM bytes original.
    value, pen, group, _ = sample(rom, regs, palettes, 0, 8, 0x140, 7, 1)
    require(pen == 16 and group % 2 == 1 and value & 0x1000 and value >> 13 == 2, "palette/category/opacity fixture")
    lower_decoder = lambda data, code, y, x: pen5(data, code, y, x) & 15
    old4 = sample(rom, regs, palettes, 0, 8, 0x140, 7, 1, decoder=lower_decoder)[0]
    old_or = sample(rom, regs, palettes, 0, 8, 0x140, 7, 1, palette_or=True)[0]
    require(old4 != value and old_or != value, "known-old decoder mutation was not rejected")
    flips = 0
    for fbits in range(4):
        regs[3] = (regs[3] & ~0xc0) | (fbits << 6)
        for bits in range(4):
            for override in range(4):
                regs[1] = (regs[1] & ~3) | override
                attr = bits << SHIFT[fbits][0]
                _, actual, _, flags = sample(rom, regs, palettes, 0, attr, 0x40, 1, 2)
                expected_flags = bits & override
                expected = planar_mame_pen(rom, 0x40, 5 if expected_flags & 2 else 2, 6 if expected_flags & 1 else 1)
                require(flags == expected_flags and actual == expected, "FBIT/flip override fixture")
                flips += 1
    return {"planar_layout_original_pixels": generic, "original_pen26": True, "original_pen16_opaque": True,
            "odd_row_byte_address": 0x3205, "populated_fifth_eof": 0x27ffff,
            "eof_original_pen": pen5(rom, 0xffff, 7, 7), "legal_register_attribute_fixture": {"attr": 8, "fbits": 3, "packed": value},
            "flip_override_cases": flips, "known_old_4bpp_rejected": old4 != value,
            "known_old_palette_or_rejected": old_or != value, "scope": "Original ROM pixels with legal constructed register/attribute edge cases; no RTL consumer test."}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--project-root", type=Path, required=True)
    ap.add_argument("--output", type=Path)
    args = ap.parse_args(); root = args.project_root.resolve()
    out = args.output or root / "private/mystic-tile-oracle"
    require(not out.exists(), "oracle output already exists; preserve prior evidence")
    sources = {name: root / "ref/mame" / name for name in SOURCES}
    for name, path in sources.items():
        require(digest(path.read_bytes()) == SOURCES[name], "pinned MAME source changed: " + name)
    rom_path = root / "private/mystwarr-regions/k056832.bin"
    rom = rom_path.read_bytes(); require(digest(rom) == ROM_SHA, "original canonical tile ROM changed")
    captures = (("scene-play1800", "play-01", 1800), ("scene-attract900", "scene-03", 900))
    paths = [Path(__file__), rom_path, *sources.values()]
    for _, directory, frame in captures:
        paths += [root / "private/mystic-capture" / directory / f"f{frame:05d}-{name}.bin"
                  for name in ("k56_regs", "k56_regsb", "k56_vram", "k55_regs")]
    before = {str(p): digest(p.read_bytes()) for p in paths}
    report = {"passed": False, "reviewer": "/root/research_mystic", "mame_commit": PIN,
              "scope": "Current-source per-layer Mystic tile palette/opacity/category oracle from original historical capture inputs, not old-MAME RGB or a game qualification.",
              "inputs_sha256": before, "unsupported_configurations": UNSUPPORTED, "scenes": []}
    out.mkdir(parents=True)
    for label, directory, frame in captures:
        base = root / "private/mystic-capture" / directory
        read = lambda name: (base / f"f{frame:05d}-{name}.bin").read_bytes()
        regs = struct.unpack("<32H", read("k56_regs")); regsb = struct.unpack("<4H", read("k56_regsb"))
        vram = struct.unpack("<69632H", read("k56_vram")); palettes = read("k55_regs")
        require(len(palettes) == 128, "K55 capture size")
        pixels, summaries, owners = render(regs, palettes, vram, rom)
        require(len(pixels) == 4*WIDTH*HEIGHT*2, "oracle payload length")
        edges = edge_checks(rom, regs, palettes)
        scene = out / label; scene.mkdir()
        pixel_path = scene / "pixels.bin"; pixel_path.write_bytes(pixels)
        state = ["FRAME " + str(frame), "K56REGS " + " ".join(f"{v:04x}" for v in regs),
                 "K56REGSB " + " ".join(f"{v:04x}" for v in regsb), "K55REGS " + " ".join(f"{v:04x}" for v in palettes)]
        state += ["VRAM " + str(p) + " " + " ".join(f"{v:04x}" for v in vram[p*4096:(p+1)*4096]) for p in range(17)]
        state_path = scene / "state.txt"; state_path.write_text("\n".join(state) + "\n")
        header = {"schema": 1, "set": "mystwarr", "title": "Mystic Warriors (ver EAA)", "frame": frame,
                  "capture": directory, "mame_commit": PIN, "profile_mystic": True,
                  "width": WIDTH, "height": HEIGHT, "visible_origin": [ORIGIN_X, ORIGIN_Y], "layers": 4,
                  "order": "layer-major, row-major, x increasing", "dtype": "u16LE",
                  "bits": {"palette": [0, 11], "opaque": 12, "category": [13, 14], "zero": 15},
                  "transparent_semantics": "palette and category retained even for pen0; only opaque is cleared. Unassociated pages emit zero.",
                  "k55_layer_enables_applied": False, "unsupported_configurations": UNSUPPORTED,
                  "layers_config_and_counts": summaries, "page_owners": owners, "edge_checks": edges,
                  "pixels_path": str(pixel_path), "pixels_sha256": digest(pixels),
                  "state_path": str(state_path), "state_sha256": digest(state_path.read_bytes()), "inputs_sha256": before}
        header_path = scene / "header.json"; header_path.write_text(json.dumps(header, indent=2) + "\n")
        report["scenes"].append({"scene": label, "header_path": str(header_path), "header_sha256": digest(header_path.read_bytes()),
                                  "pixels_sha256": digest(pixels), "pixels": 4*WIDTH*HEIGHT, "edge_checks": edges})
    report["inputs_unchanged"] = all(digest(Path(p).read_bytes()) == value for p, value in before.items())
    report["passed"] = report["inputs_unchanged"]
    report["hardware_verified"] = False; report["game_playable"] = False
    (WORKTREE / "evidence/m2-tile-oracle.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "scenes": [s["scene"] for s in report["scenes"]], "pixels_per_scene": 4*WIDTH*HEIGHT}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
