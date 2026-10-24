#include "Vtb_m2_names_compat_top.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

static Vtb_m2_names_compat_top d;
static uint64_t clocks=0,records=0,ranges=0;
static unsigned cases=0,filtered=0,bypass=0,word_negatives=0,reset_cases=0,max_build=0;
static std::string active;
using State=std::map<std::string,std::vector<unsigned>>;
struct Fixture {std::string name;State state;std::vector<uint32_t> expected;};
static void tick(){d.clk=0;d.eval();d.clk=1;d.eval();clocks++;}
static void fail(const char*what,unsigned actual=0,unsigned expected=0){
    printf("RESULT_JSON {\"passed\":false,\"failure\":\"%s\",\"case\":\"%s\",\"cases\":%u,\"actual\":%u,\"expected\":%u,\"clocks\":%llu}\n",what,active.c_str(),cases,actual,expected,(unsigned long long)clocks);exit(1);
}
static void require(bool yes,const char*what,unsigned a=0,unsigned b=0){if(!yes)fail(what,a,b);}
static State state(const std::string&path){
    std::ifstream f(path);require(bool(f),"state_open");State st;std::string line;
    while(std::getline(f,line)){std::istringstream row(line);std::string key;row>>key;
        if(key.empty()||key=="VRAM"||key=="FRAME")continue;
        unsigned v;while(row>>std::hex>>v)st[key].push_back(v);
    }return st;
}
static void load(const State&st){
    const auto &ram=st.at("SPRITERAM"),&a=st.at("K46REGS"),&b=st.at("K47REGS"),&c=st.at("K55REGS"),&e=st.at("K38REGS");
    require(ram.size()==2048&&a.size()>=8&&b.size()>=7&&c.size()>=42&&e.size()>=11,"state_shape");
    d.mystic=1;d.stream_enable=1;d.opset=b[6];d.objset1=a[5];d.k46_offy=(a[2]<<8)|a[3];
    d.shdprisel=c[41]&63;d.shadow_priorities=c[37]|c[38]<<8|c[39]<<16;d.shadowon=0;
    d.priority_c=c[13];d.priority_d=c[14];
    for(unsigned t=0;t<3;t++)for(unsigned k=0;k<3;k++){int v=e[2+t*3+k]&511;if(v&256)v-=512;if(v>7||v<-7)d.shadowon|=1<<t;}
    for(unsigned i=0;i<2048;i++){d.ram_we=1;d.ram_waddr=i;d.ram_wdata=ram[i];tick();}d.ram_we=0;
}
static std::array<unsigned,4> build(){
    std::array<unsigned,4> elapsed{};d.start=1;tick();d.start=0;
    for(unsigned n=1;n<50000;n++){
        tick();for(unsigned k=0;k<4;k++)if((d.done&(1<<k))&&!elapsed[k])elapsed[k]=n;
        if(std::all_of(elapsed.begin(),elapsed.end(),[](unsigned n){return n!=0;})){
            require(d.busy==0&&d.overflow==0,"completion_flags");
            for(auto n:elapsed)max_build=std::max(max_build,n);return elapsed;
        }
    }fail("build_timeout");return elapsed;
}
static void run(const std::string&name,const State&st,bool option,bool remove,bool profile=true,const std::vector<uint32_t>*golden=nullptr){
    active=name;cases++;load(st);d.opt_in=option;d.mystic=profile;if(!profile)d.stream_enable=0;
    auto times=build();
    require(times[1]==times[0]&&times[2]==times[0],"default_bypass_cycles",times[1],times[0]);
    bool gate=option&&profile&&d.priority_c==0x50&&d.priority_d==0x90;
    if(!gate)require(times[3]==times[0],"runtime_bypass_cycles",times[3],times[0]);
    for(unsigned k=1;k<3;k++)require(d.count[k]==d.count[0],"default_bypass_count",d.count[k],d.count[0]);
    std::vector<uint32_t> old,actual;
    unsigned extent=std::max(unsigned(d.count[0]),unsigned(d.count[3]));
    for(unsigned i=0;i<extent;i++){
        d.list_idx=i;tick();tick();
        if(i<d.count[0]){
            old.push_back(d.list_q[0]);
            for(unsigned k=1;k<3;k++){require(d.list_q[k]==d.list_q[0],"default_bypass_order",d.list_q[k],d.list_q[0]);records++;}
        }
        if(i<d.count[3])actual.push_back(d.list_q[3]);
    }
    if(golden)require(old==*golden,"original_header_orders");
    auto expected=old;
    if(remove)expected.erase(std::remove_if(expected.begin(),expected.end(),[](uint32_t r){return ((r>>8)&255)<8;}),expected.end());
    require(actual==expected,"compat_exact_order_difference",actual.size(),expected.size());records+=expected.size();
    for(unsigned i=0;i<256;i++){
        d.yr_addr=i;tick();tick();
        for(unsigned k=1;k<3;k++){require(d.yr_q[k]==d.yr_q[0],"default_bypass_geometry",d.yr_q[k],d.yr_q[0]);ranges++;}
        if(!(remove&&i<8)){require(d.yr_q[3]==d.yr_q[0],"unfiltered_geometry",d.yr_q[3],d.yr_q[0]);ranges++;}
    }
    if(remove){filtered++;require(old.size()==actual.size()+8,"exact_eight_omitted",old.size(),actual.size()+8);}
    else bypass++;
    printf("CASE %s original=%zu compat=%zu cycles=%u/%u/%u/%u\n",name.c_str(),old.size(),actual.size(),times[0],times[1],times[2],times[3]);
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);require(argc==2,"args");d.reset=1;tick();tick();d.reset=0;
    std::ifstream f(argv[1]);require(bool(f),"cases_open");std::vector<Fixture> fixtures;std::string name,path,orders;
    while(f>>name>>path>>orders){Fixture a{name,state(path),{}};std::ifstream g(orders);require(bool(g),"orders_open");uint32_t v;while(g>>std::hex>>v)a.expected.push_back(v);fixtures.push_back(a);}
    require(fixtures.size()==4,"fixture_count");auto &portrait=fixtures[0],&road=fixtures[1],&truck=fixtures[2],&game=fixtures[3];
    // Fingerprint truth comes from the frozen original state, not DUT constants.
    const auto original=road.state.at("SPRITERAM");
    for(auto &x:fixtures){
        run(x.name+"-off",x.state,false,false,true,&x.expected);
        bool match=x.name=="road"||x.name=="truck";
        run(x.name+"-on",x.state,true,match,true,&x.expected);
    }
    for(unsigned i=0;i<64;i++){auto s=road.state;s["SPRITERAM"][i]^=1;run("word-"+std::to_string(i),s,true,false);word_negatives++;}
    for(unsigned ent=0;ent<8;ent++){
        auto s=road.state;s["SPRITERAM"][8*ent]&=0x7fff;run("inactive-"+std::to_string(ent),s,true,false);
        s=road.state;s["SPRITERAM"][8*ent]^=0x100;run("w0-high-bit-"+std::to_string(ent),s,true,false);
        s=road.state;s["SPRITERAM"][8*ent]=(original[8*ent]&0xff00)|0x80;run("excluded-z-"+std::to_string(ent),s,true,false);
        s=road.state;s["SPRITERAM"][8*ent]+=0x40;run("accepted-high-z-"+std::to_string(ent),s,true,true);
    }
    auto high=road.state;for(unsigned i=0;i<8;i++)high["SPRITERAM"][8*i]+=0x40;
    run("all-high-z",high,true,true);
    auto mixed=road.state;for(unsigned i=0;i<8;i+=2)mixed["SPRITERAM"][8*i]+=0x40;
    run("mixed-observed-z",mixed,true,true);
    for(unsigned n=0;n<8;n++){auto s=road.state;std::fill(s["SPRITERAM"].begin()+8*n,s["SPRITERAM"].begin()+64,0);run("partial-set-"+std::to_string(n),s,true,false);}
    auto wrong=road.state;wrong["K55REGS"][13]^=1;run("priority-c-mismatch",wrong,true,false);
    wrong=road.state;wrong["K55REGS"][14]^=1;run("priority-d-mismatch",wrong,true,false);
    run("gaiapolis-profile-bypass",road.state,true,false,false);
    // An extra ordinary copy outside the designated entries must remain listed.
    auto duplicate=road.state;std::copy(original.begin(),original.begin()+8,duplicate["SPRITERAM"].begin()+8*20);run("outside-slot-duplicate",duplicate,true,true);
    run("reentry-off",road.state,false,false);run("reentry-on",road.state,true,true);run("reentry-off-again",road.state,false,false);
    run("switch-gameplay",game.state,true,false);run("switch-back-road",road.state,true,true);run("return-portrait",portrait.state,true,false);
    active="reset-during-prepass";load(road.state);d.opt_in=1;d.start=1;tick();d.start=0;
    for(unsigned i=0;i<25;i++)tick();require((d.busy&8)&&!(d.done&8),"prepass_not_busy");
    d.reset=1;tick();require(d.busy==0&&d.done==0,"reset_cancels_build");d.reset=0;tick();reset_cases++;
    auto mismatch=road.state;mismatch["SPRITERAM"][63]=1;
    run("post-reset-mismatch",mismatch,true,false);run("post-reset-full-match",road.state,true,true);
    require(word_negatives==64&&filtered>=10&&bypass>64&&reset_cases==1&&records>0&&ranges>0,"zero_coverage");
    printf("RESULT_JSON {\"passed\":true,\"cases\":%u,\"filtered_cases\":%u,\"bypass_cases\":%u,\"fingerprint_word_negatives\":%u,\"reset_during_prepass_cases\":%u,\"records_compared\":%llu,\"geometry_ranges_compared\":%llu,\"max_build_clocks\":%u,\"clocks\":%llu,\"physical_hardware_verified\":false}\n",cases,filtered,bypass,word_negatives,reset_cases,(unsigned long long)records,(unsigned long long)ranges,max_build,(unsigned long long)clocks);
    d.final();return 0;
}
