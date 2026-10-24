#include "Vtb_m2_order_top.h"
#include "verilated.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
static Vtb_m2_order_top d;
static unsigned cases=0;
static uint64_t clocks=0;
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();clocks++;}
static void need(bool b,const char*message){if(!b){fprintf(stderr,"FAIL case%u clock%llu %s count%u busy%u\n",cases,(unsigned long long)clocks,message,unsigned(d.count),unsigned(d.busy));exit(1);}}
static void word(unsigned a,unsigned v){d.ram_we=1;d.ram_waddr=a;d.ram_wdata=v;tick();d.ram_we=0;}
static void clear(){for(unsigned a=0;a<2048;a++)word(a,0);}
static unsigned build(){
    d.start=1;tick();d.start=0;
    for(unsigned n=1;n<=50000;n++){tick();if(d.done){need(!d.busy,"done releases busy");return n;}}
    need(false,"list must complete within50000clocks of vblank budget");return 0;
}
static void compare(const std::vector<uint32_t>& expected){
    need(d.count==expected.size(),"exact object count");need(!d.overflow,"legal object bound");
    for(unsigned n=0;n<expected.size();n++){d.list_idx=n;tick();tick();if(d.list_q!=expected[n])fprintf(stderr,"index%u actual%08x expected%08x\n",n,unsigned(d.list_q),expected[n]);need(d.list_q==expected[n],"sorted public record");}
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);d.reset=1;tick();tick();d.reset=0;d.mystic=0;d.stream_enable=0;d.shdprisel=0x39;
    clear();word(7*8,0x8037);word(7*8+6,0x00a0);cases++;unsigned ordinary=build();compare({0xa0370700});
    clear();cases++;unsigned empty=build();compare({});
    unsigned partition_max=0;
    for(unsigned profile=0;profile<2;profile++)for(unsigned stream=0;stream<2;stream++){
        clear();d.mystic=profile;d.stream_enable=stream;std::vector<uint32_t> expected;
        for(unsigned e=0;e<24;e++){
            unsigned z=(e*73+19)&255,pri=((e*5)%8)<<5,shadow=e%4,effect=e%4;
            word(e*8,0x8000|z);word(e*8+6,(shadow<<10)|(effect<<8)|pri);
            unsigned mode=(profile&&effect?2:0)|(shadow?1:0);
            expected.push_back((pri<<24)|(z<<16)|(e<<8)|(mode<<4));
            if(shadow){unsigned table=shadow-1,spri=table==0?16:table==1?64:96,cond=stream&&profile?((0x39>>(table*2))&3):0;expected.push_back((spri<<24)|(z<<16)|(e<<8)|(4<<4)|(cond<<2)|table);}
        }
        std::sort(expected.begin(),expected.end(),[&](uint32_t a,uint32_t b){
            auto deferred=[](uint32_t x){unsigned c=(x>>2)&3;return c==1||c==2;};
            if(profile&&stream&&deferred(a)!=deferred(b))return !deferred(a);
            return a>b;
        });
        cases++;partition_max=std::max(partition_max,build());compare(expected);
        clear();cases++;partition_max=std::max(partition_max,build());compare({});
    }
    printf("RESULT_JSON {\"passed\":true,\"cases\":%u,\"ordinary_clocks\":%u,\"empty_clocks\":%u,\"partition_max_clocks\":%u,\"clocks\":%llu}\nPASS empty and stable deferred object partition\n",cases,ordinary,empty,partition_max,(unsigned long long)clocks);
}
