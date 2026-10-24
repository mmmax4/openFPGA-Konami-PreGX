#include "Vtb_m2_empty_tile04.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <map>
#include <sstream>
#include <string>
#include <vector>

static Vtb_m2_empty_tile04 *d;
static std::vector<uint8_t> rom;
static std::vector<uint16_t> oracle,vram;
static uint64_t cycles=0,checks=0,pixels=0,errors=0,protocol=0,summary_checks=0;
static unsigned starts=0,completions=0,aborts=0,resets=0,max_work=0;
static uint64_t line_began=0;
static bool check_summary=false;
static unsigned expected_summary=15;
struct Port {bool busy=false;unsigned address=0,wait=0;uint64_t began=0,requests=0,acks=0,cancels=0;unsigned min_latency=999,max_latency=0;};
static Port vp,rp;
static void fail(const char *what,unsigned got,unsigned want) {
 if(errors<12)printf("ERROR %s got=%x expected=%x cycle=%llu\n",what,got,want,(unsigned long long)cycles);
 errors++;
}
static void equal(const char *what,unsigned got,unsigned want){checks++;if(got!=want)fail(what,got,want);}
static std::vector<uint8_t> bytes(const char *p){std::ifstream f(p,std::ios::binary);if(!f)exit(2);return {std::istreambuf_iterator<char>(f),{}};}
static void service(Port &p,bool req,unsigned address,bool is_rom) {
 if(d->reset||d->line_start){if(p.busy)p.cancels++;p.busy=false;return;}
 if(!p.busy&&req){p.busy=true;p.address=address;p.wait=is_rom?12+((address>>3)&7):5+(address&3);p.began=cycles;p.requests++;}
 if(!p.busy)return;
 if(!req||address!=p.address){protocol++;p.busy=false;return;}
 if(p.wait){p.wait--;return;}
 unsigned latency=unsigned(cycles-p.began);if(latency<p.min_latency)p.min_latency=latency;if(latency>p.max_latency)p.max_latency=latency;p.acks++;
 if(is_rom){unsigned at=p.address*5;if(at+4>=rom.size())exit(2);d->rq=(unsigned(rom[at])<<24)|(unsigned(rom[at+1])<<16)|(unsigned(rom[at+2])<<8)|rom[at+3];d->fifth=rom[at+4];d->rack=1;}
 else{d->vq=vram.at(p.address);d->vack=1;}
 p.busy=false;
}
static void tick(unsigned count=1){while(count--){
 d->clk=0;d->eval();d->vack=d->rack=0;service(vp,d->vreq,d->vaddr,false);service(rp,d->rreq,d->raddr,true);d->eval();d->clk=1;d->eval();cycles++;
 if(check_summary&&!d->line_start){summary_checks++;equal("scan-bank summary",d->summary,expected_summary);}
 if(d->unsupported)fail("unsupported original state",1,0);
}}
static unsigned mask(unsigned y){unsigned result=0;for(unsigned l=0;l<4;l++)for(unsigned x=0;x<288;x++)if(oracle.at(l*64512+y*288+x)&4096){result|=1<<l;break;}return result;}
static void begin(unsigned y,unsigned read_mask){
 if(d->busy)aborts++;
 check_summary=false;d->line=y+16;d->line_start=1;tick();d->line_start=0;starts++;line_began=cycles;
 expected_summary=read_mask;check_summary=true;equal("bank swap summary",d->summary,read_mask);equal("producer starts",d->busy,1);
 printf("START row=%u readmask=%x aborted=%u cycle=%llu\n",y,read_mask,aborts,(unsigned long long)cycles);
}
static void finish(){unsigned clocks=0;while(d->busy&&clocks++<20000)tick();equal("producer completes",d->busy,0);completions++;unsigned work=unsigned(cycles-line_began);if(work>max_work)max_work=work;}
static void scan(unsigned y){
 equal("expected opaque summary",d->summary,mask(y));
 for(unsigned x=0;x<288;x++){
  d->px=x;tick(2);std::array<unsigned,4> got={d->packed0,d->packed1,d->packed2,d->packed3};
  for(unsigned l=0;l<4;l++){pixels++;equal("original tile pixel",got[l],oracle.at(l*64512+y*288+x));}
 }
}
static void pending(bool rom_port,unsigned minimum_clocks){
 tick(minimum_clocks);unsigned n=0;while(!(rom_port?(d->rreq&&rp.busy):(d->vreq&&vp.busy))&&d->busy&&n++<10000)tick();
 equal(rom_port?"ROM pending before abort":"VRAM pending before abort",rom_port?(d->rreq&&rp.busy):(d->vreq&&vp.busy),1);
}
static void reset(){check_summary=false;d->line_start=0;d->reset=1;tick(5);resets++;equal("reset conservative mask",d->summary,15);d->reset=0;tick(3);expected_summary=15;check_summary=true;equal("reset release conservative mask",d->summary,15);}
int main(int argc,char **argv){
 Verilated::commandArgs(argc,argv);if(argc!=4)return 2;rom=bytes(argv[1]);if(rom.size()!=0x500000)return 2;
 auto packed=bytes(argv[3]);if(packed.size()!=258048*2)return 2;for(unsigned i=0;i<packed.size();i+=2)oracle.push_back(packed[i]|(unsigned(packed[i+1])<<8));
 std::map<std::string,std::vector<unsigned>> fields;std::ifstream f(argv[2]);std::string row;
 while(getline(f,row)){std::istringstream in(row);std::string key,value;in>>key;int page=-1;if(key=="VRAM")in>>page;std::vector<unsigned> data;while(in>>value)data.push_back(std::stoul(value,nullptr,16));if(page>=0)vram.insert(vram.end(),data.begin(),data.end());else fields[key]=data;}
 if(vram.size()!=69632||fields["K56REGS"].size()!=32||fields["K55REGS"].size()!=128)return 2;
 d=new Vtb_m2_empty_tile04;d->clk=0;d->reset=1;d->line_start=0;d->reg_we=d->cb_we=0;d->eval();reset();
 for(unsigned i=0;i<32;i++){d->reg_we=1;d->reg_addr=i;d->reg_data=fields["K56REGS"][i];tick();}d->reg_we=0;
 for(unsigned i=0;i<4;i++){d->cb_we=1;d->cb_addr=i;d->cb_data=(fields["K55REGS"][23+i]<<4)&255;tick();}d->cb_we=0;
 equal("original row119 mask",mask(119),8);equal("original row223 mask",mask(223),2);equal("original row0 mask",mask(0),10);
 begin(119,15);finish();equal("write completion does not select own bank",d->summary,15);
 begin(223,8);scan(119);finish();
 begin(0,2);scan(223);finish();
 begin(119,10);scan(0);finish();
 // Cancel a real outstanding VRAM request; next scan bank is incomplete.
 begin(223,8);pending(false,0);begin(0,15);finish();
 begin(119,10);scan(0);finish();
 // Mid-line ROM cancellation after original data have already been emitted.
 begin(223,8);pending(true,1200);begin(119,15);finish();
 begin(223,8);scan(119);finish();
 // Reset while an actual ROM request is outstanding invalidates both banks.
 begin(0,2);pending(true,0);reset();
 begin(119,15);finish();begin(223,8);scan(119);finish();
 reset();
 bool pass=!errors&&!protocol&&pixels==6*4*288&&aborts==2&&resets==3&&vp.cancels&&rp.cancels&&summary_checks;
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"protocol_errors\":%llu,\"checks\":%llu,\"original_pixels_compared\":%llu,\"summary_checks\":%llu,\"line_starts\":%u,\"line_completions\":%u,\"line_aborts\":%u,\"reset_cases\":%u,\"max_component_work_clocks\":%u,\"VRAM_requests\":%llu,\"ROM_requests\":%llu,\"VRAM_cancels\":%llu,\"ROM_cancels\":%llu,\"VRAM_latency_min\":%u,\"VRAM_latency_max\":%u,\"ROM_latency_min\":%u,\"ROM_latency_max\":%u,\"cycles\":%llu,\"hardware_verified\":false}\n",pass?"true":"false",(unsigned long long)errors,(unsigned long long)protocol,(unsigned long long)checks,(unsigned long long)pixels,(unsigned long long)summary_checks,starts,completions,aborts,resets,max_work,(unsigned long long)vp.requests,(unsigned long long)rp.requests,(unsigned long long)vp.cancels,(unsigned long long)rp.cancels,vp.min_latency,vp.max_latency,rp.min_latency,rp.max_latency,(unsigned long long)cycles);
 delete d;return pass?0:1;
}
