#include "Vm3_vio03_profiles_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>
static Vm3_vio03_profiles_top d;
static std::vector<uint8_t> rom;
static std::ofstream transcript;
static uint64_t errors=0,checks=0,ticks=0,fragments=0,orders=0,requests=0,late_acks=0;
static uint64_t fragment_stalls=0,order_stalls=0,scan_pixels=0,solid_pixels=0,shadow_pixels=0,alpha_fragments=0;
static unsigned completed=0,aborted=0,transition_count=0,profile=0,mode=0;
static unsigned profile_lines[3]={},mode_lines[3]={},profile_mode_lines[9]={},selected[2]={};
static bool pending=false,held=false,compare=true;
static unsigned address=0,held_address=0,remaining=0;
static const unsigned waits[]={6,80,7,63};
using Fragment=std::array<unsigned,8>;
static void need(bool v,const char* what){checks++;if(!v){if(errors<24)printf("ERROR %s tick=%llu transition=%u profile=%u mode=%u\n",what,(unsigned long long)ticks,transition_count,profile,mode);errors++;}}
static uint64_t raw(unsigned a){uint64_t q=0;for(unsigned b=0;b<8;b++)q=(q<<8)|rom[a*8+b];return q;}
static unsigned pen(unsigned a,unsigned x){unsigned p=0;for(unsigned b=0;b<4;b++)p|=((rom[a*8+(x/8)*4+b]>>(7-x%8))&1)<<b;return p;}
static Fragment fragment(unsigned i){return{d.x[i],d.pen[i],unsigned((d.shadow>>i)&1),d.level[i],d.shadow_table[i],d.condition[i],d.z[i],d.priority_code[i]};}
static void compare_ports(){
 need(d.busy==0||d.busy==3,"busy cycle equality");
 need(d.rom_req==0||d.rom_req==3,"ROM request cycle equality");
 if(d.rom_req)need(d.rom_addr[0]==d.rom_addr[1],"ROM requested address equality");
 need(d.order_valid==0||d.order_valid==3,"order valid cycle equality");
 if(d.order_valid){need(d.order_priority[0]==d.order_priority[1]&&(d.order_deferred==0||d.order_deferred==3),"order public metadata equality");}
 need(d.valid==0||d.valid==3,"fragment valid cycle equality");
 if(d.valid)need(fragment(0)==fragment(1),"full public fragment payload equality, including stalled cycle");
 need(d.objects[0]==d.objects[1]&&d.rows[0]==d.rows[1]&&d.columns[0]==d.columns[1]&&d.writes[0]==d.writes[1],"public diagnostic counters equality");
 // RAM/list addresses only have a consumption contract once rendering is active.
 if(d.busy)need(d.ram_addr[0]==d.ram_addr[1]&&d.list_idx[0]==d.list_idx[1]&&d.yr_addr[0]==d.yr_addr[1],"actual synchronous memory request equality");
}
static void prepare(){
 d.clk=0;d.rom_ack=0;d.ready=ticks%11!=3&&ticks%11!=4;d.order_ready=ticks%13>=4;d.eval();
 if(!d.rom_req||(held&&d.rom_addr[0]!=held_address))held=false;
 if(!pending&&!held&&d.rom_req){
  pending=true;address=d.rom_addr[0];remaining=waits[requests%4]+1;requests++;
  transcript<<"REQUEST "<<ticks<<' '<<address<<' '<<remaining<<'\n';
 }
 if(pending&&!--remaining){
  // Deliver immutable data even if reset or profile change withdrew the request.
  d.rom_q=raw(address);d.rom_fifth=uint16_t(raw(address));d.rom_ack=1;
  if(!d.rom_req||d.rom_addr[0]!=address)late_acks++;
  else{held=true;held_address=address;}
  pending=false;transcript<<"ACK "<<ticks<<' '<<address<<' '<<unsigned(d.reset)<<'\n';
 }
 d.eval();if(compare)compare_ports();
}
static void edge(){d.clk=1;d.eval();d.clk=0;d.eval();ticks++;}
static void tick(){prepare();edge();}
static void choose_profile(unsigned p){profile=p;d.mystic=p==1;d.violent=p==2;}
static void descriptor(unsigned a,unsigned drawmode){
 mode=drawmode;unsigned code=a/16,row=a%16;int top=16-int(row);
 int dx=profile==0?-61:profile==1?-48:-62;
 int dy=profile==0?-22:profile==1?-24:-23;
 int cls=profile==1?24:40;
 d.words[0]=0x8010;d.words[1]=code;
 d.words[2]=unsigned(-(top+8-dy))&1023;
 d.words[3]=unsigned(cls+12+8-dx)&1023;
 d.words[4]=64;d.words[5]=64;d.words[6]=0x0100;
 d.order=(32u<<24)|(16u<<16)|(drawmode<<4)|(2u<<2)|1u;
 d.line=16;d.list_count=1;
}
static void reset_to(unsigned p,bool preserve_pending){
 d.reset=1;d.start=0;choose_profile(p);compare=false;
 if(!preserve_pending){pending=held=false;}
 for(unsigned i=0;i<256;i++){tick();if(i>=2)need(!d.busy&&!d.valid&&!d.order_valid&&!d.rom_req,"reset drains public work while profile settles");}
 need(!pending,"old ROM ACK delivered inside 256-cycle reset window");
 d.reset=0;compare=true;tick();
}
static void start(){d.start=1;tick();d.start=0;}
static void compare_scan(){
 need(d.opaque==0||d.opaque==3,"legacy opaque flag equality");
 need(d.scan_shadow==0||d.scan_shadow==3,"legacy shadow flag equality");
 if(d.opaque)need(d.scan_pen[0]==d.scan_pen[1]&&d.scan_pri[0]==d.scan_pri[1]&&d.scan_effect[0]==d.scan_effect[1],"legacy solid payload equality");
 if(d.scan_shadow)need(d.scan_table[0]==d.scan_table[1]&&d.scan_shpri[0]==d.scan_shpri[1],"legacy shadow payload equality");
}
static void scan_completed_legacy(){
 // Public scanout reads the previous bank. A zero-object next line swaps banks,
 // exposing the completed bank while clearing the other one. No hierarchy peeks.
 d.list_count=0;start();unsigned visible=0;
 for(unsigned x=0;x<376;x++){
  d.px=x;tick();compare_scan();scan_pixels++;
  if(d.opaque||d.scan_shadow)visible++;
  solid_pixels+=(d.opaque&1)!=0;shadow_pixels+=(d.scan_shadow&1)!=0;
  transcript<<"PIXEL "<<completed<<' '<<x<<' '<<unsigned(d.opaque&1)<<' '<<(d.opaque?d.scan_pen[0]:0)<<' '<<(d.opaque?d.scan_pri[0]:0)<<' '<<(d.opaque?d.scan_effect[0]:0)<<' '<<unsigned(d.scan_shadow&1)<<' '<<(d.scan_shadow?d.scan_table[0]:0)<<' '<<(d.scan_shadow?d.scan_shpri[0]:0)<<'\n';
 }
 for(unsigned n=0;d.busy&&n<20000;n++)tick();
 need(!d.busy,"zero-object scanout helper terminates");need(visible>0,"legacy completed line has visible original-data pixels");
 d.list_count=1;
}
static void finish(){
 unsigned count=0,order_count=0,n=0;bool ran=d.busy;
 for(;n<20000;n++){
  prepare();
  if(d.order_valid&&!d.order_ready)order_stalls++;
  if(d.valid&&!d.ready)fragment_stalls++;
  if((d.order_valid&1)&&d.order_ready){orders++;order_count++;transcript<<"ORDER "<<completed<<' '<<ticks<<' '<<unsigned(d.order_priority[0])<<' '<<unsigned(d.order_deferred&1)<<'\n';}
  if((d.valid&1)&&d.ready){
   fragments++;count++;auto f=fragment(0);transcript<<"FRAGMENT "<<completed<<' '<<ticks;for(unsigned x:f)transcript<<' '<<x;transcript<<'\n';
   if(mode==5)need(f[2]==1,"shadow mode observable at accepted consumer");
   if(mode==2){need(f[3]==128,"alpha mode observable at accepted consumer");alpha_fragments++;}
  }
  edge();ran|=d.busy;if(ran&&!d.busy)break;
 }
 need(n<20000,"bounded meaningful line completion");
 if(profile){need(count>0&&order_count==1,"exactly one public streaming order with visible original-data fragments");}
 else{need(count==0&&order_count==0,"Gaia uses legacy public bank consumer");scan_completed_legacy();}
 unsigned mi=mode==0?0:mode==5?1:2;profile_lines[profile]++;mode_lines[mi]++;profile_mode_lines[profile*3+mi]++;completed++;
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=3)return 2;
 std::ifstream f(argv[1],std::ios::binary);rom={std::istreambuf_iterator<char>(f),{}};if(rom.size()!=0x800000)return 2;
 transcript.open(argv[2]);if(!transcript)return 2;
 unsigned found=0;
 for(unsigned a=0;a<0x100000&&found<2;a++){
  bool mixed=false,visible=false;unsigned first=pen(a,0);
  for(unsigned x=0;x<16;x++){unsigned p=pen(a,x);mixed|=p!=first;visible|=p>0&&p<15;}
  if(mixed&&visible&&(!found||a/16!=selected[0]/16))selected[found++]=a;
 }
 need(found==2,"two distinct original asymmetric visible rows");if(errors)return 1;
 const unsigned modes[3]={0,5,2};
 d.start=0;d.px=0;d.rom_ack=0;d.rom_q=0;d.rom_fifth=0;
 for(unsigned from=0;from<3;from++)for(unsigned to=0;to<3;to++){
  transcript<<"TRANSITION "<<transition_count<<' '<<from<<' '<<to<<'\n';
  unsigned selected_mode=modes[(from+to)%3];
  reset_to(from,false);descriptor(selected[0],selected_mode);start();finish();
  descriptor(selected[1],selected_mode);start();bool reached=false;
  for(unsigned n=0;n<20000;n++){
   prepare();
   if(pending&&remaining>=3){need(d.busy==3,"abort occurs during active original-data ROM transaction");reached=true;edge();break;}
   edge();
  }
  need(reached,"new distinct row has an outstanding ROM transaction before abort");
  uint64_t before=late_acks;reset_to(to,true);need(late_acks==before+1,"exactly one late old-profile ACK delivered during reset");aborted++;
  descriptor(selected[1],selected_mode);start();finish();
  descriptor(selected[1],selected_mode);start();finish();transition_count++;
 }
 need(transition_count==9&&completed==27&&aborted==9,"all9 ordered profile transitions,27 completed lines,9 aborts");
 need(profile_lines[0]==9&&profile_lines[1]==9&&profile_lines[2]==9,"all profiles have9 completed lines");
 need(mode_lines[0]==9&&mode_lines[1]==9&&mode_lines[2]==9,"solid/shadow/alpha each have9 completed lines");
 for(unsigned n:profile_mode_lines)need(n==3,"every profile/mode pair has3 meaningful completed lines");
 need(solid_pixels>0&&shadow_pixels>0&&alpha_fragments>0,"all draw modes observable at actual consumers");
 need(fragment_stalls>0&&order_stalls>0&&late_acks==9,"backpressure and9 late replies exercised");
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"transitions\":%u,\"completed_lines\":%u,\"aborted_lines\":%u,\"profile_lines\":[%u,%u,%u],\"mode_lines\":[%u,%u,%u],\"profile_mode_lines\":[%u,%u,%u,%u,%u,%u,%u,%u,%u],\"fragments\":%llu,\"orders\":%llu,\"requests\":%llu,\"late_acks\":%llu,\"fragment_stalls\":%llu,\"order_stalls\":%llu,\"legacy_scan_pixels\":%llu,\"legacy_solid_pixels\":%llu,\"legacy_shadow_pixels\":%llu,\"alpha_fragments\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,transition_count,completed,aborted,profile_lines[0],profile_lines[1],profile_lines[2],mode_lines[0],mode_lines[1],mode_lines[2],profile_mode_lines[0],profile_mode_lines[1],profile_mode_lines[2],profile_mode_lines[3],profile_mode_lines[4],profile_mode_lines[5],profile_mode_lines[6],profile_mode_lines[7],profile_mode_lines[8],(unsigned long long)fragments,(unsigned long long)orders,(unsigned long long)requests,(unsigned long long)late_acks,(unsigned long long)fragment_stalls,(unsigned long long)order_stalls,(unsigned long long)scan_pixels,(unsigned long long)solid_pixels,(unsigned long long)shadow_pixels,(unsigned long long)alpha_fragments);
 return errors?1:0;
}
