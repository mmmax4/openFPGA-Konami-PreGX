// Independent memory-profile gate. Original bytes only enter through download;
// observations use the core ports and a passive SDRAM-pin monitor, never DUT state.
#include "Vtb_m2_mem_top.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

static Vtb_m2_mem_top *d;
static uint64_t clocks=0;
static unsigned errors=0, checks=0, cancellations=0, eep_count=0;
static unsigned tile_nonzero=0, sprite_large_sum=0;
static bool mystic=false;
static std::vector<uint8_t> image;
static std::array<int,128> eep;
static std::ofstream trace;
static std::array<uint64_t,9> previous{};
struct Read { uint64_t clock; unsigned word; };
static std::vector<Read> reads;
static unsigned prog,snd,tile,chr,map,pcm,spr,end;
static constexpr unsigned HEAD=16384, SHRINK=9;
static void bad(const char *what,uint64_t got,uint64_t expected) {
    if (errors<20) std::printf("ERROR %s got=%llx expected=%llx clock=%llu\n",what,
        (unsigned long long)got,(unsigned long long)expected,(unsigned long long)clocks);
    errors++;
}
static void eq(const char *what,uint64_t got,uint64_t expected) {checks++;if(got!=expected)bad(what,got,expected);}
static void tick(unsigned n=1) {
    while(n--) {
        d->clk=0;d->eval();d->clk=1;d->eval();clocks++;
        if(d->eep_we){eep[d->eep_addr]=d->eep_data;eep_count++;}
        if(d->sd_read_pulse)reads.push_back({clocks,d->sd_read_word});
        if(!d->test_run && ((d->tile_ack&&!d->tile_req)||(d->spr_ack&&!d->spr_req)))
            bad("withdrawn graphics request ACK",1,0);
        if(trace.is_open()) {
            // Canonical valid-interface waveform, run-length encoded by cycle.
            // Unqualified data buses are deliberately masked, never compared as valid data.
            std::array<uint64_t,9> v={
                uint64_t(d->ready)|(uint64_t(d->test_run)<<1)|(uint64_t(d->test_done)<<2)|
                (uint64_t(d->prog_ack)<<3)|(uint64_t(d->snd_ack)<<4)|(uint64_t(d->tile_ack)<<5)|
                (uint64_t(d->spr_ack)<<6)|(uint64_t(d->pcm_ack)<<7)|(uint64_t(d->vram_ack)<<8)|
                (uint64_t(d->map_ack)<<9)|(uint64_t(d->blk_ack)<<10)|(uint64_t(d->blk_wr)<<11),
                (d->prog_ack?uint64_t(d->prog_q):0)|(d->snd_ack?uint64_t(d->snd_q)<<16:0)|
                (d->pcm_ack?uint64_t(d->pcm_q)<<24:0)|(d->vram_ack?uint64_t(d->vram_q)<<32:0)|
                (d->map_ack?uint64_t(d->map_q)<<48:0),
                d->tile_ack?uint64_t(d->tile_q)|(uint64_t(d->tile_fifth)<<32):0,
                d->spr_ack?uint64_t(d->spr_q):0,
                d->spr_ack?uint64_t(d->spr_fifth):0,
                d->blk_wr?uint64_t(d->blk_data)|(uint64_t(d->blk_idx)<<16):0,
                uint64_t(d->test_ok)|(uint64_t(d->test_stable)<<8)|(uint64_t(d->test_mask)<<16)|
                (uint64_t(d->vram_ok)<<24)|(uint64_t(d->vram_bad)<<25),
                d->eep_we?uint64_t(d->eep_data)|(uint64_t(d->eep_addr)<<8)|(1ull<<63):0,
                d->sd_read_pulse?uint64_t(d->sd_read_word)|(1ull<<63):0};
            if(clocks==1||v!=previous){trace.write((char*)&clocks,sizeof clocks);trace.write((char*)v.data(),sizeof v);previous=v;}
        }
    }
}
static unsigned be16(unsigned a){return (unsigned(image.at(a))<<8)|image.at(a+1);}
static uint64_t bytes(unsigned a,unsigned n){uint64_t v=0;while(n--)v=(v<<8)|image.at(a++);return v;}
static void load(unsigned a,unsigned n){for(unsigned k=0;k<n;k++){d->dl_addr=a+k;d->dl_data=image.at(a+k);d->dl_we=1;tick();d->dl_we=0;tick(7);}}
static bool ack(uint8_t &a,const char *what){for(unsigned k=0;k<5000;k++){tick();if(a)return true;}bad(what,0,1);return false;}
static unsigned prog_read(unsigned w){d->prog_req=1;d->prog_addr=w;ack(d->prog_ack,"program timeout");unsigned q=d->prog_q;d->prog_req=0;tick(2);return q;}
static unsigned snd_read(unsigned b){d->snd_req=1;d->snd_addr=b;ack(d->snd_ack,"sound timeout");unsigned q=d->snd_q;d->snd_req=0;tick(2);return q;}
static unsigned pcm_read(unsigned b){d->pcm_req=1;d->pcm_addr=b;ack(d->pcm_ack,"PCM timeout");unsigned q=d->pcm_q;d->pcm_req=0;tick(2);return q;}
static void vwrite(unsigned a,unsigned v,unsigned be){d->vram_req=1;d->vram_addr=a;d->vram_we=1;d->vram_be=be;d->vram_wdata=v;ack(d->vram_ack,"VRAM write timeout");d->vram_req=0;d->vram_we=0;tick(2);}
static unsigned vread(unsigned a){d->vram_req=1;d->vram_addr=a;d->vram_we=0;ack(d->vram_ack,"VRAM read timeout");unsigned q=d->vram_q;d->vram_req=0;tick(2);return q;}
static void tile_value(unsigned row){unsigned a=tile+row*(mystic?5:4);eq("tile low32",d->tile_q,bytes(a,4));eq("tile fifth",d->tile_fifth,mystic?image.at(a+4):0);if(mystic&&image.at(a+4))tile_nonzero++;}
static void spr_value(unsigned row){unsigned a=spr+row*(mystic?10:8);eq("sprite low64",d->spr_q,bytes(a,8));eq("sprite fifth16",d->spr_fifth,mystic?be16(a+8):0);if(mystic){unsigned sum=0;for(unsigned b=0;b<10;b++)sum+=image.at(a+b);if(sum>2047)sprite_large_sum++;}}
static void burst(bool sprite,unsigned row){
    size_t start=reads.size();unsigned words=sprite?(mystic?5:4):(mystic?3:2);
    unsigned base=sprite?((mystic?0x340000:0x300000)+row*(mystic?5:4)):
                         ((mystic?5*row:4*row)/2);
    if(sprite){d->spr_req=1;d->spr_addr=row;ack(d->spr_ack,"sprite timeout");spr_value(row);}
    else {d->tile_req=1;d->tile_addr=row;ack(d->tile_ack,"tile timeout");tile_value(row);}
    eq("isolated burst READ count",reads.size()-start,words);
    for(unsigned k=0;k<words&&start+k<reads.size();k++)eq("burst pin address",reads[start+k].word,base+k);
    if(reads.size()>start&&clocks-reads.back().clock<3)bad("ACK before final CL3 response",clocks-reads.back().clock,3);
    d->spr_req=0;d->tile_req=0;tick(3);
}
static void cancel(bool sprite,unsigned mode){
    // Start row1, then withdraw/restart or change address while the burst is active.
    // No internal access or forced state: synchronize to an observed READ pin command.
    size_t start=reads.size();if(sprite){d->spr_req=1;d->spr_addr=1;}else{d->tile_req=1;d->tile_addr=1;}
    unsigned n=0;while(reads.size()==start&&n++<5000)tick();
    if(reads.size()==start){bad("cancel no in-flight READ",0,1);return;}
    if(mode!=2){d->tile_req=0;d->spr_req=0;tick(mode==0?1:100);if(d->tile_ack||d->spr_ack)bad("withdrawn request ACK",1,0);}
    unsigned row=sprite?102:204;size_t restart=reads.size();unsigned wanted=sprite?(mystic?0x340000:0x300000)+row*(mystic?5:4):(row*(mystic?5:4))/2;
    if(sprite){d->spr_addr=row;d->spr_req=1;ack(d->spr_ack,"sprite restart timeout");spr_value(row);}
    else{d->tile_addr=row;d->tile_req=1;ack(d->tile_ack,"tile restart timeout");tile_value(row);}
    unsigned fresh=0;for(size_t k=restart;k<reads.size();k++)if(reads[k].word>=wanted&&reads[k].word<wanted+(sprite?(mystic?5:4):(mystic?3:2)))fresh++;
    eq("new row complete before ACK",fresh,sprite?(mystic?5:4):(mystic?3:2));
    d->tile_req=0;d->spr_req=0;tick(100);cancellations++;
}
static void gaia_extra(){
    for(unsigned off:{0u,2u,4094u,0x9fffeu}){d->map_req=1;d->map_addr=off;ack(d->map_ack,"map timeout");eq("Gaia map",d->map_q,be16(map+off));d->map_req=0;tick(2);}
    for(unsigned t:{0u,1u,0x2fffu}){
        d->blk_req=1;d->blk_addr=t;uint64_t mask=0;unsigned count=0;
        for(unsigned n=0;n<10000;n++){tick();if(d->blk_wr){unsigned i=d->blk_idx;eq("Gaia ROZ data",d->blk_data,be16(chr+t*128+(i%16)*8+(i/16)*2));mask|=1ull<<i;count++;}if(d->blk_ack)break;}
        eq("Gaia ROZ all64",mask,~0ull);eq("Gaia ROZ once each",count,64);d->blk_req=0;tick(2);
    }
}
static void contention(){
    unsigned seed=0x185607u;auto rnd=[&](){seed=seed*1664525u+1013904223u;return seed>>8;};
    unsigned done[6]={},addr[6]={},hold[6]={};bool on[6]={},vwrite_phase=true;
    std::array<unsigned,64> vr{};for(unsigned a=0;a<64;a++){vr[a]=be16(prog+2*a);vwrite(a,vr[a],3);}
    unsigned pending_v=0;const unsigned target=128;
    for(unsigned n=0;n<300000;n++){
        // At most one standing request per public port. All six ports overlap.
        for(unsigned k=0;k<6;k++)if(!on[k]&&done[k]<target&&(rnd()%4)==0){
            on[k]=true;hold[k]=0;
            switch(k){case 0:addr[k]=rnd()%2048;d->prog_addr=addr[k];d->prog_req=1;break;
            case 1:addr[k]=rnd()%256;d->snd_addr=addr[k];d->snd_req=1;break;
            case 2:addr[k]=rnd()%(HEAD/(mystic?5:4));d->tile_addr=addr[k];d->tile_req=1;break;
            case 3:addr[k]=rnd()%(HEAD/(mystic?10:8));d->spr_addr=addr[k];d->spr_req=1;break;
            case 4:addr[k]=rnd()%HEAD;d->pcm_addr=addr[k];d->pcm_req=1;break;
            case 5:addr[k]=rnd()%64;d->vram_addr=addr[k];d->vram_req=1;d->vram_we=vwrite_phase;d->vram_be=3;pending_v=be16(prog+2*(rnd()%2048));d->vram_wdata=pending_v;break;}
        }
        tick();uint8_t acks[]={d->prog_ack,d->snd_ack,d->tile_ack,d->spr_ack,d->pcm_ack,d->vram_ack};
        for(unsigned k=0;k<6;k++){
            if(acks[k]&&!on[k])bad("ACK without standing consumer",k,6);
            if(on[k])hold[k]++;
            if(on[k]&&acks[k]){
                switch(k){case 0:eq("contended program",d->prog_q,be16(prog+2*addr[k]));d->prog_req=0;break;
                case 1:eq("contended sound",d->snd_q,image.at(snd+addr[k]));d->snd_req=0;break;
                case 2:tile_value(addr[k]);d->tile_req=0;break;
                case 3:spr_value(addr[k]);d->spr_req=0;break;
                case 4:eq("contended PCM",d->pcm_q,image.at(pcm+addr[k]));d->pcm_req=0;break;
                case 5:if(vwrite_phase)vr[addr[k]]=pending_v;else eq("contended VRAM",d->vram_q,vr[addr[k]]);vwrite_phase=!vwrite_phase;d->vram_req=0;d->vram_we=0;break;}
                on[k]=false;done[k]++;
            }
        }
        bool finished=true;for(unsigned k=0;k<6;k++)if(done[k]<target)finished=false;
        if(finished)break;
    }
    for(unsigned k=0;k<6;k++)eq("contention progress",done[k],target);
    std::printf("CONTENTIONS prog=%u snd=%u tile=%u spr=%u pcm=%u vram=%u\n",done[0],done[1],done[2],done[3],done[4],done[5]);tick(100);
}
static void memtest(){
    // Loading address0 restarts lsum: only exactly the tested original prefix
    // is reloaded now, so earlier boundary windows cannot pollute its sums.
    const unsigned counts[]={mystic?0x100000u:0x180000u,0x40000,0x80000,0x3000,0x50000,0x400000,mystic?0x80000u:0x100000u};
    const unsigned bases[]={prog,snd,tile,chr,map,pcm,spr};
    const unsigned units[]={2,1,mystic?5u:4u,128,2,1,mystic?10u:8u};
    if(mystic){
        unsigned fifth=0,large=0;
        for(unsigned r=0;r<(counts[2]>>SHRINK);r++)if(image.at(tile+5*r+4))fifth++;
        for(unsigned r=0;r<(counts[6]>>SHRINK);r++){unsigned sum=0;for(unsigned b=0;b<10;b++)sum+=image.at(spr+10*r+b);if(sum>2047)large++;}
        if(!fifth||!large)bad("original memtest prefixes must discriminate fifth/12bit",0,1);
        std::printf("CHECKSUM_COVERAGE nonzero_tile_fifth=%u sprite_sums_above2047=%u\n",fifth,large);
    }
    for(unsigned r=0;r<7;r++)if(!mystic||(r!=3&&r!=4))load(bases[r],(counts[r]>>SHRINK)*units[r]);tick(500);
    d->test_start=1;tick(4);d->test_start=0;unsigned n=0;
    while(!d->test_done&&n++<12000000)tick();
    eq("memtest done",d->test_done,1);eq("memtest active mask",d->test_mask,mystic?0x67:0x7f);
    eq("memtest original sum",d->test_ok,mystic?0x67:0x7f);eq("memtest stable",d->test_stable,mystic?0x67:0x7f);eq("memtest VRAM",d->vram_ok,1);
    std::printf("MEMTEST done=%u mask=%02x ok=%02x stable=%02x vram=%u clocks=%u\n",d->test_done,d->test_mask,d->test_ok,d->test_stable,d->vram_ok,n);
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc<4){std::fprintf(stderr,"usage: tb_m2_mem ROM mystic slow [trace]\n");return 2;}
    mystic=std::atoi(argv[2]);bool slow=std::atoi(argv[3]);std::ifstream in(argv[1],std::ios::binary);image.assign(std::istreambuf_iterator<char>(in),{});
    if(image.size()!=(mystic?0xdc0080u:0x1360080u)){std::fprintf(stderr,"ROM size mismatch\n");return 2;}
    prog=0;snd=mystic?0x200000:0x300000;tile=mystic?0x240000:0x340000;chr=0x540000;map=0x6c0000;pcm=mystic?0x4c0000:0x760000;spr=mystic?0x8c0000:0xb60000;end=mystic?0xdc0000:0x1360000;
    if(argc>4)trace.open(argv[4],std::ios::binary);eep.fill(-1);d=new Vtb_m2_mem_top;d->mystic=mystic;d->rd_late=!slow;d->burst_slow=slow;d->ps_slow=slow;d->sram_slow=slow;d->sram_slow_wr=slow;d->init=1;tick(8);d->init=0;
    unsigned w=0;while(!d->ready&&w++<100000)tick();eq("memory ready",d->ready,1);
    std::vector<unsigned> starts={prog,snd,tile,pcm,spr};if(!mystic){starts.push_back(chr);starts.push_back(map);}
    std::vector<unsigned> lengths={snd-prog,tile-snd,(mystic?pcm:chr)-tile,spr-pcm,end-spr};if(!mystic){lengths.push_back(map-chr);lengths.push_back(pcm-map);}
    for(size_t k=0;k<starts.size();k++){load(starts[k],HEAD);load(starts[k]+lengths[k]-HEAD,HEAD);}load(end,128);tick(600);
    eq("EEPROM delivered128",eep_count,128);for(unsigned a=0;a<128;a++)eq("original EEPROM",eep[a],image.at(end+a));
    // Reversed byte order and lone byte flushes, using the unchanged original bytes.
    for(unsigned a:{10u,2048u}){load(a+1,1);tick(300);load(a,1);tick(300);eq("download byte lanes",prog_read(a/2),be16(a));}
    for(unsigned a:{0u,1u,2u,63u,1023u,(snd-prog)/2-1})eq("program original",prog_read(a),be16(prog+2*a));
    for(unsigned a:{0u,1u,255u,tile-snd-1})eq("sound original",snd_read(a),image.at(snd+a));
    for(unsigned a:{0u,1u,511u,1023u,spr-pcm-1})eq("PCM original",pcm_read(a),image.at(pcm+a));
    unsigned tile_rows=((mystic?pcm:chr)-tile)/(mystic?5:4),spr_rows=(end-spr)/(mystic?10:8);
    for(unsigned a:{0u,1u,2u,3u,203u,204u,205u,206u,512u,513u,tile_rows-2,tile_rows-1})burst(false,a);
    for(unsigned a:{0u,1u,2u,3u,101u,102u,103u,912u,913u,spr_rows-2,spr_rows-1})burst(true,a);
    if(!mystic)gaia_extra();
    unsigned original0=be16(prog+32),original1=be16(prog+34);vwrite(0x1234,original0,3);vwrite(0x1234,original1,2);eq("VRAM upper lane",vread(0x1234),(original1&0xff00)|(original0&255));vwrite(0x1234,original0,1);eq("VRAM lower lane",vread(0x1234),(original1&0xff00)|(original0&255));
    if(!errors){for(unsigned mode=0;mode<3;mode++){cancel(false,mode);cancel(true,mode);}contention();}
    if(!errors)memtest();eq("SDRAM protocol monitor",d->sd_protocol_errors,0);
    if(mystic&&(!tile_nonzero||!sprite_large_sum))bad("Mystic data coverage",0,1);
    if(trace.is_open()){uint64_t marker=~0ull;trace.write((char*)&marker,sizeof marker);trace.write((char*)&clocks,sizeof clocks);trace.close();}
    std::printf("RESULT_JSON {\"passed\":%s,\"mystic\":%s,\"slow\":%s,\"errors\":%u,\"checks\":%u,\"cycles\":%llu,\"cancellations\":%u,\"eeprom_bytes\":%u,\"nonzero_tile_fifth_checks\":%u,\"sprite_sums_above2047\":%u,\"physical_timing_qualified\":false}\n",errors?"false":"true",mystic?"true":"false",slow?"true":"false",errors,checks,(unsigned long long)clocks,cancellations,eep_count,tile_nonzero,sprite_large_sum);
    std::printf("%s M2 memory actual public consumers\n",errors?"FAIL":"PASS");delete d;return errors?1:0;
}
