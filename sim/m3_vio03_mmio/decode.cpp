#include "Vm3_vio03_mmio_decode.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
static Vm3_vio03_mmio_decode d;
int main(int argc,char **argv){
 Verilated::commandArgs(argc,argv);uint64_t samples=0,errors=0,known_alias_negatives=0,targets[3]={};
 uint64_t prev55=0;uint32_t prev56=0;unsigned prev56b=0;bool initialized=false;
 for(unsigned profile=0;profile<4;profile++)for(unsigned a=0;a<0x800000;a++){
  d.clk=0;d.mystic=profile&1;d.violent=bool(profile&2);d.a=a;d.eval();
  if(initialized&&(d.k55!=prev55||d.k56!=prev56||d.k56b!=prev56b)){if(errors<4)printf("ERROR combinational destination profile%u word%06x\n",profile,a);errors++;}
  uint64_t x=d.old55;uint32_t y=d.old56;unsigned z=d.old56b;bool other=d.other_match;
  uint64_t weakened=d.raw55&&(a&63)<48?(uint64_t(1)<<(a&63)):0;known_alias_negatives+=weakened!=x;
  d.clk=1;d.eval();
  unsigned bits=__builtin_popcountll(d.k55)+__builtin_popcount(d.k56)+__builtin_popcount(d.k56b);
  if(d.k55!=x||d.k56!=y||d.k56b!=z||bits>1||(bits&&other)){if(errors<8)printf("ERROR targets profile%u word%06x got%012llx/%08x/%x expected%012llx/%08x/%x collateral%u\n",profile,a,(unsigned long long)d.k55,d.k56,d.k56b,(unsigned long long)x,y,z,other);errors++;}
  targets[0]+=bool(x);targets[1]+=bool(y);targets[2]+=bool(z);prev55=d.k55;prev56=d.k56;prev56b=d.k56b;initialized=true;samples++;
 }
 if(samples!=33554432||targets[0]!=192||targets[1]!=128||targets[2]!=16||known_alias_negatives!=192)errors++;
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"word_profile_samples\":%llu,\"accepted_k55\":%llu,\"accepted_k56\":%llu,\"accepted_k56b\":%llu,\"weakened_A7_guard_counterexamples\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)samples,(unsigned long long)targets[0],(unsigned long long)targets[1],(unsigned long long)targets[2],(unsigned long long)known_alias_negatives);return errors?1:0;
}
