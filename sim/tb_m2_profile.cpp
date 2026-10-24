// Lead public-port image identity test. Reads original files without writes.
#include "Vpregx_rom_profile.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <vector>
static Vpregx_rom_profile d;
static unsigned long long clocks=0, starts=0, checks=0;
static void check(bool ok,const char* s){ ++checks; if(!ok){fprintf(stderr,"FAIL clock%llu: %s\n",clocks,s);exit(1);} }
static void tick(){d.clk=0;d.eval();starts+=d.begin_image;d.clk=1;d.eval();++clocks;}
static void byte(unsigned a,unsigned b){d.dl_we=0;tick();d.dl_addr=a;d.dl_data=b;d.dl_we=1;for(int n=0;n<8;n++)tick();}
static std::vector<unsigned char> load(const char* p){std::ifstream f(p,std::ios::binary);check(bool(f),"original image open");return {std::istreambuf_iterator<char>(f),{}};}
static void stream(const std::vector<unsigned char>& b,bool mystic,bool corrupt=false){
    auto oldstarts=starts;
    for(unsigned a=0;a<b.size();a++){
        byte(a,b[a]^((corrupt && a==0x1000)?1:0)); // transmission fault only
        if(a<255)check(!d.identified && !d.valid,"prefix incomplete keeps reset");
        else if(a==255)check(d.identified && d.mystic==mystic && !d.valid,"profile known before region boundary");
        if(a+1==b.size())check(d.valid==!corrupt,"complete ordered original CRC or payload fault");
        else if(d.valid)check(false,"no early valid");
    }
    check(starts==oldstarts+1,"one begin pulse despite eight-clock held WE");
    d.dl_we=0;for(int n=0;n<64;n++){tick();check(d.valid==!corrupt && d.mystic==mystic,"idle stable identity");}
    printf("stream mode%u bytes%zu corrupt%u PASS clocks%llu\n",mystic,b.size(),corrupt,clocks);fflush(stdout);
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc!=3)return 2;
    check(!d.valid&&!d.identified&&!d.mystic,"powerup holds reset");
    auto g=load(argv[1]),m=load(argv[2]);
    check(g.size()==0x1360080 && m.size()==0xdc0080,"exact frozen image lengths");
    // An unstarted transfer and interrupted prefix cannot identify a game.
    byte(255,g[255]);check(!d.identified&&!d.valid,"missing address zero");
    for(unsigned a=0;a<256;a++)byte(a,m[a]^(a==23?1:0));
    check(!d.identified&&!d.valid,"unknown prefix refused");
    for(unsigned a=0;a<256;a++)byte(a==20?21:a,g[a]);
    check(!d.identified&&!d.valid,"out of order prefix refused");
    stream(g,false);stream(m,true);stream(g,false);
    stream(m,true,true);
    // A new valid prefix followed by a skipped entire body must stay invalid.
    for(unsigned a=0;a<256;a++)byte(a,g[a]);
    check(d.identified&&!d.mystic&&!d.valid,"fresh prefix after CRC failure");
    byte(g.size()-1,g.back());check(!d.valid,"truncated body refused");
    // Recovery via a fresh download already proved both directions above.
    printf("PASS checks%llu clocks%llu starts%llu; original files unchanged by harness\n",checks,clocks,starts);
}
