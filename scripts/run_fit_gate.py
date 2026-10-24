#!/usr/bin/env python3
"""Durable private build job. Native work survives the Codex/tool session.

The user service owns compile -> DQ audit -> extraction -> timing summary.
It never approves constraints/warnings, packages, installs, or edits sources.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
JOBS = ROOT / 'build/jobs'


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, data):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data, indent=2) + '\n')
    temp.replace(path)


def unit(label):
    return 'pregx-fit-' + label + '.service'


def stages():
    return [
        ('preflight-sta', ['bash', 'scripts/build.sh', 'sta']),
        ('preflight-summary', [sys.executable, 'scripts/timing_summary.py',
                               'projects/output_files/gaia_pocket.sta.summary']),
        ('compile', ['bash', 'scripts/build.sh', 'compile']),
        ('audit-sdram', ['bash', 'scripts/build.sh', 'audit-sdram']),
        ('extract-dq', [sys.executable, 'scripts/read_sdram_fit.py',
            'build/verification/sdram-timing', '--scope', 'new-fit',
            '--compile-manifest', 'build/verification/quartus-compile-inputs.json',
            '--audit-manifest', 'build/verification/quartus-audit-sdram-inputs.json',
            '--artifact', 'projects/output_files/gaia_pocket.rbf',
            '--artifact', 'projects/output_files/gaia_pocket.fit.rpt']),
        ('qualify-summary', [sys.executable, 'scripts/qualify_fit.py']),
    ]


def archive(job, record):
    """Keep a source-bound result even if a later job replaces canonical files."""
    files = []
    for name, mode in (('preflight-sta', 'sta'), ('compile', 'compile'), ('audit-sdram', 'audit-sdram')):
        if name == 'preflight-sta' and 'compile' in record['stages']:
            continue  # final compile supersedes preflight report files
        p = ROOT / ('build/verification/quartus-' + mode + '-inputs.json')
        if name not in record['stages']:
            continue
        stage = record['stages'][name]
        if not p.exists() or 'finished_utc' not in stage:
            continue
        files.append(p)
        manifest = json.loads(p.read_text())
        if not (stage['started_utc'] <= manifest.get('started_utc', '') <= stage['finished_utc']):
            record.setdefault('unbound_stage_manifests', []).append(name)
            files.pop()
            continue  # e.g. build.sh refused a held native lock before begin
        if name in ('compile', 'preflight-sta'):
            files += [ROOT / n for n in manifest['inputs']]
            files += [ROOT / n for n in manifest.get('artifacts_after', {})]
        else:
            files += [ROOT / n for n in manifest.get('review_outputs_after', {})]
    if record['stages'].get('qualify-summary', {}).get('exit_code') == 0:
        files.append(ROOT / 'evidence/gaiapolis-fit.json')
    hashes = {}
    for p in sorted(set(files)):
        if not p.is_file():
            continue
        relative = p.relative_to(ROOT)
        dest = job / 'snapshot' / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, dest)
        hashes[str(relative)] = sha(dest)
    record['snapshot_sha256'] = hashes


def run(job, record):
    # A second launcher cannot overlap the entire chain. Each Quartus stage
    # additionally uses build.sh's existing native-project lock.
    lock = (JOBS / 'fit-gate.lock').open('w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        record.update(state='failed', error='Another durable fit job owns the lock.', finished_utc=now())
        save(job / 'status.json', record)
        return 1
    record.update(state='running', started_utc=now(), pid=os.getpid())
    save(job / 'status.json', record)
    exit_code = 1
    try:
        for name, command in stages():
            if name.startswith('preflight-') and record.get('skip_preflight_because'):
                continue
            record['active_stage'] = name
            entry = {'command': command, 'started_utc': now(),
                     'log': str((job / (name + '.log')).relative_to(ROOT))}
            record['stages'][name] = entry
            save(job / 'status.json', record)
            with (job / (name + '.log')).open('wb') as output:
                result = subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                                        stdout=output, stderr=subprocess.STDOUT)
            entry.update(exit_code=result.returncode, finished_utc=now(),
                         log_sha256=sha(job / (name + '.log')))
            (job / (name + '.exit')).write_text(str(result.returncode) + '\n')
            save(job / 'status.json', record)
            if result.returncode:
                record.update(state='failed', next_step='Inspect failed stage and archived inputs; do not restart blindly.')
                exit_code = result.returncode
                break
        else:
            record.update(state='awaiting_review', next_step='Review all timing constraints/warnings and DQ bounds; then timed SDRAM gate and private package audit.')
            exit_code = 0
    except Exception as exc:
        record.update(state='failed', error=str(exc), next_step='Inspect service/status/logs; preserve inputs before repair.')
    finally:
        record.update(finished_utc=now(), orchestrator_unchanged=sha(Path(__file__)) == record['orchestrator_sha256'])
        try:
            archive(job, record)
        except Exception as exc:
            record.update(state='failed', archive_error=str(exc))
            exit_code = 1
        if not record['orchestrator_unchanged']:
            record.update(state='failed', error='Orchestrator changed while active.')
            exit_code = 1
        record['exit_code'] = exit_code
        save(job / 'status.json', record)
    return exit_code


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action', choices=('start', 'run', 'status'))
    ap.add_argument('label')
    ap.add_argument('--skip-preflight-because',
        help='Start only: record why the old fitted netlist cannot decide a new fit; final timing gate always remains required.')
    args = ap.parse_args()
    if args.skip_preflight_because and args.action != 'start':
        raise SystemExit('--skip-preflight-because is only valid for a new start')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,47}', args.label):
        raise SystemExit('Use a unique lowercase alphanumeric/hyphen label (max 48 characters).')
    job = JOBS / args.label
    status = job / 'status.json'
    if args.action == 'start':
        job.mkdir(parents=True, exist_ok=False)
        record = {'label': args.label, 'unit': unit(args.label), 'state': 'launch_requested',
                  'created_utc': now(), 'orchestrator_sha256': sha(Path(__file__)), 'stages': {},
                  'skip_preflight_because': args.skip_preflight_because,
                  'scope': 'Native fit/STA only. Simulation, independent review and physical Pocket qualification remain separate.'}
        save(status, record)
        env = os.environ.copy()
        runtime = Path('/run/user') / str(os.getuid())
        if not env.get('XDG_RUNTIME_DIR') and runtime.is_dir() and runtime.stat().st_uid == os.getuid():
            env['XDG_RUNTIME_DIR'] = str(runtime)
        result = subprocess.run(['systemd-run', '--user', '--no-block', '--collect',
            '--unit=' + unit(args.label), '--property=WorkingDirectory=' + str(ROOT),
            sys.executable, str(Path(__file__).resolve()), 'run', args.label],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
        (job / 'launch.log').write_text(result.stdout)
        if result.returncode:
            record.update(state='launch_failed', exit_code=result.returncode)
            save(status, record)
        print(result.stdout.strip())
        print('Checkpoint: ' + str(status))
        return result.returncode
    record = json.loads(status.read_text())
    if args.action == 'status':
        print(json.dumps({k: v for k, v in record.items() if k not in ('snapshot_sha256',)}, indent=2))
        return 0
    if record['state'] != 'launch_requested' or sha(Path(__file__)) != record['orchestrator_sha256']:
        raise SystemExit('Job already started or launcher changed; never resume by restarting it.')
    return run(job, record)


if __name__ == '__main__':
    raise SystemExit(main())
