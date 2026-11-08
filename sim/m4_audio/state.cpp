// Constructed legal transactions; original M4 PCM and original frame1800chip1ch2
// register seed. Pinned upstream is independent prior art, not a silicon oracle.
#include "Vtb_m4_audio_state.h"
#include "verilated.h"
#include <array>
#include <vector>
#include <fstream>
#include <iterator>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <algorithm>
static Vtb_m4_audio_state*d;static std::vector<unsigned char>pcm,seed;static uint64_t clocks=0;static unsigned errors=0,checks=0,rom_reads[2]={},case_errors=0;static std::array<unsigned,8>ce{};
struct Port{bool pending=false,answered=false;unsigned address=0,wait=0;};static Port port[2];
static void eq(const char*s,unsigned a,unsigned b){checks++;if(a!=b){if(errors<18)printf("ERROR %s got=%x expected=%x cycle=%llu\n",s,a,b,(unsigned long long)clocks);errors++;}}
static void tick(unsigned n=1){while(n--){
 for(unsigned i=0;i<2;i++){
  d->ack[i]=0;
  if(d->reset){port[i]={};continue;}
  if(port[i].pending){if(!d->req[i])port[i]={};else if(!port[i].answered){if(port[i].wait)port[i].wait--;else{d->ack[i]=1;d->q[i]=pcm.at(port[i].address);port[i].answered=true;rom_reads[i]++;}}}
  else if(d->req[i]){port[i].pending=true;port[i].address=d->rom_addr[i];port[i].wait=23+(port[i].address&15);}
 }
 d->clk=0;d->eval();d->clk=1;d->eval();clocks++;
}}
static void write(unsigned a,unsigned v){d->cs=1;d->wr=1;d->rd=0;d->addr=a;d->data=v;tick();d->wr=0;tick(3);d->cs=0;}
static std::array<unsigned,2>read(unsigned a){d->cs=1;d->rd=1;d->wr=0;d->addr=a;tick(4);std::array<unsigned,2>q={d->rdata[0],d->rdata[1]};d->cs=0;d->rd=0;tick(2);return q;}
static void checkread(const char*s,unsigned a,unsigned expect){auto q=read(a);eq(s,q[0],expect);eq("pinned literal MAME register expected",q[1],expect);}
static void pos(unsigned p){write(12,p&255);write(13,(p>>8)&255);write(14,(p>>16)&255);}
static void readpos(const char*s,unsigned p){checkread(s,12,p&255);checkread(s,13,(p>>8)&255);checkread(s,14,(p>>16)&255);}
static unsigned A,B;static unsigned audible=0,sample_checks=0,rvb_mismatches=0;
static void reset(bool clear=false){d->reset=1;d->cs=d->wr=d->rd=d->cen=0;tick(8);d->reset=0;tick(8);write(0x22f,0);
 for(unsigned a=0;a<15;a++)write(a,seed.at(64+a));
 if(clear){write(0x22e,0x80);for(unsigned a=0;a<32768;a++)write(0x22d,0);write(0x22e,0);}
}
static void configure(unsigned mode,bool reverb){
 reset(true);write(0x200,mode);write(0x201,seed.at(0x205));if(!reverb)write(4,255);else write(4,3); // constructed legal attenuation; dry reference then echo
 pos(A|(mode==4?1:0));write(0x22f,1);pos(A|(mode==4?1:0));write(0x214,1);tick(48);
}
static void samples(const char*name,unsigned n,bool reverb){
 unsigned start=errors,nonzero[2]={},mismatch=0,reads0=rom_reads[0],reads1=rom_reads[1];
 for(unsigned s=0;s<n;s++){
  d->cen=1;tick();d->cen=0;tick(1999);
  if(d->l[0]||d->r[0])nonzero[0]++;if(d->l[1]||d->r[1])nonzero[1]++;
  unsigned before=errors;eq(name,d->l[0],d->l[1]);eq(name,d->r[0],d->r[1]);if(errors!=before)mismatch++;
  sample_checks++;
 }
 eq("reference meaningful original PCM samples",nonzero[1]>16,1);audible+=nonzero[1];if(reverb)rvb_mismatches=mismatch;
 printf("STATE_CASE name=%s samples=%u mismatched_samples=%u candidate_nonzero=%u pinned_nonzero=%u candidate_ROM=%u pinned_ROM=%u errors=%u\n",name,n,mismatch,nonzero[0],nonzero[1],rom_reads[0]-reads0,rom_reads[1]-reads1,errors-start);
}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=3)return 2;std::ifstream pf(argv[1],std::ios::binary),sf(argv[2],std::ios::binary);pcm.assign(std::istreambuf_iterator<char>(pf),{});seed.assign(std::istreambuf_iterator<char>(sf),{});if(pcm.size()!=0x400000||seed.size()!=560)return 2;
 A=seed[64+12]|unsigned(seed[64+13])<<8|unsigned(seed[64+14])<<16;B=seed[64+8]|unsigned(seed[64+9])<<8|unsigned(seed[64+10])<<16;if(A==B||A>=pcm.size()||B>=pcm.size())return 2;
 d=new Vtb_m4_audio_state;unsigned start=errors;
 reset();pos(A);write(0x22f,1);pos(A);write(0x214,1);tick(48);readpos("keyon originalposition",A);
 pos(B);readpos("UPDATE_AT_KEYON position hidden until nextkeyon",A);write(0x214,1);tick(48);readpos("keyon copies all three position bytes",B);ce[0]=errors-start;
 start=errors;reset();pos(A);write(0x22f,0x81);pos(B);write(0x214,1);tick(48);checkread("hold bit7 prevents active keyon",0x22c,0);readpos("hold still copies position bytes",B);
 write(0x22f,1);write(0x214,1);tick(48);checkread("normal keyon sets active",0x22c,1);write(0x22f,0x81);write(0x215,1);tick(16);checkread("hold bit7 prevents keyoff",0x22c,1);write(0x22f,0);pos(A);readpos("disabled directposition ordinary",A);ce[1]=errors-start;
 start=errors;configure(0,false);samples("ordinary_PCM8_loop",128,false);ce[2]=errors-start;
 start=errors;configure(4,false);samples("ordinary_PCM16_odd",96,false);ce[3]=errors-start;
 start=errors;configure(0x20,false);samples("ordinary_PCM8_reverse_loop",96,false);ce[4]=errors-start;
 start=errors;configure(0,true);samples("constructed_reverb_originaldelay",2560,true);ce[5]=errors-start;
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%u,\"checks\":%u,\"cycles\":%llu,\"latch_errors\":%u,\"holdbit7_errors\":%u,\"ordinary_PCM8_errors\":%u,\"ordinary_PCM16odd_errors\":%u,\"ordinary_reverse_errors\":%u,\"reverb_errors\":%u,\"reverb_mismatched_samples\":%u,\"sample_checks\":%u,\"pinned_nonzero_samples\":%u,\"ROM_reads_candidate\":%u,\"ROM_reads_pinned\":%u,\"original_seed_A\":%u,\"original_seed_B\":%u,\"physical_verified\":false}\n",errors?"false":"true",errors,checks,(unsigned long long)clocks,ce[0],ce[1],ce[2],ce[3],ce[4],ce[5],rvb_mismatches,sample_checks,audible,rom_reads[0],rom_reads[1],A,B);
 delete d;return errors?1:0;
}
