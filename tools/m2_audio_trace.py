#!/usr/bin/env python3
"""Freeze bounded original Mystic PCM events for a later public-port gain gate.

This is data preparation, not an executed audio comparison. Frame-only timestamps
cannot establish exact sample phase. Never infer original hidden/reverb state
from register/position-latch snapshots.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT.parents[1]
ORIGINAL_IMAGE_SHA = 'cadcdcefa1a782435356f3aacacac4f79b5a48c05bb9872b7b0cba539d777808'


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, default=MAIN / 'private/mystic-audio-fixture')
    args = ap.parse_args()
    dest = args.output.resolve()
    if dest.exists():
        raise SystemExit('Never overwrite frozen data; use another output path')
    source = MAIN / 'private/mystic-capture/play-01'
    image = MAIN / 'private/mystwarr-m2-memory.rom'
    pcm = source / 'pcm-loaded.bin'
    if sha(image) != ORIGINAL_IMAGE_SHA:
        raise SystemExit('Original image identity mismatch')
    if pcm.read_bytes() != image.read_bytes()[0x4c0000:0x8c0000]:
        raise SystemExit('Captured PCM does not match original compact image')
    frames = (source / 'frames.txt').read_text()
    end = int(re.search(r'END frames=(\d+)', frames)[1])
    rows = []
    for line_number, line in enumerate((source / 'mame.log').read_text().splitlines(), 1):
        m = re.fullmatch(r'K539_WRITE (\d+) ([0-9A-F]+) ([0-9A-F]+)', line)
        if not m:
            continue
        frame, address, value = int(m[1]), int(m[2], 16), int(m[3], 16)
        if not (0xe000 <= address <= 0xe22f or 0xe400 <= address <= 0xe62f) or value > 255:
            raise SystemExit('Invalid observed chip write')
        rows.append((frame, address, value, line_number))
    # Early self-test log has invalid frame labels, including labels beyond the
    # capture END bound. Keep the log immutable; select only declared bounded
    # late windows and validate all intervening labels/order, never repair them.
    first = next(i for i, row in enumerate(rows) if row[0] == 724)
    late = rows[first:]
    if any(not 724 <= row[0] <= end for row in late):
        raise SystemExit('Late event timestamp outside observed frame range')
    if any(a[0] > b[0] for a, b in zip(late, late[1:])):
        raise SystemExit('Late event timestamps are not monotonic')
    dest.mkdir(parents=True)
    inputs = {str(p): sha(p) for p in (Path(__file__).resolve(), image, pcm,
              source / 'mame.log', source / 'frames.txt', MAIN / 'tools/capture_mystic.lua')}
    report = dict(schema=1, reviewer='lead', scope='Original-data preparation only; zero DUT audio comparisons executed.',
                  source_capture='Historical MAME0.220 play-01; original unmodified ROM/PCM.',
                  timing='Frame labels only. Intra-frame replay spacing must be declared constructed; no exact-cycle/original-waveform claim.',
                  hidden_state='Snapshots contain registers and position latches, not reverb RAM, interpolation/DPCM history or timer phase. A future public-port cold reconstruction is a bounded model experiment.',
                  original_pcm_path=str(pcm), original_pcm_sha256=sha(pcm),
                  excluded_early_timestamp_rows=sum(row[0] > end for row in rows[:first]),
                  windows=[], inputs_sha256=inputs, hardware_verified=False, audio_qualified=False)
    for seed, start, stop in ((724, 725, 740), (1800, 1801, 1810)):
        selected = [row for row in late if start <= row[0] <= stop]
        if not selected or {row[0] for row in selected} != set(range(start, stop + 1)):
            raise SystemExit('Zero comparisons/events or a missing selected event frame')
        prefix = f'f{seed:05d}'
        target = dest / prefix
        target.mkdir()
        artifacts = {}
        for chip in (1, 2):
            for kind, length in (('regs', 560), ('pos_latch', 24)):
                p = source / f'{prefix}-k539_{chip}_{kind}.bin'
                if p.stat().st_size != length:
                    raise SystemExit('Snapshot length mismatch')
                inputs[str(p)] = sha(p)
                q = target / p.name
                q.write_bytes(p.read_bytes())
                artifacts[str(q)] = sha(q)
        event_file = target / 'events.tsv'
        event_file.write_text('# frame chip offset_hex byte_hex original_log_line\n' + ''.join(
            f'{f}\t{1 if a < 0xe400 else 2}\t{a & 0x3ff:03x}\t{v:02x}\t{line}\n'
            for f, a, v, line in selected))
        artifacts[str(event_file)] = sha(event_file)
        report['windows'].append(dict(seed_frame=seed, first_frame=start, last_frame=stop,
                                      events=len(selected), events_per_chip=[sum((a < 0xe400) == (c == 1) for _, a, _, _ in selected) for c in (1, 2)],
                                      artifacts_sha256=artifacts))
    report['inputs_unchanged'] = all(sha(Path(p)) == h for p, h in inputs.items())
    if not report['inputs_unchanged']:
        raise SystemExit('Input changed during preparation')
    manifest = dest / 'manifest.json'
    manifest.write_text(json.dumps(report, indent=2) + '\n')
    evidence = ROOT / 'evidence/m2-audio-trace.json'
    evidence.write_text(json.dumps(dict(manifest_path=str(manifest), manifest_sha256=sha(manifest),
        reviewer='lead', scope=report['scope'], windows=[{k: v for k, v in w.items() if k != 'artifacts_sha256'} for w in report['windows']],
        audio_qualified=False), indent=2) + '\n')
    print(evidence.read_text())


if __name__ == '__main__':
    main()
