#include "Vm3_vio12_mmio_decode.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
static Vm3_vio12_mmio_decode d;
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);uint64_t samples=0,errors=0,k000_targets=0,live_ext_checks=0,stale_address_controls=0;uint64_t prev55=0;unsigned prev56=0,prev56b=0,prev_control=0;bool initialized=false;
 for(unsigned profile=0;profile<4;profile++)for(unsigned a=0;a<0x800000;a++){
  // Address permutation alternates far pages and adjacent indices; every word
  // is visited once. It detects capture from previous A rather than rawsharedA.
  unsigned address=(a&1)?(0x7fffff-(a>>1)):(a>>1);
  d.clk=0;d.mystic=profile&1;d.violent=bool(profile&2);d.a=address;d.eval();
  unsigned control=d.k000|(d.local_other<<1)|(d.vram<<2);
  if(initialized&&(d.k55!=prev55||d.k56!=prev56||d.k56b!=prev56b||control!=prev_control))errors++;
  d.clk=1;d.eval();
  if(d.k55!=d.old55||d.k56!=d.old56||d.k56b!=d.old56b||d.k000!=d.old_k000||d.local_other!=d.old_other||d.vram!=d.old_vram){if(errors<8)printf("ERROR profile%u rawword%06x newcontrols%u%u%u old%u%u%u\n",profile,address,d.k000,d.local_other,d.vram,d.old_k000,d.old_other,d.old_vram);errors++;}
  control=d.k000|(d.local_other<<1)|(d.vram<<2);
  if(initialized)stale_address_controls+=control!=prev_control;
  for(unsigned ext=0;ext<2;ext++){
   bool actual=d.local_other||(d.vram&&ext),expected=d.old_other||(d.old_vram&&ext);
   if(actual!=expected)errors++;live_ext_checks++;
  }
  k000_targets+=d.k000;prev55=d.k55;prev56=d.k56;prev56b=d.k56b;prev_control=control;initialized=true;samples++;
 }
 if(samples!=33554432||k000_targets!=32||live_ext_checks!=67108864||stale_address_controls==0)errors++;
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"word_profile_samples\":%llu,\"K000_targets\":%llu,\"live_vram_ext_checks\":%llu,\"stale_address_negative_controls\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)samples,(unsigned long long)k000_targets,(unsigned long long)live_ext_checks,(unsigned long long)stale_address_controls);return errors?1:0;
}
