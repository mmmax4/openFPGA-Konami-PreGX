// Bounded original-program board probe; no ROM patches or internal state writes.
#include "Vtb_m2_main_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <vector>
#include <string>
static Vtb_m2_main_top d;
static std::vector<unsigned char> image,tile,spr;
static std::vector<unsigned short> vram(65536,0);
static unsigned clocks=0,steps=0,pr=0,tr=0,sr=0,vr=0,vw=0,wrambus=0,mmio=0,eepedges=0,irq2edges=0,irq4edges=0;
static unsigned pt=0,tt=0,st=0,vt=0,pa=0,ta=0,sa=0,va=0,vdata=0,vbe=0;
static bool pp=false,tp=false,sp=false,vp=false,vwrite=false;
static bool oldec=false,oldi2=false,oldi4=false;
static FILE*trace;
static void ck(bool ok,const char*msg){if(!ok){fprintf(stderr,"FAIL clock%u pc/bus%06x %s\n",clocks,unsigned(d.dbg_addr),msg);exit(1);}}
static std::vector<unsigned char> load(const char*p){std::ifstream f(p,std::ios::binary);ck(bool(f),"original input open");return {std::istreambuf_iterator<char>(f),{}};}
static void tick(){
 d.rom_ack=0;d.tile_ack=0;d.spr_ack=0;d.vc_ack=0;
 if(!d.reset){
  if(!pp&&d.rom_req){pp=true;pt=12;pa=d.rom_addr;}
  else if(pp&&!--pt){ck(d.rom_req&&d.rom_addr==pa,"ROM request stable");ck(pa<0x100000,"original program boundary");d.rom_q=image[2*pa]*256+image[2*pa+1];d.rom_ack=1;pp=false;++pr;}
  if(!tp&&d.tile_req){tp=true;tt=12+(ta%11);ta=d.tile_addr;}
  else if(tp&&!--tt){ck(d.tile_req&&d.tile_addr==ta,"tile request stable");ck(ta<0x80000,"original tile boundary");unsigned at=5*ta;d.tile_q=(unsigned(tile[at])<<24)|(unsigned(tile[at+1])<<16)|(unsigned(tile[at+2])<<8)|tile[at+3];d.tile_fifth=tile[at+4];d.tile_ack=1;tp=false;++tr;}
  if(!sp&&d.spr_req){sp=true;st=14+(sa%13);sa=d.spr_addr;}
  else if(sp&&!--st){ck(d.spr_req&&d.spr_addr==sa,"sprite request stable");ck(sa<0x80000,"original sprite boundary");unsigned long long q=0;for(int i=0;i<8;i++)q=q*256+spr[8*sa+i];d.spr_q=q;d.spr_fifth=spr[0x400000+2*sa]*256+spr[0x400001+2*sa];d.spr_ack=1;sp=false;++sr;}
  if(!vp&&d.vc_req){vp=true;vt=7;va=d.vc_addr;vwrite=d.vc_we;vdata=d.vc_wdata;vbe=d.vc_be;}
  else if(vp&&!--vt){ck(d.vc_req&&d.vc_addr==va&&d.vc_we==vwrite,"VRAM request stable");if(vwrite){if(vbe&2)vram[va]=(vram[va]&255)|(vdata&0xff00);if(vbe&1)vram[va]=(vram[va]&0xff00)|(vdata&255);++vw;}else ++vr;d.vc_q=vram[va];d.vc_ack=1;vp=false;}
 }
 d.cen_16m=clocks%6==0;d.raster_start=clocks%6144==0;d.raster_line=(clocks/6144)%264;
 d.clk=0;d.eval();d.clk=1;d.eval();++clocks;
 if(!d.reset){
  ck(!d.unexpected_roz,"Mystic must not use PSAC");ck(!d.rb_oob,"original access must not enter unsupported ROM bounds");
  if(d.eep_clk&&!oldec)++eepedges;oldec=d.eep_clk;
  if(d.irq2&&!oldi2)++irq2edges;if(d.irq4&&!oldi4)++irq4edges;oldi2=d.irq2;oldi4=d.irq4;
  if(d.dbg_step){++steps;unsigned a=d.dbg_addr;if(a>=0x200000&&a<0x210000)++wrambus;if(a>=0x480000&&a<0x49e008)++mmio;
   fprintf(trace,"%u %06x %04x %u %u%u%u %u%u\n",clocks,a,unsigned(d.dbg_data),unsigned(d.dbg_busstate),unsigned(d.eep_cs),unsigned(d.eep_clk),unsigned(d.eep_di),unsigned(d.irq2),unsigned(d.irq4));}
 }
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=5)return 2;
 image=load(argv[1]);tile=load(argv[2]);spr=load(argv[3]);ck(image.size()==0xdc0080&&tile.size()==0x500000&&spr.size()==0x500000,"exact original images");trace=fopen(argv[4],"w");ck(trace,"trace open");
 d.reset=1;for(unsigned i=0;i<128;i++){d.eep_we=1;d.eep_addr=i;d.eep_data=image[0xdc0000+i];tick();}d.eep_we=0;for(int i=0;i<8;i++)tick();d.reset=0;
 for(unsigned n=0;n<16000000 && !(vr>1000 && vw>1000 && mmio>100 && eepedges>10);n++){
  d.pause=n>=12000&&n<12256;tick();
  if(n==12032){unsigned before=steps;for(unsigned q=0;q<192;q++){tick();ck(steps==before,"CPU quiet after pause drain");}n+=192;}
 }
 fclose(trace);printf("RESULT board-only cycles%u steps%u rom%u wram_bus%u mmio%u tile%u spr%u vram_r%u vram_w%u eep_clock_edges%u irq2_edges%u irq4_edges%u last_addr%06x\n",clocks,steps,pr,wrambus,mmio,tr,sr,vr,vw,eepedges,irq2edges,irq4edges,unsigned(d.dbg_addr));
 fflush(stdout);
 ck(steps>10000&&pr>1000&&vr>1000&&vw>1000&&mmio>100&&eepedges>10,"original program exercises mapped VRAM and EEPROM/MMIO");
 printf("PASS COVERAGE gate=%04x K56reg0=%04x; no audio CPU/raster renderer/gaia_mem/APF/whole-game qualification\n",unsigned(d.k56regsb[3]),unsigned(d.k56regs[0]));
}
