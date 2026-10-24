#!/usr/bin/env python3
"""Verify original ZIP members against the pinned MAME ROM declarations.

Read-only with respect to ROMs; records metadata/hashes, never ROM bytes.
Public evidence is a summary; exact member details stay under private/.
"""
import argparse
import hashlib
import json
import re
import sys
import zipfile
import zlib
from pathlib import Path

MAME_COMMIT = "76af2d6d907f0df822dca1d5146454cc5ee18294"
SOURCE_HASHES = {
    "mystwarr.cpp": "ece43729edea2dc86615fb96f19d0c3cc8fc93a8776fc38353e31a48235fec9a",
    "mystwarr.h": "0272bc6205ddc3c4529c2e670e35572d51a9fdeebad1f73bc3cfc79db11812a3",
    "mystwarr_v.cpp": "960e935ad8cf16e3e37d019f2a04a31942041a107a907023aa89434d386bc257",
    "k053246_k053247_k055673.cpp": "fc534b7b0e250b80a9706a99622a339f681fa49e5ad207bc027e410c6f9f1f27",
    "k054156_k054157_k056832.cpp": "39ed73342c569faa276d48561189d7900a88354b5a8261de3a78d06156b52091",
}
SETS = ("gaiapols", "mystwarr", "viostorm", "metamrph", "mtlchamp", "mmaulers")


def sha256_file(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def declarations(source, name):
    body = re.search(r"ROM_START\(\s*" + re.escape(name) + r"\s*\)(.*?)ROM_END", source, re.S)
    if not body:
        raise ValueError(f"ROM_START missing: {name}")
    title = re.search(r"GAME\(\s*\d+,\s*" + re.escape(name) + r"\s*,[^\n]*?\b(ROT\d+)\s*,\s*\"[^\"]+\"\s*,\s*\"([^\"]+)\"", source)
    if not title:
        raise ValueError(f"GAME title missing: {name}")
    entries, regions, region = [], [], None
    for line in body.group(1).splitlines():
        r = re.search(r'ROM_REGION\w*\(\s*(0x[0-9a-fA-F]+)\s*,\s*"([^\"]+)"', line)
        if r:
            region = r.group(2)
            regions.append({"name": region, "bytes": int(r.group(1), 16)})
        r = re.search(r'(ROM_LOAD\w*)\(\s*"([^\"]+)"\s*,\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)\s*,\s*CRC\(([0-9a-fA-F]{8})\)\s*SHA1\(([0-9a-fA-F]{40})\)', line)
        if r:
            method, filename, offset, size, crc, sha1 = r.groups()
            entries.append({"filename": filename, "region": region, "load_method": method,
                            "offset": int(offset, 16), "bytes": int(size, 16),
                            "crc32": crc.lower(), "sha1": sha1.lower()})
        elif "ROM_LOAD" in line:
            raise ValueError(f"Unparsed ROM declaration in {name}: {line}")
    if not entries:
        raise ValueError(f"Empty declarations for {name}")
    return title.group(2), title.group(1), regions, entries


def audit_zip(path, expected):
    checks, extra = [], []
    with zipfile.ZipFile(path) as archive:
        infos = [i for i in archive.infolist() if not i.is_dir()]
        names = [i.filename for i in infos]
        if len(names) != len(set(names)):
            raise ValueError(f"Duplicate ZIP member names: {path}")
        by_name = {i.filename: i for i in infos}
        for declaration in expected:
            name = declaration["filename"]
            check = {"expected": declaration}
            if name not in by_name:
                check.update(status="missing", actual=None)
            else:
                payload = archive.read(name)  # ZipFile also verifies stored CRC.
                actual = {"bytes": len(payload), "crc32": f"{zlib.crc32(payload) & 0xffffffff:08x}",
                          "sha1": hashlib.sha1(payload).hexdigest(),
                          "sha256": hashlib.sha256(payload).hexdigest()}
                check.update(actual=actual, status="pass" if all(actual[k] == declaration[k] for k in ("bytes", "crc32", "sha1")) else "mismatch")
            checks.append(check)
        required = {e["filename"] for e in expected}
        for name in names:
            if name not in required:
                payload = archive.read(name)
                extra.append({"filename": name, "bytes": len(payload),
                              "crc32": f"{zlib.crc32(payload) & 0xffffffff:08x}",
                              "sha1": hashlib.sha1(payload).hexdigest(),
                              "sha256": hashlib.sha256(payload).hexdigest()})
    return checks, extra


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rom-dir", type=Path, default=root / "roms")
    parser.add_argument("--source-dir", type=Path, default=root / "ref/mame")
    parser.add_argument("--summary", type=Path, default=root / "evidence/rom-audit.json")
    parser.add_argument("--details", type=Path, default=root / "private/rom-audit-details.json")
    parser.add_argument("--sets", nargs="+", choices=SETS, default=list(SETS))
    args = parser.parse_args()
    source_hashes = {name: sha256_file(args.source_dir / name) for name in SOURCE_HASHES}
    if source_hashes != SOURCE_HASHES:
        raise ValueError("MAME inputs changed; pin/review the new reference before auditing")
    source = (args.source_dir / "mystwarr.cpp").read_text()
    summary = {"schema": 1, "scope": "original ZIP ROM bytes vs MAME size/CRC32/SHA1; no FPGA support qualification",
               "reviewer": "research agent", "mame_commit": MAME_COMMIT,
               "mame_source_sha256": source_hashes, "sets": []}
    details = {"schema": 1, "mame_commit": MAME_COMMIT, "sets": []}
    failed = False
    for name in args.sets:
        title, orientation, regions, expected = declarations(source, name)
        path = args.rom_dir / f"{name}.zip"
        checks, extra = audit_zip(path, expected)
        passed = sum(c["status"] == "pass" for c in checks)
        ok = passed == len(expected)
        failed |= not ok
        item = {"set": name, "title": title, "orientation": orientation,
                "zip_bytes": path.stat().st_size, "zip_sha256": sha256_file(path),
                "required_members": len(expected), "verified_members": passed,
                "extra_members": len(extra), "status": "pass" if ok else "fail", "regions": regions}
        summary["sets"].append(item)
        details["sets"].append({**item, "members": checks, "extras": extra})
        print(f"{name}: {item['status']} {passed}/{len(expected)} size/CRC32/SHA1, {len(extra)} extra members")
    summary["status"] = "fail" if failed else "pass"
    for path, data in ((args.summary, summary), (args.details, details)):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + "\n")
    return int(failed)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        print(f"audit_roms: {error}", file=sys.stderr)
        sys.exit(2)
