// Actual tile pipeline, linebuffers and scanout using public real memory ports.
// State/ROM/oracle are original inputs. No synthetic attributes or DUT forcing.
#include "Vtb_m2_tile_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <map>
#include <sstream>
#include <string>
#include <vector>

static Vtb_m2_tile_top *d;
static uint64_t clocks=0,errors=0,compared=0,cancel_compared=0;
static unsigned worst=0,lines=0,deadline_failures=0,rom_responses=0,vram_responses=0;
static bool mw=false,sampling=false;
static unsigned width=376,pixel_period=12,scan_start=480,display_y=0;
static std::ofstream trace;
static std::array<uint64_t,5> previous{};
static bool trace_first=true;
static void failure(const char *what,uint64_t got,uint64_t expected){
    if(errors<16)std::printf("ERROR %s got=%llx expected=%llx clock=%llu\n",what,(unsigned long long)got,(unsigned long long)expected,(unsigned long long)clocks);errors++;
}
static std::array<uint16_t,4> pixels(){return {d->packed0,d->packed1,d->packed2,d->packed3};}
static void tick(unsigned n=1){while(n--){
    d->clk=0;d->eval();d->clk=1;d->eval();clocks++;
    rom_responses+=d->observed_rom_ack;vram_responses+=d->observed_vram_ack;
    if(trace.is_open()){
        auto p=pixels();std::array<uint64_t,5> v={
            uint64_t(d->busy)|(uint64_t(d->pending_rom)<<1)|(uint64_t(d->pending_vram)<<2)|
            (uint64_t(d->observed_rom_ack)<<3)|(uint64_t(d->observed_vram_ack)<<4)|
            (uint64_t(d->line_start)<<5)|(uint64_t(sampling)<<6)|(uint64_t(d->unsupported)<<7),
            d->pending_rom?uint64_t(d->observed_rom_addr):0,
            d->pending_vram?uint64_t(d->observed_vram_addr):0,
            sampling?uint64_t(p[0])|(uint64_t(p[1])<<16)|(uint64_t(p[2])<<32)|(uint64_t(p[3])<<48):0,
            sampling?uint64_t(d->px)|(uint64_t(display_y)<<16):0};
        if(trace_first||v!=previous){trace.write((char*)&clocks,8);trace.write((char*)v.data(),sizeof v);previous=v;trace_first=false;}
    }
}}
struct State{std::map<std::string,std::vector<unsigned>> fields;std::array<std::vector<unsigned>,17> vram;};
static State state_load(const std::string &path){
    std::ifstream file(path);if(!file){std::fprintf(stderr,"Cannot read state %s\n",path.c_str());std::exit(2);}State st;std::string line;
    while(std::getline(file,line)){
        std::istringstream row(line);std::string key;if(!(row>>key)||key[0]=='#')continue;
        int page=-1;if(key=="VRAM")row>>page;std::vector<unsigned> values;std::string value;
        while(row>>value)values.push_back(std::stoul(value,nullptr,16));
        if(page>=0&&page<17)st.vram[page]=values;else st.fields[key]=values;
    }return st;
}
static std::vector<uint8_t> read_bytes(const std::string &path){std::ifstream f(path,std::ios::binary);if(!f){std::fprintf(stderr,"Cannot read %s\n",path.c_str());std::exit(2);}return {std::istreambuf_iterator<char>(f),{}};}
static std::vector<uint16_t> oracle_load(const std::string &path){
    if(path=="-")return {};auto b=read_bytes(path);if(b.size()!=4*224*width*2){std::fprintf(stderr,"Oracle size mismatch\n");std::exit(2);}std::vector<uint16_t> v;for(size_t i=0;i<b.size();i+=2)v.push_back(unsigned(b[i])|(unsigned(b[i+1])<<8));return v;
}
static void write_words(const std::string &path,const std::vector<uint16_t>&v){std::ofstream f(path,std::ios::binary);for(auto w:v){f.put(char(w));f.put(char(w>>8));}}
static void setup(const State &st){
    d->reset=1;d->setup_mode=1;d->setup_req=0;d->line_start=0;tick(100);
    auto regs=st.fields.at("K56REGS");auto cb=st.fields.at("K55REGS");
    if(regs.size()!=32||cb.size()<27){std::fprintf(stderr,"Incomplete original registers\n");std::exit(2);}
    for(unsigned i=0;i<32;i++){d->reg_we=1;d->reg_addr=i;d->reg_data=regs[i];tick();}d->reg_we=0;
    for(unsigned i=0;i<4;i++){d->cb_we=1;d->cb_addr=i;d->cb_data=(cb[23+i]<<4)&255;tick();}d->cb_we=0;
    for(unsigned page=0;page<16;page++){
        if(st.vram[page].size()!=4096){std::fprintf(stderr,"VRAM page %u incomplete\n",page);std::exit(2);}
        for(unsigned i=0;i<4096;i++){
            d->setup_req=1;d->setup_addr=page*4096+i;d->setup_wdata=st.vram[page][i];unsigned c=0;
            while(!d->setup_ack&&c++<200)tick();if(!d->setup_ack)failure("VRAM setup timeout",0,1);
            d->setup_req=0;tick(2);
        }
    }d->setup_mode=0;tick(100);d->reset=0;tick(2);
}
static std::vector<uint16_t> line_run(unsigned render_y,int expected_y,const std::vector<uint16_t>&oracle){
    std::vector<uint16_t> got(4*width);d->line=render_y;d->line_start=1;tick();d->line_start=0;
    unsigned complete=0;bool was_busy=d->busy;
    // One actual 6144-clock line. The previous bank scans while this one renders.
    for(unsigned c=1;c<6144;c++){
        bool scan=expected_y>=0&&c>=scan_start&&c<scan_start+width*pixel_period;
        if(scan&&((c-scan_start)%pixel_period)==0)d->px=(c-scan_start)/pixel_period;
        sampling=scan&&((c-scan_start)%pixel_period)==2;display_y=expected_y<0?0:unsigned(expected_y);
        tick();
        if(was_busy&&!d->busy&&!complete)complete=c;was_busy=d->busy;
        if(sampling){unsigned x=(c-scan_start)/pixel_period;auto p=pixels();for(unsigned l=0;l<4;l++){
            got[l*width+x]=p[l];
            if(!oracle.empty()){uint16_t exp=oracle[(l*224+unsigned(expected_y))*width+x];compared++;if(p[l]!=exp)failure("packed palette/opaque/category",p[l],exp);}
        }}
    }sampling=false;lines++;if(!complete||d->busy){deadline_failures++;failure("6144-clock line deadline",complete,6144);}else if(complete>worst)worst=complete;
    return got;
}
static std::vector<uint16_t> cancel_line(bool rom,const std::vector<uint16_t>&oracle){
    d->reset=1;tick(100);d->reset=0;tick(2);d->line=50;d->line_start=1;tick();d->line_start=0;
    unsigned c=0;while(!(rom?d->pending_rom:d->pending_vram)&&c++<1000)tick();
    if(c>=1000)failure("No real pending request for cancellation",0,1);
    // Real line_start aborts the active producer; no memory/DUT signal forcing.
    line_run(70,-1,oracle);
    auto pixels=line_run(71,70-16,oracle);cancel_compared+=4*width;return pixels;
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc<5){std::fprintf(stderr,"usage: tile ROM mystic cases.tsv outdir [trace]\n");return 2;}
    mw=std::atoi(argv[2]);width=mw?288:376;pixel_period=mw?16:12;scan_start=(mw?24:40)*pixel_period;
    auto rom=read_bytes(argv[1]);if(rom.size()!=(mw?0xdc0080u:0x1360080u)){std::fprintf(stderr,"ROM identity size mismatch\n");return 2;}
    d=new Vtb_m2_tile_top;d->mystic=mw;d->reset=1;d->init=1;tick(8);d->init=0;unsigned init=0;while(!d->ready&&init++<100000)tick();if(!d->ready){failure("SDRAM ready",0,1);return 1;}
    unsigned base=mw?0x240000:0x340000,len=mw?0x280000:0x200000;
    for(unsigned i=0;i<len;i++){d->dl_we=1;d->dl_addr=base+i;d->dl_data=rom[base+i];tick();d->dl_we=0;tick(7);}tick(500);
    std::ifstream cases(argv[3]);if(!cases){std::fprintf(stderr,"Cannot read cases\n");return 2;}std::string row;unsigned scenes=0;
    if(argc>5)trace.open(argv[5],std::ios::binary);
    while(std::getline(cases,row)){
        if(row.empty())continue;std::istringstream r(row);std::string statepath,oraclepath,tag;std::getline(r,statepath,'\t');std::getline(r,oraclepath,'\t');std::getline(r,tag,'\t');
        auto st=state_load(statepath);auto oracle=oracle_load(oraclepath);setup(st);
        std::vector<uint16_t> out(4*224*width);line_run(16,-1,oracle);
        for(unsigned y=0;y<224;y++){auto p=line_run(17+y,int(y),oracle);for(unsigned l=0;l<4;l++)for(unsigned x=0;x<width;x++)out[(l*224+y)*width+x]=p[l*width+x];}
        write_words(std::string(argv[4])+"/"+tag+".pixels.bin",out);
        auto a=cancel_line(false,oracle),b=cancel_line(true,oracle);a.insert(a.end(),b.begin(),b.end());write_words(std::string(argv[4])+"/"+tag+".cancel.bin",a);
        if(d->unsupported)failure("Original supported scene unsupported",1,0);scenes++;std::printf("SCENE %s full_pixels=%u cancellation_pixels=%u worst=%u errors=%llu\n",tag.c_str(),4*224*width,8*width,worst,(unsigned long long)errors);
    }
    if(!scenes)failure("No scenes executed",0,1);
    if(d->protocol_errors)failure("SDRAM logical protocol",d->protocol_errors,0);
    if(trace.is_open()){uint64_t marker=~0ull;trace.write((char*)&marker,8);trace.write((char*)&clocks,8);trace.close();}
    std::printf("RESULT_JSON {\"passed\":%s,\"mystic\":%s,\"scenes\":%u,\"errors\":%llu,\"oracle_pixels_compared\":%llu,\"cancellation_pixels\":%llu,\"lines\":%u,\"worst_line_clocks\":%u,\"deadline_failures\":%u,\"rom_ack_observations\":%u,\"vram_ack_observations\":%u,\"cycles\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",mw?"true":"false",scenes,(unsigned long long)errors,(unsigned long long)compared,(unsigned long long)cancel_compared,lines,worst,deadline_failures,rom_responses,vram_responses,(unsigned long long)clocks);
    std::printf("%s M2 actual tile linebuffer/scanout\n",errors?"FAIL":"PASS");delete d;return errors?1:0;
}
