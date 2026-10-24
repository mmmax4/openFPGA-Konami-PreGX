#!/usr/bin/env python3
"""Separate SD0EN-off Mystic full-shadow corners; frozen mixer oracle untouched."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
from types import SimpleNamespace

WORKTREE = Path(__file__).resolve().parents[1]
REFERENCE_SHA = "df2020d6e43dd7d110702a63d1d63a82f220fd5d5ffa8298b08bbbdb55340c5e"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(ok, text):
    if not ok:
        raise ValueError(text)


def parse_state(path):
    state = {"VRAM": [0]*(17*4096)}
    for line in Path(path).read_text().splitlines():
        fields = line.split()
        if fields[0] == "FRAME":
            continue
        if fields[0] == "VRAM":
            page = int(fields[1]); values = [int(v, 16) for v in fields[2:]]
            require(len(values) == 4096, "VRAM page size")
            state["VRAM"][page*4096:(page+1)*4096] = values
        else:
            state[fields[0]] = [int(v, 16) for v in fields[1:]]
    return state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(); root = args.project_root.resolve()
    out = args.output or root/"private/mystic-mixer-fullshadow"
    require(not out.exists(), "Preserve existing output; choose fresh private path")
    rp = WORKTREE/"tools/m2_mixer_reference.py"
    require(sha(rp) == REFERENCE_SHA, "Frozen full mixer reference changed")
    spec = importlib.util.spec_from_file_location("frozen_full_mixer", rp)
    ref = importlib.util.module_from_spec(spec); spec.loader.exec_module(ref)
    tile, sprite, rgb = [ref.load_module(name) for name in ref.MODULE_HASHES]
    hp = root/"private/mystic-mixer-oracle/scene-play1800/header.json"
    require(sha(hp) == "ca2807632508913cd6c737d55a95c1d6a96ba30000f86e38cf1f615a8e463c53", "Frozen original header changed")
    original = json.loads(hp.read_text())
    require(sha(original["state_path"]) == original["state_sha256"], "Frozen original state changed")
    parent = parse_state(original["state_path"])
    tr = Path(original["canonical_tile_ROM"]).read_bytes()
    sr = Path(original["canonical_sprite_ROM"]).read_bytes()
    require(hashlib.sha256(tr).hexdigest() == tile.ROM_SHA and hashlib.sha256(sr).hexdigest() == sprite.ROM_SHA,
            "Canonical original ROM changed")
    inputs = dict(original["inputs_sha256"])
    inputs.update({str(Path(__file__).resolve()): sha(Path(__file__)), str(hp): sha(hp),
                   original["state_path"]: sha(original["state_path"])})
    require(all(sha(path) == value for path, value in inputs.items()), "Frozen independent input changed")
    # Wrong model mirrors the finding, not any RTL: mode5 is falsely treated
    # as callback FULLSHADOW, forcing cond3 and losing deferred partition/gate.
    def wrong_objects(state):
        return [dict(obj, shadow_condition=3) if obj["drawmode"] == 5 else obj
                for obj in sprite.objects(state)]
    wrong_sprite = SimpleNamespace(objects=wrong_objects, tiles=sprite.tiles,
                                   pen5=sprite.pen5, alpha_level=sprite.alpha_level)
    report = {"schema": 1, "reviewer": "/root/research_mystic", "mame_commit": ref.PIN,
              "scope": "Separate original-ROM legal SD0EN-off/full-shadow fixture, static current-source RGB; no RTL/native compiler/hardware execution",
              "inputs_sha256": inputs, "passed": False, "scenes": [],
              "source_facts": {"mystwarr_v.cpp:89-95": "Mystic callback builds base|low5palette|effect; does not request K055555_FULLSHADOW",
                               "current_konamigx_v.cpp:537-544": "Callback FULLSHADOW flag creates mode5, table3 and host priority",
                               "current_konamigx_v.cpp:560-567": "Separate SD0EN-off shadowcode1 path also creates mode5, table0, without callback flag",
                               "current_konamigx_v.cpp:626-632": "Only color&K055555_FULLSHADOW forces condition3; otherwise K55SHD_PRI_SEL supplies condition, including mode5",
                               "sprite_cpp:438-443": "mode5 uses nonzero pens, threshold1, including original pen16"},
              "correction": "Earlier statement mode5 always implies condition3 was invalid for the Mystic SD0EN-off path. Callback flag and drawmode are distinct.",
              "numeric_fullshadow_macro": "Exact macro numeric value not needed/assumed; symbolic primary flag decision and absence in actual callback are retained."}
    out.mkdir(parents=True)
    for condition, priority in ((1, 16), (2, 32)):
        st = ref.constructed(parent)
        st["K46REGS"][5] &= ~32
        st["K55REGS"][37] = priority
        st["K55REGS"][41] = condition
        st["SPRITERAM"][3*8+1] = 0x1f  # Original pen16: full shadow, never maxpen-only.
        st["SPRITERAM"][4*8:5*8] = [0]*8  # Remove unrelated second partial shadow.
        objects = sprite.objects(st)
        full = [obj for obj in objects if obj["drawmode"] == 5]
        require(len(full) == 1 and full[0]["shadow_condition"] == condition and full[0]["shadow_table"] == 0,
                "Full-shadow primary metadata")
        require(sprite.pen5(sr, 0x1f, 0, 0) == 16, "Original nonmax pen16 fixture")
        packed, tile_stats, owners = tile.render(st["K56REGS"], st["K55REGS"], st["VRAM"], tr)
        values = struct.unpack("<"+str(4*ref.W*ref.H)+"H", packed)
        planes = [values[l*ref.W*ref.H:(l+1)*ref.W*ref.H] for l in range(4)]
        colors, stats, _, order, _ = ref.render(st, planes, sr, sprite, rgb)
        wrong, wrong_stats, wrong_pool, wrong_order, _ = ref.render(st, planes, sr, wrong_sprite, rgb)
        differences = [i for i, (a, b) in enumerate(zip(colors, wrong)) if a != b]
        require(differences, "Wrong forcecond3 model must differ")
        if condition == 1:
            require(stats["counts"].get("shadow_writes", 0) == 0 and stats["counts"].get("deferred_rejects", 0) > 0,
                    "Cond1 pri16 must reject against final top32")
        else:
            require(stats["counts"].get("shadow_condition2_writes", 0) == 256,
                    "Cond2 pri32 must accept all256 original nonzero full-shadow pixels")
        index = differences[0]
        scene = out/f"scene-cond{condition}"; scene.mkdir()
        state = scene/"state.txt"; state.write_text(ref.state_text(st, 1800))
        pixel = scene/"rgb.bin"; pixel.write_bytes(struct.pack("<"+str(ref.W*ref.H)+"I", *colors))
        pp = scene/"tile-planes.bin"; pp.write_bytes(packed)
        delta = {key: [{"index": i, "before": a, "after": b} for i, (a, b) in enumerate(zip(parent[key], st[key])) if a != b]
                 for key in st if key != "VRAM" and st[key] != parent[key]}
        delta["VRAM"] = {"range_words": [0, 65536], "step_words": 2, "write_attr": 8, "write_code": 64,
                         "scroll_page16_unchanged": True}
        checks = {"wrong_forcecond3_pixel_mismatches": len(differences),
                  "witness": {"x": ref.X0+index%ref.W, "y": ref.Y0+index//ref.W,
                              "expected_RGB": colors[index], "wrong_forcecond3_RGB": wrong[index]},
                  "original_pen": 16, "fullshadow_threshold": 1,
                  "correct_statistics": stats, "wrong_forcecond3_statistics": wrong_stats}
        header = {"schema": 1, "set": "mystwarr", "title": "Mystic Warriors (ver EAA)", "frame": 1800,
                  "capture": "play-01", "source_kind": "constructed_legal_SD0ENoff_fullshadow_original_ROM_palette",
                  "mame_commit": ref.PIN, "profile_mystic": True, "width": ref.W, "height": ref.H,
                  "visible_origin": [ref.X0, ref.Y0], "sprite_offsets": [-48, -24],
                  "dtype": "u32LE 0x00RRGGBB", "order": "row-major, x increasing", "pixels": ref.W*ref.H,
                  "pixels_path": str(pixel), "pixels_sha256": sha(pixel),
                  "state_path": str(state), "state_sha256": sha(state),
                  "tile_planes_path": str(pp), "tile_planes_sha256": sha(pp),
                  "tile_planes_format": "four layer-major u16LE, palette11:0,opaque12,category14:13",
                  "canonical_tile_ROM": original["canonical_tile_ROM"], "canonical_sprite_ROM": original["canonical_sprite_ROM"],
                  "state_semantics": original["state_semantics"], "backdrop_mode": original["backdrop_mode"],
                  "constructed_parent": str(hp), "constructed_deltas": delta,
                  "registers": {key: st[key] for key in original["registers"]},
                  "objects": objects, "global_paint_order": order, "tile_summaries": tile_stats, "page_owners": owners,
                  "fullshadow_case": {"SD0EN": False, "raw_shadow_code": 1, "callback_FULLSHADOW_flag": False,
                                      "mode": 5, "table": 0, "K55_condition": condition,
                                      "selected_shadow_priority": priority, "expected_deferred": True,
                                      "correct_raw_order": full[0]["order"], "correct_object": full[0],
                                      "wrong_forcecond3_objects": wrong_pool, "wrong_forcecond3_paint_order": wrong_order},
                  "statistics": stats, "constructed_checks": checks, "unsupported": ref.LIMITS,
                  "inputs_sha256": inputs, "hardware_verified": False, "game_playable": False}
        oh = scene/"header.json"; oh.write_text(json.dumps(header, indent=2)+"\n")
        report["scenes"].append({"scene": scene.name, "header_path": str(oh), "header_sha256": sha(oh),
                                  "pixels_sha256": sha(pixel), "condition": condition, "priority": priority,
                                  "fullshadow_object": full[0], "checks": checks})
        print(json.dumps({"scene": scene.name, "RGB_sha256": sha(pixel), "mismatches_wrong_forcecond3": len(differences),
                          "statistics": stats}), flush=True)
    require(all(sha(path) == value for path, value in inputs.items()), "Frozen original changed")
    report.update(passed=True, inputs_unchanged=True, hardware_verified=False, game_playable=False)
    (WORKTREE/"evidence/m2-fullshadow-oracle.json").write_text(json.dumps(report, indent=2)+"\n")
    (out/"manifest.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps({"passed": True, "scenes": 2, "frozen_existing_oracles_unchanged": True}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
