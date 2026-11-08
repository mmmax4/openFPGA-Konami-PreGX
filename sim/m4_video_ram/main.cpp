// Public synchronous memory contract, with unmodified Gaia/Metamorphic bytes.
// The flat reference is the original Gaia cache/line memory shape. Road views
// are checked against the explicit physical allocation, including atomic slices.
#include "Vpregx_video_ram.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <random>
#include <stdexcept>
#include <vector>
static Vpregx_video_ram d;
static std::array<uint16_t,8192> mem{};
static std::array<uint16_t,3072> line{};
static uint64_t checks=0,cycles=0;
static void require(bool v,const char* why){++checks;if(!v)throw std::runtime_error(why);}
static std::vector<uint8_t> load(const char* p){std::ifstream f(p,std::ios::binary);require(bool(f),"original input open");return {std::istreambuf_iterator<char>(f),{}};}
static void edge(bool checking=true){
 uint16_t g=mem[d.g_ra],f=mem[d.f_ra],l=line[d.metam?d.r_lb_ra:d.g_lb_ra];
 uint64_t col=0;uint32_t group[3]={};
 for(unsigned i=0;i<4;i++)col|=uint64_t(mem[(4+i)*512+d.c_ra])<<(16*i);
 for(unsigned i=0;i<5;i++)group[i/2]|=uint32_t(mem[(8+i)*512+d.cache_ra])<<(16*(i%2));
 if(!d.metam){if(d.g_we)mem[d.g_wa]=d.g_wdata;if(d.g_lb_we)line[d.g_lb_wa]=d.g_lb_wdata;}
 else {
  if(d.f_we)mem[d.f_wa]=d.f_wdata;
  if(d.c_we)for(unsigned i=0;i<4;i++)mem[(4+i)*512+d.c_wa]=(d.c_wdata>>(16*i))&65535;
  if(d.cache_we)for(unsigned i=0;i<5;i++)mem[(8+i)*512+d.cache_wa]=(d.cache_wdata[i/2]>>(16*(i%2)))&65535;
  if(d.r_lb_we)line[d.r_lb_wa]=d.r_lb_wdata;
 }
 d.clk=0;d.eval();d.clk=1;d.eval();++cycles;
 if(!checking)return;
 if(!d.metam)require(d.g_q==g,"Gaia original flat-cache registered read/bank selection");
 else {
  require(d.f_q==f,"Road frame word registered bank selection");
  require(d.c_q==(col&((uint64_t(1)<<53)-1)),"Column atomic four-slice registered read");
  for(unsigned i=0;i<3;i++)require(d.cache_q[i]==group[i],"Group atomic five-slice registered read");
 }
 require(d.g_lb_q==l && d.r_lb_q==(l&511),"Shared line registered read/owner");
}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);if(argc!=3)return 2;try{
 auto gaia=load(argv[1]),road=load(argv[2]);require(gaia.size()>0x6c0000&&road.size()==0x40000,"original sizes");
 d.metam=0;d.g_we=1;
 for(unsigned a=0;a<8192;a++){d.g_wa=a;d.g_wdata=(unsigned(gaia[0x540000+2*a])<<8)|gaia[0x540001+2*a];edge(false);}
 d.g_we=0;d.g_lb_we=1;
 for(unsigned a=0;a<3072;a++){d.g_lb_wa=a;d.g_lb_wdata=(unsigned(gaia[0x540000+2*a])<<4|gaia[0x540001+2*a])&4095;edge(false);}
 d.g_lb_we=0;
 // Every high bank transition with a different low address on consecutive clocks.
 for(unsigned a=0;a<8192;a++){d.g_ra=(a*513+31)&8191;d.g_lb_ra=(a*131)%3072;edge();}
 std::mt19937 rng(0x4a1193);
 for(unsigned a=0;a<60000;a++){
  d.metam=(a/1000)%2; // caller changes ownership only between bounded epochs
  d.g_ra=rng()%8192;d.g_wa=(a%11==0)?d.g_ra:rng()%8192;d.g_we=(rng()&3)==0;d.g_wdata=rng();
  d.f_ra=rng()%2048;d.f_wa=(a%13==0)?d.f_ra:rng()%2048;d.f_we=(rng()&1);d.f_wdata=(unsigned(road[(2*a)%road.size()])<<8)|road[(2*a+1)%road.size()];
  d.c_ra=rng()%512;d.c_wa=(a%17==0)?d.c_ra:rng()%512;d.c_we=rng()&1;d.c_wdata=(uint64_t(rng()&0x1fffff)<<32)|rng();
  d.cache_ra=rng()%512;d.cache_wa=(a%19==0)?d.cache_ra:rng()%512;d.cache_we=rng()&1;
  d.cache_wdata[0]=rng();d.cache_wdata[1]=rng();d.cache_wdata[2]=rng()&65535;
  d.g_lb_ra=rng()%3072;d.g_lb_wa=(a%7==0)?d.g_lb_ra:rng()%3072;d.g_lb_we=rng()&1;d.g_lb_wdata=rng()&4095;
  d.r_lb_ra=rng()%3072;d.r_lb_wa=(a%5==0)?d.r_lb_ra:rng()%3072;d.r_lb_we=rng()&1;d.r_lb_wdata=rng()&511;
  edge();
 }
 // Re-read every Gaia address after road writes: writes reached the SAME storage.
 d.metam=0;d.g_we=0;d.g_lb_we=0;
 for(unsigned a=0;a<8192;a++){d.g_ra=a;d.g_lb_ra=a%3072;edge();}
 printf("PASS cycles=%llu checks=%llu Gaia/road alias, ownership, atomic slices, old-data logical collisions; physical collision mode unqualified\n",(unsigned long long)cycles,(unsigned long long)checks);return 0;
 }catch(const std::exception&e){fprintf(stderr,"FAIL cycle%llu: %s\n",(unsigned long long)cycles,e.what());return 1;}}
