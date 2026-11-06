#include "Vm3_vio03_response_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>
static Vm3_vio03_response_top d;
static std::vector<uint8_t> rom;
static uint64_t errors=0,checks=0,late_acks=0,ticks=0;
static unsigned cases=0,hit_cases=0,miss_cases=0,pending_cancels=0,profile_cancels=0;
static bool pending=false,held=false;
static unsigned address=0,held_address=0,remaining=0;
using Fragment=std::array<unsigned,8>;
struct Stream {std::vector<Fragment> fragments;unsigned orders=0;bool operator==(const Stream &s)const{return orders==s.orders&&fragments==s.fragments;}};
static void need(bool ok,const char *why){checks++;if(!ok){if(errors<32)printf("ERROR %s case=%u state=%u cache=%u pending=%u\n",why,cases,d.diagnostic_state,d.cache_state,d.response_pending);errors++;}}
static uint64_t raw(unsigned a){uint64_t q=0;for(unsigned b=0;b<8;b++)q=(q<<8)|rom[a*8+b];return q;}
static unsigned pen(unsigned a,unsigned x){unsigned p=0;for(unsigned b=0;b<4;b++)p|=((rom[a*8+(x/8)*4+b]>>(7-x%8))&1)<<b;return p;}
static void prepare(){
 d.clk=0;d.rom_ack=0;d.ready=(ticks%11!=3);d.order_ready=(ticks%13>=2);d.eval();
 if(!d.rom_req||(held&&d.rom_addr!=held_address))held=false;
 if(!pending&&!held&&d.rom_req){pending=true;address=d.rom_addr;remaining=27;}
 if(pending&&!--remaining){
  // Deliberately deliver an already-issued immutable reply even after abort.
  // The production gaia_mem may suppress it; the cache must reject it too.
  d.rom_q=raw(address);d.rom_ack=1;
  if(!d.rom_req||d.rom_addr!=address)late_acks++;
  else {held=true;held_address=address;}
  pending=false;
 }
 d.eval();
}
static void edge(){d.clk=1;d.eval();d.clk=0;d.eval();ticks++;}
static void reset(){
 d.reset=1;d.start=0;d.violent=1;d.rom_ack=0;pending=held=false;
 for(unsigned i=0;i<12;i++){prepare();edge();}d.reset=0;
}
static void descriptor(unsigned a){
 unsigned code=a/16,row=a%16;int top=16-int(row);
 d.words[0]=0x8010;d.words[1]=code;d.words[2]=unsigned(-(top+8+23))&1023;
 d.words[3]=(40+12+8+62)&1023;d.words[4]=64;d.words[5]=64;d.words[6]=0x0100;
 d.order=(32u<<24)|(16u<<16)|(2u<<2)|1u;d.line=16;
}
static void start(){d.start=1;prepare();edge();d.start=0;}
static Stream finish(){
 Stream s;bool ran=d.busy;unsigned n=0;
 for(;n<20000;n++){
  prepare();
  if(d.valid&&d.ready)s.fragments.push_back({d.x,d.pen,d.shadow,d.level,d.shadow_table,d.condition,d.z,d.priority_code});
  if(d.order_valid&&d.order_ready){need(d.order_priority==32&&d.order_deferred,"Order metadata");s.orders++;}
  edge();ran|=d.busy;if(ran&&!d.busy)break;
 }
 need(n<20000,"Bounded full-line completion");need(s.orders==1,"Exactlyone new-line order");need(!s.fragments.empty(),"Original target contains visible fragments");return s;
}
int main(int argc,char **argv){
 Verilated::commandArgs(argc,argv);if(argc!=3)return 2;
 std::ifstream f(argv[1],std::ios::binary);rom={std::istreambuf_iterator<char>(f),{}};if(rom.size()!=0x800000)return 2;
 std::ofstream transcript(argv[2]);if(!transcript)return 2;
 unsigned selected[2]={};unsigned found=0;
 for(unsigned a=0;a<0x100000&&found<2;a++){
  bool visible=false,mixed=false;unsigned first=pen(a,0);
  for(unsigned x=0;x<16;x++){unsigned p=pen(a,x);visible|=p>0&&p<15;mixed|=p!=first;}
  if(visible&&mixed&&(!found||a/16!=selected[0]/16)){selected[found++]=a;}
 }
 need(found==2,"Two distinct original nonempty asymmetric rows");if(errors)return 1;
 reset();descriptor(selected[1]);start();Stream golden=finish();
 for(unsigned warm=0;warm<2;warm++)for(unsigned action=0;action<3;action++)for(unsigned stage=0;stage<3;stage++){
  reset();descriptor(selected[0]);
  if(warm){start();finish();}
  start();bool reached=false;
  for(unsigned n=0;n<20000;n++){
   prepare();
   bool target=stage==0?d.cache_state==(warm?2:5):stage==1?bool(d.cache_response):bool(d.response_pending);
   if(target){
    reached=true;need(d.busy,"Abort occurs during actual active drawer");
    // Next descriptor differs, so a stale response cannot accidentally pass.
    descriptor(selected[1]);
    if(action==0)d.start=1;
    else if(action==1)d.reset=1;
    else {d.violent=0;d.reset=1;}
    d.eval();edge();d.start=0;
    if(action){
     for(unsigned k=0;k<4;k++){prepare();edge();need(!d.response_pending,"Reset/profile clears pending response");}
     // Restore the profile while reset remains asserted, matching the actual
     // Pocket256clock release guard. Late memory reply still arrives naturally.
     d.violent=1;
     for(unsigned k=0;k<256;k++){prepare();edge();need(!d.response_pending,"Settled profile under reset clears pending response");}
     d.reset=0;start();
    }
    break;
   }
   edge();
  }
  need(reached,"Miss/hit selected response stage reached");
  Stream actual=finish();need(actual==golden,"Full new-line stream equals clean original-row execution");
  transcript<<"CASE "<<cases<<" WARM "<<warm<<" ACTION "<<action<<" STAGE "<<stage<<" ORDERS "<<actual.orders<<'\n';
  for(auto &v:actual.fragments){transcript<<"FRAGMENT";for(unsigned x:v)transcript<<' '<<x;transcript<<'\n';}
  cases++;hit_cases+=warm;miss_cases+=!warm;pending_cancels+=stage==2;profile_cancels+=action==2;
 }
 need(cases==18&&hit_cases==9&&miss_cases==9&&pending_cancels==6&&profile_cancels==6,"All18 cancellation cases executed");need(late_acks>0,"Withdrawn request receives late original-data ACK");
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"cases\":%u,\"late_acks\":%llu,\"hit_cases\":%u,\"miss_cases\":%u,\"pending_cancels\":%u,\"profile_cancels\":%u,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,cases,(unsigned long long)late_acks,hit_cases,miss_cases,pending_cancels,profile_cancels);
 return errors?1:0;
}
