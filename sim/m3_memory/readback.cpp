// Public CPU readback request/row ports. Original canonical dumps, no ROM edits.
#include "Vmystic_rom_readback.h"
#include "verilated.h"
#include <fstream>
#include <iterator>
#include <vector>
#include <cstdio>
#include <cstdlib>
#include "mame_oracle.h"
static k056832_device tile_oracle;
static k053247_device sprite_oracle;
static Vmystic_rom_readback d;
static std::vector<unsigned char> tiles,sprites;
static unsigned checks=0,clocks=0,fetches=0,timer=0,row=0,owner=0,sequence=0;
static bool delivered=false;
static void ck(bool ok,const char*msg){++checks;if(!ok){fprintf(stderr,"FAIL clock%u check%u %s\n",clocks,checks,msg);exit(1);}}
static void step(){
    d.tile_ack=0;d.spr_ack=0;
    bool active=owner==1?d.tile_req:owner==2?d.spr_req:false;
    if(owner && !active){owner=0;timer=0;delivered=false;}
    ck(!(d.tile_req&&d.spr_req),"one owner");
    if(!owner&&(d.tile_req||d.spr_req)){
        owner=d.tile_req?1:2;row=owner==1?d.tile_addr:d.spr_addr;
        timer=6+(sequence++*7)%31;delivered=false;++fetches;
    }
    if(owner){
        ck(row==(owner==1?d.tile_addr:d.spr_addr),"held memory address");
        if(timer)--timer;
        else if(!delivered){
            delivered=true;
            if(owner==1){ck(row<0x100000,"populated tile only");unsigned b=5*row;
                d.tile_q=(unsigned(tiles[b])<<24)|(unsigned(tiles[b+1])<<16)|(unsigned(tiles[b+2])<<8)|tiles[b+3];
                d.tile_fifth=tiles[b+4];d.tile_ack=1;
            }else{ck(row<0x100000,"valid sprite row");unsigned long long q=0;for(int i=0;i<8;i++)q=q*256+sprites[8*row+i];
                d.spr_q=q;d.spr_fifth=0;d.spr_ack=1;
            }
        }
    }
    d.clk=0;d.eval();d.clk=1;d.eval();++clocks;
}
static void release(){d.req=0;step();step();ck(!d.ack&&!d.tile_req&&!d.spr_req,"release clears pending");}
static unsigned tile_expect(unsigned bank,unsigned off,bool plane,bool&bad){
    if(bank & 0x80000000u){bad=true;return 0;} // explicitly unsupported signed/OOB MAME bank
    unsigned at=10240*(bank%768)+5*(plane?off/4:off/2);
    bad=at+4>=tiles.size();if(bad)return 0;
    tile_oracle.m_cur_gfx_banks=bank%768;tile_oracle.m_regsb[2]=plane?8:0;
    return tile_oracle.mw_rom_word_r(off);
}
static unsigned spr_expect(unsigned word,unsigned off,bool&bad){
    unsigned w=(word/4)*4+(off<4?2:0)+(off%4);bad=2*w+1>=sprites.size();if(bad)return 0;
    sprite_oracle.m_kx46_regs[6]=(word>>16)&255;sprite_oracle.m_kx46_regs[7]=(word>>8)&255;sprite_oracle.m_kx46_regs[4]=word&255;
    return sprite_oracle.k055673_rom_word_r(off);
}
static void read(bool sprite,unsigned bankword,unsigned off,bool plane=false){
    release();d.sprite=sprite;d.offset=off;d.tile_bank=bankword;d.sprite_word=bankword;d.tile_plane5=plane;d.req=1;
    unsigned n=0;while(!d.ack){step();ck(++n<100,"transaction bounded with variable ACK");}
    bool bad=false;unsigned expected=sprite?spr_expect(bankword,off,bad):tile_expect(bankword,off,plane,bad);
    if(d.data!=expected){fprintf(stderr,"kind%u bankword%x off%x plane%u actual%04x expected%04x\n",sprite,bankword,off,plane,unsigned(d.data),expected);ck(false,"original raw MMIO result");}
    ck(bool(d.out_of_range)==bad,"out of region explicit instead of alias");
    for(int i=0;i<4;i++){step();ck(!d.ack&&d.data==expected,"one ACK and held result");}
}
static std::vector<unsigned char> load(const char*p){std::ifstream f(p,std::ios::binary);ck(bool(f),"original input open");return {std::istreambuf_iterator<char>(f),{}};}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc!=3)return 2;tiles=load(argv[1]);sprites=load(argv[2]);ck(tiles.size()==0x600000&&sprites.size()==0x800000,"original canonical lengths");
    tile_oracle.m_rombase=tiles;sprite_oracle.m_gfxrom=sprites;
    d.violent=1;d.reset=1;d.req=0;step();step();d.reset=0;
    // Every canonical bank0..511, first/last of both window halves, lower and5th.
    for(unsigned bank:{0u,1u,255u,256u,510u,511u,512u,513u,613u,614u,615u,766u,767u})for(unsigned off:{0u,1u,2u,3u,0x7feu,0x7ffu,0xffeu,0xfffu,0x1ffcu,0x1ffdu,0x1ffeu,0x1fffu}){read(false,bank,off);read(false,bank,off,true);}
    for(unsigned bank:{768u,769u,1024u,65536u,0x123456u,0x7fffffffu,0x80000000u})for(unsigned off:{0u,1u,0x1fffu}){read(false,bank,off);read(false,bank,off,true);}
    for(unsigned off=0;off<8;off++)for(unsigned word:{0u,1u,2u,3u,0x3cu,0x3du,0x7c0u,0x7c1u,0xe00u,0x1ffffcu,0x1ffffdu,0x1ffffeu,0x1fffffu,0x200000u,0x3ffffcu,0x3fffffu,0x400000u,0xffffffu})read(true,word,off);
    unsigned seed=0x550832;
    for(unsigned i=0;i<256;i++){seed=seed*1664525u+1013904223u;unsigned bank=seed&0x7fffffffu;seed=seed*1664525u+1013904223u;read(false,bank,seed&0x1fff);read(false,bank,seed&0x1fff,true);read(true,seed&0x3fffff,(seed>>20)&7);}
    // All memory latencies and cancellation before or while waiting for a row.
    for(unsigned wait=1;wait<40;wait++){
        release();d.sprite=wait&1;d.offset=0;d.tile_bank=0;d.sprite_word=0x7c0;d.req=1;
        for(unsigned i=0;i<wait;i++)step();release();
        for(int i=0;i<40;i++){step();ck(!d.ack,"cancel never leaks a later ACK");}
        read(false,0,0x400,true);read(true,0x3d,1);
    }
    release();printf("RESULT_JSON {\"passed\":true,\"checks\":%u,\"cycles\":%u,\"fetches\":%u,\"cancellations\":39}\n",checks,clocks,fetches);
}
