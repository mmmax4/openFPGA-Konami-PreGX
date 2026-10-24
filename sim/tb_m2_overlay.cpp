#include "Vtb_m2_overlay.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);if(argc!=3)return 2;
 int mode=atoi(argv[1]),offset=atoi(argv[2]),period=mode?16:12;
 const int frame=6144*264;unsigned checks=0,errors=0,bypass_errors=0,green=0,dark=0,gap=0;
 Vtb_m2_overlay d;d.reset=1;d.mystic=mode;d.clk=0;d.clk_vid=0;d.eval();
 for(int n=0;n<frame*6;n++){
  d.clk=(n%2)==0;int pos=(n+offset)%(period*2);if(pos==0)d.clk_vid=1;if(pos==period)d.clk_vid=0;
  if(n==71)d.reset=0;d.eval();
  if(pos==0&&n>frame*4){
   checks++;if(d.actual!=d.expected){errors++;if(errors<4)fprintf(stderr,"difference half%d expected%06x actual%06x\n",n,d.expected,d.actual);}
   if(d.bypass!=d.rgb)bypass_errors++;
   green+=d.actual==0x20e020;dark+=d.actual==0x303030;gap+=d.actual==0;
  }
 }
 printf("%s mode%d phase%d sampled_pixels%u mismatches%u bypass_errors%u green%u dark%u gaps%u; native video-clock consumer, not physical FPGA timing\n",errors||bypass_errors||!green||!dark||!gap?"FAIL":"PASS",mode,offset,checks,errors,bypass_errors,green,dark,gap);
 return errors||bypass_errors||!green||!dark||!gap?1:0;
}
