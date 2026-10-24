#include "Vtb_m2_zslot_top.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>
static Vtb_m2_zslot_top d;
static uint64_t clocks=0, compared=0;
static unsigned cases=0, max_build=0, bypass_cases=0;
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();clocks++;}
static void fail(const char*kind,unsigned actual=0,unsigned expected=0){
    printf("RESULT_JSON {\"passed\":false,\"failure\":\"%s\",\"cases\":%u,\"actual\":%u,\"expected\":%u,\"records_compared\":%llu,\"clocks\":%llu}\n",
           kind,cases,actual,expected,(unsigned long long)compared,(unsigned long long)clocks);exit(1);
}
static std::map<std::string,std::vector<unsigned>> state(const std::string&path){
    std::ifstream f(path);if(!f)fail("state_open");std::string line;
    std::map<std::string,std::vector<unsigned>> result;
    while(std::getline(f,line)){
        std::istringstream row(line);std::string key;row>>key;
        if(key=="VRAM"||key=="FRAME"||key.empty())continue;
        unsigned value;while(row>>std::hex>>value)result[key].push_back(value);
    }
    return result;
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc!=2)fail("args");
    d.reset=1;tick();tick();d.reset=0;
    std::ifstream cases_file(argv[1]);if(!cases_file)fail("cases_open");std::string line;
    while(std::getline(cases_file,line)){
        std::istringstream row(line);std::string state_file,expected_file;unsigned bypass_count=0;
        row>>state_file>>expected_file>>bypass_count;
        auto st=state(state_file);auto &ram=st["SPRITERAM"],&k46=st["K46REGS"],&k47=st["K47REGS"],&k55=st["K55REGS"],&k38=st["K38REGS"];
        if(ram.size()!=2048||k46.size()!=8||k47.size()<7||k55.size()<42||k38.size()<11)fail("state_shape");
        d.mystic=1;d.stream_enable=1;d.opset=k47[6];d.objset1=k46[5];d.k46_offy=(k46[2]<<8)|k46[3];
        d.shdprisel=k55[41]&63;d.shadow_priorities=k55[37]|(k55[38]<<8)|(k55[39]<<16);d.shadowon=0;
        for(unsigned t=0;t<3;t++)for(unsigned c=0;c<3;c++){
            int v=k38[2+t*3+c]&511;if(v&256)v-=512;if(v>7||v<-7)d.shadowon|=1<<t;
        }
        for(unsigned i=0;i<2048;i++){d.ram_we=1;d.ram_waddr=i;d.ram_wdata=ram[i];tick();}d.ram_we=0;
        std::vector<uint32_t> expected;std::ifstream exp(expected_file);if(!exp)fail("expected_open");
        uint32_t v;while(exp>>std::hex>>v)expected.push_back(v);
        cases++;d.start=1;tick();d.start=0;unsigned n=0;
        for(;n<50000;n++){tick();if(d.done)break;}
        if(n==50000||d.busy||d.overflow)fail("build_completion");
        if(n>max_build)max_build=n;
        if(d.count!=expected.size())fail("object_count",d.count,expected.size());
        for(unsigned i=0;i<expected.size();i++){
            d.list_idx=i;tick();tick();
            if(d.list_q!=expected[i])fail("ordered_record",d.list_q,expected[i]);compared++;
        }
        if(bypass_count){
            // Same original RAM, without resetting the DUT: the Mystic-only
            // policy must not alter the other profile's list cardinality.
            d.mystic=0;d.stream_enable=0;d.start=1;tick();d.start=0;
            unsigned m=0;for(;m<50000;m++){tick();if(d.done)break;}
            if(m==50000||d.busy||d.overflow)fail("bypass_completion");
            if(d.count!=bypass_count)fail("profile_bypass_count",d.count,bypass_count);
            bypass_cases++;
        }
    }
    if(cases<2||!compared)fail("zero_coverage");
    printf("RESULT_JSON {\"passed\":true,\"cases\":%u,\"profile_bypass_cases\":%u,\"records_compared\":%llu,\"max_build_clocks\":%u,\"clocks\":%llu}\n",
           cases,bypass_cases,(unsigned long long)compared,max_build,(unsigned long long)clocks);
}
