// Independent sprite producer+consumer gate. All objects are built from public
// sprite-RAM setup; original ROM and separately labelled legal constructed states.
#include "Vtb_m2_sprite_top.h"
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

static Vtb_m2_sprite_top *d;
static uint64_t clocks=0,errors=0,compared=0,list_compared=0;
static unsigned width=376,period=12,scan_start=480,worst=0,lines=0,deadlines=0;
static unsigned build_worst=0,prefetch_requests=0,request_with_pixel_writes=0,ack_with_writes=0;
static unsigned cancels=0,cancel_prefetch_overlap=0,uncovered_cancels=0;
static bool mw=false,sampling=false;
static constexpr uint64_t MASK=((1ull<<23)-1)|(1ull<<31)|(3ull<<32)|(255ull<<34);
static std::ofstream trace;
static std::array<uint64_t,5> previous{};
static bool first_trace=true,old_req=false;
static unsigned old_rom=0,old_writes=0;
static bool emitting=false;
static void error(const char *what,uint64_t got,uint64_t expected){if(errors<20)std::printf("ERROR %s got=%llx expected=%llx clock=%llu\n",what,(unsigned long long)got,(unsigned long long)expected,(unsigned long long)clocks);errors++;}
static void tick(unsigned n=1){while(n--){
    d->clk=0;d->eval();d->clk=1;d->eval();clocks++;
    emitting=d->dbg_pxw!=old_writes;
    if(old_req&&d->observed_rom_req&&old_rom!=d->observed_rom_addr&&!d->line_start)prefetch_requests++;
    if(emitting&&d->observed_rom_req)request_with_pixel_writes++;
    if(emitting&&d->observed_rom_ack)ack_with_writes++;
    old_req=d->observed_rom_req;old_rom=d->observed_rom_addr;old_writes=d->dbg_pxw;
    if(trace.is_open()){
        std::array<uint64_t,5> v={uint64_t(d->busy)|(uint64_t(d->observed_rom_req)<<1)|(uint64_t(d->observed_rom_ack)<<2)|(uint64_t(d->line_start)<<3)|(uint64_t(sampling)<<4),
            d->observed_rom_req?uint64_t(d->observed_rom_addr):0,sampling?(d->packed_pixel&MASK):0,sampling?uint64_t(d->px):0,
            uint64_t(d->dbg_objs)|(uint64_t(d->dbg_rows)<<32)};
        if(first_trace||v!=previous){trace.write((char*)&clocks,8);trace.write((char*)v.data(),sizeof v);previous=v;first_trace=false;}
    }
}}
static std::vector<uint8_t> bytes(const std::string&p){std::ifstream f(p,std::ios::binary);if(!f){std::fprintf(stderr,"Cannot read %s\n",p.c_str());std::exit(2);}return {std::istreambuf_iterator<char>(f),{}};}
static std::vector<uint64_t> words64(const std::string&p){if(p=="-")return {};auto b=bytes(p);if(b.size()!=width*224*8){std::fprintf(stderr,"Oracle length mismatch\n");std::exit(2);}std::vector<uint64_t> v;for(size_t i=0;i<b.size();i+=8){uint64_t w=0;for(unsigned j=0;j<8;j++)w|=uint64_t(b[i+j])<<(8*j);v.push_back(w);}return v;}
static std::vector<uint32_t> words32(const std::string&p){if(p=="-")return {};auto b=bytes(p);if(b.size()%4){std::fprintf(stderr,"List length mismatch\n");std::exit(2);}std::vector<uint32_t> v;for(size_t i=0;i<b.size();i+=4)v.push_back(unsigned(b[i])|(unsigned(b[i+1])<<8)|(unsigned(b[i+2])<<16)|(unsigned(b[i+3])<<24));return v;}
template<class T>static void write_words(const std::string&p,const std::vector<T>&v){std::ofstream f(p,std::ios::binary);for(auto w:v)for(unsigned j=0;j<sizeof(T);j++)f.put(char(uint64_t(w)>>(8*j)));}
static std::map<std::string,std::vector<unsigned>> load_state(const std::string&p){
    std::ifstream f(p);if(!f){std::fprintf(stderr,"Cannot read state\n");std::exit(2);}std::map<std::string,std::vector<unsigned>> s;std::string row;
    while(std::getline(f,row)){std::istringstream r(row);std::string key;if(!(r>>key)||key[0]=='#'||key=="VRAM")continue;std::string word;while(r>>word)s[key].push_back(std::stoul(word,nullptr,16));}return s;
}
static void tables(const std::string&zoom,const std::string&recip){
    for(unsigned sel=0;sel<2;sel++){std::ifstream f(sel?recip:zoom);std::string row;unsigned i=0;while(f>>row){d->tab_we=1;d->tab_sel=sel;d->tab_waddr=i++;d->tab_wdata=std::stoul(row,nullptr,16);tick();}if(i!=(sel?2048:1024))error("Lookup table length",i,sel?2048:1024);}d->tab_we=0;
}
// Current pinned k054338_device::set_alpha_level, with Mystic invert_alpha(1).
// Setup comes from public K38 registers, never oracle pixel/object outcomes.
static unsigned alpha_level(const std::vector<unsigned>&k38,unsigned effect){
    if(!effect)return 255;
    unsigned mix=(k38[13+((effect>>1)&1)]>>((~effect<<3)&8))&255;
    unsigned level=mix&31;if(!(mix&32))level=31-level;
    return (level<<3)|(level>>2)|((mix&32)?256:0)|((k38[15]&2)?512:0);
}
static std::vector<uint32_t> setup(const std::map<std::string,std::vector<unsigned>>&s,const std::vector<uint32_t>&expected){
    d->reset=1;d->line_start=0;d->build=0;d->inspect_list=0;tick(100);
    const auto &ram=s.at("SPRITERAM"),&k46=s.at("K46REGS"),&k47=s.at("K47REGS"),&k55=s.at("K55REGS"),&k38=s.at("K38REGS");
    if(ram.size()!=2048||k46.size()<6||k47.size()<7||k55.size()<40||k38.size()<16){std::fprintf(stderr,"Incomplete registers/RAM\n");std::exit(2);}
    for(unsigned i=0;i<ram.size();i++){d->ram_we=1;d->ram_waddr=i;d->ram_wdata=ram[i];tick();}d->ram_we=0;
    unsigned shadowon=0;for(unsigned t=0;t<3;t++)for(unsigned c=0;c<3;c++){int v=k38[2+t*3+c]&511;if(v>=256)v-=512;if(v< -7||v>7)shadowon|=1u<<t;}
    d->cfg_we=1;d->opset_i=k47[6];d->objset1_i=k46[5]&255;d->shadowon_i=shadowon;d->shdpri0_i=k55[37];d->shdpri1_i=k55[38];d->shdpri2_i=k55[39];d->k46r5_i=k46[5]&255;
    d->k46offx_i=((k46[0]&255)<<8)|(k46[1]&255);d->k46offy_i=((k46[2]&255)<<8)|(k46[3]&255);d->colorbase_i=(k55[27]<<(mw?5:4))&127;
    d->alpha1_i=mw?alpha_level(k38,1):255;d->alpha2_i=mw?alpha_level(k38,2):255;d->alpha3_i=mw?alpha_level(k38,3):255;
    tick();d->cfg_we=0;d->reset=0;tick(2);
    d->build=1;tick();d->build=0;unsigned c=0;while(!d->build_done&&c++<245760)tick();if(!d->build_done)error("Vblank list build deadline",c,245760);if(c>build_worst)build_worst=c;if(d->overflow)error("List overflow",1,0);
    if(mw&&d->count!=expected.size())error("Actual producer object count",d->count,expected.size());
    std::vector<uint32_t> list;d->inspect_list=1;
    for(unsigned i=0;i<d->count&&i<512;i++){d->inspect_idx=i;tick(2);list.push_back(d->inspect_q);if(mw){list_compared++;if(i>=expected.size()||d->inspect_q!=expected[i])error("Actual producer ordered object",d->inspect_q,i<expected.size()?expected[i]:0);}}
    d->inspect_list=0;tick(2);return list;
}
static std::vector<uint64_t> line_run(unsigned render_y,int scan_y,const std::vector<uint64_t>&oracle){
    std::vector<uint64_t> out(width);d->line=render_y;d->line_start=1;tick();d->line_start=0;unsigned complete=0;bool was_busy=d->busy;
    for(unsigned c=1;c<6144;c++){
        bool scan=scan_y>=0&&c>=scan_start&&c<scan_start+width*period;if(scan&&(c-scan_start)%period==0)d->px=(c-scan_start)/period;
        sampling=scan&&(c-scan_start)%period==2;tick();if(was_busy&&!d->busy&&!complete)complete=c;was_busy=d->busy;
        if(sampling){unsigned x=(c-scan_start)/period;uint64_t got=d->packed_pixel&MASK;out[x]=got;if(!oracle.empty()){uint64_t exp=oracle[unsigned(scan_y)*width+x]&MASK;compared++;if(got!=exp)error("Sprite public pixel metadata",got,exp);}}
    }sampling=false;lines++;if(!complete||d->busy){deadlines++;error("6144-clock draw deadline",complete,6144);}else if(complete>worst)worst=complete;return out;
}
static std::vector<uint64_t> cancel(bool want_prefetch,unsigned dense,const std::vector<uint64_t>&oracle){
    d->line=16+dense;d->line_start=1;tick();d->line_start=0;unsigned c=0;bool overlap=false;
    while(c++<6000){tick();if(d->observed_rom_req&&(!want_prefetch||emitting)){overlap=emitting;break;}if(!d->busy)break;}
    if(!d->observed_rom_req){
        // A scene need not contain a multi-column object. Report this as scope,
        // and still test cancellation at a real request, without forcing state.
        d->line=16+dense;d->line_start=1;tick();d->line_start=0;c=0;while(!d->observed_rom_req&&d->busy&&c++<6000)tick();
    }
    if(!d->observed_rom_req){uncovered_cancels++;return {};}
    unsigned recover=dense==223?222:dense+1;line_run(16+recover,-1,oracle);auto out=line_run(16+((recover+1)%224),int(recover),oracle);cancels++;if(want_prefetch&&overlap)cancel_prefetch_overlap++;return out;
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc<7){std::fprintf(stderr,"usage: sprite ROM mystic cases.tsv outdir zoom.hex recip.hex [trace]\n");return 2;}
    mw=std::atoi(argv[2]);width=mw?288:376;period=mw?16:12;scan_start=(mw?24:40)*period;
    auto rom=bytes(argv[1]);if(rom.size()!=(mw?0xdc0080u:0x1360080u)){std::fprintf(stderr,"ROM size mismatch\n");return 2;}
    d=new Vtb_m2_sprite_top;d->mystic=mw;d->reset=1;d->init=1;tick(8);d->init=0;unsigned c=0;while(!d->ready&&c++<100000)tick();if(!d->ready){error("Memory not ready",0,1);return 1;}
    tables(argv[5],argv[6]);unsigned base=mw?0x8c0000:0xb60000,len=mw?0x500000:0x800000;
    for(unsigned i=0;i<len;i++){d->dl_we=1;d->dl_addr=base+i;d->dl_data=rom[base+i];tick();d->dl_we=0;tick(7);}tick(500);
    std::ifstream configs(argv[3]);if(!configs){std::fprintf(stderr,"Missing cases\n");return 2;}std::string row;unsigned scenes=0;if(argc>7)trace.open(argv[7],std::ios::binary);
    while(std::getline(configs,row)){
        if(row.empty())continue;std::istringstream r(row);std::string sp,op,lp,tag;std::getline(r,sp,'\t');std::getline(r,op,'\t');std::getline(r,lp,'\t');std::getline(r,tag,'\t');auto oracle=words64(op);auto expected=words32(lp);auto list=setup(load_state(sp),expected);write_words(std::string(argv[4])+"/"+tag+".list.bin",list);
        std::vector<uint64_t> out;line_run(16,-1,oracle);for(unsigned y=0;y<224;y++){auto p=line_run(17+y,int(y),oracle);out.insert(out.end(),p.begin(),p.end());}write_words(std::string(argv[4])+"/"+tag+".pixels.bin",out);
        unsigned dense=112,best=0;const auto &density=oracle.empty()?out:oracle;for(unsigned y=0;y<224;y++){unsigned n=0;for(unsigned x=0;x<width;x++)n+=bool(density[y*width+x]&((1ull<<12)|(1ull<<31)));if(n>best){best=n;dense=y;}}
        auto a=cancel(false,dense,oracle),b=cancel(true,dense,oracle);a.insert(a.end(),b.begin(),b.end());write_words(std::string(argv[4])+"/"+tag+".cancel.bin",a);scenes++;std::printf("SCENE %s objects=%u full_pixels=%u dense_y=%u worst=%u errors=%llu\n",tag.c_str(),unsigned(list.size()),width*224,dense,worst,(unsigned long long)errors);
    }
    if(!scenes)error("Zero scenes",0,1);if(d->protocol_errors)error("SDRAM protocol",d->protocol_errors,0);
    if(trace.is_open()){uint64_t marker=~0ull;trace.write((char*)&marker,8);trace.write((char*)&clocks,8);trace.close();}
    std::printf("RESULT_JSON {\"passed\":%s,\"mystic\":%s,\"scenes\":%u,\"errors\":%llu,\"oracle_pixels_compared\":%llu,\"ordered_objects_compared\":%llu,\"lines\":%u,\"worst_line_clocks\":%u,\"deadline_failures\":%u,\"worst_build_clocks\":%u,\"prefetch_requests\":%u,\"requests_with_pixel_writes\":%u,\"acks_with_pixel_writes\":%u,\"cancellations\":%u,\"cancel_during_emit_request\":%u,\"uncovered_cancels\":%u,\"cycles\":%llu,\"hardware_verified\":false}\n",errors?"false":"true",mw?"true":"false",scenes,(unsigned long long)errors,(unsigned long long)compared,(unsigned long long)list_compared,lines,worst,deadlines,build_worst,prefetch_requests,request_with_pixel_writes,ack_with_writes,cancels,cancel_prefetch_overlap,uncovered_cancels,(unsigned long long)clocks);
    std::printf("%s M2 actual sprite producer/linebuffer/scanout\n",errors?"FAIL":"PASS");delete d;return errors?1:0;
}
