// /root/verify_metam: public ports, original captures and independent memory responders.
// Pixel agreement with the separately pinned MiSTer consumer; not an independent MAME oracle.
#include "Vm4_video_tile_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
#include <stdexcept>
static Vm4_video_tile_top d;
static uint64_t cycles=0,pixels=0,errors=0,visible=0,cancellations=0;
static unsigned variant=0,variable=0,deadlines=0,protocol=0;
static std::vector<uint8_t>rom;
static std::array<uint16_t,65536>ram{};
struct Memory{bool active=false,held=false;unsigned address=0,wait=0,serial=0,acks=0;};
static std::array<Memory,3>vr,rr;
static void need(bool b,const char*s){if(!b)throw std::runtime_error(s);}
static std::vector<uint8_t>read(const char*p){std::ifstream f(p,std::ios::binary);need(bool(f),p);return{std::istreambuf_iterator<char>(f),{}};}
static unsigned le16(const std::vector<uint8_t>&b,unsigned n){return b.at(n)|unsigned(b.at(n+1))<<8;}
static void tick(){
 d.clk=0;d.vram_ack=d.rom_ack=0;d.eval();
 if(d.reset){vr={};rr={};}
 else for(unsigned i=0;i<3;i++){
  auto port=[&](Memory&r,bool req,unsigned address,bool tile){
   if(!req){if(r.active)cancellations++;r.active=false;r.held=false;return;}
   if(r.held&&address!=r.address)r.held=false;
   if(r.active&&address!=r.address){protocol++;r.active=false;}
   if(!r.active&&!r.held){r.active=true;r.address=address;r.wait=(tile?12:5)+(variable?r.serial%(tile?9:5):0);r.serial++;}
   if(r.active){if(r.wait)r.wait--;else{
    if(tile){unsigned a=address*5;need(a+5<=rom.size(),"Original tile ROM bounds");d.rom_q[i]=(unsigned(rom[a])<<24)|(unsigned(rom[a+1])<<16)|(unsigned(rom[a+2])<<8)|rom[a+3];d.rom_fifth[i]=rom[a+4];need(!rom[a+4],"M4 erased fifth plane changed");d.rom_ack|=1u<<i;}
    else{d.vram_q[i]=ram.at(address);d.vram_ack|=1u<<i;}
    r.active=false;r.held=true;r.acks++;
   }}
  };
  port(vr[i],d.vram_req&(1u<<i),d.vram_addr[i],false);port(rr[i],d.rom_req&(1u<<i),d.rom_addr[i],true);
 }
 d.eval();d.clk=1;d.eval();cycles++;
}
static void dump(const std::string&p,const std::vector<uint16_t>&v){std::ofstream f(p,std::ios::binary);need(bool(f),"Pixel output");for(auto x:v){f.put(char(x));f.put(char(x>>8));}}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);if(argc!=8)return 2;try{
 auto regs=read(argv[1]),vram=read(argv[2]),k55=read(argv[3]);rom=read(argv[4]);variable=std::stoul(argv[5]);variant=std::stoul(argv[6]);need(variant<2,"Variant0new1old");
 need(regs.size()==64&&vram.size()>=131072&&k55.size()==128&&rom.size()==0x500000,"Original snapshot sizes");
 for(unsigned i=0;i<32;i++)d.regs[i]=le16(regs,2*i);for(unsigned i=0;i<65536;i++)ram[i]=le16(vram,2*i);
 for(unsigned l=0;l<4;l++)d.colorbase[l]=(unsigned(k55[23+l])<<4)&255;
 d.reset=1;d.line_start=0;d.px=0;for(unsigned i=0;i<256;i++)tick();d.reset=0;tick();
 std::vector<uint16_t>out(4*288*224,65535),ref(out);unsigned unsup=0,ref_unsup=0;unsigned worst=0,ref_worst=0;
 for(unsigned row=0;row<=224;row++){
  if(row){deadlines+=bool(d.busy&(1u<<variant));deadlines+=bool(d.busy&4);}
  d.line=17+row;d.line_start=1;tick();d.line_start=0;unsigned done=0,refdone=0;
  for(unsigned c=1;c<6144;c++){
   bool scan=row>0&&c>=24*16&&c<(24+288)*16;unsigned x=scan?(c-24*16)/16:0;
   if(scan&&c%16==0)d.px=x;tick();unsup|=(d.unsupported>>variant)&1;ref_unsup|=(d.unsupported>>2)&1;
   if(!done&&!(d.busy&(1u<<variant)))done=c;if(!refdone&&!(d.busy&4))refdone=c;
   if(scan&&c%16==2)for(unsigned l=0;l<4;l++){
    auto a=(d.opaque[variant]&(1u<<l))?d.pix[variant][l]&2047u:65535u;
    auto b=(d.opaque[2]&(1u<<l))?d.pix[2][l]&2047u:65535u;
    unsigned at=l*288*224+(row-1)*288+x;out[at]=a;ref[at]=b;pixels++;visible+=b!=65535;
    if(a!=b){if(errors<8)fprintf(stderr,"PIXEL_DIFFERENCE row%u x%u layer%u actual%04x reference%04x\n",row-1,x,l,a,b);errors++;}
   }
  }
  if(done>worst)worst=done;if(refdone>ref_worst)ref_worst=refdone;
 }
 dump(std::string(argv[7])+".actual.bin",out);dump(std::string(argv[7])+".mister.bin",ref);
 bool passed=!errors&&!deadlines&&!protocol&&!unsup&&!ref_unsup;
 printf("RESULT_JSON {\"passed\":%s,\"variant\":%u,\"variable_latency\":%u,\"cycles\":%llu,\"pixels_compared\":%llu,\"pixel_errors\":%llu,\"reference_visible_pixels\":%llu,\"line_deadline_checks\":448,\"deadline_failures\":%u,\"unsupported\":%u,\"reference_unsupported\":%u,\"protocol_errors\":%u,\"cancellations\":%llu,\"worst_line_clocks\":%u,\"reference_worst_line_clocks\":%u,\"VRAM_responses\":%u,\"ROM_responses\":%u,\"hardware_verified\":false}\n",passed?"true":"false",variant,variable,(unsigned long long)cycles,(unsigned long long)pixels,(unsigned long long)errors,(unsigned long long)visible,deadlines,unsup,ref_unsup,protocol,(unsigned long long)cancellations,worst,ref_worst,vr[variant].acks,rr[variant].acks);return passed?0:1;
 }catch(const std::exception&e){fprintf(stderr,"FAIL %s\n",e.what());return 2;}}
