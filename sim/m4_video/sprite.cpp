#include "Vm4_sprite_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <vector>
static Vm4_sprite_top d;
static uint64_t clocks=0,fragments=0,errors=0,pixels=0,stalls=0,rom_acks=0;
static unsigned latency=0,deadline_errors=0,protocol=0,line_number=0;
static std::vector<uint8_t>rom;
static std::array<uint64_t,288>actual{};
static std::array<unsigned,288>oz,sz,sp;
static bool collecting=false,pending=false,held=false;
static unsigned address=0,waits=0,serial=0;
static void need(bool b,const char*s){if(!b)throw std::runtime_error(s);}
static std::vector<uint8_t>bytes(const std::string&p){std::ifstream f(p,std::ios::binary);need(bool(f),p.c_str());return{std::istreambuf_iterator<char>(f),{}};}
static unsigned le16(const std::vector<uint8_t>&b,unsigned n){return b.at(n)|(unsigned(b.at(n+1))<<8);}
static uint64_t le64(const std::vector<uint8_t>&b,unsigned n){uint64_t r=0;for(unsigned i=0;i<8;i++)r|=uint64_t(b.at(n+i))<<(i*8);return r;}
using Fragment=std::array<unsigned,8>;
static Fragment f(){return{d.x,d.pen,d.level,d.shadow,d.table_index,d.condition,d.z,d.priority_code};}
static bool held_fragment=false;static Fragment prior{};
static void tick(){
 d.clk=0;d.rom_ack=0;d.eval();
 if(!d.rom_req){pending=false;held=false;}
 if(held&&d.rom_addr!=address)held=false;
 if(pending&&d.rom_addr!=address){protocol++;pending=false;}
 if(d.rom_req&&!pending&&!held){pending=true;address=d.rom_addr;waits=14+(latency?serial%22:0);serial++;}
 if(pending){if(waits)waits--;else{need(address*8+8<=rom.size(),"Original sprite bounds");uint64_t q=0;for(unsigned i=0;i<8;i++)q=(q<<8)|rom[address*8+i];d.rom_q=q;d.rom_ack=1;rom_acks++;pending=false;held=true;}}
 d.eval();if(held_fragment)need(d.valid&&f()==prior,"Held original sprite fragment changed");
 held_fragment=d.valid&&!d.ready;prior=f();stalls+=held_fragment;
 if(collecting&&d.valid&&d.ready){
  need(d.x<288,"M4 clip width");unsigned x=d.x,z=d.z,pri=d.priority_code;fragments++;
  if(!d.shadow){need((d.pen&15)!=0,"Opaque sprite pen0");if(oz[x]>=z){oz[x]=z;uint64_t mask=(uint64_t(1)<<21)-1;mask|=uint64_t(255)<<23;mask|=uint64_t(31)<<50;
   uint64_t v=(d.pen&2047u)|(uint64_t(1)<<12)|(uint64_t(pri)<<13)|(uint64_t(z)<<23)|(uint64_t(d.pen&15)<<50);actual[x]=(actual[x]&~mask)|v;}}
  else if(sz[x]>=z&&sp[x]>pri){sz[x]=z;sp[x]=pri;uint64_t mask=((uint64_t(1)<<50)-1)^((uint64_t(1)<<31)-1);
   uint64_t v=(uint64_t(1)<<31)|(uint64_t(d.table_index)<<32)|(uint64_t(pri)<<34)|(uint64_t(z)<<42);actual[x]=(actual[x]&~mask)|v;}
 }
 d.clk=1;d.eval();clocks++;
}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);if(argc!=10)return 2;try{
 auto ram=bytes(argv[1]),r46=bytes(argv[2]),r47=bytes(argv[3]),r55=bytes(argv[4]),r38=bytes(argv[5]);rom=bytes(argv[6]);auto expected=bytes(argv[7]),orders=bytes(argv[8]);latency=std::stoul(argv[9]);
 need(ram.size()>=4096&&r46.size()==8&&r47.size()>=16&&r55.size()==128&&r38.size()>=32&&rom.size()==0x800000&&expected.size()==288*224*8&&orders.size()%4==0,"Original sprite fixture sizes");
 for(unsigned i=0;i<8;i++){d.k46[i]=r46[i];d.k47[i]=le16(r47,2*i);}for(unsigned i=0;i<48;i++)d.k55[i]=r55[i];for(unsigned i=0;i<16;i++)d.k38[i]=le16(r38,2*i);
 d.reset=1;d.ready=d.order_ready=1;for(unsigned i=0;i<256;i++)tick();
 for(unsigned i=0;i<2048;i++){d.ram_we=1;d.ram_waddr=i;d.ram_wdata=le16(ram,2*i);tick();}d.ram_we=0;d.reset=0;tick();
 d.build=1;tick();d.build=0;unsigned build_cycles=0;while(!d.build_done&&build_cycles++<245760)tick();need(d.build_done&&!d.overflow,"Original sprite list vblank deadline");need(d.count==orders.size()/4,"Original MAME object count");
 d.inspect=1;for(unsigned i=0;i<d.count;i++){d.inspect_index=i;tick();tick();unsigned v=0;for(unsigned b=0;b<4;b++)v|=unsigned(orders[4*i+b])<<(8*b);if(d.list_q!=v){fprintf(stderr,"LIST mismatch index%u actual%08x expected%08x\n",i,unsigned(d.list_q),v);throw std::runtime_error("MAME ordered original objects");}}d.inspect=0;tick();tick();
 uint64_t mask=((uint64_t(1)<<21)-1)|(uint64_t(255)<<23)|(((uint64_t(1)<<50)-1)^((uint64_t(1)<<31)-1))|(uint64_t(31)<<50);unsigned worst=0;uint64_t visible=0;
 for(unsigned y=0;y<224;y++){
  actual={};oz.fill(255);sz.fill(255);sp.fill(255);line_number=y;collecting=true;held_fragment=false;
  d.line=15+y;d.start=1;tick();d.start=0;unsigned done=0;
  for(unsigned c=1;c<6144;c++){d.ready=(c%17!=3&&c%17!=4);d.order_ready=(c%19!=7);tick();if(!done&&!d.busy)done=c;}
  if(d.busy||!done)deadline_errors++;if(done>worst)worst=done;collecting=false;
  for(unsigned x=0;x<288;x++){uint64_t want=le64(expected,8*(y*288+x))&mask;pixels++;visible+=bool(want&(uint64_t(1)<<12));if(actual[x]!=want){if(errors<8)fprintf(stderr,"SPRITE mismatch y%u x%u actual%016llx expected%016llx\n",y,x,(unsigned long long)actual[x],(unsigned long long)want);errors++;}}
 }
 bool pass=!errors&&!deadline_errors&&!protocol;
 printf("RESULT_JSON {\"passed\":%s,\"pixels_compared\":%llu,\"pixel_errors\":%llu,\"original_visible_pixels\":%llu,\"accepted_fragments\":%llu,\"consumer_stall_cycles\":%llu,\"line_deadline_checks\":224,\"deadline_failures\":%u,\"worst_line_clocks\":%u,\"ROM_responses\":%llu,\"protocol_errors\":%u,\"object_count\":%u,\"list_build_clocks\":%u,\"variable_latency\":%u,\"hardware_verified\":false}\n",pass?"true":"false",(unsigned long long)pixels,(unsigned long long)errors,(unsigned long long)visible,(unsigned long long)fragments,(unsigned long long)stalls,deadline_errors,worst,(unsigned long long)rom_acks,protocol,unsigned(d.count),build_cycles,latency);return pass?0:1;
 }catch(const std::exception&e){fprintf(stderr,"FAIL %s\n",e.what());return 2;}}
