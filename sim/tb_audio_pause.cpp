#include "Vtb_audio_pause_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <fstream>
#include <iterator>
#include <memory>
#include <utility>
static void need(bool b,const char*m){if(!b){fprintf(stderr,"FAIL %s\n",m);exit(1);}}
static std::vector<unsigned char> bytes(const char*p){std::ifstream f(p,std::ios::binary);need(f.good(),p);return {std::istreambuf_iterator<char>(f),{}};}
struct Board {
 Vtb_audio_pause_top d;const std::vector<unsigned char>&pcm;
 bool pending=false,held=false;unsigned remain=0,requests=0,request_addr=0,done=0;
 std::vector<std::pair<unsigned,unsigned>> samples;
 std::vector<unsigned> addresses;
 Board(const std::vector<unsigned char>&p):pcm(p){}
 void tick(){
  d.ack=0;
  if(pending){need(d.req && d.rom_addr==request_addr,"ROM request held until ACK");if(!--remain){d.ack=1;d.q=pcm.at(request_addr);pending=false;held=true;}}
  else if(!d.req)held=false;
  if(d.req&&!pending&&!held){pending=true;request_addr=d.rom_addr;remain=9+(requests++%11);addresses.push_back(request_addr);}
  d.clk=0;d.eval();d.clk=1;d.eval();
  if(d.done){done++;samples.push_back({d.l,d.r});}
 }
 void write(unsigned a,unsigned v){d.cs=1;d.wr=1;d.rd=0;d.addr=a;d.wdata=v;tick();d.wr=0;tick();d.cs=0;}
 void init(const std::vector<unsigned char>&reg){
  d.reset=1;d.pause=0;d.cen=0;d.cs=0;d.wr=0;d.rd=0;for(int n=0;n<8;n++)tick();d.reset=0;
  // Initialize chip RAM by its real streaming port, no direct array writes.
  write(0x22e,0x80);for(unsigned n=0;n<32768;n++)write(0x22d,0);
  for(unsigned a=0;a<560;a++)if(a!=0x214&&a!=0x215&&a!=0x22c&&a!=0x22d&&a!=0x22e&&a!=0x22f)write(a,reg[a]);
  write(0x22e,reg[0x22e]);write(0x214,reg[0x22c]);write(0x22f,reg[0x22f]);
 }
};
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);need(argc==3,"usage regs PCM");auto reg=bytes(argv[1]),pcm=bytes(argv[2]);
 need(reg.size()==560&&pcm.size()==0x400000,"original data sizes");need(reg[0x22c]!=0&&(reg[0x22f]&1),"original channels active");
 Board control(pcm),paused(pcm);control.init(reg);paused.init(reg);
 bool triggered=false;unsigned pause_ticks=0,stable=0;unsigned tc=0,sp=0;
 for(unsigned n=0;n<144000;n++){
  control.d.cen=paused.d.cen=(n%2000)==0;
  if(!triggered&&n>4200&&paused.pending){triggered=true;paused.d.pause=1;}
  if(paused.d.pause){pause_ticks++;if(pause_ticks==10000)paused.d.pause=0;}
  control.tick();paused.tick();
  if(paused.d.pause&&pause_ticks>2000){
   need(!paused.d.busy&&!paused.d.req,"PCM renderer and pending ROM drain");
   if(stable++)need(tc==paused.d.timer_count&&sp==paused.d.stream_pos,"paused timer/stream stable");
   tc=paused.d.timer_count;sp=paused.d.stream_pos;
  }
 }
 need(triggered&&stable>7000,"in-flight pause coverage");need(paused.samples.size()>50,"nonempty original sample trace");
 unsigned nonzero=0;for(unsigned n=0;n<paused.samples.size();n++){
  need(paused.samples[n]==control.samples.at(n),"ordered original PCM samples differ after pause");
  nonzero+=paused.samples[n].first!=0||paused.samples[n].second!=0;
 }
 need(nonzero>20,"representative nonzero original PCM samples");
 need(paused.addresses.size()>100,"original PCM requests exercised");
 for(unsigned n=0;n<paused.addresses.size();n++)need(paused.addresses[n]==control.addresses.at(n),"PCM address sequence differs");
 // Real streaming read held across pause/ACK: one byte, pointer only on release.
 paused.d.cen=0;for(int n=0;n<2000;n++)paused.tick();
 paused.write(0x22f,reg[0x22f]|0x10);paused.write(0x22e,0);
 paused.d.cs=1;paused.d.rd=1;paused.d.addr=0x22d;paused.d.pause=1;
 unsigned first_requests=paused.requests;for(int n=0;n<100;n++)paused.tick();
 need(paused.requests==first_requests+1&&!paused.d.stall,"stream in-flight request completed in pause");
 need(paused.d.rdata==pcm[0]&&paused.d.stream_pos==0,"stream held read byte and pointer");
 for(int n=0;n<200;n++)paused.tick();need(paused.d.stream_pos==0&&paused.requests==first_requests+1,"held stream no replay");
 paused.d.pause=0;paused.d.rd=0;paused.d.cs=0;for(int n=0;n<10;n++)paused.tick();need(paused.d.stream_pos==1,"one pointer increment at release");
 printf("PASS audio pause: %zu ordered samples, %u nonzero, %zu ROM addresses, %u stable clocks; held stream ACK/read/release PASS\n",paused.samples.size(),nonzero,paused.addresses.size(),stable);
}
