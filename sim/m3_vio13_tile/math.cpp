#include "Vm3_vio13_tile_math.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
static Vm3_vio13_tile_math d;
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);uint64_t samples=0,errors=0,both=0;
 for(unsigned profile=0;profile<4;profile++)for(unsigned layer=0;layer<4;layer++)for(unsigned value=0;value<65536;value++){
  d.mystic=profile&1;d.violent=bool(profile&2);d.layer=layer;d.scroll=value;d.eval();
  if(d.current_value!=d.old_value){if(errors<8)printf("ERROR actualsource vx0 profile%u layer%u scroll%04x old%03x new%03x\n",profile,layer,value,d.old_value,d.current_value);errors++;}
  samples++;both+=profile==3;
 }
 if(samples!=1048576||both!=262144)errors++;
 printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"scroll_layer_profile_samples\":%llu,\"both_high_samples\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",(unsigned long long)errors,(unsigned long long)samples,(unsigned long long)both);return errors?1:0;
}
