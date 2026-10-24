#include "Vtb_sound_pause.h"
#include "verilated.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <sstream>
#include <vector>

struct Command {unsigned long long cycle;bool irq;unsigned off,data;};

struct Memory {
    bool busy=false,ack=false;
    unsigned addr=0,remain=0,reads=0;
    void cycle(bool req,unsigned a,unsigned latency,unsigned base,
               const std::vector<unsigned char>& rom,CData& outack,CData& data) {
        bool previous=ack;ack=false;
        if(busy) {
            if(!req || a!=addr) throw std::runtime_error("request moved before original ROM ack");
            if(--remain==0) {ack=true;data=rom.at(base+addr);busy=false;++reads;}
        } else if(req && !previous) {busy=true;addr=a;remain=latency;}
        outack=ack;
    }
};
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    if(argc!=4) return 2;
    const unsigned max_cycles=std::stoul(argv[3]);
    std::ifstream f(argv[1],std::ios::binary);
    std::vector<unsigned char> image((std::istreambuf_iterator<char>(f)),{});
    if(image.size()!=0x1360080) {std::cerr<<"original ROM length\n";return 2;}
    std::ifstream trace(argv[2]);std::string line;std::vector<Command> commands;
    unsigned long long previous_cycle=0;
    while(std::getline(trace,line)) {
        std::istringstream row(line);std::string kind;unsigned frame,address,data;
        if(!(row>>kind) || (kind!="MAIN_SOUND_WRITE" && kind!="MAIN_SOUND_IRQ")) continue;
        if(!(row>>frame>>std::hex>>address>>data)) throw std::runtime_error("bad original command trace");
        // Original trace has frame resolution only. Preserve order with at least
        // 24 clocks between same-frame bus writes; do not claim cycle-exact timing.
        unsigned long long at=100ULL+1622016ULL*frame;
        if(at<=previous_cycle) at=previous_cycle+24;
        previous_cycle=at;
        if(data>255) throw std::runtime_error("expected debugger-normalized byte data");
        if(kind=="MAIN_SOUND_WRITE" && (address<0x48a000 || address>0x48a01f || (address&1)))
            throw std::runtime_error("unexpected K054321 write lane/address");
        if(kind=="MAIN_SOUND_IRQ" && address!=0x6e0000) throw std::runtime_error("unexpected original IRQ address");
        commands.push_back({at,kind=="MAIN_SOUND_IRQ",(address>>1)&15,data});
    }
    if(commands.size()<2) {std::cerr<<"missing original commands\n";return 2;}
    Vtb_sound_pause d;Memory program,pcm;unsigned cycles=0,acks=0;bool last_ack=false,paused=false;
    d.clk=0;d.reset=1;d.irq_pulse=0;d.main_wr=0;d.main_off=0;d.main_data=0;d.rom_ack=0;d.pcm_ack=0;d.rom_q=0;d.pcm_q=0;
    auto tick=[&]() {
        d.clk=0;d.cen_8m=!paused && cycles%12==0;d.cen_48k=!paused && cycles%2000==0;d.eval();
        if(!d.reset) {
            program.cycle(d.rom_req,d.rom_addr,12,0x300000,image,d.rom_ack,d.rom_q);
            pcm.cycle(d.pcm_req,d.pcm_addr,10,0x760000,image,d.pcm_ack,d.pcm_q);
        }
        d.eval();d.clk=1;d.eval();
        if(d.ack_active && !last_ack) ++acks;
        last_ack=d.ack_active;++cycles;
    };
    try {
        for(unsigned i=0;i<100;++i) tick();d.reset=0;
        // Actual original main writes initialize the latch; Z80 controls IFF/EI.
        unsigned command_index=0;
        while(cycles<max_cycles && !(d.ack_active && !d.irq_pending)) {
            d.main_wr=0;d.irq_pulse=0;
            if(command_index<commands.size() && cycles==commands[command_index].cycle) {
                const auto &cmd=commands[command_index++];
                d.irq_pulse=cmd.irq;d.main_wr=!cmd.irq;d.main_off=cmd.off;d.main_data=cmd.data;
                std::cout<<"ORIGINAL_COMMAND cycle="<<cycles<<" irq="<<cmd.irq<<" off="<<cmd.off<<"\n"<<std::flush;
            }
            tick();
            if(cycles%20000000==0) std::cout<<"PROGRESS cycles="<<cycles<<" pc="<<std::hex<<d.dbg_pc<<std::dec<<" reads="<<program.reads<<"\n"<<std::flush;
        }
        d.main_wr=0;d.irq_pulse=0;
        if(!(d.ack_active && !d.irq_pending)) {
            std::cout<<"UNCOVERED no real IRQ ACK after original boot cycles="<<cycles<<" pc="<<std::hex<<d.dbg_pc<<"\n";
            return 3;
        }
        std::cout<<"REAL_ACK cycles="<<cycles<<" pc="<<std::hex<<d.dbg_pc<<std::dec<<" reads="<<program.reads<<" ack_events="<<acks<<"\n";
        paused=true;tick();tick();
        d.irq_pulse=1;tick();d.irq_pulse=0;
        if(!d.irq_pending) throw std::runtime_error("last-drain IRQ was not latched");
        for(unsigned i=0;i<48;++i) {
            tick();
            if(!d.irq_pending) throw std::runtime_error("NEGATIVE pending last-drain IRQ cleared with CEN0/held ACK");
            if(!d.ack_active) throw std::runtime_error("CPU ACK changed while CEN0");
        }
        std::cout<<"PAUSE_HOLD_PASS pending survives48cycles\n";
        // A fresh IRQ must survive the old ACK tail. Only a distinct new ACK may consume it.
        unsigned old_acks=acks;paused=false;
        for(unsigned i=0;i<1000 && acks==old_acks;++i) {
            tick();
            if(!d.irq_pending && acks==old_acks)
                throw std::runtime_error("NEGATIVE new pending IRQ consumed by old ACK tail on resume");
        }
        std::cout<<"PASS sound IRQ pause/resume oldack="<<old_acks<<" newack="<<acks<<" pending="<<unsigned(d.irq_pending)<<" cycles="<<cycles<<"\n";
        d.final();return 0;
    } catch(const std::exception&e) {std::cerr<<e.what()<<" cycles="<<cycles<<"\n";d.final();return 1;}
}
