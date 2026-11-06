#include "Vm3_vio03_rows_top.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
static Vm3_vio03_rows_top d;
static std::vector<uint8_t> rom;
static uint64_t checks=0,errors=0,pixels=0,order_stalls=0,fragment_stalls=0;
static uint64_t early_entries=0,wait_entries=0,early_skips=0,wait_skips=0;
static unsigned cases=0,zero_cases=0,modes[6]={},kind_cases[4]={},max_cycles=0,late_prefetches=0;
static void need(bool ok,const char *what){checks++;if(!ok){if(errors<32)printf("ERROR %s case=%u state=%u x=%u pen=%u\n",what,cases,d.diagnostic_state,d.x,d.pen);errors++;}}
static void edge(){d.clk=1;d.eval();d.clk=0;d.eval();}
static unsigned pen(unsigned address,unsigned x){unsigned p=0;for(unsigned b=0;b<4;b++)p|=((rom[address*8+(x/8)*4+b]>>(7-x%8))&1)<<b;return p;}
static uint64_t raw(unsigned address){uint64_t q=0;for(unsigned b=0;b<8;b++)q=(q<<8)|rom[address*8+b];return q;}
using Fragment=std::array<unsigned,8>; // x,pen,shadow,level,table,condition,z,priority
static Fragment fragment(){return{d.x,d.pen,d.shadow,d.level,d.shadow_table,d.condition,d.z,d.priority_code};}
int main(int argc,char **argv){
 Verilated::commandArgs(argc,argv);if(argc!=3)return 2;
 std::ifstream f(argv[1],std::ios::binary);if(!f)return 2;rom={std::istreambuf_iterator<char>(f),{}};if(rom.size()!=0x800000)return 2;
 std::ofstream transcript(argv[2]);if(!transcript)return 2;
 unsigned chosen[4]={};bool found[4]={};
 for(unsigned a=0;a<0x100000;a++){
  unsigned kinds=0;bool asymmetric=false;for(unsigned x=0;x<16;x++){unsigned p=pen(a,x);kinds|=p==0?1:p==15?2:4;asymmetric|=p!=pen(a,15-x);}
  int k=kinds==1?0:kinds==2?1:kinds==7?2:((kinds&1)&&(kinds&4)&&!(kinds&2)&&asymmetric)?3:-1;
  if(k>=0&&!found[k]){chosen[k]=a;found[k]=true;}
  if(found[0]&&found[1]&&found[2]&&found[3])break;
 }
 for(bool v:found)need(v,"All4original rowtypes found");if(errors)return 1;
 for(unsigned k=0;k<4;k++)printf("ORIGINAL_ROW kind=%u address=%05x raw=%016llx\n",k,chosen[k],(unsigned long long)raw(chosen[k]));
 static const unsigned xo[8]={0,1,4,5,16,17,20,21},yo[8]={0,2,8,10,32,34,40,42};
 for(unsigned kind=0;kind<4;kind++)for(unsigned mode=0;mode<6;mode++)for(unsigned variant=0;variant<4;variant++){
  unsigned code=chosen[kind]/16,source_row=chosen[kind]%16;
  unsigned width=variant==2?2:variant==3?4:1,scale=variant==2?32:variant==3?128:64;
  unsigned flipx=variant==1||variant==3,flipy=variant==1||variant==2;
  int left=variant==1?-5:variant==2?365:variant==3?96:12;
  unsigned dw=1024/scale,zoom=(0x400000+scale/2)/scale;
  // Height remains16; choose centerY so the requested original raw source row
  // covers native line16 even whenYflipped. No internal state/table forcing.
  unsigned yoff=flipy?15-source_row:source_row;
  int top=16-int(yoff);unsigned center_x=40+left+((zoom*width)>>13);
  d.reset=1;d.start=0;d.ready=d.order_ready=1;d.rom_ack=0;d.rom_q=0;
  for(unsigned i=0;i<12;i++){d.clk=0;d.eval();edge();}d.reset=0;
  d.words[0]=0x8010|((width==4?2:width==2?1:0)<<8)|(flipx?0x1000:0)|(flipy?0x2000:0);
  d.words[1]=code;d.words[2]=unsigned(-(top+8+23))&1023;d.words[3]=(center_x+62)&1023;
  d.words[4]=64;d.words[5]=scale;d.words[6]=0x0100;
  d.order=(32u<<24)|(16u<<16)|(mode<<4)|(2u<<2)|1u;d.line=16;
  std::vector<Fragment> expected,actual;
  unsigned xa=(code&1)|((code>>1)&2)|((code>>2)&4),ya=((code>>1)&1)|((code>>2)&2)|((code>>3)&4);
  for(unsigned column=0;column<width;column++){
   unsigned selected=flipx?width-1-column:column;
   unsigned tile=(code&~63u)+xo[(selected+xa)&7]+yo[ya];
   for(unsigned dx=0;dx<dw;dx++){
    int x=left+int(column*dw+dx);if(x<0||x>=384)continue;
    unsigned source_x=(dx*16)/dw;if(flipx)source_x=15-source_x;
    unsigned p=pen(tile*16+source_row,source_x);
    bool candidate=mode<4?(p!=0&&(!(mode&3)||p<15)):(mode==5?p>=1:p==15);
    if(candidate)expected.push_back({unsigned(x),p,unsigned(mode>=4),(mode&2)?128u:255u,1,2,16,32});
   }
  }
  d.start=1;d.clk=0;d.eval();edge();d.start=0;
  bool pending=false,held=false,ran=false,held_fragment=false,held_order=false;
  unsigned address=0,held_address=0,delay=0,requests=0,orders=0,order_wait_budget=3;
  Fragment previous_fragment{};unsigned previous_priority=0,previous_deferred=0;
  unsigned cycles=0;
  for(;cycles<20000;cycles++){
   d.ready=(cycles%11!=3&&cycles%11!=4&&cycles%17!=9);
   d.order_ready=(cycles%13>=4);d.rom_ack=0;d.clk=0;d.eval();
   if(order_wait_budget&&d.order_valid){d.order_ready=0;order_wait_budget--;d.eval();}
   if(!d.rom_req||(held&&d.rom_addr!=held_address))held=false;
   if(!pending&&!held&&d.rom_req){pending=true;address=d.rom_addr;static const unsigned waits[]={6,80,7,63};delay=waits[requests++%4]+1;}
   if(pending&&!--delay){
    if(d.rom_req&&d.rom_addr==address){d.rom_q=raw(address);d.rom_ack=1;held=true;held_address=address;}
    pending=false;
   }
   d.eval();
   if(held_fragment)need(d.valid&&fragment()==previous_fragment,"Held fragment valid/payload stability");
   if(held_order)need(d.order_valid&&d.order_priority==previous_priority&&d.order_deferred==previous_deferred,"Held order stability");
   held_fragment=d.valid&&!d.ready;previous_fragment=fragment();fragment_stalls+=held_fragment;
   held_order=d.order_valid&&!d.order_ready;previous_priority=d.order_priority;previous_deferred=d.order_deferred;order_stalls+=held_order;
   if(d.order_valid&&d.order_ready){orders++;need(d.order_priority==32&&d.order_deferred,"Original orderpriority/deferred");}
   if(d.valid&&d.ready)actual.push_back(fragment());
   unsigned oldstate=d.diagnostic_state;bool request_wait=pending;edge();unsigned newstate=d.diagnostic_state;
   // Source-bound state encoding: SX3=30,ROWW=31,PIX=32,NEXTTX=33.
   if(oldstate==30&&(newstate==32||newstate==33)){early_entries++;early_skips+=newstate==33;}
   if(oldstate==31&&(newstate==32||newstate==33)){wait_entries++;wait_skips+=newstate==33;}
   if(oldstate==30&&newstate==31&&request_wait)late_prefetches++;
   if(d.busy)ran=true;if(ran&&!d.busy)break;
  }
  need(cycles<20000,"Bounded producer completion");need(orders==1,"Exactlyone orderhandshake evenempty");need(actual==expected,"Full original pixel/controlstream equality");
  if(actual!=expected){printf("STREAM_DIFFERENCE expected=%zu actual=%zu\n",expected.size(),actual.size());for(unsigned i=0;i<std::min(actual.size(),expected.size());i++)if(actual[i]!=expected[i]){printf("FIRST_DIFFERENCE i=%u expected_x=%u pen=%u shadow=%u level=%u actual_x=%u pen=%u shadow=%u level=%u\n",i,expected[i][0],expected[i][1],expected[i][2],expected[i][3],actual[i][0],actual[i][1],actual[i][2],actual[i][3]);break;}}
  transcript<<"CASE "<<cases<<' '<<kind<<' '<<mode<<' '<<variant<<" ORDER "<<orders<<" 32 1\n";
  for(const auto &a:actual){transcript<<"FRAGMENT";for(unsigned v:a)transcript<<' '<<v;transcript<<'\n';}
  printf("CASE %u kind=%u mode=%u variant=%u expected=%zu actual=%zu cycles=%u requests=%u\n",cases,kind,mode,variant,expected.size(),actual.size(),cycles,requests);
  cases++;modes[mode]++;kind_cases[kind]++;pixels+=expected.size();zero_cases+=expected.empty();max_cycles=std::max(max_cycles,cycles);
 }
 need(cases==96,"96cases complete");need(order_stalls>0&&fragment_stalls>0,"Order andfragment backpressure exercised");need(early_entries>0&&wait_entries>0&&late_prefetches>0,"Early andlate rowentry exercised");need(zero_cases>0,"Zero-fragment orders exercised");
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"cases\":%u,\"original_pixels_compared\":%llu,\"zero_fragment_cases\":%u,\"mode_cases\":[%u,%u,%u,%u,%u,%u],\"row_kind_cases\":[%u,%u,%u,%u],\"order_stalls\":%llu,\"fragment_stalls\":%llu,\"early_entries\":%llu,\"wait_entries\":%llu,\"early_empty_skips\":%llu,\"wait_empty_skips\":%llu,\"late_prefetch_waits\":%u,\"max_case_cycles\":%u,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,cases,(unsigned long long)pixels,zero_cases,modes[0],modes[1],modes[2],modes[3],modes[4],modes[5],kind_cases[0],kind_cases[1],kind_cases[2],kind_cases[3],(unsigned long long)order_stalls,(unsigned long long)fragment_stalls,(unsigned long long)early_entries,(unsigned long long)wait_entries,(unsigned long long)early_skips,(unsigned long long)wait_skips,late_prefetches,max_cycles);
 return errors?1:0;
}
