#!/usr/bin/env python3
"""Compare retained native RGB with original current-texture MAME PNGs.

Read-only review: preserves failed raw screen:pixels holdouts and never changes
captured state, ROM, RTL, native executable, or prior execution receipts.
"""
from pathlib import Path
import hashlib,json,re,struct,sys
DEV=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(DEV/'tools'))
import pngio
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 base=DEV/'build/verification/m4-video'
 result={'reviewer':'/root/verify_metam','native_execution_owner':'lead','scope':__doc__,'inputs_sha256':{str(Path(__file__)):sha(__file__),str(DEV/'tools/pngio.py'):sha(DEV/'tools/pngio.py')},'cases':[],'native_rerun':False,'hardware_verified':False}
 for frame,cap,job in [(600,'metamrph-reference/m4-attract01','rgb01'),(2400,'metamrph-reference/m4-attract01','rgb01'),(3000,'metamrph-reference/m4-attract01','rgb-rest01'),(3600,'metamrph-road-reference/m4-road-attract360-03','rgb-rest01')]:
  folder=DEV/'private'/cap;manifest=folder/'manifest.json';j=json.loads(manifest.read_text());assert j['complete'] and j['native_exit']==0 and j['inputs_unchanged'] and j['child_reaped']
  frames=folder/'frames.txt';assert sha(frames)==j['outputs_sha256']['frames.txt']
  captures=list(map(int,re.findall(r'^CAPTURE (\d+) ',frames.read_text(),re.M)));ordinal=captures.index(frame)
  rel=f'snap/metamrph/{ordinal:04d}.png';png=folder/rel;assert sha(png)==j['outputs_sha256'][rel]
  w,h,rgb=pngio.read(png);assert (w,h)==(288,224)
  expected=[(rgb[i]<<16)|(rgb[i+1]<<8)|rgb[i+2]for i in range(0,len(rgb),3)]
  name=f'f{frame:05d}-road35-mode0';native=base/job/(name+'.actual.rgb');source=base/job/(name+'.source.rgb');raw=base/'rgb01/data'/f'f{frame:05d}'/'pixels-current.bin'
  act=struct.unpack('<64512I',native.read_bytes());soft=struct.unpack('<64512I',source.read_bytes());old=struct.unpack('<64512I',raw.read_bytes())
  paths=[manifest,frames,png,native,source,raw,base/job/'manifest.json']
  result['inputs_sha256'].update({str(p):sha(p)for p in paths})
  result['cases'].append({'frame':frame,'capture_png_ordinal':ordinal,'original_png_path':str(png),'pixels':64512,'native_actual_vs_original_PNG_errors':sum(a!=b for a,b in zip(act,expected)),'native_source_vs_original_PNG_errors':sum(a!=b for a,b in zip(soft,expected)),'native_actual_vs_raw_getter_errors':sum(a!=(b&0xffffff)for a,b in zip(act,old))})
 result['all_four_original_PNG_holdouts_exact']=all(c['native_actual_vs_original_PNG_errors']==c['native_source_vs_original_PNG_errors']==0 for c in result['cases'])
 assert result['all_four_original_PNG_holdouts_exact']
 result['negative_raw_getter_results_preserved']=True
 audit=DEV/'private/metamorphic-phase-order-audit-20261107'
 result['research_source_audit_manifest_sha256']=sha(audit/'manifest.json')
 result['pinned_MAME_commit']='f34f02505e32c1993c6a782b6814232cbfc74e36'
 result['research_source_audit_reviewer']='/root/research_metam'
 result['phase_source_sha256']={str(audit/n):sha(audit/n)for n in ['video.cpp','screen.cpp','luaengine.cpp','emumem_het.cpp','luaengine_mem.cpp']}
 result['source_facts']={'post_render_callbacks':'video.cpp220 finish_screen_updates then frame_hook227 then MACHINE_NOTIFY_FRAME258','raw_getter':'screen.cpp1493/1495 reads m_bitmap[m_curbitmap]','display_texture_flip':'screen.cpp1793..1795 select current bitmap texture then m_curbitmap=1-m_curbitmap','tap_order':'emumem_het.cpp57..62 tap before write handler; Lua nil return retains write data'}
 out=DEV/'evidence/m4-video-original-png-independent-review.json';out.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result['cases'],indent=2))
if __name__=='__main__':main()
