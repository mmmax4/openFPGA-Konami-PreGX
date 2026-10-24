// Profile-gain differential gate using original events/PCM and real chip engines.
#include "Vtb_m2_audio_gain.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <sstream>
#include <string>
#include <vector>
static Vtb_m2_audio_gain *d;
static std::vector<uint8_t> pcm;
static uint64_t cycles=0,checks=0,mismatches[2]={},nonzero[2]={},requests[3]={},protocol_errors=0;
struct Port {bool busy=false;unsigned address=0,wait=0;};
static Port port[3];
struct WindowMask {unsigned seed,profile,c1,c2,r1,r2;};
static std::vector<WindowMask> window_masks;
static unsigned required_mask=0;
static bool coverage[2]={};
static void tick(unsigned n=1){while(n--){
 for(unsigned i=0;i<3;i++){
  d->ack[i]=0;
  if(!port[i].busy&&d->req[i]){port[i]={true,d->rom_addr[i],23u+((d->rom_addr[i]>>2)&15)};requests[i]++;}
  if(port[i].busy){
   if(!d->req[i]||d->rom_addr[i]!=port[i].address){protocol_errors++;port[i].busy=false;}
   else if(port[i].wait==0){d->q[i]=pcm.at(port[i].address);d->ack[i]=1;port[i].busy=false;}
   else port[i].wait--;
  }
 }
 d->clk=0;d->eval();d->clk=1;d->eval();cycles++;
}}
static std::vector<uint8_t> bytes(const std::string &p){std::ifstream f(p,std::ios::binary);if(!f){fprintf(stderr,"Missing %s\n",p.c_str());exit(2);}return {std::istreambuf_iterator<char>(f),{}};}
static void write(unsigned chip,unsigned address,unsigned value){d->chip=chip;d->addr=address;d->data=value;d->wr=1;tick();d->wr=0;tick();}
struct Event{unsigned frame,chip,address,value,line;};
static void run(const std::string&dir,unsigned seed,unsigned first,unsigned last,bool mystic){
 d->cen=0;d->wr=0;d->reset=1;d->mystic=mystic;tick(10);d->reset=0;tick(10);
 for(unsigned chip=0;chip<2;chip++){
  char path[512];snprintf(path,sizeof(path),"%s/f%05u-k539_%u_regs.bin",dir.c_str(),seed,chip+1);auto regs=bytes(path);if(regs.size()!=560)exit(2);
  // Explicit constructed cold-start RAM, through the real streaming byte port.
  // Its pointer maps bit16 into RAM bit14, so cover through0x13fff.
  write(chip,0x22e,0x80);for(unsigned i=0;i<0x14000;i++)write(chip,0x22d,0);
  for(unsigned a=0;a<560;a++)if(a!=0x214&&a!=0x215&&a!=0x22c&&a!=0x22d&&a!=0x22e&&a!=0x22f)write(chip,a,regs[a]);
  write(chip,0x22e,regs[0x22e]);write(chip,0x214,regs[0x22c]);write(chip,0x22f,regs[0x22f]);
 }
 std::ifstream f(dir+"/events.tsv");std::vector<Event> events;std::string row;
 while(getline(f,row)){if(row.empty()||row[0]=='#')continue;std::istringstream s(row);Event e;s>>e.frame>>e.chip>>std::hex>>e.address>>e.value>>std::dec>>e.line;if(!s)exit(2);events.push_back(e);}
 unsigned emitted=0;uint64_t before=mismatches[mystic],prior_checks=checks,prior_nonzero=nonzero[mystic];
 for(unsigned frame=first;frame<=last;frame++){
  std::vector<Event> current;for(auto e:events)if(e.frame==frame)current.push_back(e);
  unsigned index=0;
  // Declared constructed spacing:811 output samples per captured frame,
  // ordered events spread evenly before sample edges,2000sys clocks/sample.
  for(unsigned sample=0;sample<811;sample++){
   unsigned count=0;
   while(index<current.size()&&index*811/current.size()<=sample){auto e=current[index++];write(e.chip-1,e.address,e.value);count++;emitted++;}
   if(d->busy[0]||d->busy[1]||d->busy[2]){protocol_errors++;}
   d->cen=1;tick();d->cen=0;tick(1999-count*2);
   unsigned reference=mystic?2:1;
   checks++;nonzero[mystic]+=(d->l[reference]!=0||d->r[reference]!=0);
   if(d->l[0]!=d->l[reference]||d->r[0]!=d->r[reference]){
    if(mismatches[mystic]<4)printf("GAIN_MISMATCH profile=%u frame=%u sample=%u got=%04x,%04x expected=%04x,%04x\n",mystic,frame,sample,d->l[0],d->r[0],d->l[reference],d->r[reference]);
    mismatches[mystic]++;
   }
  }
 }
 if(emitted!=events.size())protocol_errors++;
 unsigned reference=mystic?2:1;
 unsigned c1=d->nonzero_mask[0][0],c2=d->nonzero_mask[0][1];
 unsigned r1=d->nonzero_mask[reference][0],r2=d->nonzero_mask[reference][1];
 window_masks.push_back({seed,unsigned(mystic),c1,c2,r1,r2});
 if((c1&required_mask)==required_mask&&(r1&required_mask)==required_mask)coverage[mystic]=true;
 printf("CHANNELS seed=%u profile=%u candidate=%02x,%02x reference=%02x,%02x requiredK1=%02x\n",seed,mystic,c1,c2,r1,r2,required_mask);
 printf("WINDOW seed=%u profile=%u events=%u samples=%llu nonzero=%llu mismatches=%llu\n",seed,mystic,emitted,(unsigned long long)(checks-prior_checks),(unsigned long long)(nonzero[mystic]-prior_nonzero),(unsigned long long)(mismatches[mystic]-before));fflush(stdout);
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=4)return 2;
 pcm=bytes(argv[1]);if(pcm.size()!=4194304)return 2;
 required_mask=std::stoul(argv[3],nullptr,0);if(required_mask>255)return 2;
 struct Case {std::string dir;unsigned seed,first,last;};
 std::vector<Case> cases;std::ifstream cf(argv[2]);std::string row;
 while(getline(cf,row)){
  if(row.empty()||row[0]=='#')continue;std::istringstream stream(row);Case c;
  if(!(stream>>c.dir>>c.seed>>c.first>>c.last)||!(c.seed<c.first&&c.first<=c.last))return 2;
  cases.push_back(c);
 }
 if(cases.empty())return 2;
 d=new Vtb_m2_audio_gain;d->clk=0;d->reset=1;d->eval();
 for(bool mystic:{false,true})for(const auto &c:cases)run(c.dir,c.seed,c.first,c.last,mystic);
 bool pass=!protocol_errors&&!mismatches[0]&&!mismatches[1]&&nonzero[0]&&nonzero[1]&&checks&&coverage[0]&&coverage[1];
 printf("RESULT_JSON {\"passed\":%s,\"checks\":%llu,\"gaia_mismatches\":%llu,\"mystic_mismatches\":%llu,\"nonzero\":[%llu,%llu],\"protocol_errors\":%llu,\"requests\":[%llu,%llu,%llu],\"cycles\":%llu,\"required_k1_nonzero_mask\":%u,\"coverage_profiles\":[%s,%s],\"window_masks\":[",pass?"true":"false",(unsigned long long)checks,(unsigned long long)mismatches[0],(unsigned long long)mismatches[1],(unsigned long long)nonzero[0],(unsigned long long)nonzero[1],(unsigned long long)protocol_errors,(unsigned long long)requests[0],(unsigned long long)requests[1],(unsigned long long)requests[2],(unsigned long long)cycles,required_mask,coverage[0]?"true":"false",coverage[1]?"true":"false");
 for(unsigned i=0;i<window_masks.size();i++){
  const auto &v=window_masks[i];printf("%s{\"seed_frame\":%u,\"profile_mystic\":%s,\"candidate\":[%u,%u],\"reference\":[%u,%u]}",i?",":"",v.seed,v.profile?"true":"false",v.c1,v.c2,v.r1,v.r2);
 }
 printf("],\"hardware_verified\":false}\n");
 delete d;return pass?0:1;
}
