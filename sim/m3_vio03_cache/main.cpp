// Actual RTL helper, original immutable8MiB row bytes, external request/ACK only.
#include "Vm3_vio03_cache_top.h"
#include "verilated.h"
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
static Vm3_vio03_cache_top *d;
static std::vector<uint8_t> rom;
static uint64_t cycles=0,checks=0,errors=0,memory_requests=0,memory_acks=0;
static uint64_t memory_dropped=0,accepted=0,cancelled_stages=0,profiles=0;
static unsigned latency_min=999,latency_max=0,tag_pairs=0,bypass_checks=0;
static bool pending=false,held=false;
static unsigned pending_address=0;static uint64_t due=0;
struct Sample{bool ack;uint64_t data;};
static uint64_t row(unsigned a){if(a>=0x100000){fprintf(stderr,"badROMaddr\n");exit(2);}uint64_t q=0;for(unsigned i=0;i<8;i++)q|=uint64_t(rom[a*8+i])<<(8*i);return q;}
static void check(bool ok,const char *name){checks++;if(!ok){if(errors<32)printf("ERROR %s cycle=%llu state=%u req=%u addr=%05x mreq=%u maddr=%05x\n",name,(unsigned long long)cycles,d->diagnostic_state,d->c_req,d->c_addr,d->m_req,d->m_addr);errors++;}}
static void low(){d->clk=0;d->eval();}
static void edge(){d->clk=1;d->eval();d->clk=0;d->eval();cycles++;}
static Sample step(){
 low();d->m_ack=0;
 if(!d->m_req)held=false;
 if(pending&&cycles>=due){
  d->m_q=row(pending_address);
  // Actual gaia_mem ownership contract: old burst completion cannot ACK a
  // currently withdrawn request or one for a different20bit row address.
  if(d->m_req&&d->m_addr==pending_address){d->m_ack=1;memory_acks++;held=true;}
  else memory_dropped++;
  pending=false;
 }else if(!pending&&!held&&d->m_req){
  static const unsigned delays[]={6,80,7,63,24,55,79,12};
  unsigned wait=delays[memory_requests%8];memory_requests++;
  latency_min=std::min(latency_min,wait);latency_max=std::max(latency_max,wait);
  pending_address=d->m_addr;due=cycles+wait;pending=true;
 }
 d->eval();Sample s{bool(d->c_ack),d->c_q};
 if(d->enable&&(!d->c_req||d->reset))check(!s.ack,"No response for withdrawn/reset request");
 if(s.ack&&d->c_req){check(s.data==row(d->c_addr),"Every admitted response original complete64bit row");accepted++;}
 edge();return s;
}
static void withdraw(unsigned clocks=8){d->c_req=0;for(unsigned i=0;i<clocks;i++)step();}
static void reset_cache(){d->c_req=0;d->enable=1;d->reset=1;step();step();check(d->diagnostic_valid_count==0,"Reset invalidates32entries");d->reset=0;withdraw(84);}
static unsigned request(unsigned address){
 d->c_req=1;d->c_addr=address;unsigned n=0;
 for(;n<240;n++)if(step().ack)return n+1;
 check(false,"Request240cycle deadline");return n;
}
static void miss(unsigned a){uint64_t before=memory_requests;request(a);check(memory_requests==before+1,"Expected one memory miss");withdraw();}
static void hit(unsigned a){uint64_t before=memory_requests;unsigned n=request(a);check(memory_requests==before,"Expected cache hit without memory");check(n<=8,"Bounded synchronous packed hit");withdraw();}
static void reach(unsigned address,unsigned state){
 d->c_req=1;d->c_addr=address;unsigned n=0;
 while(d->diagnostic_state!=state&&n++<180){Sample s=step();check(!s.ack||(state==6&&d->diagnostic_state==6),"Cancellation stage reached before public response exceptFILLHI afterACK");}
 check(d->diagnostic_state==state,"Reached requested passive state");
}
int main(int argc,char **argv){
 Verilated::commandArgs(argc,argv);if(argc!=2)return 2;
 std::ifstream f(argv[1],std::ios::binary);if(!f)return 2;
 rom={std::istreambuf_iterator<char>(f),{}};if(rom.size()!=0x800000)return 2;
 d=new Vm3_vio03_cache_top;d->reset=1;d->enable=1;d->c_req=0;d->m_ack=0;d->m_q=row(0);reset_cache();
 // Pick distinct, asymmetric original rows so swapped halves/stale tags cannot
 // accidentally pass with all-zero or identical64bit values. No bytes changed.
 std::vector<unsigned> addresses;
 for(unsigned a=0;a<0x100000&&addresses.size()<40;a++){
  uint64_t q=row(a);if(!q||q==~uint64_t(0)||uint32_t(q)==uint32_t(q>>32))continue;
  bool unique=true;for(unsigned b:addresses)if(row(b)==q)unique=false;
  if(unique)addresses.push_back(a);
 }
 check(addresses.size()==40,"40distinct asymmetric original rows available");if(addresses.size()!=40)return 1;
 unsigned a=addresses[0],b=addresses[1],c=addresses[2];
 miss(a);hit(a);
 // All20tagbits: for every bit pick a real pair differing only by that bit,
 // with different original data, then require both coexist as distinct hits.
 for(unsigned bit=0;bit<20;bit++){
  unsigned mask=1u<<bit,base=0;bool found=false;
  for(unsigned x=0;x<4096&&!found;x++){unsigned y=x&~mask;if(row(y)!=row(y|mask)&&row(y)&&row(y|mask)){base=y;found=true;}}
  check(found,"Original distinct tag-bit pair exists");if(!found)continue;
  reset_cache();miss(base);miss(base|mask);hit(base);hit(base|mask);tag_pairs++;
 }
 reset_cache();for(unsigned i=0;i<32;i++)miss(addresses[i]);
 check(d->diagnostic_valid_count==32,"Fully associative32rows occupied");
 for(unsigned i=0;i<32;i++)hit(addresses[i]);
 miss(addresses[32]);miss(addresses[0]); // slot0 evicted by33rd insertion.
 // Continuous c_req: repeated same-row prefetch and changing addresses onACK.
 reset_cache();uint64_t before=memory_requests;for(unsigned i=0;i<12;i++)request(a);
 check(memory_requests==before+1,"Held same addressbacktoback onlyoneROMmiss");
 for(unsigned i=0;i<12;i++)request(i&1?a:b);withdraw();hit(a);hit(b);
 // State encoding is bound to exact compiled source: IDLE0 LOOK1 READ0=2
 // READ1=3 RESP4 MISS5 FILLHI6. Observation never steers internal state.
 for(unsigned phase=1;phase<=4;phase++){
  reset_cache();miss(a);reach(a,phase);d->c_req=0;low();check(!d->c_ack,"CancelLOOK/READ/RESP suppressesACK immediately");step();withdraw(84);hit(a);cancelled_stages++;
 }
 // Late externalACK after withdrawal or duringLOOK cannot become a response.
 // Public memorypins only; originaldata, no hidden state forcing.
 for(bool withdrawn: {false,true}){
  reset_cache();reach(a,withdrawn?5:1);if(withdrawn)d->c_req=0;
  d->m_ack=1;d->m_q=row(a);low();check(!d->c_ack,"LateACK whilewithdrawn/LOOK suppressed");edge();d->m_ack=0;withdraw(84);cancelled_stages++;
 }
 // Miss withdrawn before physicalACK: old burst still completes privately,
 // but ownership-qualified memory model drops its ACK while no request owns it.
 reset_cache();reach(b,5);step();step();d->c_req=0;low();check(!d->m_req&&!d->c_ack,"CancelMISS withdraws lower request");step();withdraw(84);miss(b);cancelled_stages++;
 // Address changes whileoldrequestLOOK/RESP/MISS: no stale hit orROMresponse.
 for(unsigned phase: {1u,4u,5u}){
  reset_cache();if(phase!=5)miss(a);reach(a,phase);if(phase==5)step();
  d->c_addr=b;low();check(!d->c_ack,"Address drift suppresses old response");
  if(phase==5)check(!d->m_req,"Address drift withdraws old miss");
  request(b);withdraw(84);hit(b);cancelled_stages++;
 }
 // MissACK admits current row before packed high-half fill. Withdraw/change
 // immediately afterACK must allow immutable fill completion and correct hits.
 reset_cache();request(a);check(d->diagnostic_state==6,"MissACK reaches packedFILLHI");
 d->c_req=0;step();withdraw();hit(a);cancelled_stages++;
 reset_cache();request(a);d->c_addr=b;request(b);withdraw();hit(a);hit(b);
 // Reset at every activephase: no response survives; previouslycachedrow misses.
 for(unsigned phase=1;phase<=6;phase++){
  reset_cache();if(phase<5)miss(a);reach(a,phase);
  d->reset=1;low();check(!d->c_ack&&!d->m_req,"Active reset suppresses cached interface");step();d->reset=0;withdraw(84);miss(a);profiles++;
 }
 // Exact combinational nonVio bypass, including reset, request low and ACKhigh.
 // Drive only external memory pins, always using unmodified original row data.
 withdraw(84);pending=false;held=false;d->enable=0;
 for(unsigned rst=0;rst<2;rst++)for(unsigned req=0;req<2;req++)for(unsigned ack=0;ack<2;ack++)for(unsigned i=0;i<20;i++){
  unsigned addr=(i*65537u)&0xfffff;d->reset=rst;d->c_req=req;d->c_addr=addr;d->m_ack=ack;d->m_q=row(addresses[i]);low();
  check(d->m_req==req&&d->m_addr==addr&&d->c_ack==ack&&d->c_q==row(addresses[i]),"NonVio exact req/address/ACK/data combinational bypass");edge();bypass_checks++;
 }
 d->m_ack=0;d->c_req=0;d->reset=0;d->enable=1;withdraw(84);miss(a);profiles++;
 // Profiledisable during lookup and physicalmiss invalidates allcache state;
 // lower request/data/ACK bypass remain exact for the disabled profile.
 for(unsigned phase: {1u,5u,6u}){
  reset_cache();if(phase==1)miss(a);reach(a,phase);d->enable=0;d->c_req=0;step();
  check(d->diagnostic_valid_count==0,"Profiledisable invalidates cache");
  d->enable=1;withdraw(84);miss(a);profiles++;
 }
 check(tag_pairs==20,"All20addressbit pairscovers");check(latency_min==6&&latency_max==80,"Memory6..80latencyenvelope covered");
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"original_row_responses\":%llu,\"memory_requests\":%llu,\"memory_acks\":%llu,\"cancelled_burst_completions\":%llu,\"tag_bit_pairs\":%u,\"cancellation_cases\":%llu,\"reset_profile_cases\":%llu,\"bypass_cases\":%u,\"memory_latency_min\":%u,\"memory_latency_max\":%u,\"cycles\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,(unsigned long long)accepted,(unsigned long long)memory_requests,(unsigned long long)memory_acks,(unsigned long long)memory_dropped,tag_pairs,(unsigned long long)cancelled_stages,(unsigned long long)profiles,bypass_checks,latency_min,latency_max,(unsigned long long)cycles);
 delete d;return errors?1:0;
}
