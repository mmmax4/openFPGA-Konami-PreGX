# /root/verify_metam M4 extension of existing verify_mmio synthetic board fixture.
# Original script retained in frozen context; standalone synthetic instructions only.
import struct

def need(v,s):
 if not v:raise ValueError(s)

def build_board_program(path,expected,snapshot,profile,k38):
 """New synthetic CPU case: actual public board MMIO, never game-ROM editing."""
 image=bytearray(0x100000);work=0x600000 if profile==0 else 0x200000;marker=work+0xfff0;image[:8]=struct.pack('>II',work+0xfffc,0x100);pc=0x100;reads=[];snapshots=[]
 state=[[0]*n for n in [48,32,4,16,8,8,16,2,2]]+([[0]*8] if profile==3 else [])
 # k338,k46,k47,k252,sound,in0,in1,p12,p34,eep,irq,vram,pal,sprite.
 maps=[(0x48c000,0x430000,0x450010,0x486000,0x48a000,0x48e000,0x48e020,None,None,0x6a0000,0x6e0000,0x410000,0x420000,0x400000),
       (0x48a000,0x484000,0x482010,0x49c000,0x498000,0x496000,0x496002,0x494000,0x494002,0x490000,0x49a000,0x600000,0x700000,0x400000),
       (0x254000,0x240000,0x244010,0x260000,0x268000,0x278000,0x278002,0x274000,0x274002,0x27c000,0x264000,0x300000,0x330000,0x210000)]
 k338,k46,k47,k252,sound,in0,in1,p12,p34,eep,irq,vram,pal,sprite=maps[profile if profile<3 else 2]
 def emit(*values):
  nonlocal pc
  for v in values:image[pc:pc+2]=struct.pack('>H',v);pc+=2
 def write(a,v,byte=False):emit(0x13fc if byte else 0x33fc,v,a>>16,a&65535)
 def read(a,v,byte=False):emit(0x1039 if byte else 0x3039,a>>16,a&65535);reads.append(f'{a&~1:06x} {v:04x}\n')
 def mark(phase):
  write(marker,phase)
  for bank,values in enumerate(state):
   for index,value in enumerate(values):snapshots.append(f'{phase} {bank} {index} {value:04x}\n')
 # All K338 register words from original snapshot, then distinct original
 # high/low bytes. Real K338 has public outputs but no CPU readback here.
 for phase in [1,2,3]:
  for i in range(16):
   v=k38[(i+(phase-1)*3)%16]
   if phase==1:write(k338+i*2,v);state[3][i]=v
   elif phase==2:write(k338+i*2,v>>8,True);state[3][i]=(v&0xff00)|(state[3][i]&255)
   else:write(k338+i*2+1,v&255,True);state[3][i]=(state[3][i]&0xff00)|(v&255)
  for i in range(4):
   v=k38[(i+phase*2)%16]
   if phase==1:write(k46+i*2,v);state[4][2*i]=v>>8;state[4][2*i+1]=v&255
   elif phase==2:write(k46+i*2,v>>8,True);state[4][2*i]=v>>8
   else:write(k46+i*2+1,v&255,True);state[4][2*i+1]=v&255
  for bank,base,count in [(5,k47,8)]+([(6,0x460000,16),(7,0x484000,2)]if profile==0 else[]):
   for i in range(count):
    v=k38[(i+phase)%16]
    if phase==1:write(base+i*2,v);state[bank][i]=v
    elif phase==2:write(base+i*2,v>>8,True);state[bank][i]=(v&0xff00)|(state[bank][i]&255)
    else:write(base+i*2+1,v&255,True);state[bank][i]=(state[bank][i]&0xff00)|(v&255)
  if profile==0:write(0x6c0000,0xc100);state[8]=[1,3]
  mark(phase)
 # All synchronous ordinary memory sources: alternating targets and lanes;
 # sprite tests include scattered hardware and board shadow RAM.
 for base in [work+0x200,pal,pal+2,sprite,sprite+0x80,sprite+0x1000,vram]+([0x470000]if profile==0 else[]):
  write(base,0x5aa5);read(base,0x5aa5);write(base,0x3c,True);read(base,0x3ca5);write(base+1,0x69,True);read(base,0x3c69)
 if profile==0:
  for i,v in enumerate(state[6]):read(0x460000+i*2,v)
 # Timer byte file: high-byte writes ignored, low/full writes accepted.
 for i in range(16):
  a=k252+i*2;v=(k38[i]&255);write(a,v);read(a,v);write(a,0xa5,True);read(a,v);write(a+1,v^0x5a,True);read(a,v^0x5a)
 # Current input/DIP contract and EEPROM status; no serial EEPROM command is
 # issued, no save is mutated. eep_do/ready remain high while CS is low.
 read(in0,0x9a5c if profile==0 else 0x00db);read(in1,0xf700 if profile==0 else 0x00f7)
 read(in1,0xf700 if profile==0 else 0,True);read(in1+1,0xf73a if profile==0 else 0x00f7,True)
 if profile:read(p12,0x3c69);read(p34,0xa596)
 read(sound,0xa700 if profile==0 else 0x00a7);read(sound,0xa700 if profile==0 else 0,True);read(sound+1,0xa700 if profile==0 else 0x00a7,True)
 lane=0 if profile==0 else 1;write(sound+lane,0x6a,True);write(sound+1-lane,0x43,True);write(sound+2,0x5ca5);write(irq,0x0000)
 elane=0 if profile==1 else 1;write(eep+elane,7,True);write(eep+1-elane,0,True)
 # No active K550 command during register/lane qualification. Register0 high
 # byte is explicit known NOP0x87. Real commands/ownership remain in old cases.
 if profile==2:
  for i in range(32):
   a=0x25c000+i*2;v=(0x8700|(k38[0]&255))if i==0 else k38[i%16];write(a,v);read(a,v)
   hi=0x87 if i==0 else k38[(i+3)%16]>>8;write(a,hi,True);v=(hi<<8)|(v&255);read(a,v)
   lo=k38[(i+7)%16]&255;write(a+1,lo,True);v=(v&0xff00)|lo;read(a,v)
 # Nearby ignored words must read the existing zero contract, not become a
 # stale previous decoder hit. These are outside every consumer map.
 for a in [k338+0x20,k47+0x10,k252+0x20,in0-2,eep+2,irq+2,0x510040]:read(a,0)
 mark(4);write(marker,0xffff);emit(0x60fe);need(pc<0x80000,'Board fixture size');path.write_bytes(image);expected.write_text(''.join(reads));snapshot.write_text(''.join(snapshots))
 return {'program_bytes':pc,'marker_address':marker,'checkpoints':4,'registers_per_checkpoint':144 if profile==3 else 136,'K338_all16_lanes':True,'K550_all32_lanes_readback':profile==2,'expected_reads':len(reads),'scope':'Standalone constructed TG68K; original f04880 K338 words/bytes, real public board MMIO. EEPROM pins/status only, original save untouched. Gaia map/chr requests excluded because existing BFM cannot ACK them; shared selectors still exhaustive.'}

