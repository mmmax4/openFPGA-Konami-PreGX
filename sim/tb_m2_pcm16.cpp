// Independent forward PCM8/PCM16 oracle, derived from pinned MAME k054539.cpp.
// Original register/PCM bytes; declared public-port cold reconstruction only.
#include "Vtb_m2_pcm16.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

static Vtb_m2_pcm16 *dut;
static std::vector<uint8_t> pcm, regs;
static uint64_t cycles=0, protocol_errors=0, deadline_errors=0;
static unsigned epoch=0, max_work=0, lat_min=999, lat_max=0;
static bool running=false;
static FILE *request_log,*sample_log;
struct Channel {
    bool active=false, wide=false, looping=false;
    unsigned pos=0, fraction=0, delta=0, loop=0;
    int value=0;
    uint64_t raw_checks=0, raw_errors=0, address_checks=0, address_errors=0;
    uint64_t expected_requests=0, actual_requests=0, loops=0, ends=0, carries=0;
    unsigned first_expected=0, first_actual=0;
    int first_expected_raw=0, first_actual_raw=0;
    bool got_expected=false,got_actual=false,got_expected_raw=false,got_actual_raw=false;
};
static std::array<Channel,8> channels;
static std::array<std::vector<unsigned>,8> expected,actual;
static std::array<bool,8> seen;
static std::array<int,8> raw_expected;
static std::array<bool,8> expected_active;
struct Port {bool busy=false; unsigned address=0,wait=0; uint64_t started=0;};
static Port port;
static unsigned errors_printed=0;
static void mismatch(const char *kind,unsigned ch,int got,int want) {
    if(errors_printed++<12) printf("MISMATCH tick=%u ch=%u %s got=%d expected=%d\n",epoch,ch,kind,got,want);
}
static std::vector<uint8_t> bytes(const char *path) {
    std::ifstream f(path,std::ios::binary);
    if(!f){fprintf(stderr,"Missing %s\n",path);exit(2);}
    return {std::istreambuf_iterator<char>(f),{}};
}
static unsigned u24(unsigned at) {return unsigned(regs.at(at))|(unsigned(regs.at(at+1))<<8)|(unsigned(regs.at(at+2))<<16);}
static int read_sample(unsigned ch) {
    auto &s=channels[ch];
    auto read=[&](unsigned address) {
        address&=0x3fffff;
        expected[ch].push_back(address);s.expected_requests++;
        if(!s.got_expected){s.first_expected=address;s.got_expected=true;}
        return unsigned(pcm.at(address));
    };
    unsigned low=read(s.pos);
    unsigned value=s.wide ? low|(read(s.pos+1)<<8) : low<<8;
    return value>=0x8000 ? int(value)-65536 : int(value);
}
static void prepare() {
    for(unsigned ch=0;ch<8;ch++) {
        auto &s=channels[ch];expected[ch].clear();actual[ch].clear();seen[ch]=false;
        expected_active[ch]=s.active;
        if(s.active) {
            s.fraction+=s.delta;
            while(s.fraction>=65536) {
                s.fraction-=65536;
                unsigned old=s.pos;s.pos+=s.wide?2:1;
                if(s.wide && (old>>8)!=(s.pos>>8))s.carries++;
                s.value=read_sample(ch);
                // MAME refetches the loop point once, then tests the marker
                // again; a marker at the loop point keys the channel off.
                if(s.value==-32768 && s.looping) {
                    s.pos=s.loop;s.loops++;s.value=read_sample(ch);
                }
                if(s.value==-32768) {
                    s.active=false;s.ends++;s.value=0;break;
                }
            }
        }
        raw_expected[ch]=s.value;
    }
}
static void tick() {
    dut->clk=0;dut->eval();
    if(running && dut->probe_valid) {
        unsigned ch=dut->probe_ch;auto &s=channels[ch];
        unsigned bits=dut->probe_raw&0x1ffff;
        int value=(bits&0x10000)?int(bits)-131072:int(bits);
        if(seen[ch])protocol_errors++;
        seen[ch]=true;s.raw_checks++;
        if(!s.got_actual_raw){s.first_actual_raw=value;s.got_actual_raw=true;}
        if(!s.got_expected_raw){s.first_expected_raw=raw_expected[ch];s.got_expected_raw=true;}
        bool bad=!expected_active[ch]||value!=raw_expected[ch];
        if(bad){s.raw_errors++;mismatch("raw",ch,value,raw_expected[ch]);}
        fprintf(sample_log,"%u\t%u\t%d\t%d\t%u\n",epoch,ch,value,raw_expected[ch],bad);
    }
    dut->ack=0;
    if(!port.busy && dut->req) {
        port={true,unsigned(dut->rom_addr),23u+((dut->rom_addr>>2)&15),cycles};
        if(running) {
            unsigned ch=dut->probe_ch;auto &s=channels[ch];
            actual[ch].push_back(port.address);s.actual_requests++;
            if(!s.got_actual){s.first_actual=port.address;s.got_actual=true;}
            fprintf(request_log,"%u\t%u\tactual\t%u\n",epoch,ch,port.address);
        } else protocol_errors++;
    }
    if(port.busy) {
        if(!dut->req || dut->rom_addr!=port.address) {protocol_errors++;port.busy=false;}
        else if(!port.wait) {
            unsigned latency=unsigned(cycles-port.started);
            if(latency<23 || latency>38)protocol_errors++;
            if(latency<lat_min)lat_min=latency;if(latency>lat_max)lat_max=latency;
            dut->q=pcm.at(port.address);dut->ack=1;port.busy=false;
        } else port.wait--;
    }
    dut->eval();dut->clk=1;dut->eval();cycles++;
}
static void write(unsigned address,unsigned value) {
    dut->addr=address;dut->data=value;dut->wr=1;tick();dut->wr=0;tick();
}
int main(int argc,char **argv) {
    Verilated::commandArgs(argc,argv);if(argc!=4)return 2;
    pcm=bytes(argv[1]);regs=bytes(argv[2]);unsigned ticks=std::stoul(argv[3]);
    if(pcm.size()!=4194304 || regs.size()!=560 || ticks<512 || regs[0x22c]!=0x39 || regs[0x22f]!=1)return 2;
    request_log=fopen("requests.tsv","w");sample_log=fopen("samples.tsv","w");
    if(!request_log||!sample_log)return 2;
    fprintf(request_log,"tick\tchannel\tkind\taddress\n");fprintf(sample_log,"tick\tchannel\tactual_raw\texpected_raw\tmismatch\n");
    for(unsigned ch=0;ch<8;ch++) {
        auto &s=channels[ch];s.active=regs[0x22c]&(1u<<ch);
        unsigned mode=regs[0x200+2*ch];
        if(s.active && ((mode&0x20)||((mode&12)!=0&&(mode&12)!=4)))return 2;
        s.wide=(mode&12)==4;s.looping=regs[0x201+2*ch]&1;
        s.delta=u24(ch*32);s.pos=u24(ch*32+12);s.loop=u24(ch*32+8);
    }
    dut=new Vtb_m2_pcm16;dut->clk=0;dut->cen=0;dut->wr=0;dut->ack=0;dut->reset=1;dut->eval();
    for(unsigned i=0;i<10;i++)tick();dut->reset=0;for(unsigned i=0;i<10;i++)tick();
    // Constructed cold reverb RAM initialization through actual streaming port.
    // Pointer mapping includes bit16; 0x14000 writes cover the entire 32KB RAM.
    write(0x22e,0x80);for(unsigned i=0;i<0x14000;i++)write(0x22d,0);
    for(unsigned a=0;a<560;a++)if(a!=0x214&&a!=0x215&&a!=0x22c&&a!=0x22d&&a!=0x22e&&a!=0x22f)write(a,regs[a]);
    write(0x22e,regs[0x22e]);write(0x214,regs[0x22c]);write(0x22f,regs[0x22f]);
    running=true;
    for(epoch=0;epoch<ticks;epoch++) {
        prepare();
        for(unsigned ch=0;ch<8;ch++)for(auto a:expected[ch])fprintf(request_log,"%u\t%u\texpected\t%u\n",epoch,ch,a);
        if(dut->busy||port.busy)deadline_errors++;
        dut->cen=1;
        unsigned work=0;
        for(unsigned clock=0;clock<2000;clock++) {
            tick();dut->cen=0;if(dut->busy)work=clock+1;
        }
        if(work>max_work)max_work=work;
        if(dut->busy||port.busy)deadline_errors++;
        for(unsigned ch=0;ch<8;ch++) {
            auto &s=channels[ch];
            if(expected_active[ch]&&!seen[ch]){s.raw_errors++;mismatch("missing_raw",ch,0,raw_expected[ch]);}
            unsigned count=unsigned(actual[ch].size()>expected[ch].size()?actual[ch].size():expected[ch].size());
            for(unsigned i=0;i<count;i++) {
                s.address_checks++;
                if(i>=actual[ch].size()||i>=expected[ch].size()||actual[ch][i]!=expected[ch][i]) {
                    s.address_errors++;mismatch("ROM_address",ch,i<actual[ch].size()?int(actual[ch][i]):-1,i<expected[ch].size()?int(expected[ch][i]):-1);
                }
            }
        }
    }
    fclose(request_log);fclose(sample_log);
    uint64_t raw_errors=0,address_errors=0,ordinary_errors=0;
    for(unsigned ch=0;ch<8;ch++){raw_errors+=channels[ch].raw_errors;address_errors+=channels[ch].address_errors;if(ch==3||ch==4)ordinary_errors+=channels[ch].raw_errors+channels[ch].address_errors;}
    bool covered=channels[0].raw_checks>=512&&channels[5].raw_checks>=512&&channels[3].raw_checks>=512&&channels[4].raw_checks>=512&&channels[0].carries&&channels[5].carries&&channels[5].loops;
    bool pass=covered&&!raw_errors&&!address_errors&&!protocol_errors&&!deadline_errors;
    printf("RESULT_JSON {\"passed\":%s,\"ticks\":%u,\"cycles\":%llu,\"raw_errors\":%llu,\"address_errors\":%llu,\"ordinary_pcm8_errors\":%llu,\"protocol_errors\":%llu,\"deadline_errors\":%llu,\"max_work_clocks\":%u,\"ack_latency_min\":%u,\"ack_latency_max\":%u,\"coverage\":%s,\"hardware_verified\":false,\"channels\":[",pass?"true":"false",ticks,(unsigned long long)cycles,(unsigned long long)raw_errors,(unsigned long long)address_errors,(unsigned long long)ordinary_errors,(unsigned long long)protocol_errors,(unsigned long long)deadline_errors,max_work,lat_min,lat_max,covered?"true":"false");
    for(unsigned ch=0;ch<8;ch++) {
        auto &s=channels[ch];
        printf("%s{\"channel\":%u,\"pcm_bits\":%u,\"raw_checks\":%llu,\"raw_errors\":%llu,\"address_checks\":%llu,\"address_errors\":%llu,\"expected_requests\":%llu,\"actual_requests\":%llu,\"oracle_loops\":%llu,\"oracle_ends\":%llu,\"oracle_high_byte_carries\":%llu,\"first_expected_address\":%u,\"first_actual_address\":%u}",ch?",":"",ch,s.wide?16:8,(unsigned long long)s.raw_checks,(unsigned long long)s.raw_errors,(unsigned long long)s.address_checks,(unsigned long long)s.address_errors,(unsigned long long)s.expected_requests,(unsigned long long)s.actual_requests,(unsigned long long)s.loops,(unsigned long long)s.ends,(unsigned long long)s.carries,s.first_expected,s.first_actual);
    }
    printf("]}\n");delete dut;return pass?0:1;
}
