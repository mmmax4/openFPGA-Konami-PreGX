#!/usr/bin/env python3
"""Independent inverse/ZIP audit of the compact Mystic memory image.

Does not import or execute the builder. Game data is read-only; negative
controls are separate in-memory copies passed through the same validator.
"""
import argparse
import hashlib
import json
import re
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PIN = "76af2d6d907f0df822dca1d5146454cc5ee18294"
REF_HASHES = {
    "mystwarr.cpp": "ece43729edea2dc86615fb96f19d0c3cc8fc93a8776fc38353e31a48235fec9a",
    "romload.cpp": "854873d6f1b33d1dd3614a219b4b744f8fefb11708c8389141157825599f275f",
    "romentry.h": "572a2d095ee86abafcc30e4df876e76d5a03d56d2add9d4b80dfb31835580a08",
}
SIZES = {"maincpu": 0x200000, "soundcpu": 0x40000, "k056832": 0x500000,
         "k055673": 0x500000, "gfx3": 0x40000, "k054539": 0x400000, "eeprom": 0x80}
RANGES = {"maincpu": (0, 0x200000), "soundcpu": (0x200000, 0x240000),
          "k056832": (0x240000, 0x4c0000), "k054539": (0x4c0000, 0x8c0000),
          "k055673": (0x8c0000, 0xdc0000), "eeprom": (0xdc0000, 0xdc0080)}
IMAGE_SIZE = 0xdc0080


