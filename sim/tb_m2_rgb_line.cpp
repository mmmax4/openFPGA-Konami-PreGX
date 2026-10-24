// Original lead public-interface test: independent RGB arithmetic vectors and
// constructed lead shadow/control cases. Independent verification_apf additions
// check the read-only admission probe using only public accepted transactions.
// This remains a component test; palette delivery is one registered read clock.
#include "Vpregx_rgb_line.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>
static Vpregx_rgb_line d;
static std::array<uint32_t,2048> palette{};
static uint32_t palette_q=0;
static uint64_t cycles=0,stalls=0,accepted=0,checks=0;
static uint64_t probe_queries=0,same_x_queries=0,different_x_queries=0;
static uint64_t probe_hazard_queries=0,probe_range_queries=0,probe_guard_queries=0;
static unsigned targeted_probe_cases=0,pending_age_mask=0;
static bool probe_random=true,admission_initialized=false;
static unsigned clear_remaining=0;
static std::array<int,4> admission_pending={{-1,-1,-1,-1}};
struct Vector {unsigned src,dst,level,tile,expected;};
static void need(bool b,const char*what){
    checks++;if(!b){fprintf(stderr,"FAIL cycle%llu %s\n",(unsigned long long)cycles,what);exit(1);}
}
static bool pending_address(unsigned x){
    return std::find(admission_pending.begin(),admission_pending.end(),int(x))!=admission_pending.end();
}
static bool expected_ready(unsigned x){
    return admission_initialized&&!d.reset&&!d.line_start&&!clear_remaining&&x<288&&!pending_address(x);
}
static void check_admission(){
    const unsigned probe=d.probe_x;
    need(bool(d.fragment_ready)==expected_ready(d.fragment_x),"public fragment admission scoreboard");
    need(bool(d.probe_ready)==expected_ready(probe),"public probe admission scoreboard");
    probe_queries++;
    if(probe!=d.fragment_x)different_x_queries++;
    if(pending_address(probe))probe_hazard_queries++;
    if(probe>=288)probe_range_queries++;
    if(!admission_initialized||d.reset||d.line_start||clear_remaining)probe_guard_queries++;
    const bool ready=d.fragment_ready,busy=d.busy;
    const unsigned color=d.scan_rgb,pen=d.palette_addr;
    d.probe_x=d.fragment_x;d.eval();
    same_x_queries++;need(d.probe_ready==d.fragment_ready,"same-X public ready equivalence");
    d.probe_x=probe;d.eval();
    need(bool(d.fragment_ready)==ready&&bool(d.busy)==busy&&d.scan_rgb==color&&d.palette_addr==pen,
         "probe query must not affect fragment/busy/scanout/palette outputs");
    const bool any_pending=std::any_of(admission_pending.begin(),admission_pending.end(),[](int x){return x>=0;});
    need(bool(d.busy)==bool(clear_remaining||any_pending),"accepted-only pipeline/clear busy scoreboard");
}
static void admission_clock(bool fire){
    if(d.reset){admission_initialized=false;clear_remaining=0;admission_pending.fill(-1);}
    else if(d.line_start){admission_initialized=true;clear_remaining=288;admission_pending.fill(-1);}
    else {
        for(unsigned i=3;i>0;i--)admission_pending[i]=admission_pending[i-1];
        admission_pending[0]=fire?int(d.fragment_x):-1;
        if(clear_remaining)clear_remaining--;
    }
}
static bool tick(){
    if(probe_random)d.probe_x=unsigned(cycles*73+17)&511;
    d.clk=0;d.palette_q=palette_q;d.eval();
    check_admission();
    const bool fire=d.fragment_valid&&d.fragment_ready;
    const uint32_t next=palette[d.palette_addr];
    admission_clock(fire);
    d.clk=1;d.eval();palette_q=next;d.palette_q=palette_q;d.eval();cycles++;
    if(fire)accepted++;
    return fire;
}
static void drain(){
    d.fragment_valid=0;
    for(unsigned n=0;n<600;n++){d.eval();if(!d.busy)return;tick();}
    need(false,"bounded clear/retirement");
}
static void begin(uint32_t background,bool noclip=false){
    d.fragment_valid=0;d.line_start=1;d.backdrop=background;d.noclip=noclip;tick();d.line_start=0;
    unsigned count=0;while(d.busy){tick();count++;need(count<=288,"clear deadline");}
    need(count==288,"one clear write per visible pixel");
}
static void fragment(unsigned x,unsigned pen,unsigned level=255,bool tile=false,unsigned top=40,
                     bool shadow=false,unsigned tab=0,unsigned cond=3,unsigned z=20,unsigned pri=40,
                     unsigned brightness=255){
    d.fragment_x=x;d.fragment_pen=pen;d.fragment_level=level;d.fragment_tile=tile;d.fragment_toppri=top;
    d.fragment_brightness=brightness;
    d.fragment_shadow=shadow;d.fragment_table=tab;d.fragment_condition=cond;d.fragment_z=z;d.fragment_pri=pri;
    d.fragment_valid=1;
    for(unsigned n=0;n<600;n++){if(tick()){d.fragment_valid=0;return;}stalls++;}
    need(false,"fragment ready deadline");
}
static void check_front(const std::array<uint32_t,288>& expected){
    for(unsigned x=0;x<288;x++){
        d.scan_x=x;tick();
        if(d.scan_rgb!=expected[x])fprintf(stderr,"pixel%u actual%06x expected%06x\n",x,unsigned(d.scan_rgb),expected[x]);
        need(d.scan_rgb==expected[x],"completed front RGB");
    }
}
static void present(const std::array<uint32_t,288>& expected){
    drain();begin(0xabcdef);check_front(expected);
}
static void query(unsigned x,bool want,const char*what){
    d.probe_x=x;d.eval();check_admission();need(bool(d.probe_ready)==want,what);
}
static void check_probe_controls(){
    probe_random=false;d.fragment_valid=0;d.fragment_x=23;
    d.reset=1;query(17,false,"probe blocked while reset asserted");tick();
    d.reset=0;query(17,false,"probe blocked before first initialized line");
    begin(0x123456);palette[0]=0xabcdef;
    query(287,true,"last visible probe accepted");query(288,false,"WIDTH probe rejected");
    query(511,false,"largest AW address probe rejected");
    d.fragment_x=288;query(287,true,"in-range probe independent of out-of-range fragment");
    d.fragment_x=287;query(288,false,"out-of-range probe independent of valid fragment");
    targeted_probe_cases+=5;
    fragment(17,0);d.fragment_valid=0;
    for(unsigned age=0;age<4;age++){
        d.fragment_x=23;query(17,false,"different probe detects pending address at each age");
        query(23,true,"different clear probe bypasses pending address");
        d.fragment_x=17;query(23,true,"probe ready while fragment has address hazard");
        pending_age_mask|=1u<<age;tick();targeted_probe_cases++;
    }
    query(17,true,"probe address releases after four retirement clocks");
    std::array<uint32_t,288> expected{};expected.fill(0x123456);expected[17]=palette[0];present(expected);
    // Four real accepted public transactions occupy all four pending positions.
    begin(0x234567);
    for(unsigned x=10;x<14;x++)fragment(x,0);
    d.fragment_valid=0;d.fragment_x=200;
    for(unsigned oldest=10;oldest<14;oldest++){
        for(unsigned x=oldest;x<14;x++)query(x,false,"all outstanding probe addresses blocked");
        query(200,true,"unrelated probe allowed with four-position pipeline occupied");
        tick();query(oldest,true,"oldest public address becomes admissible on retirement");
        targeted_probe_cases++;
    }
    expected.fill(0x234567);for(unsigned x=10;x<14;x++)expected[x]=palette[0];present(expected);
    // Cancel at every in-flight age. The new clear must replace the admission
    // generation and keep every query blocked through all 288 actual writes.
    for(unsigned age=0;age<4;age++){
        begin(0);fragment(5,0);d.fragment_valid=0;
        for(unsigned n=0;n<age;n++)tick();
        d.fragment_x=23;d.line_start=1;d.backdrop=0x345678;
        query(5,false,"line_start blocks pending probe combinationally");tick();d.line_start=0;
        for(unsigned n=0;n<288;n++){
            query(5,false,"new-line clearing blocks cancelled address probe");tick();
        }
        query(5,true,"new line removes cancelled address hazard after clear");
        expected.fill(0);check_front(expected);
        expected.fill(0x345678);present(expected);targeted_probe_cases++;
    }
    // Reset during a real pending hazard invalidates initialization and cannot
    // leave a stale address restriction after the following line is cleared.
    begin(0);fragment(9,0);d.fragment_valid=0;d.reset=1;
    query(9,false,"reset cancels pending probe combinationally");tick();d.reset=0;
    query(9,false,"reset requires fresh initialized line");begin(0x456789);
    query(9,true,"reset pending address cleared by next initialized line");
    expected.fill(0x456789);present(expected);targeted_probe_cases++;
    need(pending_age_mask==15,"all four pending ages covered");probe_random=true;
}
static uint32_t shadow_rgb(uint32_t rgb,const std::array<int,3>& delta,bool noclip){
    uint32_t result=0;
    for(unsigned c=0;c<3;c++){
        unsigned shift=(2-c)*8;unsigned five=(rgb>>(shift+3))&31;
        // Exact pinned dipalette.cpp299..345 clamps displacement before wrap.
        int value=int((five<<3)|(five>>2))+std::max(-255,std::min(255,delta[c]));
        unsigned byte=noclip?unsigned(value)&255:unsigned(std::max(0,std::min(255,value)));
        result|=byte<<shift;
    }
    return result;
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc!=2)return 2;
    std::vector<Vector> vectors;std::ifstream input(argv[1]);std::string line;
    while(std::getline(input,line)){
        Vector v{};need(sscanf(line.c_str(),"%x %x %x %x %x",&v.src,&v.dst,&v.level,&v.tile,&v.expected)==5,"vector parse");vectors.push_back(v);
    }
    need(vectors.size()==6726,"independent vector count");
    d.reset=1;for(int c=0;c<9;c++)d.shadow_delta[c]=unsigned(-16*(c%3+1))&511;
    tick();tick();d.reset=0;d.eval();
    need(!d.fragment_ready,"reset must require first line initialization");
    check_probe_controls();
    std::array<uint32_t,288> expected{};
    // Original intro glyph palette color. Alternate black/full fragments on
    // adjacent clocks, with hostile brightness/pen bubbles, then reverse them
    // at the same addresses without draining. This checks the actual palette
    // read/payload alignment, not just standalone multiplier arithmetic.
    begin(0x123456);palette[136]=0xf00078;
    for(unsigned x=0;x<288;x++){
        if(x%7==0){d.fragment_valid=0;d.fragment_brightness=73;d.fragment_pen=0;tick();}
        fragment(x,136,255,false,40,false,0,3,20,40,(x&1)?255:0);
    }
    for(unsigned x=0;x<288;x++){
        fragment(x,136,255,false,40,false,0,3,20,40,(x&1)?0:255);
        expected[x]=(x&1)?0:0xf00078;
    }
    // Repeated-X stalls must retain the factor of the accepted transaction.
    fragment(17,136,255,false,40,false,0,3,20,40,0);
    fragment(17,136,255,false,40,false,0,3,20,40,255);expected[17]=0xf00078;
    fragment(18,136,255,false,40,false,0,3,20,40,128);expected[18]=0x78003c;
    // Brightness precedes alpha: half of the already half-bright source.
    fragment(19,136,255,false,40,false,0,3,20,40,0);
    fragment(19,136,128,false,40,false,0,3,20,40,128);expected[19]=0x3c001e;
    // Shadow reads the accumulated destination, irrespective of source BRI0.
    fragment(20,136,255,false,40,false,0,3,20,40,255);
    fragment(20,136,255,false,0,true,0,3,20,40,0);
    expected[20]=shadow_rgb(0xf00078,{-16,-32,-48},false);
    present(expected);
    unsigned batches=0;
    for(unsigned first=0;first<vectors.size();first+=288){
        unsigned count=std::min(unsigned(vectors.size())-first,288u);expected.fill(0x123456);
        for(unsigned x=0;x<count;x++){palette[x*2]=vectors[first+x].dst;palette[x*2+1]=vectors[first+x].src;expected[x]=vectors[first+x].expected;}
        begin(0x123456);
        for(unsigned x=0;x<count;x++)fragment(x,x*2);
        for(unsigned x=0;x<count;x++){
            if(x%7==0){d.fragment_valid=0;d.fragment_pen=(x*11)%2048;tick();}
            auto v=vectors[first+x];fragment(x,x*2+1,v.level,v.tile);
        }
        present(expected);batches++;
    }
    // All three sprites contribute through actual RAM RMW. Repeated addresses
    // are offered immediately and held through ready stalls, not pre-drained.
    for(unsigned seq=0;seq<2;seq++){
        unsigned first=6720+seq*3;begin(vectors[first].dst);expected.fill(vectors[first].dst);
        for(unsigned n=0;n<3;n++)palette[n]=vectors[first+n].src;
        for(unsigned n=0;n<3;n++)fragment(17,n,vectors[first+n].level,false,40-n);
        expected[17]=vectors[first+2].expected;present(expected);
    }
    const uint64_t hazard_stalls=stalls;need(hazard_stalls>=16,"same-address hazards actually exercised");
    // Dropped deferred shadows must not modify shadow Z/priority. A later
    // otherwise accepted shadow exposes an incorrect speculative update.
    begin(0x888888);expected.fill(0x888888);palette[0]=0xa1b2c3;
    fragment(0,0,255,true,40);
    fragment(0,0,255,false,0,true,0,1,10,30); // rejects pri30 <= top40
    fragment(0,0,255,false,0,true,0,1,20,50); // would fail Z if reject wrote state
    expected[0]=shadow_rgb(palette[0],{-16,-32,-48},false);
    fragment(1,0,255,true,40);
    fragment(1,0,0,true,99); // alpha0 must preserve previous top40
    fragment(1,0,255,false,0,true,0,2,20,40);
    expected[1]=shadow_rgb(palette[0],{-16,-32,-48},false);
    fragment(2,0,255,true,255);
    fragment(2,0,255,false,0,true,0,1,20,254);
    fragment(2,0,255,false,0,true,0,2,10,255);
    expected[2]=palette[0]; // top255 always rejects deferred shadows
    fragment(3,0,255,true,40);
    fragment(3,0,255,false,0,true,0,3,30,90);
    fragment(3,0,255,false,0,true,0,3,20,80);
    fragment(3,0,255,false,0,true,0,3,10,100); // priority rejects
    expected[3]=shadow_rgb(shadow_rgb(palette[0],{-16,-32,-48},false),{-16,-32,-48},false);
    fragment(4,0,255,true,40);
    fragment(4,0,255,false,0,true,3,3,20,40);
    expected[4]=shadow_rgb(palette[0],{-80,-80,-80},false);
    present(expected);
    const std::array<std::array<int,3>,3> tables={{{-16,-32,-48},{17,-65,111},{-127,64,9}}};
    for(unsigned t=0;t<3;t++)for(unsigned c=0;c<3;c++)d.shadow_delta[t*3+c]=unsigned(tables[t][c])&511;
    begin(0x8a4cbe);expected.fill(0x8a4cbe);
    for(unsigned t=0;t<3;t++){
        fragment(t,0,255,false,0,true,t,3,20,40);
        expected[t]=shadow_rgb(0x8a4cbe,tables[t],false);
    }
    present(expected);
    for(int c=0;c<9;c++)d.shadow_delta[c]=unsigned(c%3==0?-256:c%3==1?255:-80)&511;
    for(unsigned wrap=0;wrap<2;wrap++){
        begin(0x0101ff,wrap);expected.fill(0x0101ff);
        fragment(287,0,255,false,0,true,0,3,20,40);
        expected[287]=shadow_rgb(0x0101ff,{-256,255,-80},wrap);present(expected);
    }
    // Reset and new-line cancellation suppress writes from the old generation.
    begin(0);palette[0]=0xffffff;fragment(5,0);d.reset=1;tick();d.reset=0;
    begin(0x234567);expected.fill(0x234567);present(expected);
    begin(0);fragment(7,0);d.fragment_valid=0;tick();begin(0x765432);
    expected.fill(0x765432);present(expected);
    // Check the front bank immediately after cancellation at every retirement
    // age. Clearing the next bank cannot hide an accidental late old write.
    for(unsigned age=0;age<5;age++){
        begin(0);fragment(5,0);d.fragment_valid=0;
        for(unsigned n=0;n<age;n++)tick();
        begin(0x123456);expected.fill(0);expected[5]=age==4?0xffffff:0;
        check_front(expected);expected.fill(0x123456);present(expected);
    }
    printf("RESULT_JSON {\"passed\":true,\"independent_vectors\":%u,\"vector_batches\":%u,\"ordered_sequences\":2,\"hazard_stalls\":%llu,\"accepted\":%llu,\"checks\":%llu,\"cycles\":%llu,\"probe_queries\":%llu,\"same_x_queries\":%llu,\"different_x_queries\":%llu,\"probe_hazard_queries\":%llu,\"probe_range_queries\":%llu,\"probe_guard_queries\":%llu,\"targeted_probe_cases\":%u,\"pending_age_mask\":%u,\"hardware_verified\":false}\n",
        unsigned(vectors.size()),batches,(unsigned long long)stalls,(unsigned long long)accepted,(unsigned long long)checks,(unsigned long long)cycles,
        (unsigned long long)probe_queries,(unsigned long long)same_x_queries,(unsigned long long)different_x_queries,
        (unsigned long long)probe_hazard_queries,(unsigned long long)probe_range_queries,(unsigned long long)probe_guard_queries,
        targeted_probe_cases,pending_age_mask);
    puts("PASS ordered RGB line RAM/public palette/handshake; full renderer order and timing unqualified");
}
