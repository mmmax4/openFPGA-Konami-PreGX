#include "Vtb_m2_word_cache08.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

struct Source {
    unsigned frame=0;
    std::array<uint16_t,2048> ram{};
    std::vector<uint32_t> headers;
};
static Vtb_m2_word_cache08 *d;
static uint64_t clocks=0,checks=0,errors=0,word_checks=0,stable_checks=0,address_checks=0;
static unsigned heads=0,ordered_heads=0,all_entries=0,aborts=0,resets=0,empty_cycles=0;
static unsigned premature_ready_checks=0,complete_cancellations=0;
static uint32_t rng=0x08cace51;
static uint32_t random32(){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;return rng;}
static void equal(const char *what,uint64_t got,uint64_t expected){
    checks++;if(got!=expected){if(errors<20)printf("ERROR %s got=%llx expected=%llx clock=%llu\n",what,
        (unsigned long long)got,(unsigned long long)expected,(unsigned long long)clocks);errors++;}
}
static std::array<unsigned,7> words(){return {d->word0,d->word1,d->word2,d->word3,d->word4,d->word5,d->word6};}
static void edge(){d->clk=0;d->eval();d->clk=1;d->eval();clocks++;}
static void check_words(const Source&s,unsigned ent){
    auto got=words();for(unsigned w=0;w<7;w++){word_checks++;equal("original raw word",got[w],s.ram[ent*8+w]);}
}
static void reset(){d->reset=1;d->line_start=0;d->consume=0;edge();equal("reset invalidates ready",d->ready,0);d->reset=0;resets++;}
static void setup(const Source&s){
    d->head_valid=0;reset();d->reset=1;
    for(unsigned i=0;i<2048;i++){d->setup_we=1;d->setup_addr=i;d->setup_data=s.ram[i];edge();}
    d->setup_we=0;d->reset=0;edge();
}
static void empty(unsigned n){
    d->head_valid=0;d->consume=0;
    for(unsigned i=0;i<n;i++){edge();equal("no head means not ready",d->ready,0);empty_cycles++;}
}
static void fetch(const Source&s,unsigned ent){
    d->head_valid=1;d->head_ent=ent;d->consume=0;d->clk=0;d->eval();
    equal("new head not already complete",d->ready,0);
    // Head capture, seven one-clock SRAM reads, then final response. These
    // public address/latency checks do not depend on internal FSM/tag access.
    for(unsigned n=1;n<=9;n++){
        if(n>=2&&n<=8){address_checks++;equal("seven sequential source addresses",d->ram_addr,ent*8+n-2);}
        edge();equal("complete only after final one-clock response",d->ready,n==9);
        if(n<9)premature_ready_checks++;
    }
    check_words(s,ent);heads++;
}
static void serve(const Source&s,unsigned ent,unsigned stall){
    fetch(s,ent);auto held=words();
    for(unsigned i=0;i<stall;i++){
        edge();equal("ready stays asserted under consumer stall",d->ready,1);
        auto got=words();for(unsigned w=0;w<7;w++){stable_checks++;equal("raw head words held",got[w],held[w]);}
        check_words(s,ent);
    }
    // The consumer samples the original seven words on this accepted edge.
    check_words(s,ent);d->consume=1;edge();d->consume=0;
    equal("consume invalidates old tag",d->ready,0);
}
static Source load(const char *path){
    Source s;std::ifstream in(path);std::string key,value;unsigned n;
    if(!(in>>key>>s.frame)||key!="ORIGINAL")std::exit(2);
    in>>key>>n;if(key!="RAM"||n!=2048)std::exit(2);
    for(auto &word:s.ram){in>>value;word=uint16_t(std::stoul(value,nullptr,16));}
    in>>key>>n;if(key!="HEADERS"||n>512)std::exit(2);
    for(unsigned i=0;i<n;i++){in>>value;s.headers.push_back(std::stoul(value,nullptr,16));}
    if(!in)std::exit(2);return s;
}
static void cancel(const Source&s,bool hard,unsigned elapsed,bool simultaneous_consume){
    d->head_valid=0;reset();empty(2);unsigned oldent=(13*elapsed+71)&255;
    d->head_valid=1;d->head_ent=oldent;d->consume=0;
    for(unsigned i=0;i<elapsed;i++)edge();
    if(elapsed<9)equal("cancel while incomplete",d->ready,0);
    else{equal("cancel after completion",d->ready,1);complete_cancellations++;check_words(s,oldent);}
    d->consume=simultaneous_consume;
    if(hard){d->reset=1;resets++;}else d->line_start=1;
    edge();equal("cancellation wins over response/consume",d->ready,0);
    d->reset=0;d->line_start=0;d->consume=0;
    // A distinct replacement tag must not inherit stale words or completion.
    unsigned replacement=(oldent+113)&255;serve(s,replacement,5);aborts++;
}
int main(int argc,char **argv){
    Verilated::commandArgs(argc,argv);if(argc!=3)return 2;
    d=new Vtb_m2_word_cache08;d->clk=0;d->reset=1;d->line_start=0;d->head_valid=0;
    d->head_ent=0;d->consume=0;d->setup_we=0;d->setup_addr=0;d->setup_data=0;d->eval();
    Source a=load(argv[1]),b=load(argv[2]);
    equal("original intro list cardinality",a.headers.size(),141);
    equal("original snow list cardinality",b.headers.size(),98);
    for(auto &s:{a,b}){
        setup(s);empty(17);
        for(unsigned ent=0;ent<256;ent++){serve(s,ent,ent%4);all_entries++;}
        // Original stable header order, including repeated physical entries
        // from solid/shadow operations. No source word/register is patched.
        for(unsigned pass=0;pass<2;pass++)for(auto h:s.headers){
            serve(s,(h>>8)&255,pass?random32()%32:0);ordered_heads++;
            if(pass&&!(random32()&7))empty(random32()%5+1);
        }
        // Consume/reload the same tag repeatedly: old completion cannot leak.
        for(unsigned repeat=0;repeat<16;repeat++)serve(s,255,repeat%5);
        for(bool hard:{false,true}){
            for(unsigned elapsed=0;elapsed<=9;elapsed++)cancel(s,hard,elapsed,false);
            cancel(s,hard,9,true);
        }
        empty(11);
    }
    equal("all original SRAM entries",all_entries,512);
    equal("ordered original headers twice",ordered_heads,478);
    equal("full completed head matrix",heads,1066);
    equal("response/start/complete cancellation matrix",aborts,44);
    equal("complete cancellations exercised",complete_cancellations,8);
    equal("original ready words checked",word_checks>10000,1);
    equal("stalled raw words exercised",stable_checks>10000,1);
    printf("RESULT_JSON {\"passed\":%s,\"errors\":%llu,\"checks\":%llu,\"original_frames\":2,\"all_original_entries\":%u,\"ordered_original_headers\":%u,\"completed_heads\":%u,\"original_word_checks\":%llu,\"held_word_checks\":%llu,\"read_address_checks\":%llu,\"premature_ready_checks\":%u,\"aborts\":%u,\"complete_cancellations\":%u,\"resets\":%u,\"empty_cycles\":%u,\"cycles\":%llu,\"hardware_verified\":false}\n",
        errors?"false":"true",(unsigned long long)errors,(unsigned long long)checks,all_entries,ordered_heads,heads,
        (unsigned long long)word_checks,(unsigned long long)stable_checks,(unsigned long long)address_checks,
        premature_ready_checks,aborts,complete_cancellations,resets,empty_cycles,(unsigned long long)clocks);
    delete d;return errors?1:0;
}
