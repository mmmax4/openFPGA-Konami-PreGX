#include "Vm3_gaia_audio032_top.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <sstream>
#include <string>
#include <vector>
static Vm3_gaia_audio032_top d;
static std::vector<uint8_t> pcm;
static std::ofstream transcript;
static uint64_t errors=0,checks=0,ticks=0,requests[3]={},acks[3]={};
static uint64_t legacy_cycles=0,trace_events=0,trace_samples=0,mix_vectors=0;
static uint64_t gaia_samples=0,upstream_samples=0,audible_samples=0,reverb_samples=0;
static uint64_t keyon_cases=0,position_checks=0,bit7_cases=0,cancel_cases=0,snapshot_cases=0,edge_cases=0;
static unsigned profile=0,current_case=0;static bool legacy_compare=false;
struct Memory{bool pending=false,held=false;unsigned addr=0,held_addr=0,wait=0;};
static Memory mem[3];
static std::vector<uint8_t> bytes(const std::string&p){std::ifstream f(p,std::ios::binary);if(!f){fprintf(stderr,"Missing %s\n",p.c_str());exit(2);}return{std::istreambuf_iterator<char>(f),{}};}
static void need(bool v,const char*w){checks++;if(!v){if(errors<32)printf("ERROR %s case=%u profile=%u clock=%llu\n",w,current_case,profile,(unsigned long long)ticks);errors++;}}
static int16_t signed16(unsigned x){return int16_t(uint16_t(x));}
static unsigned sat(int x){return uint16_t(std::max(-32768,std::min(32767,x)));}
static void ports(){
 if(!legacy_compare||d.reset)return;
 legacy_cycles++;
 need((d.req&1)==((d.req>>1)&1),"legacy complete-cycle ROM request");
 if(d.req&1)need(d.rom_addr[0]==d.rom_addr[1],"legacy complete-cycle ROM address");
 need((d.stall&1)==((d.stall>>1)&1),"legacy public CPU stall");
 need((d.timer&1)==((d.timer>>1)&1),"legacy timer cycle");
 if(d.cs&&d.rd)need(d.rdata[0]==d.rdata[1],"legacy public register/readback");
 need(d.chip_l0[0]==d.chip_l0[1]&&d.chip_r0[0]==d.chip_r0[1]&&d.chip_l1[0]==d.chip_l1[1]&&d.chip_r1[0]==d.chip_r1[1],"legacy both actual chip output cycles");
 need(d.l[0]==d.l[1]&&d.r[0]==d.r[1],"legacy actual board mix cycles");
}
static void tick(unsigned count=1){while(count--){
 d.clk=0;d.ack=0;d.eval();
 for(unsigned i=0;i<3;i++){
  auto&m=mem[i];bool req=(d.req>>i)&1;
  if(d.reset){m=Memory{};continue;}
  if(!req||(m.held&&d.rom_addr[i]!=m.held_addr))m.held=false;
  if(!req&&m.pending){need(false,"issued PCM request held until response");m.pending=false;}
  if(!m.pending&&!m.held&&req){m.pending=true;m.addr=d.rom_addr[i];m.wait=6+(m.addr*13u+unsigned(ticks))%75;requests[i]++;}
  if(m.pending){
   need(req&&d.rom_addr[i]==m.addr,"actual PCM address stable under latency");
   if(!--m.wait){need(m.addr<pcm.size(),"original PCM address within4MiB");d.q[i]=pcm[m.addr%pcm.size()];d.ack|=1u<<i;m.pending=false;m.held=true;m.held_addr=m.addr;acks[i]++;}
  }
 }
 d.eval();ports();d.clk=1;d.eval();d.clk=0;d.eval();ticks++;
}}
static void select(unsigned p){profile=p;d.mystic=p==1;d.violent=p==2;}
static void reset(unsigned p){
 legacy_compare=false;select(p);d.reset=1;d.cs=0;d.wr=d.rd=d.cen=0;d.addr=d.wdata=0;d.chip=0;tick(16);d.reset=0;tick(16);
 legacy_compare=p!=0;
}
static void write(unsigned chip,unsigned a,unsigned v){d.chip=chip;d.addr=a;d.wdata=v;d.cs=1;d.wr=1;d.rd=0;tick();d.wr=0;d.cs=0;tick();}
static unsigned read(unsigned chip,unsigned a,unsigned instance=0){d.chip=chip;d.addr=a;d.cs=1;d.rd=1;tick(2);unsigned v=d.rdata[instance];d.cs=0;d.rd=0;tick();return v;}
static void pos(unsigned chip,unsigned channel,unsigned value){for(unsigned b=0;b<3;b++)write(chip,channel*32+12+b,(value>>(8*b))&255);}
static unsigned read_pos(unsigned chip,unsigned channel,unsigned instance=0){unsigned v=0;for(unsigned b=0;b<3;b++)v|=read(chip,channel*32+12+b,instance)<<(8*b);position_checks++;return v;}
static void cold_ram(){
 for(unsigned chip=0;chip<2;chip++){write(chip,0x22f,0);write(chip,0x22e,0x80);for(unsigned i=0;i<32768;i++)write(chip,0x22d,0);write(chip,0x22e,0);}
}
static void parameters(unsigned chip,unsigned channel,unsigned address,unsigned mode,unsigned pan,unsigned reverb=0){
 unsigned b=channel*32;
 write(chip,b,0);write(chip,b+1,0);write(chip,b+2,1); // exact1.0 pitch, actual original PCM bytes
 write(chip,b+3,0);write(chip,b+4,reverb?0:255);write(chip,b+5,pan);
 write(chip,b+6,reverb&255);write(chip,b+7,reverb>>8);
 for(unsigned n=0;n<3;n++)write(chip,b+8+n,(address>>(8*n))&255);
 pos(chip,channel,address);write(chip,0x200+channel*2,mode);write(chip,0x201+channel*2,1);
}
static void pulse(){d.cen=1;tick();d.cen=0;}
static void busy_start(unsigned address){
 // Public active mask with bit7 hold allows a busy channel without position
 // writeback changing the inactive target's register witness.
 write(0,0x22f,0);parameters(0,1,address,4,0x18);write(0,0x22f,0x81);write(0,0x22c,2);
 // Seven PCM16 steps keep the original-data renderer busy long enough for
 // complete constructed legal CPU writes; ROM latency is6..80clocks.
 write(0,32+2,7);pulse();
 bool seen=false;for(unsigned i=0;i<2000;i++){if(d.req&1){seen=true;break;}tick();}need(seen,"actual PCM transaction establishes busy target");
}
static void keyon_tests(unsigned sample){
 reset(0);pos(0,0,0x10203);write(0,0x22f,1);pos(0,0,0x40506);
 need(read_pos(0,0)==0x10203,"enabled position writes remain latched until214");
 write(0,0x214,1);tick(128);need(read_pos(0,0)==0x40506,"keyon copies complete pending position");need((read(0,0x22c)&1)==1,"keyon activates after complete copy");keyon_cases++;current_case++;
 reset(0);pos(0,0,0x12345);write(0,0x22f,1);pos(0,0,0x34567);write(0,0x214,1);tick(128);
 write(0,0x22f,0x81);write(0,0x215,1);tick(32);need((read(0,0x22c)&1)==1,"bit7 blocks active keyoff");
 write(0,0x22c,0);write(0,0x214,1);tick(128);need((read(0,0x22c)&1)==0,"bit7 blocks active keyon");bit7_cases+=2;current_case++;
 reset(0);busy_start(sample);pos(0,0,0x10203);write(0,0x214,1);pos(0,0,0x40506);tick(3000);
 need(read_pos(0,0)==0x10203,"keyon(A) snapshots immediately; following latchB cannot replace it");snapshot_cases++;current_case++;
 reset(0);busy_start(sample);pos(0,0,0x10203);write(0,0x214,1);write(0,0x215,1);tick(3000);need((read(0,0x22c)&1)==0,"pending keyoff cancels activation");cancel_cases++;current_case++;
 for(unsigned delay=0;delay<8;delay++){
  reset(0);write(0,0x22f,1);pos(0,0,0x10203);write(0,0x214,1);tick(delay);write(0,0x215,1);tick(128);
  need((read(0,0x22c)&1)==0,"keyoff cancels queued/inprogress/completed keyon at every bounded phase");cancel_cases++;current_case++;
 }
 for(unsigned delay=0;delay<8;delay++){
  reset(0);write(0,0x22f,1);pos(0,0,0x10203);pos(0,1,0x20304);write(0,0x214,1);tick(delay);write(0,0x214,2);pos(0,0,0x40506);tick(256);
  need(read_pos(0,0)==0x10203,"concurrent retirement/new keyon cannot replay old channel with new latch");
  need(read_pos(0,1)==0x20304,"second channel pending position survives concurrent retirement");
  need((read(0,0x22c)&3)==3,"both requested channels become active");snapshot_cases++;current_case++;
 }
 // Sample pulse at queued/copy boundaries must be retained, not discarded.
 for(unsigned delay=0;delay<8;delay++){
  reset(0);parameters(0,0,sample,4,0x18);write(0,0x22f,1);pos(0,0,sample);write(0,0x214,1);tick(delay);uint64_t before=requests[0];pulse();tick(3000);
  need(requests[0]>before,"sample pulse retained while keyon copy is queued/inprogress");keyon_cases++;current_case++;
 }
}
// MAME applies the position at214 even if activation is held or later keyed
// off. The hardware byte copier may take bounded clocks, but cannot change the
// transaction ordering or resurrect activation when22f changes during the copy.
static void keyon_edge_tests(unsigned sample){
 const unsigned A=0x10203;
 reset(0);write(0,0x22f,0x81);pos(0,0,A);write(0,0x214,1);write(0,0x215,1);tick(128);
 need(read_pos(0,0)==A,"held214A then215 must still commit all positionA bytes");need((read(0,0x22c)&1)==0,"held214A then215 remains inactive");edge_cases++;current_case++;
 reset(0);write(0,0x22f,0x81);pos(0,0,A);write(0,0x214,1);write(0,0x22f,1);tick(128);
 need(read_pos(0,0)==A,"held214 then22fclear still copiesA");need((read(0,0x22c)&1)==0,"clearingbit7 after held214 cannot activate it later");edge_cases++;current_case++;
 reset(0);write(0,0x22f,1);pos(0,0,A);write(0,0x214,1);
 d.chip=0;d.addr=0x22c;d.cs=1;d.rd=1;tick();
 need((d.rdata[0]&1)==1,"allowed214 activates at transaction before copy completion");d.cs=0;d.rd=0;
 write(0,0x22f,0x81);tick(128);need(read_pos(0,0)==A,"allowed214 thenbit7hold still copiesA");need((read(0,0x22c)&1)==1,"laterbit7hold cannot suppress earlier allowed214");edge_cases++;current_case++;
 reset(0);write(0,0x22f,1);pos(0,0,A);write(0,0x214,1);write(0,0x215,1);tick(128);
 need(read_pos(0,0)==A,"allowed214 then215 preserves full already-keyed positionA");need((read(0,0x22c)&1)==0,"allowed214 then215 remains inactive");edge_cases++;current_case++;
 reset(0);busy_start(sample);pos(0,0,A);write(0,0x214,1);write(0,0x22f,0);write(0,12,6);tick(3000);
 need(read_pos(0,0)==0x10206,"queued214A then disable and direct lowbyteB keeps newestB and otherAbytes");edge_cases++;current_case++;
 reset(0);write(0,0x22f,1);pos(0,0,A);write(0,0x214,1);write(0,0x22f,0);write(0,14,4);tick(128);
 need(read_pos(0,0)==0x40203,"inprogress214A then disable and direct highbyteB cannot be overwritten by oldcopy");edge_cases++;current_case++;
}
static void mix_tests(){
 const unsigned v[]={0,1,0x7fff,0x8000,0xffff,0x4000,0xc000,0x1234};
 for(unsigned p=0;p<3;p++){
  select(p);
  for(unsigned a:v)for(unsigned b:v)for(unsigned c:v)for(unsigned e:v){
   d.probe_l0=a;d.probe_r0=b;d.probe_l1=c;d.probe_r1=e;d.eval();
   unsigned want_l=p?uint16_t(a+c):sat(signed16(b)+signed16(e));
   unsigned want_r=p?uint16_t(b+e):sat(signed16(a)+signed16(c));
   need(d.probe_l[0]==want_l&&d.probe_r[0]==want_r,"actual source mix saturation/stereo versus independent integer contract");
   if(p)need(d.probe_l[0]==d.probe_l[1]&&d.probe_r[0]==d.probe_r[1],"legacy actual mix matches frozen source");
   else need(d.probe_l[0]==d.probe_l[2]&&d.probe_r[0]==d.probe_r[2],"Gaia actual mix matches pinned upstream");mix_vectors++;
  }
 }
}
static unsigned choose_sample(bool negative){
 // Original nonconstant PCM16 data, long enough around either direction;
 // stop markers are rejected, not modified.
 for(unsigned a=1025;a+1024<pcm.size();a+=2){
  int first=signed16(pcm[a]|unsigned(pcm[a+1])<<8);if(negative?first>-16000:first<16000)continue;
  bool okay=true,mixed=false;for(int k=-256;k<=256;k+=2){unsigned x=a+k;unsigned v=pcm[x]|unsigned(pcm[x+1])<<8;okay&=v!=0x8000;mixed|=v!=unsigned(uint16_t(first));}
  if(okay&&mixed)return a;
 }need(false,"original asymmetric PCM16 region selected");return 1025;
}
static void ordinary_tests(unsigned positive,unsigned negative){
 for(unsigned test=0;test<8;test++){
  reset(0);cold_ram();unsigned address=(test&1)?negative:positive;if(test&2)address&=~1u;unsigned mode=(test&4)?0x24:4;unsigned delay=(test&1)?0x30:0;
  for(unsigned c=0;c<2;c++){
   parameters(c,5,address,mode,c?0x1f:0x11,delay);write(c,0x22f,1);pos(c,5,address);write(c,0x214,1u<<5);
  }
  tick(256);
  for(unsigned n=0;n<96;n++){
   pulse();tick(1999);
   need(d.chip_l0[0]==d.chip_l0[2]&&d.chip_r0[0]==d.chip_r0[2]&&d.chip_l1[0]==d.chip_l1[2]&&d.chip_r1[0]==d.chip_r1[2],"Gaia original PCM16/loop/reverse/reverb chip output equals pinned upstream");
   need(d.l[0]==d.l[2]&&d.r[0]==d.r[2],"Gaia actual original-data mixed output equals pinned upstream");
   need(d.l[0]==sat(signed16(d.chip_r0[0])+signed16(d.chip_r1[0]))&&d.r[0]==sat(signed16(d.chip_l0[0])+signed16(d.chip_l1[0])),"actual mix consumes actual chip outputs with specified route/clipping");
   audible_samples+=d.l[0]!=0||d.r[0]!=0;reverb_samples+=delay!=0;gaia_samples++;upstream_samples++;
   transcript<<"GAIA_SAMPLE "<<test<<' '<<n<<' '<<signed16(d.l[0])<<' '<<signed16(d.r[0])<<'\n';
  }current_case++;
 }
}
struct Event{unsigned frame,chip,address,value;};
static void legacy_replay(const std::string&config){
 std::ifstream file(config);std::string row;
 while(getline(file,row)){
  if(row.empty()||row[0]=='#')continue;std::istringstream line(row);unsigned p,first,last;std::string pcm_path,regs1,regs2,event_path;line>>p>>first>>last>>pcm_path>>regs1>>regs2>>event_path;if(!line)exit(2);
  pcm=bytes(pcm_path);need(pcm.size()==0x400000,"legacy original PCM size");reset(p);cold_ram();
  for(unsigned c=0;c<2;c++){
   auto regs=bytes(c?regs2:regs1);need(regs.size()==560,"original560-byte register seed");
   for(unsigned a=0;a<512;a++)write(c,a,regs[a]);
   for(unsigned a=0x200;a<0x230;a++)if(a!=0x214&&a!=0x215&&a!=0x22c&&a!=0x22d&&a!=0x22e&&a!=0x22f)write(c,a,regs[a]);
   write(c,0x22f,regs[0x22f]);write(c,0x22c,regs[0x22c]);
  }
  std::vector<Event> events;std::ifstream ef(event_path);std::string er;
  while(getline(ef,er)){
   if(er.empty()||er[0]=='#')continue;Event e;std::istringstream q(er);q>>e.frame>>e.chip>>std::hex>>e.address>>e.value;if(!q)exit(2);if(e.frame>=first&&e.frame<=last)events.push_back(e);
  }
  need(!events.empty(),"original bounded legacy event window nonempty");
  for(unsigned frame=first;frame<=last;frame++){
   std::vector<Event> current;for(auto e:events)if(e.frame==frame)current.push_back(e);unsigned index=0;
   for(unsigned sample=0;sample<811;sample++){
    unsigned writes=0;
    while(index<current.size()&&index*811/current.size()<=sample){auto e=current[index++];write(e.chip-1,e.address,e.value);trace_events++;writes++;}
    need(writes*2<1900,"constructed original-write spacing fits sample budget");pulse();tick(1999-writes*2);trace_samples++;
    transcript<<"LEGACY_SAMPLE "<<p<<' '<<frame<<' '<<sample<<' '<<signed16(d.l[0])<<' '<<signed16(d.r[0])<<'\n';
   }
  }current_case++;
 }
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=5)return 2;
 std::string suite=argv[1];pcm=bytes(argv[2]);if(pcm.size()!=0x400000)return 2;transcript.open(argv[4]);if(!transcript)return 2;
 d.clk=0;d.cs=d.wr=d.rd=d.cen=0;d.probe_l0=d.probe_l1=d.probe_r0=d.probe_r1=0;
 unsigned positive=choose_sample(false),negative=choose_sample(true);transcript<<"ORIGINAL_PCM_REGIONS "<<positive<<' '<<negative<<'\n';
 if(suite=="keyon"||suite=="full"){keyon_tests(positive);keyon_edge_tests(positive);}
 if(suite=="full"){mix_tests();ordinary_tests(positive,negative);legacy_replay(argv[3]);need(mix_vectors==12288&&gaia_samples==768&&upstream_samples==768&&reverb_samples==384&&audible_samples>0&&legacy_cycles>0&&trace_events>0&&trace_samples>0,"all original-data/mix/legacy coverage");}
 need(keyon_cases==9&&snapshot_cases==9&&cancel_cases==9&&bit7_cases==2&&edge_cases==6,"all keyon/snapshot/cancel/bit7 directed cases complete");
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"keyon_cases\":%llu,\"snapshot_cases\":%llu,\"cancel_cases\":%llu,\"bit7_cases\":%llu,\"edge_cases\":%llu,\"position_checks\":%llu,\"mix_vectors\":%llu,\"gaia_original_samples\":%llu,\"upstream_samples_compared\":%llu,\"audible_samples\":%llu,\"reverb_samples\":%llu,\"legacy_cycles_compared\":%llu,\"original_trace_events\":%llu,\"original_trace_samples\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,(unsigned long long)keyon_cases,(unsigned long long)snapshot_cases,(unsigned long long)cancel_cases,(unsigned long long)bit7_cases,(unsigned long long)edge_cases,(unsigned long long)position_checks,(unsigned long long)mix_vectors,(unsigned long long)gaia_samples,(unsigned long long)upstream_samples,(unsigned long long)audible_samples,(unsigned long long)reverb_samples,(unsigned long long)legacy_cycles,(unsigned long long)trace_events,(unsigned long long)trace_samples);
 return errors?1:0;
}
