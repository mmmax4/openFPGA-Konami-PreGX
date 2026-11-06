// Real paired tile public ports, immutable ROM/VRAM, constructed legal scroll
// controls. No hierarchy forcing or access to tile internal coordinates/state.
#include "Vm3_vio13_tile_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <map>
#include <sstream>
#include <string>
#include <vector>
static Vm3_vio13_tile_top d;
static std::ofstream trace;
static uint64_t errors=0,checks=0,ticks=0,pixel_checks=0,visible=0,vr_acks=0,rom_acks=0;
static unsigned profile=0,width=376,period=12,stride=4,case_id=0,lines=0,deadlines=0,deadline_errors=0,worst=0;
static unsigned original_cases=0,mode_cases=0,wrap_cases=0,live_cases=0,abort_cases=0,profile_cases[3]={},visible_profiles[3]={};
static bool variable=false,live_pending=false,live_done=false;
static unsigned vr_serial=0,rom_serial=0,live_events=0;
static std::vector<uint8_t> rom;
static std::array<uint16_t,65536> ram{};
static std::array<uint16_t,32> original_regs{};
static std::array<uint8_t,4> original_colors{};
struct Memory{bool active=false,held=false;unsigned addr=0,delay=0;};static Memory vr,rr;
static void need(bool v,const char*why){checks++;if(!v){if(errors<32)printf("ERROR %s case%u profile%u tick%llu\n",why,case_id,profile,(unsigned long long)ticks);errors++;}}
static std::vector<uint8_t> bytes(const std::string&p){std::ifstream f(p,std::ios::binary);if(!f){fprintf(stderr,"Cannot read %s\n",p.c_str());exit(2);}return{std::istreambuf_iterator<char>(f),{}};}
static void ports(){
 if(d.reset)return;
 need(d.busy==0||d.busy==3,"actual producer busy cycle equality");need(d.unsupported==0,"declared supported original/control scenario");
 need(d.vram_req==0||d.vram_req==3,"actual VRAM request cycle equality");if(d.vram_req)need(d.vram_addr[0]==d.vram_addr[1],"actual VRAM address equality");
 need(d.rom_req==0||d.rom_req==3,"actual ROM request cycle equality");if(d.rom_req)need(d.rom_addr[0]==d.rom_addr[1],"actual ROM row address equality");
 need(d.last_mix[0]==d.last_mix[1],"actual sticky mix metadata cycle equality");need(d.line_nonempty[0]==d.line_nonempty[1],"actual completed-bank nonempty summary equality");
}
static void tick(){
 d.clk=0;d.vram_ack=d.rom_ack=0;d.eval();
 if(d.reset){vr=Memory{};rr=Memory{};}
 else{
  if(!d.vram_req){vr=Memory{};}if(!d.rom_req){rr=Memory{};}
  if(d.vram_req&&!vr.active&&!vr.held){vr.active=true;vr.addr=d.vram_addr[0];vr.delay=5+(variable?vr_serial%5:0);vr_serial++;}
  if(d.rom_req&&!rr.active&&!rr.held){rr.active=true;rr.addr=d.rom_addr[0];rr.delay=12+(variable?rom_serial%9:0);rom_serial++;}
  // Change live public register inputs while the first actual linescroll RAM
  // transaction is outstanding. cur_l is never observed or forced.
  if(live_pending&&vr.active&&vr.delay>=2){
   unsigned mode=profile?1:3;d.regs[5]=(d.regs[5]&0xff00)|unsigned(mode*0x55);
   d.regs[20]=0xffff;d.regs[21]=0x1ff;d.regs[22]=0x3ff;d.regs[23]=0x7ff;
   live_pending=false;live_done=true;live_events++;trace<<"LIVE_REGISTERS "<<case_id<<' '<<ticks<<'\n';d.eval();
  }
  if(vr.active){need(d.vram_req&&d.vram_addr[0]==vr.addr,"held VRAM request payload");if(vr.delay)vr.delay--;else{d.vram_q=ram[vr.addr];d.vram_ack=1;vr.active=false;vr.held=true;vr_acks++;trace<<"VRAM_ACK "<<case_id<<' '<<ticks<<' '<<vr.addr<<'\n';}}
  if(rr.active){need(d.rom_req&&d.rom_addr[0]==rr.addr,"held ROM row request payload");if(rr.delay)rr.delay--;else{
   unsigned at=rr.addr*stride;need(at+stride<=rom.size(),"original tile ROM row bounds");if(at+stride>rom.size())at=0;
   d.rom_q=(unsigned(rom[at])<<24)|(unsigned(rom[at+1])<<16)|(unsigned(rom[at+2])<<8)|rom[at+3];d.rom_fifth=stride==5?rom[at+4]:0;d.rom_ack=1;rr.active=false;rr.held=true;rom_acks++;trace<<"ROM_ACK "<<case_id<<' '<<ticks<<' '<<rr.addr<<'\n';}}
 }
 d.eval();ports();d.clk=1;d.eval();d.clk=0;d.eval();ticks++;
}
static void reset(){
 d.reset=1;d.line_start=0;d.vram_ack=d.rom_ack=0;live_pending=false;live_done=false;vr=Memory{};rr=Memory{};vr_serial=rom_serial=0;
 // A late legal profile switch while both real consumers stay in reset.
 d.mystic=((profile+1)%3)==1;d.violent=((profile+1)%3)==2;for(unsigned i=0;i<8;i++)tick();
 d.mystic=profile==1;d.violent=profile==2;for(unsigned i=0;i<256;i++)tick();d.reset=0;tick();
}
static void configure(int mode,int wrap){
 for(unsigned i=0;i<32;i++)d.regs[i]=original_regs[i];for(unsigned i=0;i<4;i++)d.colorbase[i]=original_colors[i];
 if(mode>=0)d.regs[5]=(d.regs[5]&0xff00)|unsigned(mode*0x55);
 if(wrap>=0)for(unsigned l=0;l<4;l++){
  unsigned span=wrap==0?0:wrap==1?1:3;d.regs[12+l]=(d.regs[12+l]&~3u)|span;
  const unsigned scrolls[4]={511,0xffff,0x8000,0x7fff};d.regs[20+l]=scrolls[l]+(wrap==1?512:wrap==2?1536:0);
 }
}
static uint16_t packed(unsigned variant,unsigned layer){bool op=(d.opaque[variant]>>layer)&1;return op?uint16_t(0x1000|d.pix[variant][layer]|(d.category[variant][layer]<<13)):0;}
static void line(unsigned y,bool scan){
 d.line=y;d.line_start=1;tick();d.line_start=0;unsigned completion=0;bool was_busy=d.busy;
 for(unsigned c=1;c<6144;c++){
  unsigned start=(profile==1?24:40)*period;
  bool in=scan&&c>=start&&c<start+width*period;
  if(in&&(c-start)%period==0)d.px=(c-start)/period;
  tick();if(was_busy&&!d.busy&&!completion)completion=c;was_busy=d.busy;
  if(in&&(c-start)%period==2){
   unsigned x=(c-start)/period;
   for(unsigned l=0;l<4;l++){
    auto a=packed(0,l),b=packed(1,l);need(a==b,"actual public palette/opaque/category pixel equality");pixel_checks++;visible+=bool(a&0x1000);visible_profiles[profile]+=bool(a&0x1000);
    trace<<"PIXEL "<<case_id<<' '<<l<<' '<<x<<' '<<a<<'\n';
   }
  }
 }
 lines++;deadlines++;bool missed=!completion||d.busy;deadline_errors+=missed;need(!missed,"actual tile line finishes within6144clocks");if(completion>worst)worst=completion;
 trace<<"LINE_DONE "<<case_id<<' '<<y<<' '<<completion<<'\n';
}
static void run_case(int mode,int wrap,unsigned kind){
 reset();configure(mode,wrap);tick();trace<<"CASE "<<case_id<<' '<<profile<<' '<<kind<<' '<<mode<<' '<<wrap<<' '<<variable<<'\n';
 if(kind==3){live_pending=true;line(16,false);need(live_done,"actual pending VRAM transaction received a live register update");line(17,true);live_cases++;}
 else if(kind==4){
  d.line=16;d.line_start=1;tick();d.line_start=0;unsigned c=0;for(;c<2000;c++){if(vr.active&&vr.delay>=2)break;tick();}
  need(c<2000&&d.busy==3,"actual producer/VRAM request active before line abort");line(70,false);line(71,true);abort_cases++;
 }else{line(16,false);line(17,true);if(kind==0)original_cases++;else if(kind==1)mode_cases++;else wrap_cases++;}
 case_id++;profile_cases[profile]++;
}
static void load_state(const std::string&path){
 std::ifstream file(path);std::string line;std::map<std::string,std::vector<unsigned>>fields;std::array<std::vector<unsigned>,16> pages;
 while(getline(file,line)){std::istringstream q(line);std::string key;if(!(q>>key)||key[0]=='#')continue;int page=-1;if(key=="VRAM")q>>page;unsigned value;
  while(q>>std::hex>>value){if(page>=0&&page<16)pages[page].push_back(value);else if(page<0)fields[key].push_back(value);}
 }
 need(fields["K56REGS"].size()==32&&fields["K55REGS"].size()>=27,"original captured tile register shape");
 for(unsigned i=0;i<32;i++)original_regs[i]=fields["K56REGS"][i];for(unsigned l=0;l<4;l++)original_colors[l]=(fields["K55REGS"][23+l]<<4)&255;
 for(unsigned p=0;p<16;p++){need(pages[p].size()==4096,"original full VRAMpage");for(unsigned i=0;i<4096&&i<pages[p].size();i++)ram[p*4096+i]=pages[p][i];}
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=3)return 2;trace.open(argv[2]);if(!trace)return 2;std::ifstream configs(argv[1]);std::string row;unsigned profiles=0;
 d.clk=0;d.reset=1;d.line_start=0;d.px=0;d.vram_ack=d.rom_ack=0;d.rom_fifth=0;d.rom_q=d.vram_q=0;
 while(getline(configs,row)){
  if(row.empty()||row[0]=='#')continue;std::istringstream q(row);unsigned base,len;std::string image,state;q>>profile>>std::hex>>base>>len>>std::dec>>stride>>image>>state;if(!q||profile>2)return 2;
  auto b=bytes(image);need(base+len<=b.size(),"original canonical image tile span");if(base+len>b.size())return 2;rom.assign(b.begin()+base,b.begin()+base+len);load_state(state);width=profile==1?288:profile==2?384:376;period=profile==1?16:12;
  variable=false;run_case(-1,-1,0);
  for(unsigned latency=0;latency<2;latency++)for(unsigned mode=0;mode<4;mode++){variable=latency;run_case(mode,-1,1);}
  variable=true;for(unsigned wrap=0;wrap<3;wrap++)run_case(3,wrap,2);
  run_case(0,-1,3);run_case(0,-1,4);profiles++;
 }
 need(profiles==3&&case_id==42&&original_cases==3&&mode_cases==24&&wrap_cases==9&&live_cases==3&&abort_cases==3,"all42bounded original/control cases complete");
 need(lines==84&&deadlines==84&&deadline_errors==0&&pixel_checks==58688,"all actual public pixels and line deadlines complete");
 for(unsigned p=0;p<3;p++)need(profile_cases[p]==14&&visible_profiles[p]>0,"all3profiles include original visible tile pixels");need(vr_acks>0&&rom_acks>0&&live_events==3,"actual ROM/VRAM traffic and live updates present");
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"cases\":%u,\"original_cases\":%u,\"mode_cases\":%u,\"wrap_cases\":%u,\"live_update_cases\":%u,\"abort_cases\":%u,\"completed_lines\":%u,\"line_deadline_checks\":%u,\"deadline_failures\":%u,\"pixels_compared\":%llu,\"visible_pixels\":%llu,\"vram_responses\":%llu,\"rom_responses\":%llu,\"live_register_updates\":%u,\"worst_line_clocks\":%u,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,case_id,original_cases,mode_cases,wrap_cases,live_cases,abort_cases,lines,deadlines,deadline_errors,(unsigned long long)pixel_checks,(unsigned long long)visible,(unsigned long long)vr_acks,(unsigned long long)rom_acks,live_events,worst);return errors?1:0;
}
