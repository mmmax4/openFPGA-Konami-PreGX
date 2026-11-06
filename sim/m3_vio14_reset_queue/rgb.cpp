#include "Vm3_vio14_rgb_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
// Public actual drawer/compositor/RGB ports only. Observer ports are pure
// aliases added in frozen copies, with exact source inverse proof by runner.
static Vm3_vio14_rgb_top d;
static std::vector<uint8_t> rom;
static uint64_t checks=0,errors=0,ticks=0,requests=0,late_acks=0;
static uint64_t fragments=0,orders=0,stalls=0,order_stalls=0,pixels=0,nonzero=0;
static uint64_t reset_ready_differences=0,reset_lookahead_differences=0,reset_cycles=0;
static unsigned cases=0,warm_lines=0,recovery_lines=0,helper_lines=0,deadlines=0,worst=0;
static unsigned profile=0,mode=0,phase=0,selected[2]={};
static unsigned phase_cases[5]={},profile_cases[2]={},mode_cases[3]={};
static bool pending=false,held=false;
static unsigned address=0,remaining=0,held_address=0;
static const unsigned waits[]={6,80,7,63};
static void need(bool v,const char* what){checks++;if(!v){if(errors<24)printf("ERROR %s tick=%llu profile=%u mode=%u phase=%u\n",what,(unsigned long long)ticks,profile,mode,phase);errors++;}}
static uint64_t raw(unsigned a){need(a<0x100000,"original ROM address bounds");uint64_t q=0;if(a>=0x100000)return 0;for(unsigned b=0;b<8;b++)q=(q<<8)|rom[a*8+b];return q;}
static unsigned pen(unsigned a,unsigned x){unsigned p=0;for(unsigned b=0;b<4;b++)p|=((rom[a*8+(x/8)*4+b]>>(7-x%8))&1)<<b;return p;}
static std::array<unsigned,8> fragment(unsigned i){return{d.x[i],d.pen[i],unsigned((d.shadow>>i)&1),d.level[i],d.shadow_table[i],d.condition[i],d.z[i],d.priority_code[i]};}
static void compare(){
 need(d.busy==0||d.busy==3,"drawer busy equality");
 need(d.consumer_busy==0||d.consumer_busy==3,"actual compositor busy equality");
 need(d.rom_req==0||d.rom_req==3,"actual ROM request equality");
 if(d.rom_req)need(d.rom_addr[0]==d.rom_addr[1],"actual ROM requested address equality");
 need(d.order_valid==0||d.order_valid==3,"order valid equality");
 if(d.order_valid)need(d.order_priority[0]==d.order_priority[1]&&(d.order_deferred==0||d.order_deferred==3),"order fields equality");
 need(d.valid==0||d.valid==3,"fragment valid equality");
 if(d.valid)need(fragment(0)==fragment(1),"entire fragment payload equality including stall");
 need(d.palette_addr[0]==d.palette_addr[1],"actual palette address equality");
 need(d.rgb[0]==d.rgb[1],"actual public RGB scan pixel equality without reset mask");
 need(d.consumer_order_ready==0||d.consumer_order_ready==3,"order-ready equality");
 if(d.reset){
  need(!(d.admission[0]&8)&&!(d.admission[1]&8),"raw reset forbids actual accumulator accept");
  reset_cycles++;
  if((d.admission[0]&7)!=(d.admission[1]&7))reset_ready_differences++;
  if(d.tile_x[0]!=d.tile_x[1])reset_lookahead_differences++;
 }else{
  need(d.admission[0]==d.admission[1],"all actual ready/accept ports equal outside rawreset");
  need(d.consumer_ready==0||d.consumer_ready==3,"actual producer fragment-ready equality outside rawreset");
  need(d.tile_x[0]==d.tile_x[1],"actual synchronous tile lookahead equality outside rawreset");
 }
 if(d.busy)need(d.ram_addr[0]==d.ram_addr[1]&&d.list_idx[0]==d.list_idx[1]&&d.yr_addr[0]==d.yr_addr[1],"actual synchronous sprite RAM/list/range consumption equality");
}
static void prepare(){
 d.clk=0;d.rom_ack=0;d.eval();
 if(!d.rom_req||(held&&d.rom_addr[0]!=held_address))held=false;
 if(!pending&&!held&&d.rom_req){pending=true;address=d.rom_addr[0];remaining=waits[requests%4]+1;requests++;}
 if(pending&&!--remaining){d.rom_q=raw(address);d.rom_fifth=uint16_t(raw(address));d.rom_ack=1;if(!d.rom_req||d.rom_addr[0]!=address)late_acks++;else{held=true;held_address=address;}pending=false;}
 d.eval();compare();
 if(!d.reset){
  if((d.order_valid&1)&&(d.consumer_order_ready&1))orders++;
  if((d.order_valid&1)&&!(d.consumer_order_ready&1))order_stalls++;
  if((d.valid&1)&&(d.consumer_ready&1))fragments++;
  if((d.valid&1)&&!(d.consumer_ready&1))stalls++;
 }
}
static void edge(){d.clk=1;d.eval();d.clk=0;d.eval();ticks++;compare();}
static void tick(){prepare();edge();}
static void start(){d.start=1;tick();d.start=0;}
static void finish(unsigned already=1){
 unsigned n=already;while((d.busy||d.consumer_busy)&&n<6144){tick();n++;}
 need(!d.busy&&!d.consumer_busy,"actual drawer and RGB consumer line deadline6144");
 need(n<6144,"strict line deadline");if(n>worst)worst=n;deadlines++;
}
static void descriptor(unsigned row,unsigned operation){
 unsigned code=row/16,yr=row%16;int dy=profile==1?-24:-23,dx=profile==1?-48:-62,origin=profile==1?24:40;
 int top=16-int(yr);
 d.words[0]=0x8010;d.words[1]=code;d.words[2]=unsigned(-(top+8-dy))&1023;
 d.words[3]=unsigned(origin+12+8-dx)&1023;d.words[4]=64;d.words[5]=64;d.words[6]=0x0100;
 d.order=(32u<<24)|(16u<<16)|(operation<<4)|(2u<<2)|1u;d.line=16;d.list_count=1;
}
static void load_case(const char* path){
 std::ifstream f(path);std::string token;unsigned p,w,n,value;
 f>>token>>p>>w;if(token!="PROFILE"||p!=profile||w!=(profile==1?288:384))throw std::string("profile format");
 f>>token>>n;if(token!="K55"||n!=48)throw std::string("K55 format");for(unsigned i=0;i<n;i++){f>>std::hex>>value;d.k55regs[i]=value;}
 f>>token>>std::dec>>n;if(token!="K38"||n!=16)throw std::string("K38 format");for(unsigned i=0;i<n;i++){f>>std::hex>>value;d.k38regs[i]=value;}
 // Explicit legal constructed controls: make both tile and sprite consumers
 // observable in every reset case; preserve captured palette/tile data bytes.
 d.k55regs[45]=31;d.k38regs[15]|=1;
 for(unsigned index:{7U,10U,13U,14U})d.k55regs[index]=64;
 f>>token>>std::dec>>n;if(token!="PALETTE"||n!=2048)throw std::string("palette format");
 d.palette_we=1;for(unsigned i=0;i<n;i++){f>>std::hex>>value;d.setup_addr=i;d.setup_data=value;tick();}d.palette_we=0;
 f>>token>>std::dec>>n;if(token!="TILES"||n!=4*w)throw std::string("tiles format");
 d.tile_nonempty=0;d.tile_we=1;
 for(unsigned l=0;l<4;l++)for(unsigned x=0;x<512;x++){
  value=0;if(x<w)f>>std::hex>>value;
  if(value&4096)d.tile_nonempty|=1u<<l;
  d.setup_layer=l;d.setup_addr=x;d.setup_data=value;tick();
 }
 d.tile_we=0;if(!f)throw std::string("truncated original case");
 need(d.tile_nonempty!=0,"original completed tile row has opaque pixels");
}
static bool condition(unsigned elapsed){
 if(phase==0)return elapsed==8; // actual line clear in progress
 if(phase==1)return d.tile_x[0]>=4&&d.tile_x[0]<=16; // actual tile stream lookahead
 if(phase==2)return (d.valid&1)&&(d.consumer_ready&1); // admitted sprite fragment edge
 if(phase==3)return pending&&remaining>=4; // real outstanding immutable ROM response
 return (d.valid&1)&&(d.consumer_ready&1); // coincide rawreset and line_start
}
static void cancel(){
 bool reached=false;
 for(unsigned n=0;n<6144;n++){
  prepare();if(condition(n)){reached=true;break;}edge();
 }
 need(reached,"requested actual public reset phase reached");
 // Reset is asserted BEFORE the active clock edge, with valid/pending inputs
 // left in place; a delayed admission-ready must never become accepted work.
 d.reset=1;if(phase==4)d.start=1;d.eval();compare();edge();
 d.start=0;for(unsigned n=0;n<(phase%2)+1;n++)tick();
 need(!d.busy&&!d.consumer_busy&&!d.valid&&!d.order_valid&&!d.rom_req,"rawreset cancels all actual producer/consumer work on original edge");
 d.reset=0;tick();
}
static void scan(unsigned width){
 for(unsigned x=0;x<width;x++){d.px=x;tick();need(d.rgb[0]==d.rgb[1],"first post-reset completed line actual pixels");pixels++;nonzero+=d.rgb[0]!=0;}
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=4)return 2;
 try{
  std::ifstream f(argv[1],std::ios::binary);rom={std::istreambuf_iterator<char>(f),{}};if(rom.size()!=0x800000)return 2;
  unsigned found=0;for(unsigned a=0;a<0x100000&&found<2;a++){bool mixed=false,visible=false;unsigned first=pen(a,0);for(unsigned x=0;x<16;x++){unsigned p=pen(a,x);mixed|=p!=first;visible|=p>0&&p<15;}if(mixed&&visible&&(!found||a/16!=selected[0]/16))selected[found++]=a;}
  need(found==2,"distinct asymmetric original ROM rows");
  d.reset=1;d.start=0;d.px=0;d.rom_ack=0;d.rom_q=0;d.rom_fifth=0;d.tile_we=0;d.palette_we=0;
  const unsigned operations[]={0,5,2};
  for(profile=1;profile<=2;profile++){
   d.reset=1;d.mystic=profile==1;d.violent=profile==2;for(unsigned n=0;n<256;n++)tick();load_case(argv[profile+1]);
   for(unsigned m=0;m<3;m++)for(phase=0;phase<5;phase++){
    mode=operations[m];d.reset=1;d.start=0;for(unsigned n=0;n<256;n++)tick();need(!pending,"ROM response drained during legal256 reset profile guard");d.reset=0;tick();
    descriptor(selected[0],mode);start();finish();warm_lines++;
    descriptor(selected[1],mode);start();cancel();
    descriptor(selected[0],mode);start();finish();recovery_lines++;
    descriptor(selected[0],mode);start();scan(profile==1?288:384);finish((profile==1?288:384)+1);recovery_lines++;
    d.list_count=0;start();scan(profile==1?288:384);finish((profile==1?288:384)+1);helper_lines++;
    cases++;phase_cases[phase]++;profile_cases[profile-1]++;mode_cases[m]++;
   }
  }
 }catch(const std::string&e){printf("ERROR input %s\n",e.c_str());return 2;}
 need(cases==30&&warm_lines==30&&recovery_lines==60&&helper_lines==30&&deadlines==120,"complete30-case actual consumer reset matrix");
 need(pixels==20160&&nonzero>0,"both post-reset lines observed at actual public scanout");
 need(reset_ready_differences>0,"first-assertion rawreset-only ready difference exercised");
 need(reset_lookahead_differences>0,"actual tile lookahead reset-only difference exercised");
 need(late_acks>0&&fragments>0&&orders>0&&order_stalls>0,"late original replies and actual ordered RGB backpressure exercised");
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"cases\":%u,\"profile_cases\":[%u,%u],\"mode_cases\":[%u,%u,%u],\"phase_cases\":[%u,%u,%u,%u,%u],\"warm_lines\":%u,\"recovery_lines\":%u,\"helper_lines\":%u,\"deadline_checks\":%u,\"worst_line_clocks\":%u,\"scan_pixels\":%llu,\"nonzero_pixels\":%llu,\"accepted_fragments\":%llu,\"accepted_orders\":%llu,\"fragment_stalls\":%llu,\"order_stalls\":%llu,\"rom_requests\":%llu,\"late_acks\":%llu,\"reset_ready_differences\":%llu,\"reset_lookahead_differences\":%llu,\"reset_observations\":%llu,\"cycles\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,cases,profile_cases[0],profile_cases[1],mode_cases[0],mode_cases[1],mode_cases[2],phase_cases[0],phase_cases[1],phase_cases[2],phase_cases[3],phase_cases[4],warm_lines,recovery_lines,helper_lines,deadlines,worst,(unsigned long long)pixels,(unsigned long long)nonzero,(unsigned long long)fragments,(unsigned long long)orders,(unsigned long long)stalls,(unsigned long long)order_stalls,(unsigned long long)requests,(unsigned long long)late_acks,(unsigned long long)reset_ready_differences,(unsigned long long)reset_lookahead_differences,(unsigned long long)reset_cycles,(unsigned long long)ticks);
 return errors?1:0;
}
