// Actual TG68K and gaia_main, delayed ROM/VRAM row interfaces. Original
// game runs are unmodified. Synthetic CPU-MMIO case is a separate program.
#include "Vm3_vio13_mmio_bus.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <map>
#include <tuple>
static Vm3_vio13_mmio_bus dut;
static std::vector<uint8_t> load(const char *path) {std::ifstream f(path,std::ios::binary);if(!f)throw std::runtime_error(path);return {std::istreambuf_iterator<char>(f),{}};}
static uint16_t word(const std::vector<uint8_t> &r,unsigned a) {if(a+1>=r.size())return 0;return (r[a]<<8)|r[a+1];}
static void require(bool ok,const std::string &s) {if(!ok)throw std::runtime_error(s);}
struct Request {bool active=false;unsigned wait=0,addr=0,be=0,data=0;bool write=false;};
int main(int argc,char **argv) {
 Verilated::commandArgs(argc,argv);
 if(argc!=13) {fprintf(stderr,"usage profile program eeprom tile sprite cycles trace expected mode snapshots markeraddr col_expected\n");return 2;}
 try {
  unsigned profile=atoi(argv[1]),limit=atoi(argv[6]),mode=atoi(argv[9]);bool synthetic=mode!=0;
  unsigned marker_addr=strtoul(argv[11],nullptr,16),markers=0,register_changes=0,engine_cycles=0,col_events=0;
  std::vector<std::tuple<char,unsigned,unsigned>> col_expected;
  if(mode==3){std::ifstream f(argv[12]);char kind;unsigned off,data;while(f>>kind>>std::hex>>off>>data)col_expected.emplace_back(kind,off,data);}
  std::map<unsigned,std::map<std::pair<unsigned,unsigned>,unsigned>> snapshots;
  if(mode==2||mode==5){std::ifstream in(argv[10]);unsigned phase,bank,index,value;while(in>>phase>>bank>>index>>std::hex>>value>>std::dec)snapshots[phase][{bank,index}]=value;require(snapshots.size()==(mode==5?4:6),"Required constructed snapshot checkpoints");}
  auto prog=load(argv[2]),eep=load(argv[3]),tile=load(argv[4]),spr=load(argv[5]);
  require(eep.size()==128,"EEPROM length");
  FILE *trace=fopen(argv[7],"wb");require(trace,"trace open");
  std::vector<std::pair<unsigned,unsigned>> expected;
  if(mode==1||mode==3||mode==5) {std::ifstream in(argv[8]);unsigned a,v;while(in>>std::hex>>a>>v)expected.emplace_back(a,v);require(!expected.empty(),"no expected reads");}
  std::array<uint16_t,65536> vram{};
  Request rom,vc,tr,sr;
  unsigned nrom=0,nvc=0,ntr=0,nsr=0,steps=0,reads=0,swrites=0,cycles=0,pause_steps=0;
  bool completed=false,was_pause=false;
  dut.profile=(profile+1)%3;dut.reset=1;dut.pause=0;dut.cen_16m=0;dut.rom_ack=0;dut.vc_ack=0;dut.trom_ack=0;dut.srom_ack=0;
  auto tick=[&](){dut.clk=0;dut.eval();dut.clk=1;dut.eval();};
  for(unsigned i=0;i<128;i++){dut.ld_we=1;dut.ld_addr=i;dut.ld_wdata=eep[i];tick();}
  dut.ld_we=0;for(int i=0;i<8;i++)tick();
  // Profile changes late while realconsumerreset stays asserted. Both old/new
  // must be ready at the firstactivecycle after256stable resetclocks.
  dut.profile=profile;for(unsigned i=0;i<256;i++)tick();dut.reset=0;
  auto snapshot=[&](){std::vector<unsigned> v;for(auto x:dut.k55regs)v.push_back(x);for(auto x:dut.k56regs)v.push_back(x);for(auto x:dut.k56regsb)v.push_back(x);for(auto x:dut.k38regs)v.push_back(x);for(auto x:dut.k46regs)v.push_back(x);for(auto x:dut.k47regs)v.push_back(x);for(auto x:dut.rozctrl)v.push_back(x);for(auto x:dut.rozclip)v.push_back(x);v.push_back(dut.roz_enable);v.push_back(dut.roz_rombank);return v;};
  std::vector<unsigned> previous_registers=snapshot();uint64_t previous_io=~uint64_t(0);
  auto check_snapshot=[&](unsigned phase){require(snapshots.count(phase),"Unexpected marker phase");auto &want=snapshots[phase];require(want.size()==(mode==5?136:84),"All public targets in checkpoint");for(auto x:want){unsigned bank=x.first.first,index=x.first.second;unsigned got=0;switch(bank){case 0:require(index<48,"K55 index");got=dut.k55regs[index];break;case 1:require(index<32,"K56 index");got=dut.k56regs[index];break;case 2:require(index<4,"K56b index");got=dut.k56regsb[index];break;case 3:require(index<16,"K338 index");got=dut.k38regs[index];break;case 4:require(index<8,"K46 index");got=dut.k46regs[index];break;case 5:require(index<8,"K47 index");got=dut.k47regs[index];break;case 6:require(index<16,"ROZ index");got=dut.rozctrl[index];break;case 7:require(index<2,"clip index");got=dut.rozclip[index];break;case 8:require(index<2,"ROZ control index");got=index?dut.roz_rombank:dut.roz_enable;break;default:throw std::runtime_error("Unexpected snapshot bank");}if(got!=x.second){fprintf(stderr,"REG mismatch profile%u phase%u bank%u index%u actual%04x want%04x\n",profile,phase,bank,index,got,x.second);throw std::runtime_error("ActualpublicMMIOsideeffect mismatch");}}};
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
   advance(rom,dut.rom_req,dut.rom_addr,old_rom_ack,12+(nrom%9),nrom,[&](auto &r){dut.rom_q=word(prog,r.addr*2);dut.rom_ack=1;fprintf(trace,"ROM %u %x %04x\n",cycles,r.addr,dut.rom_q);});
   if(vc.active)require(dut.vc_we==vc.write&&dut.vc_be==vc.be&&dut.vc_wdata==vc.data,"VRAM payload changed before ACK");
   bool newvc=!vc.active&&dut.vc_req&&!old_vc_ack;
   advance(vc,dut.vc_req,dut.vc_addr,old_vc_ack,7+(nvc%11),nvc,[&](auto &r){
    if(r.write){if(r.be&2)vram[r.addr]=(vram[r.addr]&255)|(r.data&0xff00);if(r.be&1)vram[r.addr]=(vram[r.addr]&0xff00)|(r.data&255);}
    dut.vc_q=vram[r.addr];dut.vc_ack=1;fprintf(trace,"VRAM %u %x %u %u %04x %04x\n",cycles,r.addr,r.write,r.be,r.data,dut.vc_q);
   });
   if(newvc){vc.write=dut.vc_we;vc.be=dut.vc_be;vc.data=dut.vc_wdata;}
   advance(tr,dut.trom_req,dut.trom_addr,old_tr_ack,15+(ntr%13),ntr,[&](auto &r){unsigned a=r.addr*(profile==1?5:4);dut.trom_q=(uint32_t(word(tile,a))<<16)|word(tile,a+2);dut.trom_fifth=profile==1&&a+4<tile.size()?tile[a+4]:0;dut.trom_ack=1;fprintf(trace,"TILE %u %x %08x %02x\n",cycles,r.addr,dut.trom_q,dut.trom_fifth);});
   advance(sr,dut.srom_req,dut.srom_addr,old_sr_ack,17+(nsr%17),nsr,[&](auto &r){unsigned a=r.addr*8;dut.srom_q=(uint64_t(word(spr,a))<<48)|(uint64_t(word(spr,a+2))<<32)|(uint64_t(word(spr,a+4))<<16)|word(spr,a+6);dut.srom_fifth=profile==1?word(spr,0x400000+r.addr*2):0;dut.srom_ack=1;fprintf(trace,"SPRITE %u %x %016llx %04x\n",cycles,r.addr,(unsigned long long)dut.srom_q,dut.srom_fifth);});
   dut.clk=1;dut.eval();
   auto registers=snapshot();for(unsigned i=0;i<registers.size();i++)if(registers[i]!=previous_registers[i]){fprintf(trace,"REG %u %u %04x\n",cycles,i,registers[i]);register_changes++;}previous_registers=registers;
   uint64_t io=uint64_t(dut.eep_cs)|(uint64_t(dut.eep_clk)<<1)|(uint64_t(dut.eep_di)<<2)|(uint64_t(dut.dbg_irq5)<<3)|(uint64_t(dut.dbg_irq2)<<4)|(uint64_t(dut.dbg_irq4)<<5)|(uint64_t(dut.observed_ipl)<<6)|(uint64_t(dut.snd_wr)<<9)|(uint64_t(dut.snd_rd)<<10)|(uint64_t(dut.snd_irq)<<11)|(uint64_t(dut.snd_off)<<12)|(uint64_t(dut.snd_wdata)<<16)|(uint64_t(dut.col_wr)<<24)|(uint64_t(dut.col_rd)<<25)|(uint64_t(dut.col_off)<<26)|(uint64_t(dut.col_wdata)<<32);
   if(io!=previous_io||dut.snd_wr||dut.snd_rd||dut.snd_irq||dut.col_wr||dut.col_rd)fprintf(trace,"IO %u %llx\n",cycles,(unsigned long long)io);previous_io=io;
   if(mode==3&&(dut.col_wr||dut.col_rd)){
    require(col_events<col_expected.size(),"Unexpected collision consumer strobe");auto e=col_expected[col_events++];
    require(std::get<0>(e)==(dut.col_wr?'W':'R')&&std::get<1>(e)==dut.col_off&&(!dut.col_wr||std::get<2>(e)==dut.col_wdata),"Actual K054000 strobe/index/writebyte differs from constructed CPU contract");
   }
   engine_cycles+=dut.observed_engine_write;
   if(dut.dbg_step){
    steps++;
    fprintf(trace,"CPU %u %06x %04x %x %04x %u%u%u %u%u%u\n",cycles,dut.dbg_addr,dut.dbg_data,dut.dbg_busstate,dut.observed_wdat,dut.eep_cs,dut.eep_clk,dut.eep_di,dut.dbg_irq5,dut.dbg_irq2,dut.dbg_irq4);
    if((mode==1||mode==3||mode==5) && dut.dbg_addr>=0x200000 && dut.dbg_busstate!=3 && dut.dbg_busstate!=1){
     require(reads<expected.size(),"unexpected data read");
     auto e=expected[reads++];
     if(dut.dbg_addr!=e.first||dut.dbg_data!=e.second){fprintf(stderr,"READ mismatch %06x=%04x expected %06x=%04x\n",dut.dbg_addr,dut.dbg_data,e.first,e.second);throw std::runtime_error("MMIO read mismatch");}
    }
    if(synthetic && dut.dbg_busstate==3 && dut.dbg_addr==marker_addr) {
     if(mode==1||dut.observed_wdat==0xffff){completed=true;break;}
     check_snapshot(dut.observed_wdat);markers++;
    }
   }
   if(dut.snd_wr)swrites++;
   if(dut.pause&&cycles>=2032&&cycles<2256) {if(!was_pause){pause_steps=steps;was_pause=true;}require(steps==pause_steps,"CPU advanced after pause drain");}
  }
  fclose(trace);
  if(mode==1){require(completed,"synthetic CPU did not reach completion marker");require(reads==expected.size(),"expected data reads not all seen");require(swrites==2,"K054321 wrong byte-lane write count");require(dut.eep_di&&dut.eep_cs&&dut.eep_clk,"Violent EEPROM LDS bits not retained");}
  if(mode==2){require(completed,"MMIOprogramcompletion");require(markers==6,"Sixoriginalregistercheckpointsobserved");require(swrites==2,"Sound byte lane count");require(dut.eep_di&&dut.eep_cs&&dut.eep_clk,"EEPROMlane bits retained");if(profile==2)require(engine_cycles>0,"ActualK550ownershipwritescovered");}
  if(mode==3){require(completed,"Collision program completion");require(reads==expected.size(),"All expected collision/leaf reads consumed");require(col_events==col_expected.size(),"All expected real K054000 consumer events consumed");if(profile==2)require(engine_cycles>0,"Vio unmapped K550 ownership exercised");}
  if(mode==5){require(completed,"Board program completion");require(markers==4,"All4 public board checkpoints");require(reads==expected.size(),"All expected board reads consumed");require(swrites==2,"Board sound lane strobes");require(dut.eep_di&&dut.eep_cs&&dut.eep_clk,"Board EEPROM pins retain legal active lane");require(nvc>0,"Actual delayed VRAM writes/reads");require(register_changes>0,"Public board register effects");if(profile==2)require(engine_cycles==0,"Only safe K550 NOPs during complete register-lane readback");}
  if(mode==4){require(completed,"Graphics readback completion");require(ntr>0&&nsr>0,"Real tile and sprite readback ROM consumers exercised");}
  printf("COL_JSON {\"events\":%u,\"mode\":%u}\n",col_events,mode);
  printf("MMIO_JSON {\"mode\":%u,\"checkpoints\":%u,\"register_changes\":%u,\"engine_write_cycles\":%u}\n",mode,markers,register_changes,engine_cycles);
  printf("RESULT_JSON {\"passed\":true,\"profile\":%u,\"synthetic\":%s,\"steps\":%u,\"cpu_data_reads\":%u,\"program_reads\":%u,\"vram_transactions\":%u,\"tile_reads\":%u,\"sprite_reads\":%u,\"sound_writes\":%u,\"cycles\":%u}\n",profile,synthetic?"true":"false",steps,reads,nrom,nvc,ntr,nsr,swrites,cycles);
  return 0;
 }catch(const std::exception &e){fprintf(stderr,"FAIL %s\n",e.what());return 1;}
}
