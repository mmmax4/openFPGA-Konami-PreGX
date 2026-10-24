#!/usr/bin/env python3
"""Deterministic ordered RGB arithmetic vectors from exact pinned MAME helpers.

No framebuffer, ROM decoder, Z, priority, shadow or RTL is consumed. Colours
are original captured palette entries or explicitly constructed boundary data.
"""
import argparse
import hashlib
from itertools import product
import json
from pathlib import Path
import struct

WORKTREE = Path(__file__).resolve().parents[1]
PIN = "76af2d6d907f0df822dca1d5146454cc5ee18294"
SOURCES = {
    "private/mame0220/current_drawgfx.h": "474e9f40615c96213fd295372faaf58c364d176848ee9cd9724553e3be7fa530",
    "private/mame0220/current_konamigx_v.cpp": "a56e198c8b5747f2c1553fbce72ed7f223398bf710d2da091fcae6c9dc346354",
    "ref/mame/k053246_k053247_k055673.cpp": "fc534b7b0e250b80a9706a99622a339f681fa49e5ad207bc027e410c6f9f1f27",
}
PALETTES = {
    "private/mystic-capture/play-01/f01800-palette.bin": "9fbd56bc07ffaa8b41f225f979754e8b8af5403fd1c2d0de155e9862e94cff01",
    "private/mystic-capture/scene-03/f00900-palette.bin": "ab983c68250a6fc6474c4bf78c29655e1b7d1786cac31754666f070589d5cd86",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def channels(rgb):
    return ((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)


def rgb(values):
    r, g, b = values
    return (r << 16) | (g << 8) | b


def helper_blend(dst, src, alpha):
    return rgb((s*alpha+d*(256-alpha)) >> 8
               for s, d in zip(channels(src), channels(dst)))


def helper_add(dst, src):
    return rgb(min(s+d, 255) for s, d in zip(channels(src), channels(dst)))


def evaluate(src, dst, level, is_tile):
    require(0 <= src <= 0xffffff and 0 <= dst <= 0xffffff, "RGB24 range")
    require(0 <= level < 1024 and is_tile in (0, 1), "control range")
    alpha, additive = level & 255, bool(level & 256)
    if additive:
        # GX tile scratch path uses (alpha+1); sprite helper uses alpha.
        scaled = (rgb((s*(alpha+1)) >> 8 for s in channels(src)) if is_tile
                  else helper_blend(0, src, alpha))
        return helper_add(dst, scaled)
    if level == 255 or (is_tile and alpha == 255):
        return src
    # Alpha0 returns dst. For sprites encoded512 preserves the alpha path,
    # but helper arithmetic still returns dst. MIXPRI has no implemented swap.
    return helper_blend(dst, src, alpha)


def packed_helpers(src, dst, level, is_tile):
    """Independent expression shape: literal masks/shifts in drawgfx.h."""
    a = level & 255
    def blend(d, s):
        return sum((((s & mask)*a+(d & mask)*(256-a)) >> 8) & mask
                   for mask in (0xff, 0xff00, 0xff0000))
    if level & 256:
        scaled = (sum((((src >> shift) & 255)*(a+1) >> 8) << shift
                      for shift in (0, 8, 16)) if is_tile else blend(0, src))
        return sum(min((dst & mask)+(scaled & mask), mask)
                   for mask in (0xff, 0xff00, 0xff0000))
    if level == 255 or (is_tile and a == 255):
        return src
    return blend(dst, src)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(); root = args.project_root.resolve()
    out = args.output or root/"private/m2-rgb-oracle"
    require(not out.exists(), "Preserve existing oracle; choose a fresh output")
    inputs = {str(Path(__file__)): sha(Path(__file__).read_bytes())}
    for relative, expected in {**SOURCES, **PALETTES}.items():
        path = root/relative; value = sha(path.read_bytes())
        require(value == expected, "Pinned source/capture changed: "+relative)
        inputs[str(path)] = value
    rows, groups, sequences = [], [], []
    def append(src, dst, level, tile):
        value = evaluate(src, dst, level, tile)
        require(value == packed_helpers(src, dst, level, tile), "Channel/packed helper mismatch")
        rows.append((src, dst, level, tile, value))
        return value
    colors = [rgb(v) for v in product((0, 1, 254, 255), repeat=3)]
    first = len(rows)
    for i, src in enumerate(colors):
        for dst in (0, 0xffffff, colors[63-i], colors[(i*17+11) % 64]):
            for a, flags, tile in product((0, 140, 255), (0, 256, 512, 768), (0, 1)):
                append(src, dst, a+flags, tile)
    groups.append({"name": "constructed_channel_boundaries", "first": first, "count": len(rows)-first,
                   "source_kind": "constructed", "channel_values": [0, 1, 254, 255]})
    palettes = []
    for relative in PALETTES:
        data = (root/relative).read_bytes(); require(len(data) == 8192, "Palette size")
        words = struct.unpack("<4096H", data)
        values = [((words[2*i] & 255) << 16) | words[2*i+1] for i in range(2048)]
        palettes.append(values)
        first = len(rows); pairs = []
        for i in range(12):
            si, di = i, (i*97+33) % 2048
            pairs.append({"src_index": si, "dst_index": di})
            for a, flags, tile in product((0, 140, 255), (0, 256, 512, 768), (0, 1)):
                append(values[si], values[di], a+flags, tile)
        groups.append({"name": relative, "first": first, "count": len(rows)-first,
                       "source_kind": "original_palette_RGB_constructed_controls", "pairs": pairs})
    def sequence(name, sources, background, kind):
        first = len(rows); dst = background
        for src in sources:
            dst = append(src, dst, 140, 0)
        omitted = []
        for skip in range(len(sources)):
            value = background
            for i, src in enumerate(sources):
                if i != skip:
                    value = evaluate(src, value, 140, 0)
            require(value != dst, "Every sequence colour must contribute")
            omitted.append(value)
        sequences.append({"name": name, "first": first, "count": len(sources), "background": background,
                          "source_kind": kind, "expected_final": dst, "omit_each_final": omitted,
                          "semantics": "Each row dst equals previous row expected; caller may replay as ordered accumulator"})
    sequence("three_constructed_alpha_RGB_contributors", [0xff0000, 0x00ff00, 0x0000ff], 0,
             "constructed_RGB_and_order")
    sequence("three_original_palette_RGB_contributors", [palettes[0][i] for i in (2, 6, 8)], palettes[0][0],
             "original_palette_RGB_constructed_order")
    require(evaluate(0xffffff, 0, 255, 0) == 0xffffff, "Exact255 opaque bypass")
    require(evaluate(0xffffff, 0, 767, 0) == 0xfefefe, "Sprite MIXPRI255 stays alpha")
    require(evaluate(0xffffff, 0, 767, 1) == 0xffffff, "Tile lowalpha255 copies")
    require(evaluate(0xffffff, 0, 396, 0) == 0x8b8b8b, "Sprite additive coefficient")
    require(evaluate(0xffffff, 0, 396, 1) == 0x8c8c8c, "Tile additive coefficient")
    mutations = {"sprite_additive_wrong_plus1": 0, "normal_blend_wrong_div255_roundnearest": 0,
                 "sprite_wrong_lowalpha255_copy": 0, "MIXPRI_wrong_operand_swap": 0}
    for src, dst, level, tile, expected in rows:
        a = level & 255
        if not tile and level & 256:
            wrong = helper_add(dst, rgb(s*(a+1) >> 8 for s in channels(src)))
            mutations["sprite_additive_wrong_plus1"] += wrong != expected
        if not level & 256 and a == 140:
            wrong = rgb((s*a+d*(255-a)+127)//255 for s, d in zip(channels(src), channels(dst)))
            mutations["normal_blend_wrong_div255_roundnearest"] += wrong != expected
        if not tile and level == 767:
            mutations["sprite_wrong_lowalpha255_copy"] += src != expected
        if level & 512:
            mutations["MIXPRI_wrong_operand_swap"] += evaluate(dst, src, level, tile) != expected
    require(all(mutations.values()), "Mutation not discriminated")
    out.mkdir(parents=True)
    vp = out/"vectors.txt"
    vp.write_text("".join(f"{s:06x} {d:06x} {level:03x} {tile:x} {expected:06x}\n"
                          for s, d, level, tile, expected in rows))
    header = {"schema": 1, "scope": "Ordered RGB arithmetic only; no Z, priorities, pens/ROM decoding, shadow, latency/deadline or physical-chip claim",
              "mame_commit": PIN, "dtype": "ASCII hexadecimal whitespace, five columns, no comment/header lines",
              "fields": ["src24", "dst24", "level10", "is_tile", "expected24"],
              "C_scan_format": "%x %x %x %x %x", "vector_count": len(rows),
              "vectors_path": str(vp), "vectors_sha256": sha(vp.read_bytes()), "groups": groups, "sequences": sequences,
              "normalization": "Exact level255 copies. Sprite level767 stays alpha path; tile lowalpha255 copies regardless MIXPRI. MIXPRI adds no operand swap.",
              "source_lines": {"current_drawgfx.h": [506, 511, 532, 537], "current_konamigx_v.cpp": [824, 867],
                               "k053246_k053247_k055673.cpp": [447, 450, 549, 567]}, "inputs_sha256": inputs}
    hp = out/"header.json"; hp.write_text(json.dumps(header, indent=2)+"\n")
    unchanged = all(sha(Path(path).read_bytes()) == digest for path, digest in inputs.items())
    require(unchanged, "Frozen input changed")
    report = {"schema": 1, "reviewer": "/root/research_mystic", "passed": True, "inputs_unchanged": unchanged,
              "inputs_sha256": inputs, "header_path": str(hp), "header_sha256": sha(hp.read_bytes()),
              "vectors_path": str(vp), "vectors_sha256": sha(vp.read_bytes()), "vector_count": len(rows),
              "independent_expression_comparisons": len(rows), "negative_mutations": mutations, "sequences": sequences,
              "scope": header["scope"], "hardware_verified": False, "RTL_execution": False,
              "palette_RGB_original": True, "arithmetic_controls_and_orders_constructed": True}
    (WORKTREE/"evidence/m2-rgb-oracle.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps({"passed": True, "vectors": len(rows), "negative_mutations": mutations, "sequences": len(sequences)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
