#!/usr/bin/env python3
"""Add original frame1200 voice-active window without mutating frozen audio data."""
import copy
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT.parents[1]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    original = MAIN/'private/mystic-audio-fixture/manifest.json'
    assert sha(original)=='787261b42204adae64f23df9930927a793eb1127458d2cd9fccc77c2ad75e355'
    data=json.loads(original.read_text()); inputs=dict(data['inputs_sha256'])
    assert all(sha(Path(p))==h for p,h in inputs.items())
    dest=MAIN/'private/mystic-audio-fixture-allgains02';dest.mkdir(exist_ok=False)
    report=copy.deepcopy(data);report['windows']=[]
    for window in data['windows']:
        updated=copy.deepcopy(window);updated['artifacts_sha256']={}
        folder=dest/f"f{window['seed_frame']:05d}";folder.mkdir()
        for p,h in window['artifacts_sha256'].items():
            old=Path(p);assert sha(old)==h;inputs[p]=h
            target=folder/old.name;target.write_bytes(old.read_bytes())
            updated['artifacts_sha256'][str(target)]=sha(target)
        report['windows'].append(updated)
    source=MAIN/'private/mystic-capture/play-01';seed=1200;folder=dest/f'f{seed:05d}';folder.mkdir()
    artifacts={}
    for chip in (1,2):
        for kind,length in (('regs',560),('pos_latch',24)):
            p=source/f'f{seed:05d}-k539_{chip}_{kind}.bin';assert p.stat().st_size==length
            inputs[str(p)]=sha(p);target=folder/p.name;target.write_bytes(p.read_bytes());artifacts[str(target)]=sha(target)
    rows=[]
    for line_number,line in enumerate((source/'mame.log').read_text().splitlines(),1):
        m=re.fullmatch(r'K539_WRITE (\d+) ([0-9A-F]+) ([0-9A-F]+)',line)
        if m and 1201<=int(m[1])<=1216:
            frame,address,value=int(m[1]),int(m[2],16),int(m[3],16)
            assert (0xe000<=address<=0xe22f or 0xe400<=address<=0xe62f) and value<256
            rows.append((frame,1 if address<0xe400 else 2,address&0x3ff,value,line_number))
    assert len(rows)==507 and all(1201<=r[0]<=1216 for r in rows)
    assert all(a[0]<=b[0] for a,b in zip(rows,rows[1:]))
    p=folder/'events.tsv';p.write_text('# frame chip offset_hex byte_hex original_log_line\n'+''.join(f'{f}\t{c}\t{a:03x}\t{v:02x}\t{line}\n' for f,c,a,v,line in rows));artifacts[str(p)]=sha(p)
    active=[(folder/f'f{seed:05d}-k539_{c}_regs.bin').read_bytes()[0x22c] for c in (1,2)];cover=active.copy()
    for _,chip,address,value,_ in rows:
        c=chip-1
        if address==0x214:active[c]|=value
        if address==0x215:active[c]&=~value
        if address==0x22c:active[c]=value
        cover=[a|b for a,b in zip(cover,active)]
    assert cover[0]&0x7f==0x7f
    report['windows'].append(dict(seed_frame=seed,first_frame=1201,last_frame=1216,events=len(rows),
        events_per_chip=[sum(r[1]==c for r in rows) for c in (1,2)],active_union=cover,artifacts_sha256=artifacts))
    inputs[str(original)]=sha(original);inputs[str(Path(__file__).resolve())]=sha(Path(__file__))
    report.update(inputs_sha256=inputs,inputs_unchanged=all(sha(Path(p))==h for p,h in inputs.items()),
        scope='Original-data preparation only; extra1200 window exercises K1low gain, newly doubled ch4 and existing voice gain. Zero DUT comparisons from preparation.',
        parent_manifest=str(original),parent_manifest_sha256=sha(original),audio_qualified=False)
    assert report['inputs_unchanged']
    manifest=dest/'manifest.json';manifest.write_text(json.dumps(report,indent=2)+'\n')
    evidence=dict(reviewer='lead',manifest_path=str(manifest),manifest_sha256=sha(manifest),scope=report['scope'],
        windows=[{k:v for k,v in w.items() if k!='artifacts_sha256'} for w in report['windows']],audio_qualified=False)
    (ROOT/'evidence/m2-audio-allgains-data.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps(evidence,indent=2))


if __name__=='__main__':
    main()
