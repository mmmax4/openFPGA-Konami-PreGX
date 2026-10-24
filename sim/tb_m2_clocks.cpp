#include "Vtb_m2_clocks.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
static void check(bool ok,const char*message){if(!ok){fprintf(stderr,"FAIL %s\n",message);exit(1);}}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);unsigned checks=0,cases=0;
 for(int mode=0;mode<2;mode++)for(int offset=1;offset<(mode?32:24);offset+=2){
  cases++;
  Vtb_m2_clocks d;d.reset=1;d.clk=0;d.clk_vid=0;d.mystic=mode;
  int period=mode?16:12,lastvideo=-1,cycle=0,lastpix=-1,last8=-1,last16=-1;
  int pixels=0,cpu8=0,cpu16=0,audio=0;
  // Actual toggle/2FF handover at all noncoincident half-step phases.
  // Reset releases once on a falling system edge; profile/clock switching is outside scope.
  for(int n=0;n<period*2*500;n++){
   bool sys=(n%2)==0;d.clk=sys;if(sys)cycle++;
   int pos=(n+offset)%(period*2);
   if(pos==0){d.clk_vid=1;lastvideo=cycle;}
   if(pos==period)d.clk_vid=0;
   if(n==71)d.reset=0;d.eval();
   if(sys && n>period*2*40){
    check(d.c16==d.r16&&d.c8==d.r8&&d.c48==d.r48,"CPU/audio enables differ from actual baseline reference");checks++;
    if(d.cp){
     check(cycle-lastvideo==period-1,"pixel handover phase");
     if(lastpix>=0)check(cycle-lastpix==period,"pixel cadence");lastpix=cycle;pixels++;
    }
    if(!mode)check(d.cp==d.c8,"Gaia pixel waveform changed");
    if(mode){
     if(d.c8){if(last8>=0)check(cycle-last8==12,"Mystic Z80 must stay 8MHz");last8=cycle;cpu8++;}
     if(d.c16){if(last16>=0)check(cycle-last16==6,"Mystic main tokens must stay 16MHz");last16=cycle;cpu16++;}
    }
    if(d.c48)audio++;
   }
  }
  check(pixels>400&&audio>=2,"nonempty pixel/audio coverage");
  if(mode)check(cpu8>pixels&&cpu16>cpu8,"rates independent of 6MHz video");
 }
 printf("PASS m2 clock component %u comparisons; %u mode/phase cases\n",checks,cases);
}