class ReviewFailure(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise ReviewFailure(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def original_members(driver, archive):
    """Parse the pinned declarations, then audit every original ZIP member."""
    for name, expected in REF_HASHES.items():
        require(sha((driver.parent / name).read_bytes()) == expected, "pinned reference changed: " + name)
    text = driver.read_text()
    body = re.search(r"ROM_START\(\s*mystwarr\s*\)(.*?)ROM_END", text, re.S).group(1)
    declarations = re.findall(
        r'ROM_LOAD\w*\(\s*"([^"]+)"\s*,\s*0x[\da-fA-F]+\s*,\s*(0x[\da-fA-F]+)'
        r'\s*,\s*CRC\(([\da-f]{8})\)\s*SHA1\(([\da-f]{40})\)', body)
    require(len(declarations) == 17, "expected 17 original ROM declarations")
    require(re.search(r"ROM_RELOAD\(\s*0x20000\s*,\s*0x20000\s*\)", body), "sound reload directive absent")
    require("ROM_GROUPWORD | ROM_SKIP(3) | ROM_REVERSE" in text, "tile macro word/reverse contract changed")
    require("ROM_GROUPBYTE | ROM_SKIP(4)" in text, "tile macro fifth-plane contract changed")
    with zipfile.ZipFile(archive) as z:
        require(len(z.namelist()) == 17 and set(z.namelist()) == {d[0] for d in declarations}, "ZIP members/duplicates changed")
        members = {name: z.read(name) for name, *_ in declarations}
    for name, size, crc, digest in declarations:
        raw = members[name]
        require(len(raw) == int(size, 16), "ZIP length: " + name)
        require(f"{zlib.crc32(raw) & 0xffffffff:08x}" == crc, "ZIP CRC: " + name)
        require(hashlib.sha1(raw).hexdigest() == digest, "ZIP SHA1: " + name)
    return members


def decode_image(image):
    """Undo the transport without using the builder's forward row transform."""
    require(len(image) == IMAGE_SIZE, "compact image size/EOF mismatch")
    region = {name: image[lo:hi] for name, (lo, hi) in RANGES.items()}
    region["k056832"] += bytes(0x280000)
    packed = region["k055673"]
    sprite = bytearray(0x500000)
    # Transpose the ten byte lanes independently: eight four-plane lanes,
    # followed by the left/right fifth-plane bytes for every one of 0x80000 rows.
    for lane in range(8):
        sprite[lane:0x400000:8] = packed[lane::10]
    sprite[0x400000::2] = packed[8::10]
    sprite[0x400001::2] = packed[9::10]
    region["k055673"] = bytes(sprite)
    region["gfx3"] = bytes(0x40000)
    return region


def extract_members(region):
    """Inverse canonical MAME records directly to all 17 source files."""
    p, t, s = region["maincpu"], region["k056832"], region["k055673"]
    files = {"128eaa01.20f": p[:0x80000:2], "128eaa02.20g": p[1:0x80000:2],
             "128a03.19f": p[0x100000::2], "128a04.19g": p[0x100001::2],
             "128a05.6b": region["soundcpu"][:0x20000],
             "128a10.3h": t[4:0x280000:5], "128a12.12k": s[0x400000::2],
             "128a11.10k": s[0x400001::2], "128a06.2d": region["k054539"][:0x200000],
             "128a07.1d": region["k054539"][0x200000:], "mystwarr.nv": region["eeprom"]}
    for name, low, high in (("128a08.1h", 1, 0), ("128a09.1k", 3, 2)):
        member = bytearray(0x100000)
        member[::2], member[1::2] = t[low:0x280000:5], t[high:0x280000:5]
        files[name] = bytes(member)
    for lane, name in enumerate(("128a16.22k", "128a15.20k", "128a14.19k", "128a13.17k")):
        member = bytearray(0x100000)
        member[::2], member[1::2] = s[2*lane:0x400000:8], s[2*lane+1:0x400000:8]
        files[name] = bytes(member)
    return files


def validate_image(image, canonical, members):
    """The exact validator used for the real artifact and every mutation."""
    for name, size in SIZES.items():
        require(len(canonical[name]) == size, "canonical length: " + name)
    require(not any(canonical["k056832"][0x280000:]), "omitted tile tail must be erased00")
    require(not any(canonical["gfx3"]), "omitted gfx3 must be erased00")
    decoded = decode_image(image)
    for name in SIZES:
        require(decoded[name] == canonical[name], "inverse canonical mismatch: " + name)
    require(not any(decoded["maincpu"][0x80000:0x100000]), "main ROM hole not zero")
    require(decoded["soundcpu"][0x20000:] == members["128a05.6b"], "sound reload mismatch")
    extracted = extract_members(decoded)
    require(set(extracted) == set(members), "inverse member set mismatch")
    for name, expected in members.items():
        require(extracted[name] == expected, "inverse ZIP member mismatch: " + name)
    return decoded


def negative_controls(image, canonical, members):
    results = {}

    def reject(label, mutation, changed_canonical=None, detail=None):
        require(mutation != image or changed_canonical is not None, "negative fixture was a no-op: " + label)
        try:
            validate_image(mutation, canonical if changed_canonical is None else changed_canonical, members)
        except ReviewFailure as exc:
            results[label] = {"rejected": True, "reason": str(exc), "detail": detail}
        else:
            raise ReviewFailure("mutation accepted: " + label)

    # Choose demonstrably distinct original bytes; an all-zero word cannot
    # distinguish wrong ordering and must not count as a passing negative.
    spr = RANGES["k055673"][0]
    row = next(r for r in range(0x80000) if image[spr+10*r+8] != image[spr+10*r+9])
    changed = bytearray(image); at = spr+10*row+8
    changed[at], changed[at+1] = changed[at+1], changed[at]
    reject("sprite_fifth_pair_swapped", changed, detail={"row": row, "image_offset": at})
    tile = RANGES["k056832"][0]
    row = next(r for r in range(1, 0x80000, 2) if image[tile+5*r+3] != image[tile+5*r+4])
    changed = bytearray(image); at = tile+5*row+3
    changed[at], changed[at+1] = changed[at+1], changed[at]
    reject("tile_odd_row_fifth_misplaced", changed, detail={"row": row, "image_offset": at})
    for label, at in (("sprite_final_fifth_byte", 0xdc0000-1),
                      ("sound_reload_byte", 0x220000), ("main_hole_byte", 0x80000),
                      ("eeprom_final_byte", IMAGE_SIZE-1)):
        changed = bytearray(image); changed[at] ^= 1
        reject(label, changed, detail={"image_offset": at})
    reject("image_truncated_eeprom_eof", image[:-1])
    for label, name, at in (("nonzero_omitted_tile_tail", "k056832", 0x280000),
                            ("nonzero_omitted_gfx3", "gfx3", 0)):
        source = dict(canonical); raw = bytearray(source[name]); raw[at] = 1; source[name] = bytes(raw)
        reject(label, image, source, {"canonical_region": name, "offset": at})
    return results


def validate_manifests(meta, source_meta, image, canonical, args):
    require(meta.get("schema") == 1 and meta.get("status") == "built_for_m2_memory_component", "builder schema/status")
    for record in (meta, source_meta):
        require(record.get("set") == "mystwarr" and record.get("title") == "Mystic Warriors (ver EAA)", "manifest game/title")
        require(record.get("mame_commit") == PIN and record.get("driver_sha256") == REF_HASHES["mystwarr.cpp"], "manifest driver identity")
    require(source_meta.get("rotation") == "ROT0" and source_meta.get("unloaded_byte_fill") == 0, "canonical manifest fill/orientation")
    zip_hash = sha(args.rom_zip.read_bytes())
    require(meta.get("source_zip_sha256") == zip_hash == source_meta.get("zip_sha256"), "manifest original ZIP identity")
    require(meta.get("source_manifest_sha256") == sha(args.source_manifest.read_bytes()), "canonical manifest identity")
    require(meta.get("builder_sha256") == sha(args.builder.read_bytes()), "builder source identity")
    require(meta.get("image_path") == str(args.image.resolve()), "builder image path")
    require(meta.get("image_bytes") == len(image) and meta.get("image_sha256") == sha(image), "builder image size/hash")
    hashes = {name: sha(data) for name, data in canonical.items()}
    require(meta.get("source_regions_sha256") == hashes, "builder canonical region identities")
    require(set(source_meta.get("regions", {})) == set(SIZES), "canonical manifest region set")
    for name, data in canonical.items():
        entry = source_meta["regions"][name]
        require(entry.get("bytes") == len(data) and entry.get("sha256") == sha(data), "canonical manifest region: " + name)
    segments = []
    for name, (lo, hi) in RANGES.items():
        label = {"k056832": "tile_rows5", "k055673": "sprite_rows10"}.get(name, name)
        segments.append({"name": label, "offset": lo, "bytes": hi-lo, "sha256": sha(image[lo:hi])})
    require(meta.get("segments") == segments, "builder segment offsets/lengths/hashes")
    require(meta.get("sdram_word_bases") == {"tile": 0, "pcm": 0x140000, "sprite": 0x340000}, "SDRAM word bases")
    require(meta.get("omitted_erased_regions") == {"tile_tail": [0x280000, 0x500000], "gfx3": [0, 0x40000]}, "omitted-region metadata")
    require(meta.get("hardware_verified") is False and meta.get("game_playable") is False, "builder qualification scope")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", type=Path, required=True, help="original canonical region directory")
    ap.add_argument("--image", type=Path, required=True)
    ap.add_argument("--builder-evidence", type=Path, required=True)
    ap.add_argument("--builder", type=Path, default=ROOT / "scripts/build_m2_memory_image.py", help="hash binding only; never imported")
    ap.add_argument("--source-manifest", type=Path)
    ap.add_argument("--rom-zip", type=Path, required=True)
    ap.add_argument("--driver", type=Path, default=ROOT / "ref/mame/mystwarr.cpp")
    ap.add_argument("--output", type=Path, default=ROOT / "evidence/m2-memory-image-review.json")
    args = ap.parse_args()
    if args.source_manifest is None:
        args.source_manifest = args.source.resolve().parent.parent / "evidence/mystwarr-regions.json"
    inputs = [Path(__file__), args.image, args.builder_evidence, args.builder, args.source_manifest, args.rom_zip]
    inputs += [args.source / (name + ".bin") for name in SIZES]
    inputs += [args.driver.parent / name for name in REF_HASHES]
    before = {str(p.resolve()): sha(p.read_bytes()) for p in inputs}
    report = {"reviewer": "/root/research_mystic", "passed": False, "mame_commit": PIN,
              "scope": "Independent compact-image inverse, full-byte seven-canonical-region and all-17-original-ZIP-member checks. Packing only; no RTL loader/fetch, simulation, fit or physical qualification.",
              "inputs_sha256": before, "image_bytes": args.image.stat().st_size,
              "image_layout_byte_ranges": RANGES, "sdram_word_bases": {"tile": 0, "pcm": 0x140000, "sprite": 0x340000},
              "hardware_verified": False, "mystic_playable": False}
    try:
        members = original_members(args.driver, args.rom_zip)
        canonical = {name: (args.source / (name + ".bin")).read_bytes() for name in SIZES}
        image = args.image.read_bytes()
        decoded = validate_image(image, canonical, members)
        validate_manifests(json.loads(args.builder_evidence.read_text()), json.loads(args.source_manifest.read_text()), image, canonical, args)
        report["regions_sha256"] = {name: sha(data) for name, data in decoded.items()}
        report["original_members_roundtrip"] = {name: True for name in members}
        report["negative_controls"] = negative_controls(image, canonical, members)
        report["checks"] = {"all_seven_regions_full_byte_match": True, "all_17_members_inverse": True,
                            "pinned_driver_and_headers": True, "zip_crc32_sha1": True,
                            "sound_reload_and_main_hole": True, "tile_tail_and_gfx3_erased00": True,
                            "all_region_eof_bytes": all(decoded[name][-16:] == raw[-16:] for name, raw in canonical.items()),
                            "builder_and_source_manifests": True, "negative_controls_rejected": all(c["rejected"] for c in report["negative_controls"].values())}
        report["passed"] = all(report["checks"].values())
    except (ReviewFailure, OSError, ValueError, KeyError) as exc:
        report["error"] = str(exc)
    finally:
        report["inputs_unchanged"] = all(sha(Path(p).read_bytes()) == value for p, value in before.items())
        report["passed"] = report["passed"] and report["inputs_unchanged"]
        report["exit_code"] = 0 if report["passed"] else 1
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "error": report.get("error")}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
