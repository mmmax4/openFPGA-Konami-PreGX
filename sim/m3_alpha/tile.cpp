// Actual K056832 public VRAM/ROM/scanout ports. Original captured register/data
// arrays; declared in-memory low2attribute changes exercise legal mix metadata.
#include "Vk056832_tilemap.h"
#include "verilated.h"
#include <vector>
#include <fstream>
#include <iterator>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
static Vk056832_tilemap d;
static unsigned long long cycles=0,checks=0,pixel_checks=0;
static unsigned responses=0,nonzero=0,cases=0,romresponses=0,mode=0;
static std::vector<unsigned char> rom;
static std::vector<unsigned> ram;
struct Pending{bool on=false,done=false;unsigned address=0,timer=0;};
static Pending vr,rr;
static void need(bool ok,const char*m){checks++;if(!ok){fprintf(stderr,"FAIL clock%llu mode%u %s last%u\n",cycles,mode,m,unsigned(d.last_mix));exit(1);}}
static unsigned payload(unsigned address){unsigned v=ram.at(address);if((address&1)==0&&mode<4)v=(v&~3u)|mode;return v;}
static void tick(){
 d.vram_ack=0;d.rom_ack=0;
 if(vr.on&&!d.vram_req)vr={};if(rr.on&&!d.rom_req)rr={};
 if(!vr.on&&d.vram_req)vr={true,false,unsigned(d.vram_addr),5};
 if(!rr.on&&d.rom_req)rr={true,false,unsigned(d.rom_addr),12};
 if(vr.on){need(vr.address==d.vram_addr,"held publicVRAMaddress");if(vr.timer)vr.timer--;else if(!vr.done){d.vram_q=payload(vr.address);d.vram_ack=1;vr.done=true;responses++;}}
 if(rr.on){need(rr.address==d.rom_addr,"held publicROMaddress");if(rr.timer)rr.timer--;else if(!rr.done){unsigned at=rr.address*5;need(at+4<rom.size(),"real canonicalROMbounds");d.rom_q=(unsigned(rom[at])<<24)|(unsigned(rom[at+1])<<16)|(unsigned(rom[at+2])<<8)|rom[at+3];d.rom_fifth=rom[at+4];d.rom_ack=1;rr.done=true;romresponses++;}}
 d.clk=0;d.eval();d.clk=1;d.eval();cycles++;
}
static void reset(){d.reset=1;d.line_start=0;tick();tick();d.reset=0;tick();need(d.last_mix==0,"reset globalmixzero");vr={};rr={};}
static void line(unsigned y){d.line=y;d.line_start=1;tick();d.line_start=0;unsigned n=0;while(d.busy&&n++<100000)tick();need(n<100000,"bounded producercompletion");need(!d.unsupported,"legal originalXYconfiguration");}
static void run(unsigned category,unsigned expected,bool scan){mode=category;line(16);need(d.last_mix==expected,"lastnonzero originalcallbackrule");
 if(scan){
  // Swap completed line into actual scan bank and read the registered public
  // line RAM while next line runs with the same declared attributes.
  d.line=17;d.line_start=1;tick();d.line_start=0;
  unsigned visible=0;
  for(unsigned x=0;x<(d.violent?384u:d.mystic?288u:376u);x++){
   d.px=x;tick();tick();
   for(unsigned l=0;l<4;l++)if((d.opaque>>l)&1){pixel_checks++;need(d.category[l]==expected,"category carriedwithactualoriginalpen");visible++;}
  }
  need(visible>0,"originalnonzeropensreachscanconsumer");nonzero+=visible;
  unsigned n=0;while(d.busy&&n++<100000)tick();need(n<100000,"scanlineproducercompletes");need(d.last_mix==expected,"scan_does_not_clear_mix");
 }
 cases++;
}
static std::vector<unsigned char> bytes(const char*p){std::ifstream f(p,std::ios::binary);need(bool(f),"originalinputopen");return {std::istreambuf_iterator<char>(f),{}};}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=5)return 2;
 auto regs=bytes(argv[1]),cb=bytes(argv[2]),v=bytes(argv[3]);rom=bytes(argv[4]);
 need(regs.size()==64&&cb.size()==128&&v.size()==139264&&rom.size()==0x600000,"originalcaptureshapes");
 for(unsigned i=0;i<32;i++)d.regs[i]=regs[i*2]|unsigned(regs[i*2+1])<<8;
 for(unsigned i=0;i<4;i++)d.colorbase[i]=(cb[23+i]<<4)&255;
 for(unsigned i=0;i<v.size();i+=2)ram.push_back(v[i]|unsigned(v[i+1])<<8);
 d.violent=1;d.mystic=0;mode=4;reset();run(4,0,false); // untouched original category0
 // Category replacements are fixture RAM writes only, never a ROM/program/save
 // edit. Zero metadata after1/2/3must retain the last nonzero global state.
 for(unsigned cat=1;cat<4;cat++){run(cat,cat,true);run(0,cat,false);}
 reset();run(0,0,false);reset();d.violent=0;d.mystic=1;run(3,0,false);reset();d.mystic=0;run(2,0,false);
 need(responses>0&&romresponses>0&&nonzero>0,"actualVRAM_ROM_and_pixelconsumers_executed");
 printf("RESULT_JSON {\"passed\":true,\"cases\":%u,\"checks\":%llu,\"pixel_checks\":%llu,\"vram_responses\":%u,\"rom_responses\":%u,\"cycles\":%llu,\"hardware_verified\":false}\n",cases,checks,pixel_checks,responses,romresponses,cycles);return 0;
}
