#!/usr/bin/env python3
"""Small independent enable gate; no ROM, Quartus or long simulation."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/verification/tv80-enable'
BIN=ROOT/'build/toolchain/iverilog12/installed/bin'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    OUT.mkdir(parents=True,exist_ok=False)
    names=['sim/tb_tv80_enable.sv','sim/run_tv80_enable.py','rtl/clk_enables.sv',
           'modules/cpu-tv80/tv80s_cen.v','modules/cpu-tv80/tv80_core.v',
           'modules/cpu-tv80/tv80_reg.v','modules/cpu-tv80/tv80_alu.v','modules/cpu-tv80/tv80_mcode.v']
    frozen={p:sha(ROOT/p) for p in names}
    command=[str(BIN/'iverilog'),'-g2012','-s','tb_tv80_enable','-o',str(OUT/'test.vvp')]
    command +=[str(ROOT/p) for p in names if p.endswith(('.v','.sv'))]
    with (OUT/'compile.log').open('w') as log:
        cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=20)
    (OUT/'compile.exit').write_text(str(cp.returncode)+'\n')
    cases={}
    if cp.returncode==0:
        for label,gap in [('positive',8),('negative-assume-12',12)]:
            cmd=[str(BIN/'vvp'),str(OUT/'test.vvp'),f'+MIN_GAP={gap}']
            with (OUT/(label+'.log')).open('w') as log:
                r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=10)
            (OUT/(label+'.exit')).write_text(str(r.returncode)+'\n')
            cases[label]={'command':cmd,'exit':r.returncode,'log_sha256':sha(OUT/(label+'.log')),
                          'explicit_pass':'PASS actual TV80/CEN public enable hold' in (OUT/(label+'.log')).read_text()}
    unchanged=all(sha(ROOT/p)==h for p,h in frozen.items())
    passed=cp.returncode==0 and unchanged and cases['positive']['exit']==0 and cases['positive']['explicit_pass'] and cases['negative-assume-12']['exit']!=0
    record={'reviewer':'verification agent','passed':passed,'compile_command':command,'compile_exit':cp.returncode,
            'sources_sha256':frozen,'sources_unchanged':unchanged,'cases':cases,
            'scope':'Actual divider arbitrary resync and TV80 public-output holds only; synthetic NOP input, no game/audio qualification',
            'hardware_verified':False}
    (OUT/'manifest.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2));return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
