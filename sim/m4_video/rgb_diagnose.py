#!/usr/bin/env python3
"""Read-only finite original RGB diagnostics. Shifted outputs are hypotheses, never repaired game data."""
from pathlib import Path
import json,struct,hashlib,itertools,time
DEV=Path(__file__).resolve().parents[2];O=DEV/'build/verification/m4-video/rgb01'
W,H=288,224;N=W*H
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def u16(p):b=p.read_bytes();return struct.unpack('<'+'H'*(len(b)//2),b)
def u32(p):b=p.read_bytes();return tuple(x&0xffffff for x in struct.unpack('<'+'I'*(len(b)//4),b))
def main():
 result={'reviewer':'/root/verify_metam','scope':__doc__,'native_RTL_rerun':False,'inputs_sha256':{},'scenes':{}}
 for prefix in ['f00600','f02400','f03000','f03600']:
  p=O/'data'/prefix
  files={n:p/n for n in ['tiles-reference.bin','palette.bin','k55_regs.bin','k38_regs.bin','k56_regs.bin','pixels-current.bin']}
  result['inputs_sha256'].update({str(x):sha(x)for x in files.values()})
  tile=u16(files['tiles-reference.bin']);pal=u16(files['palette.bin']);r55=files['k55_regs.bin'].read_bytes();r38=u16(files['k38_regs.bin']);r56=u16(files['k56_regs.bin']);mame=u32(files['pixels-current.bin']);palette=[((pal[2*i]&255)<<16)|pal[2*i+1]for i in range(2048)]
  colors=[[palette[v&2047]if v!=65535 else -1 for v in tile[l*N:(l+1)*N]]for l in range(4)]
  brightness=[]
  for l in range(4):
   s=(r55[42]>>(2*l))&3;f=255 if not s else r38[11]&255 if s==1 else r38[12]>>8 if s==2 else r38[12]&255;brightness.append(f)
   if f!=255:colors[l]=[sum(((((c>>b)&255)*f)>>8)<<b for b in [0,8,16]) if c>=0 else -1 for c in colors[l]]
  priority=[r55[i]for i in [7,10,13,14]];order=sorted([l for l in range(4)if r55[45]&(1<<l)],key=lambda l:(-priority[l],-l))
  alpha=[]
  for l in range(4):
   e=((r55[33]>>(2*l))&3)&((r55[34]>>(2*l))&3);v=0 if not e else r38[13]&255 if e==1 else r38[14]>>8 if e==2 else r38[14]&255;n=(v&31) if(v&32) else 31-(v&31);alpha.append(255 if not e else(n<<3)|(n>>2))
  background=((r38[0]&255)<<16)|r38[1];cache={}
  def render(dx=(0,0,0,0),dy=(0,0,0,0),alphas=None,ordering=None):
   out=[background]*N
   for l in order if ordering is None else ordering:
    a=(alpha if alphas is None else alphas)[l]
    if not a:continue
    for y in range(H):
     sy=y+dy[l]
     if sy<0 or sy>=H:continue
     for x in range(W):
      sx=x+dx[l]
      if sx<0 or sx>=W:continue
      src=colors[l][sy*W+sx]
      if src<0:continue
      at=y*W+x
      if a==255:out[at]=src;continue
      key=(src,out[at],a)
      if key not in cache:cache[key]=sum(((((src>>s)&255)*a+((out[at]>>s)&255)*(256-a))>>8)<<s for s in [0,8,16])
      out[at]=cache[key]
   return out
  def metrics(v):
   bad=[i for i,(a,b)in enumerate(zip(v,mame))if a!=b]
   return {'full_errors':len(bad),'interior_errors':sum(2<=i%W<W-2 and 2<=i//W<H-2 for i in bad)}
  baseline=render();scene={'baseline':metrics(baseline),'alpha':alpha,'brightness':brightness,'priority':priority,'regsDX':list(r56[20:24]),'regsDY':list(r56[16:20]),'hypotheses':[]}
  if all(alpha[l]==255 and brightness[l]==255 for l in order):
   visible=[-1]*N
   for l in order:
    for i,pv in enumerate(tile[l*N:(l+1)*N]):
     if pv!=65535:visible[i]=pv&2047
   associations={}
   for pen,expected in zip(visible,mame):associations.setdefault(pen,set()).add(expected)
   scene['visible_pen_to_MAME']=[{'pen':pen,'source_RGB':background if pen<0 else palette[pen],'MAME_RGBs':sorted(expected),'pixels':visible.count(pen)} for pen,expected in sorted(associations.items())]
   scene['unique_MAME_color_per_visible_pen']=all(len(v)==1 for v in associations.values())
  native=O/(prefix+'-road35-mode0.source.rgb')
  if native.exists():scene['software_source_matches_native_source']=tuple(baseline)==u32(native);assert scene['software_source_matches_native_source']
  if scene['baseline']['full_errors']:
   for layer in range(4):
    for amount in [-2,-1,1,2]:
     dx=[0]*4;dx[layer]=amount;scene['hypotheses'].append({'layer':layer,'dx':amount,'dy':0,**metrics(render(dx=dx))})
    for amount in [-1,1]:
     dy=[0]*4;dy[layer]=amount;scene['hypotheses'].append({'layer':layer,'dx':0,'dy':amount,**metrics(render(dy=dy))})
   scene['hypotheses'].sort(key=lambda x:x['interior_errors']);scene['best_single_shift']=scene['hypotheses'][0]
   for amount in [-1,1]:
    aa=alpha[:];aa[1]=max(0,min(255,aa[1]+amount));scene['hypotheses'].append({'alpha_layer1':aa[1],**metrics(render(alphas=aa))})
   scene['reverse_paint_order']=metrics(render(ordering=list(reversed(order))))
   scene['all_paint_orders']=sorted([{'order':list(o),**metrics(render(ordering=o))}for o in itertools.permutations(order)],key=lambda x:x['full_errors'])
   scene['layer_hidden']=sorted([{'layer':l,**metrics(render(ordering=[o for o in order if o!=l]))}for l in order],key=lambda x:x['full_errors'])
  result['scenes'][prefix]=scene;print(prefix,scene['baseline'],'best',scene.get('best_single_shift'),flush=True)
 out=DEV/'build/verification/m4-video/rgb01-review';out.mkdir(exist_ok=True)
 result['script_sha256']=sha(Path(__file__));(out/'finite-hypotheses.json').write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
