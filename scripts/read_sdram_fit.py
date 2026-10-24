#!/usr/bin/env python3
"""Extract source-bound Quartus full_path DQ data; JSON to stdout, no mutations."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import sys


class ReviewError(ValueError):
    pass


def need(test, message):
    if not test:
        raise ReviewError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(path):
    return {"path": str(path), "sha256": sha(path)}


def rnd(number):
    return round(number, 3)


def close(a, b, message):
    need(abs(a - b) <= 0.0031, f"{message}: {a} != {b}")


def one(items, description):
    need(len(items) == 1, f"Expected one {description}, found {len(items)}")
    return items[0]


def cells(text):
    return [[c.strip() for c in line.strip().strip(';').split(';')]
            for line in text.splitlines() if line.lstrip().startswith(';')]


def block(text, start, end):
    need(text.count(start) == 1 and text.count(end) == 1,
         f"Missing/duplicate block {start} / {end}")
    return text.split(start, 1)[1].split(end, 1)[0]


def timing_rows(text):
    result = []
    for row in cells(text):
        if len(row) != 7:
            continue
        try:
            total, incr = float(row[0]), float(row[1])
        except ValueError:
            continue
        result.append({"total_ns": total, "increment_ns": incr, "rf": row[2],
                       "type": row[3], "fanout": row[4], "location": row[5],
                       "element": row[6]})
    return result


def label(rows, name):
    return one([r for r in rows if r["element"] == name], name)


def parse_report(path, row):
    text = path.read_text()
    bit, check = int(row['bit']), row['check']
    found = re.findall(r'Report Timing: Found (\d+) (setup|hold) paths', text)
    need(found == [('1', check)], f"Unexpected path count/type: {path}")
    need('-detail full_path' in text, f"Not a full_path report: {path}")
    need(re.search(rf"\b{row['model']}\s+{row['voltage']}mV\s+{row['temperature']}C Model",
                   text, re.I), f"Corner mismatch: {path}")
    summary = {v[0]: v[1] for v in cells(block(text, '; Path Summary', '; Statistics'))
               if len(v) == 2}
    need(summary.get('From Node') == f'dram_dq[{bit}]', f"Wrong source: {path}")
    need(re.search(rf'\|sdram_ctrl:[^|]+\|dq_in\[{bit}\]$', summary.get('To Node', '')),
         f"Wrong destination: {path}")
    need(summary.get('Launch Clock') == 'dram_clk', f"Wrong launch clock: {path}")
    arrival = timing_rows(block(text, '; Data Arrival Path', '; Data Required Path'))
    required = timing_rows(text.split('; Data Required Path', 1)[1])
    launch = label(arrival, 'launch edge time')
    launch_clock = label(arrival, 'clock path')
    capture = label(required, 'latch edge time')
    capture_clock = label(required, 'clock path')
    cppr = label(required, 'clock pessimism removed')
    uncertainty = label(required, 'clock uncertainty')
    external = one([v for v in arrival if v['type'] == 'iExt'], 'external input delay')
    data = label(arrival, 'data path')
    dq_d = one([v for v in arrival if v['element'].endswith(f'|dq_in[{bit}]|d')], 'DQ D pin')
    dq_clk = one([v for v in required if v['element'].endswith(f'|dq_in[{bit}]|clk')], 'DQ clock pin')
    dq_q = one([v for v in arrival if v['element'] == summary['To Node']], 'DQ data endpoint')
    clk_cell = one([v for v in required if v['element'] == summary['To Node'] and v['type'] == 'CELL'],
                   'DQ clock cell endpoint')
    need(label(arrival, 'source latency')['increment_ns'] == 0 and
         label(required, 'source latency')['increment_ns'] == 0, 'Nonzero source latency unsupported')
    stats = {v[0]: float(v[1]) for v in cells(block(text, '; Statistics', '; Data Arrival Path'))
             if len(v) == 7 and v[0] in ('Clock Skew', 'Data Delay', 'Setup Relationship', 'Hold Relationship')}
    slack = float(summary['Slack'])
    arrival_time, required_time = float(summary['Data Arrival Time']), float(summary['Data Required Time'])
    close(slack, float(row['slack_ns']), 'TSV/report slack')
    close(slack, (required_time - arrival_time) if check == 'setup' else (arrival_time - required_time),
          'Slack reconstruction')
    close(launch_clock['total_ns'], launch['total_ns'] + launch_clock['increment_ns'], 'Launch insertion')
    close(capture_clock['total_ns'], capture['total_ns'] + capture_clock['increment_ns'], 'Capture insertion')
    close(cppr['total_ns'], clk_cell['total_ns'] + cppr['increment_ns'], 'CPPR endpoint')
    close(capture_clock['total_ns'], cppr['total_ns'], 'Effective clock path')
    close(stats['Clock Skew'], capture_clock['increment_ns'] - launch_clock['increment_ns'], 'Effective skew')
    close(stats['Data Delay'], data['increment_ns'], 'Data path delay')
    close(arrival_time, launch_clock['total_ns'] + external['increment_ns'] + data['increment_ns'],
          'Arrival reconstruction')
    close(required_time, uncertainty['total_ns'] + required[-1]['increment_ns'], 'Required reconstruction')
    physical_skew = launch_clock['increment_ns'] - (dq_clk['total_ns'] - capture['total_ns'])
    equivalent_skew = -stats['Clock Skew']
    return {"corner": int(row['corner']), "model": row['model'], "voltage_mv": int(row['voltage']),
            "temperature_c": int(row['temperature']), "bit": bit, "check": check,
            "report": identity(path), "slack_ns": slack,
            "launch_edge_ns": launch['total_ns'], "latch_edge_ns": capture['total_ns'],
            "relationship_ns": stats[check.title() + ' Relationship'],
            "multicycle_setup_end": summary.get('Multicycle - Setup End'),
            "external_constraint_ns": external['increment_ns'], "external_transition": external['rf'],
            "data_arrival_ns": arrival_time, "data_required_ns": required_time,
            "raw_path": {"arrival": arrival, "required": required},
            "physical": {
                "launch_pin_insertion_ns": launch_clock['increment_ns'],
                "launch_pin_edge_ns": launch_clock['total_ns'],
                "capture_clk_pin_insertion_ns": rnd(dq_clk['total_ns'] - capture['total_ns']),
                "capture_clk_pin_edge_ns": dq_clk['total_ns'],
                "launch_minus_capture_clk_pin_ns": rnd(physical_skew),
                "input_pin_to_d_ns": rnd(dq_d['total_ns'] - external['total_ns']),
                "data_endpoint_cell_ns": dq_q['increment_ns'],
                "capture_endpoint_cell_ns": clk_cell['increment_ns']},
            "sta_equivalent": {
                "capture_endpoint_insertion_before_cppr_ns": rnd(clk_cell['total_ns'] - capture['total_ns']),
                "cppr_ns": cppr['increment_ns'],
                "capture_effective_insertion_ns": capture_clock['increment_ns'],
                "launch_minus_capture_effective_ns": rnd(equivalent_skew),
                "input_data_delay_ns": data['increment_ns'],
                "skew_plus_data_ns": rnd(equivalent_skew + data['increment_ns']),
                "uncertainty_increment_ns": uncertainty['increment_ns'],
                "endpoint_setup_or_hold_increment_ns": required[-1]['increment_ns']}}


def hash_by_basename(mapping, name):
    return one([value for key, value in mapping.items() if Path(key).name == name], f"manifest entry {name}")


def span(values):
    return {"min": min(values), "max": max(values)}


def summarize(paths):
    result = []
    for corner in sorted({p['corner'] for p in paths}):
        group = [p for p in paths if p['corner'] == corner]
        first = group[0]
        info = {k: first[k] for k in ('corner', 'model', 'voltage_mv', 'temperature_c')}
        info['checks'] = {}
        for check in ('setup', 'hold', 'combined'):
            selected = [p for p in group if check == 'combined' or p['check'] == check]
            fields = [('physical', key) for key in selected[0]['physical']] + [
                ('sta_equivalent', key) for key in selected[0]['sta_equivalent']]
            info['checks'][check] = {"count": len(selected), "slack_ns": span([p['slack_ns'] for p in selected]),
                **{family: {key: span([p[family][key] for p in selected])
                            for fam, key in fields if fam == family}
                   for family in ('physical', 'sta_equivalent')}}
        result.append(info)
    return result


def compare_bench(paths, manifest):
    ranges = manifest.get('fitted_clock_pad_ranges_ps', {})
    need(ranges, 'Bench manifest lacks fitted_clock_pad_ranges_ps')
    failures = []
    for p in paths:
        name = p['model'] + str(p['temperature_c'])
        need(name in ranges, f'Bench lacks corner {name}')
        skew, pad = ranges[name]
        for field, limits in [('launch_minus_capture_effective_ns', skew), ('input_data_delay_ns', pad)]:
            value = p['sta_equivalent'][field] * 1000
            if value < limits[0] - 0.01 or value > limits[1] + 0.01:
                failures.append({**{k: p[k] for k in ('corner', 'bit', 'check')},
                                 "field": field, "actual_ps": rnd(value), "bench_bounds_ps": limits})
    return {"representation": "sta_equivalent; includes cell/CPPR, not unique physical delays",
            "all_reported_values_covered": not failures, "outside_bounds": failures,
            "scope": "Interval coverage only; does not assert simulation PASS or equivalent pulse aperture"}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('report_dir', type=Path, help='directory containing paths.tsv and cornerN-dqNN-{setup,hold}.rpt')
    ap.add_argument('--scope', required=True, choices=('diagnostic-old', 'new-fit'))
    ap.add_argument('--audit-manifest', required=True, type=Path)
    ap.add_argument('--compile-manifest', type=Path)
    ap.add_argument('--artifact', type=Path, action='append', default=[], help='canonical RBF/SOF and fit.rpt; repeat')
    ap.add_argument('--bench-manifest', type=Path, help='optional frozen timed-bench manifest to check interval coverage')
    ap.add_argument('--expected-corners', type=int, default=4)
    args = ap.parse_args()
    audit = json.loads(args.audit_manifest.read_text())
    need(audit.get('build_mode') == 'audit-sdram' and audit.get('status') == 'passed' and
         audit.get('exit_code') == 0 and audit.get('inputs_unchanged') is True, 'Audit did not finish cleanly')
    audited_files = audit['review_outputs_after']
    tsv = args.report_dir / 'paths.tsv'
    need(sha(tsv) == hash_by_basename(audited_files, 'paths.tsv'), 'TSV/audit hash mismatch')
    with tsv.open(newline='') as stream:
        rows = list(csv.DictReader(stream, delimiter='\t'))
    keys = [(int(r['corner']), int(r['bit']), r['check']) for r in rows]
    expected = {(c, b, check) for c in range(args.expected_corners) for b in range(16) for check in ('setup', 'hold')}
    need(len(keys) == len(expected) and set(keys) == expected, 'Incomplete/duplicate corner-bit-check matrix')
    paths = []
    for row in rows:
        need(row['paths'] == '1', 'TSV path count must be one')
        report = args.report_dir / f"corner{row['corner']}-dq{int(row['bit']):02d}-{row['check']}.rpt"
        need(sha(report) == hash_by_basename(audited_files, report.name), f'Report/audit hash mismatch: {report}')
        paths.append(parse_report(report, row))
    binding = {"audit_manifest": identity(args.audit_manifest), "canonical_compile_bound": False,
               "artifacts": []}
    if args.compile_manifest:
        compile_record = json.loads(args.compile_manifest.read_text())
        need(compile_record.get('build_mode') == 'compile' and compile_record.get('status') == 'passed' and
             compile_record.get('exit_code') == 0 and compile_record.get('inputs_unchanged') is True,
             'Canonical compile did not finish cleanly')
        need(compile_record['inputs'] == audit['inputs'], 'Compile/audit source or constraint inputs differ')
        need(compile_record.get('finished_utc', '') <= audit.get('started_utc', ''), 'Audit predates compile completion')
        for artifact in args.artifact:
            digest = sha(artifact)
            need(digest == hash_by_basename(compile_record['artifacts_after'], artifact.name) ==
                 hash_by_basename(audit['artifacts_after'], artifact.name), f'Compile/audit/artifact mismatch: {artifact}')
            binding['artifacts'].append(identity(artifact))
        bound = any(p.suffix in ('.rbf', '.sof') for p in args.artifact) and any(
            p.name.endswith('.fit.rpt') for p in args.artifact)
        binding.update(compile_manifest=identity(args.compile_manifest), canonical_compile_bound=bound)
    need(args.scope != 'new-fit' or binding['canonical_compile_bound'],
         'new-fit requires matching clean compile manifest, actual RBF/SOF and fit.rpt')
    output = {"schema": "pregx-sdram-full-path-v1", "scope": args.scope,
              "reviewer": "research agent; extraction only", "extractor": identity(Path(__file__)),
              "provenance": binding, "paths_tsv": identity(tsv), "path_count": len(paths),
              "reported_dq_setup_hold_nonnegative": all(p['slack_ns'] >= 0 for p in paths),
              "full_fit_qualified": False, "hardware_verified": False,
              "corner_intervals_ns": summarize(paths), "paths": paths,
              "limitations": [
                  "Only the worst reported path per bit/check; not all transitions/paths or all timing checks.",
                  "Raw insertion includes common root-clock propagation; effective insertion includes endpoint cell and CPPR.",
                  "Independent min/max interval combinations are an envelope, not a single physical operating point.",
                  "D/Q register cell delay and CPPR cannot be treated as unique external wire propagation.",
                  "Board propagation and SDRAM tAC/tOH/tHZ are separate datasheet/board inputs, not extracted here.",
                  "A positive DQ gate does not qualify command/write/output paths, all clocks or the full fit."]}
    if args.bench_manifest:
        output['bench_comparison'] = {"manifest": identity(args.bench_manifest),
                                      **compare_bench(paths, json.loads(args.bench_manifest.read_text()))}
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ReviewError, KeyError, ValueError, OSError) as exc:
        print(f'SDRAM extraction failed: {exc}', file=sys.stderr)
        raise SystemExit(2)
