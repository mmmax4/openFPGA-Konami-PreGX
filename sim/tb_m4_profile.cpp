// Lead four-profile public-port image identity test. Reads original files without writes.
#include "Vpregx_rom_profile.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <vector>
static Vpregx_rom_profile d;
static bool metam(){
#ifdef M4_HAS_METAM
 return d.metam;
#else
 return false;
#endif
}
static unsigned long long clocks=0, starts=0, checks=0;
static void check(bool ok,const char* s){ ++checks; if(!ok){fprintf(stderr,"FAIL clock%llu: %s\n",clocks,s);exit(1);} }
static void tick(){d.clk=0;d.eval();starts+=d.begin_image;d.clk=1;d.eval();++clocks;}
static void byte(unsigned a,unsigned b){d.dl_we=0;tick();d.dl_addr=a;d.dl_data=b;d.dl_we=1;for(int n=0;n<8;n++)tick();}
static std::vector<unsigned char> load(const char* p){std::ifstream f(p,std::ios::binary);check(bool(f),"original image open");return {std::istreambuf_iterator<char>(f),{}};}
static void stream(const std::vector<unsigned char>& b,unsigned profile,bool corrupt=false,bool reordered=false){
    auto oldstarts=starts;
    for(unsigned a=0;a<b.size();a++){
        byte(reordered && (a==0x1000 || a==0x1001) ? (a^1) : a,b[a]^((corrupt && a==0x1000)?1:0)); // transmission fault only
        if(a<255)check(!d.identified && !d.valid,"prefix incomplete keeps reset");
        else if(a==255)check(d.identified && d.mystic==(profile==1) && d.violent==(profile==2) && metam()==(profile==3) && !d.valid,"profile known before region boundary");
        if(a+1==b.size())check(d.valid==!(corrupt || reordered),"complete ordered original CRC or payload fault");
        else if(d.valid)check(false,"no early valid");
    }
    check(starts==oldstarts+1,"one begin pulse despite eight-clock held WE");
    d.dl_we=0;for(int n=0;n<64;n++){tick();check(d.valid==!(corrupt || reordered) && d.mystic==(profile==1) && d.violent==(profile==2) && metam()==(profile==3),"idle stable identity");}
    printf("stream mode%u bytes%zu corrupt%u PASS clocks%llu\n",profile,b.size(),corrupt,clocks);fflush(stdout);
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc!=5)return 2;
    check(!d.valid&&!d.identified&&!d.mystic&&!d.violent&&!metam(),"powerup holds reset");
    auto g=load(argv[1]),m=load(argv[2]),v=load(argv[3]),f=load(argv[4]);
    check(g.size()==0x1360080 && m.size()==0xdc0080 && v.size()==0x1240080 && f.size()==0x1280080,"exact frozen image lengths");
    // An unstarted transfer and interrupted prefix cannot identify a game.
    byte(255,g[255]);check(!d.identified&&!d.valid,"missing address zero");
    for(unsigned a=0;a<256;a++)byte(a,m[a]^(a==23?1:0));
    check(!d.identified&&!d.valid,"unknown prefix refused");
    for(unsigned a=0;a<256;a++)byte(a==20?21:a,g[a]);
    check(!d.identified&&!d.valid,"out of order prefix refused");
    // Check the previously unsupported prefix first: the same fixture must fail on M3.
    for(unsigned a=0;a<256;a++)byte(a,f[a]);
    check(d.identified && metam() && !d.mystic && !d.violent && !d.valid,"Metamorphic prefix identified independently");
    stream(f,3);stream(g,0);stream(m,1);stream(v,2);stream(f,3);
    stream(f,3,false,true); // CRC unchanged; only address ordering is wrong
    stream(f,3,true);
    stream(v,2); // recover into the existing ordinary RNG profile
    byte(v.size(),0);check(!d.valid,"extra trailing byte clears valid");
    for(unsigned a=0;a<256;a++)byte(a,f[a]);
    byte(f.size()-1,f.back());check(!d.valid,"truncated Metamorphic refused");
    // A new valid prefix followed by a skipped entire body must stay invalid.
    for(unsigned a=0;a<256;a++)byte(a,g[a]);
    check(d.identified&&!d.mystic&&!d.violent&&!d.valid,"fresh prefix after CRC failure");
    byte(g.size()-1,g.back());check(!d.valid,"truncated body refused");
    // Recovery via a fresh download already proved both directions above.
    printf("PASS checks%llu clocks%llu starts%llu; original files unchanged by harness\n",checks,clocks,starts);
}
