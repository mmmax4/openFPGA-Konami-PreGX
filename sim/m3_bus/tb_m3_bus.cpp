// Actual TG68K and gaia_main, delayed ROM/VRAM row interfaces. Original
// game runs are unmodified. Synthetic CPU-MMIO case is a separate program.
#include "Vtb_m3_bus.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>
static Vtb_m3_bus dut;
static std::vector<uint8_t> load(const char *path) {std::ifstream f(path,std::ios::binary);if(!f)throw std::runtime_error(path);return {std::istreambuf_iterator<char>(f),{}};}
static uint16_t word(const std::vector<uint8_t> &r,unsigned a) {if(a+1>=r.size())return 0;return (r[a]<<8)|r[a+1];}
static void require(bool ok,const std::string &s) {if(!ok)throw std::runtime_error(s);}
struct Request {bool active=false;unsigned wait=0,addr=0,be=0,data=0;bool write=false;};
int main(int argc,char **argv) {
 Verilated::commandArgs(argc,argv);
 if(argc!=10) {fprintf(stderr,"usage profile program eeprom tile sprite cycles trace expected synthetic\n");return 2;}
 try {
  unsigned profile=atoi(argv[1]),limit=atoi(argv[6]);bool synthetic=atoi(argv[9]);
  auto prog=load(argv[2]),eep=load(argv[3]),tile=load(argv[4]),spr=load(argv[5]);
  require(eep.size()==128,"EEPROM length");
  FILE *trace=fopen(argv[7],"wb");require(trace,"trace open");
  std::vector<std::pair<unsigned,unsigned>> expected;
  if(synthetic) {std::ifstream in(argv[8]);unsigned a,v;while(in>>std::hex>>a>>v)expected.emplace_back(a,v);require(!expected.empty(),"no expected reads");}
  std::array<uint16_t,65536> vram{};
  Request rom,vc,tr,sr;
  unsigned nrom=0,nvc=0,ntr=0,nsr=0,steps=0,reads=0,swrites=0,cycles=0,pause_steps=0;
  bool completed=false,was_pause=false;
  dut.profile=profile;dut.reset=1;dut.pause=0;dut.cen_16m=0;dut.rom_ack=0;dut.vc_ack=0;dut.trom_ack=0;dut.srom_ack=0;
  auto tick=[&](){dut.clk=0;dut.eval();dut.clk=1;dut.eval();};
  for(unsigned i=0;i<128;i++){dut.ld_we=1;dut.ld_addr=i;dut.ld_wdata=eep[i];tick();}
  dut.ld_we=0;for(int i=0;i<8;i++)tick();dut.reset=0;
  for(cycles=0;cycles<limit;cycles++) {
   dut.clk=0;dut.eval();
   dut.cen_16m=(cycles%6)==0;
   dut.pause=!synthetic && ((cycles>=2000&&cycles<2256)||(cycles>=6000&&cycles<6256));
   dut.vblank_rise=!synthetic && cycles==3000;
   dut.raster_start=!synthetic && cycles==5000;dut.raster_line=0;
   bool old_rom_ack=dut.rom_ack,old_vc_ack=dut.vc_ack,old_tr_ack=dut.trom_ack,old_sr_ack=dut.srom_ack;
   dut.rom_ack=0;dut.vc_ack=0;dut.trom_ack=0;dut.srom_ack=0;
   auto advance=[&](Request &r,bool req,unsigned addr,bool prevack,unsigned delay,unsigned &n,auto complete){
    if(r.active) {
     require(req&&addr==r.addr,"address/request changed while pending");
     if(--r.wait==0){complete(r);r.active=false;n++;}
    } else if(req&&!prevack){r.active=true;r.wait=delay;r.addr=addr;}
   };
   advance(rom,dut.rom_req,dut.rom_addr,old_rom_ack,12+(nrom%9),nrom,[&](auto &r){dut.rom_q=word(prog,r.addr*2);dut.rom_ack=1;});
   if(vc.active)require(dut.vc_we==vc.write&&dut.vc_be==vc.be&&dut.vc_wdata==vc.data,"VRAM payload changed before ACK");
   bool newvc=!vc.active&&dut.vc_req&&!old_vc_ack;
   advance(vc,dut.vc_req,dut.vc_addr,old_vc_ack,7+(nvc%11),nvc,[&](auto &r){
    if(r.write){if(r.be&2)vram[r.addr]=(vram[r.addr]&255)|(r.data&0xff00);if(r.be&1)vram[r.addr]=(vram[r.addr]&0xff00)|(r.data&255);}
    dut.vc_q=vram[r.addr];dut.vc_ack=1;
   });
   if(newvc){vc.write=dut.vc_we;vc.be=dut.vc_be;vc.data=dut.vc_wdata;}
   advance(tr,dut.trom_req,dut.trom_addr,old_tr_ack,15+(ntr%13),ntr,[&](auto &r){unsigned a=r.addr*(profile==1?5:4);dut.trom_q=(uint32_t(word(tile,a))<<16)|word(tile,a+2);dut.trom_fifth=profile==1&&a+4<tile.size()?tile[a+4]:0;dut.trom_ack=1;});
   advance(sr,dut.srom_req,dut.srom_addr,old_sr_ack,17+(nsr%17),nsr,[&](auto &r){unsigned a=r.addr*8;dut.srom_q=(uint64_t(word(spr,a))<<48)|(uint64_t(word(spr,a+2))<<32)|(uint64_t(word(spr,a+4))<<16)|word(spr,a+6);dut.srom_fifth=profile==1?word(spr,0x400000+r.addr*2):0;dut.srom_ack=1;});
   dut.clk=1;dut.eval();
   if(dut.dbg_step){
    steps++;
    fprintf(trace,"%u %06x %04x %x %u%u%u %u%u%u\n",cycles,dut.dbg_addr,dut.dbg_data,dut.dbg_busstate,dut.eep_cs,dut.eep_clk,dut.eep_di,dut.dbg_irq5,dut.dbg_irq2,dut.dbg_irq4);
    if(synthetic && dut.dbg_addr>=0x200000 && dut.dbg_busstate!=3 && dut.dbg_busstate!=1){
     require(reads<expected.size(),"unexpected data read");
     auto e=expected[reads++];
     if(dut.dbg_addr!=e.first||dut.dbg_data!=e.second){fprintf(stderr,"READ mismatch %06x=%04x expected %06x=%04x\n",dut.dbg_addr,dut.dbg_data,e.first,e.second);throw std::runtime_error("MMIO read mismatch");}
    }
    if(synthetic && dut.dbg_busstate==3 && dut.dbg_addr==0x20fff0) {completed=true;break;}
   }
   if(dut.snd_wr)swrites++;
   if(dut.pause&&cycles>=2032&&cycles<2256) {if(!was_pause){pause_steps=steps;was_pause=true;}require(steps==pause_steps,"CPU advanced after pause drain");}
  }
  fclose(trace);
  if(synthetic){require(completed,"synthetic CPU did not reach completion marker");require(reads==expected.size(),"expected data reads not all seen");require(swrites==2,"K054321 wrong byte-lane write count");require(dut.eep_di&&dut.eep_cs&&dut.eep_clk,"Violent EEPROM LDS bits not retained");}
  printf("RESULT_JSON {\"passed\":true,\"profile\":%u,\"synthetic\":%s,\"steps\":%u,\"cpu_data_reads\":%u,\"program_reads\":%u,\"vram_transactions\":%u,\"tile_reads\":%u,\"sprite_reads\":%u,\"sound_writes\":%u,\"cycles\":%u}\n",profile,synthetic?"true":"false",steps,reads,nrom,nvc,ntr,nsr,swrites,cycles);
  return 0;
 }catch(const std::exception &e){fprintf(stderr,"FAIL %s\n",e.what());return 1;}
}
