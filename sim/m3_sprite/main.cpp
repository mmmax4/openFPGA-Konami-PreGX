#include "Vm3_sprite_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <map>
static Vm3_sprite_top d;
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();}
static void need(bool a,const char*s){if(!a){fprintf(stderr,"FAIL %s\n",s);exit(1);}}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);need(argc==2,"sprite canonical path");
 FILE*f=fopen(argv[1],"rb");need(f,"ROMopen");std::vector<unsigned char>rom(0x800000);need(fread(rom.data(),1,rom.size(),f)==rom.size(),"ROMlength");fclose(f);
 unsigned checks=0,cases=0,errors=0;unsigned code=0;
 // An original row containing transparent, ordinary and shadow pens.
 auto pixel=[&](unsigned addr,unsigned c){unsigned p=0;for(unsigned b=0;b<4;b++)p|=((rom[addr*8+(c/8)*4+b]>>(7-c%8))&1)<<b;return p;};
 bool found=false;for(code=0;code<65536;code++){unsigned kinds=0;for(unsigned c=0;c<16;c++){unsigned v=pixel(code*16,c);kinds|=v==0?1:v==15?2:4;}if(kinds==7){found=true;break;}}need(found,"original varied row");
 for(int left: {0,12,368,376})for(unsigned mode:{0u,1u}){
  d.reset=1;d.start=0;d.ready=1;d.rom_ack=0;for(unsigned i=0;i<12;i++)tick();d.reset=0;
  d.words[0]=0x8010;d.words[1]=code;d.words[2]=977;d.words[3]=40+left+8+62;d.words[4]=64;d.words[5]=64;d.words[6]=0x0c00;
  d.order=(16u<<16)|(mode<<4);d.line=16;d.start=1;tick();d.start=0;
  std::map<unsigned,unsigned>expected,actual;
  for(unsigned c=0;c<16;c++){unsigned v=pixel(code*16,c);if(left+(int)c<384&&v&&(!mode||v<15))expected[left+c]=v;}
  unsigned delay=0;bool pending=false;unsigned a=0;bool ran=false;unsigned cycles=0;
  for(;cycles<8000;cycles++){
   d.ready=(cycles%11!=3&&cycles%11!=4);d.clk=0;d.eval();
   if(d.valid&&d.ready){need(!actual.count(d.x),"duplicate fragment");actual[d.x]=d.pen;}
   d.rom_ack=0;
   if(!pending&&d.rom_req){pending=true;delay=6+(d.rom_addr%19);a=d.rom_addr;}
   if(pending&&!--delay){uint64_t q=0;for(unsigned b=0;b<8;b++)q=(q<<8)|rom[a*8+b];d.rom_q=q;d.rom_ack=1;pending=false;}
   d.clk=1;d.eval();
   if(d.busy)ran=true;if(ran&&!d.busy)break;
  }
  printf("case left%d mode%u code%u expected%zu actual%zu cycles%u\n",left,mode,code,expected.size(),actual.size(),cycles);
  for(auto p:expected)if(actual[p.first]!=p.second)fprintf(stderr,"mismatch x%u want%u got%u\n",p.first,p.second,actual[p.first]);
  need(cycles<8000,"deadline");if(actual!=expected)errors++;checks+=expected.size();cases++;
 }
 printf("RESULT sprite cases%u pixelchecks%u errors%u\n",cases,checks,errors);need(errors==0,"all original RNG pixels/clip/shadow acceptance");puts("PASS sprite");
}
