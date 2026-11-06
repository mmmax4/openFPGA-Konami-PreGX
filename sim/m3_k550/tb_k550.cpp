// Public K055550 register and bus-master contract exercised with delayed responses.
// Reference command implementation is extracted unchanged from pinned MAME;
// mame_k550.inc retains its original BSD-3-Clause notice and copyright holders.
#include "Vk550.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
// GCC9 compatibility shim for the C++20 double constant used by MAME.
namespace std { namespace numbers { inline constexpr double pi=3.141592653589793238462643383279502884; } }
#include <stdexcept>
#include <string>
#include <vector>
using u8=uint8_t; using u16=uint16_t; using u32=uint32_t; using offs_t=unsigned;
static constexpr unsigned MEM_SIZE=1<<24;
struct address_space {
    std::vector<u8> bytes=std::vector<u8>(MEM_SIZE);
    u16 read_word(u32 a) const { a&=0xffffff; return (bytes[a]<<8)|bytes[(a+1)&0xffffff]; }
    u32 read_dword(u32 a) const { return (u32(read_word(a))<<16)|read_word(a+2); }
    void write_byte(u32 a,u8 v) { bytes[a&0xffffff]=v; }
    void write_word(u32 a,u16 v) { write_byte(a,v>>8);write_byte(a+1,v); }
    void write_dword(u32 a,u32 v) { write_word(a,v>>16);write_word(a+2,v); }
};
static constexpr int AS_PROGRAM=0;
struct cpu_shim { address_space mem; address_space &space(int) { return mem; } };
struct machine_shim { u32 rand() { return 0x1234; } };
struct konamigx_state {
    u16 m_prot_data[32]{};
    cpu_shim cpu; cpu_shim *m_maincpu=&cpu;
    machine_shim mach; machine_shim &machine() { return mach; }
    void K055550_word_w(offs_t offset,u16 data,u16 mem_mask);
};
#define COMBINE_DATA(ptr) (*(ptr)=(*(ptr)&~mem_mask)|(data&mem_mask))
#define ACCESSING_BITS_8_15 (mem_mask&0xff00)
#include "mame_k550.inc"
#undef COMBINE_DATA
#undef ACCESSING_BITS_8_15
static Vk550 dut;
static konamigx_state ref;
static address_space mem;
static uint64_t cycles=0,transactions=0,reads=0,writes=0,commands=0,checks=0;
static unsigned pending=0,delay_left=0,max_delay=0;
static u32 latched_addr=0; static u16 latched_wdata=0; static u8 latched_be=0;static bool latched_write=false;
static bool zero_vector=false;
static void require(bool ok,const std::string &s) { ++checks;if(!ok) throw std::runtime_error(s); }
static void tick() {
    dut.clk=0;dut.eval();
    if(!dut.reset && pending) {
        require(dut.m_a==latched_addr && dut.m_be==latched_be && dut.m_we==latched_write && dut.m_wd==latched_wdata,"master payload changed while waiting");
        require(!dut.m_go,"master duplicated request while pending");
    }
    dut.m_done=0;
    if(dut.reset) pending=0;
    else if(pending && --delay_left==0) {
        if(latched_write) {
            if(latched_be&2)mem.write_byte(latched_addr*2,latched_wdata>>8);
            if(latched_be&1)mem.write_byte(latched_addr*2+1,latched_wdata);
        } else dut.m_rd=mem.read_word(latched_addr*2);
        dut.m_done=1;pending=0;
    }
    bool go=dut.m_go && !dut.reset;
    u32 a=dut.m_a;u16 wd=dut.m_wd;u8 be=dut.m_be;bool we=dut.m_we;
    dut.clk=1;dut.eval();++cycles;
    if(go) {
        require(!pending,"more than one master transaction outstanding");
        pending=1;latched_addr=a;latched_wdata=wd;latched_be=be;latched_write=we;
        delay_left=2+((transactions*13+7)%30);max_delay=std::max(max_delay,delay_left);++transactions;
        if(we)++writes;else ++reads;
    }
}
static void reset() {
    dut.reset=1;dut.wr=0;for(int i=0;i<4;i++)tick();
    require(!dut.busy && !dut.m_go,"reset did not stop command");
    dut.reset=0;for(int i=0;i<4;i++)tick();
    for(int r=0;r<32;r++) {dut.rd_idx=r;dut.eval();require(dut.rd_q==0,"register not reset");}
    std::fill(std::begin(ref.m_prot_data),std::end(ref.m_prot_data),0);
}
static void reg(int idx,u16 value,int be=3) {
    require(!dut.busy,"CPU writes while chip busy");
    dut.idx=idx;dut.wdata=value;dut.be=be;dut.wr=1;tick();
    dut.wr=0;tick();ref.K055550_word_w(idx,value,((be&2)?0xff00:0)|((be&1)?0xff:0));
}
static void pair(int r,u32 value) {reg(r,value>>16);reg(r+1,value);}
static void compare(const std::string &label) {
    for(int r=0;r<32;r++) {
        dut.rd_idx=r;dut.eval();
        if(zero_vector && r==16) require(dut.rd_q<256,"zero homing result not 8bit");
        else require(dut.rd_q==ref.m_prot_data[r],label+" register "+std::to_string(r)+" mismatch: "+std::to_string(dut.rd_q)+"/"+std::to_string(ref.m_prot_data[r]));
    }
    require(mem.bytes==ref.cpu.mem.bytes,label+" memory differs");
}
static void cmd(u8 command,const std::string &label,bool fullword=false) {
    reg(0,(u16(command)<<8)|(ref.m_prot_data[0]&255),fullword?3:2);
    require(dut.busy,"command did not assert busy");
    u32 budget=10000000;
    while(dut.busy && --budget)tick();
    require(budget && !pending,label+" command hung or dropped outstanding master");
    ++commands;compare(label);
}
static void setword(u32 a,u16 data) {mem.write_word(a,data);ref.cpu.mem.write_word(a,data);}
int main(int argc,char **argv) {
    Verilated::commandArgs(argc,argv);
    try {
        if(argc!=2)throw std::runtime_error("maincpu image argument required");
        for(unsigned a=0;a<MEM_SIZE;a++)mem.bytes[a]=u8((a*37)^(a>>7)^0xa5);
        std::ifstream input(argv[1],std::ios::binary);std::vector<char> rom((std::istreambuf_iterator<char>(input)),{});
        require(rom.size()==0x100000,"original EAC program length");
        std::copy(rom.begin(),rom.end(),mem.bytes.begin());ref.cpu.mem.bytes=mem.bytes;
        reset();
        // Each byte lane combines independently; LDS register0 never triggers.
        reg(13,0xa500,2);reg(13,0x005a,1);reg(0,0x003c,1);
        require(!dut.busy && transactions==0,"LDS register0 wrongly triggers");compare("byte lanes");
        // Statically reconstructed original EAC caller987e/helper98f2:
        // destination210000, 256-byte units, 256 units. Includes sprite and plain RAM.
        pair(7,0x210000);pair(10,0x100);pair(12,0);reg(9,2);reg(1,0x3f00,2);reg(0,0xff,1);
        cmd(0x9f,"original EAC 64KiB clear");
        require(transactions==32768,"64KiB clear transaction count");
        pair(7,0x211000);reg(0,0xef,1);cmd(0x9f,"original EAC 60KiB clear");
        // Model-defined ordinary and odd-size boundaries; payload remains word-wide.
        for(unsigned size: {0u,1u,2u,3u,17u}) {
            pair(7,0x200104);pair(10,size);reg(13,0x5ac3);reg(0,2,1);
            cmd(0x97,"fill boundary "+std::to_string(size),true);
        }
        // Original-program bytes supply real palette/ROM source data; address
        // is a constructed test address, not claimed to be an observed copy trace.
        pair(2,0x10000);pair(7,0x330000);pair(10,0x80);cmd(0x98,"original ROM data copy");
        pair(10,0);cmd(0x98,"zero copy");
        // Original EAC collision header at18b7a: table21ab00, stride80,
        // reg1 high09 -> hit list byte18. Geometry values below are boundary cases.
        const u32 base=0x21ab00;
        pair(2,base);pair(5,0x80);reg(1,0x0900);reg(0,3,1);
        for(int o=0;o<4;o++)for(int axis=0;axis<3;axis++) {
            int center=o==0?0:o==1?10:o==2?20:0;
            if(o==3 && axis==2)center=32767;
            setword(base+o*0x80+axis*6,center);setword(base+o*0x80+axis*6+2,0);setword(base+o*0x80+axis*6+4,10);
        }
        cmd(0xa0,"original collision header with constructed geometry");
        require(mem.bytes[base+18]==0x80 && mem.bytes[base+19]==0 && mem.bytes[base+20]==0,"overlap/boundary/separate collision outcomes");
        // Odd hit-list offset checks both write byte lanes and final unpaired byte.
        reg(1,19<<7);reg(0,3,1);cmd(0xa0,"odd collision hit list");
        reg(0,0,1);cmd(0xa0,"zero collision count");
        pair(5,0);reg(0,2,1);cmd(0xa0,"zero collision stride");
        // Original hardcoded87 request is acknowledged with no writes, matching
        // current MAME's declared incomplete/no-effect implementation.
        pair(7,0x210e00);reg(1,0x1f);reg(9,0x10);pair(10,0);pair(12,0);reg(0,0,1);
        auto before87=transactions;cmd(0x87,"original hardcoded87");require(before87==transactions,"87 unexpectedly touches memory");
        for(int dx: {-32768,-301,-1,0,1,301,32767})for(int dy:{-32768,-301,-1,0,1,301,32767}) {
            reg(12,u16(dx));reg(13,u16(dy));zero_vector=!dx&&!dy;
            cmd(0xc0,"homing boundary "+std::to_string(dx)+","+std::to_string(dy));
            zero_vector=false;
        }
        u32 rng=0x5a10b42;
        for(int i=0;i<2048;i++) {
            rng=rng*1664525u+1013904223u;int dx=int16_t(rng>>16);
            rng=rng*1664525u+1013904223u;int dy=int16_t(rng>>16);
            if(!dx&&!dy)dy=1;
            reg(12,u16(dx));reg(13,u16(dy));cmd(0xc0,"homing random");
        }
        // Reset while a fill write waits: pending transaction is cancelled by
        // board reset, command/register state clear, then fresh command works.
        pair(7,0x200000);pair(10,0x100);reg(0,0xff,1);reg(0,0x9f00,2);
        u32 guard=1000;while(!pending && --guard)tick();require(guard,"reset fixture never reached waiting transaction");
        reset();mem.bytes=ref.cpu.mem.bytes;
        auto beforeReset=transactions;for(int i=0;i<40;i++)tick();require(transactions==beforeReset,"master request after reset");
        pair(7,0x200000);pair(10,2);reg(13,0x6789);cmd(0x9f,"new command after reset");
        printf("RESULT_JSON {\"passed\":true,\"commands\":%llu,\"checks\":%llu,\"transactions\":%llu,\"reads\":%llu,\"writes\":%llu,\"max_ack_delay_clocks\":%u,\"cycles\":%llu}\n",(unsigned long long)commands,(unsigned long long)checks,(unsigned long long)transactions,(unsigned long long)reads,(unsigned long long)writes,max_delay,(unsigned long long)cycles);
        return 0;
    } catch(const std::exception &e) {fprintf(stderr,"FAIL %s after%llu cycles\n",e.what(),(unsigned long long)cycles);return 1;}
}
