// Actual common cabinet wrapper versus unmodified Gaia, pinned Mystic port bits.
#include "Vtb_m2_inputs.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
static Vtb_m2_inputs d;static unsigned checks=0;
static void ck(bool b,const char*m){++checks;if(!b){fprintf(stderr,"FAIL %s\n",m);exit(1);}}
static void ev(){d.eval();ck(d.in0_p1==d.legacy_in0&&d.p2==d.legacy_p2,"Gaia low/coin/service unchanged");if(!d.mystic)ck(d.in1==d.legacy_in1,"Gaia DIP/Test unchanged");else{ck((d.in1&8)==0,"Mystic poll bit3 always0");ck((d.in1&3)==3,"EEPROM placeholders");}}
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);
 for(unsigned keys=0;keys<256;keys++)for(unsigned dirs=0;dirs<16;dirs++)for(unsigned dip=0;dip<32;dip++){
  d.p1_keys=keys;d.p2_keys=keys^0xa5;d.p1_dirs=dirs;d.p2_dirs=dirs^15;d.dips=dip;
  d.test_select=(keys>>4)&15;d.service_select=keys&15;d.test_manual=keys&1;d.mystic=0;ev();d.mystic=1;ev();
  ck(((d.in1>>4)&1)==((dip>>4)&1),"independent Mystic stereo DIP");ck(((d.in1>>5)&1)==!(dip&4),"actual coin DIP");ck(((d.in1>>6)&1)==!(dip&8),"actual players DIP");
  ck((d.in1&4)==((d.in0_p1>>9)&4),"Test moved to actual Mystic bit2");
  ck((d.mystic_p12&255)==(d.in0_p1&255)&&(d.mystic_p12>>8)==d.p2,"physical P1/P2 word lane order");
 }
 d.p1_keys=d.p2_keys=d.p3_keys=d.p4_keys=0;d.p1_dirs=d.p2_dirs=d.p3_dirs=d.p4_dirs=0;d.test_manual=0;d.test_select=d.service_select=0;d.dips=0;d.mystic=1;ev();
 ck(d.mystic_in0==255&&d.mystic_p12==65535&&d.mystic_p34==65535&&d.in1==0xe7,"original released/default DIP board");
 for(unsigned p=0;p<4;p++)for(unsigned k=0;k<8;k++){
  d.p1_keys=d.p2_keys=d.p3_keys=d.p4_keys=0;
  if(p==0)d.p1_keys=1u<<k;else if(p==1)d.p2_keys=1u<<k;else if(p==2)d.p3_keys=1u<<k;else d.p4_keys=1u<<k;ev();
  ck((d.mystic_in0^255)==(k==6?1u<<p:0),"independent four-player coins");
  unsigned expected=0;if(k==0||k==3)expected=16;if(k==1||k==2)expected=32;if(k==5)expected=64;if(k==7)expected=128;
  unsigned word=p<2?d.mystic_p12:d.mystic_p34;ck(((word>>(8*(p&1)))&255)==(expected^255),"four-player actual action/start lanes");
 }
 d.p1_keys=d.p2_keys=d.p3_keys=d.p4_keys=0;
 for(unsigned dir=0;dir<4;dir++){
  d.p1_dirs=d.p2_dirs=d.p3_dirs=d.p4_dirs=1u<<dir;ev();ck(d.mystic_p12==((65535u)^((1u<<dir)|(1u<<(dir+8))))&&d.mystic_p34==d.mystic_p12,"four actual direction lanes");
 }
 printf("PASS checks%u ordinaryGaia131072cases MysticDIP/Test/fourplayers/privateboards; combinational only\n",checks);
}
