#!/usr/bin/env python3
"""Fail closed on every timing record at all four Pocket device corners.

Checks a report only; does not qualify an RBF, constraints or hardware.
"""
import json
from pathlib import Path
import re
import sys

REQUIRED = ('Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width')
EXPECTED_CORNERS = {'Slow 1100mV 85C', 'Slow 1100mV 0C',
                    'Fast 1100mV 85C', 'Fast 1100mV 0C'}


def check(path):
    summary = path.read_text()
    records = [{'type': kind, 'slack_ns': float(slack), 'tns_ns': float(tns)}
        for kind, slack, tns in re.findall(
            r'Type\s*:\s*(.+)\nSlack\s*:\s*([-+\d.]+)\nTNS\s*:\s*([-+\d.]+)', summary)]
    corners = set(re.findall(r'(Slow \d+mV \d+C|Fast \d+mV \d+C) Model', summary))
    if not records or not EXPECTED_CORNERS.issubset(corners):
        raise SystemExit('missing timing records or one of the four Pocket device corners')
    for corner in corners:
        for kind in REQUIRED:
            if not any(r['type'].startswith(f'{corner} Model {kind} ') for r in records):
                raise SystemExit(f'missing {kind} check at {corner}')
    if any(r['slack_ns'] < 0 or r['tns_ns'] < 0 for r in records):
        raise SystemExit('negative slack/TNS: timing summary fails')
    return records, corners


if __name__ == '__main__':
    records, corners = check(Path(sys.argv[1]))
    print(json.dumps({'scope': 'summary only; fit/constraints not qualified',
        'corners': sorted(corners), 'minimum_slack_ns': {
            k: min(r['slack_ns'] for r in records if f'Model {k} ' in r['type'])
            for k in REQUIRED}}, indent=2))
