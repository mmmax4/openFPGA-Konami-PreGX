// Independent memory-profile gate. Original bytes only enter through download;
// observations use the core ports and a passive SDRAM-pin monitor, never DUT state.
#include "Vtb_m4_mem_top.h"
#include "verilated.h"
#include <array>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

static Vtb_m4_mem_top *d;
static uint64_t clocks=0;
static unsigned errors=0, checks=0, cancellations=0, eep_count=0;
static unsigned tile_nonzero=0, sprite_large_sum=0;
static bool mystic=false;static unsigned profile=3;static unsigned roadbase=0;
static unsigned road_bursts=0,road_checks=0,road_cancellations=0,road_writes=0,ps_commits=0;
static unsigned state_read_min=99999,state_read_max=0,state_write_min=99999,state_write_max=0;
static uint64_t last_commit=0;static std::array<unsigned,3> max_gap{};static std::array<unsigned,16384> state_words{};
static std::vector<bool> loaded;
static unsigned loaded_bytes=0;
static std::vector<uint8_t> image;
static std::array<int,128> eep;
static std::ofstream trace;
static std::array<uint64_t,9> previous{};
struct Read { uint64_t clock; unsigned word; };
static std::vector<Read> reads;
static unsigned prog,snd,tile,chr,map,pcm,spr,end;
static constexpr unsigned HEAD=512, SHRINK=9;
static void bad(const char *what,uint64_t got,uint64_t expected) {
    if (errors<20) std::printf("ERROR %s got=%llx expected=%llx clock=%llu\n",what,
        (unsigned long long)got,(unsigned long long)expected,(unsigned long long)clocks);
    errors++;
}
static void eq(const char *what,uint64_t got,uint64_t expected) {checks++;if(got!=expected)bad(what,got,expected);}
static void tick(unsigned n=1) {
    while(n--) {
        d->clk=0;d->eval();d->clk=1;d->eval();clocks++;
        if(d->ps0_write_commit){ps_commits++;last_commit=clocks;}
        if(d->road_ack&&d->road_we&&d->ps0_write_active)bad("road ACK while pin WE low",1,0);
        if(d->lvc_ack&&!d->lvc_req&&!d->test_run)bad("road ROM ACK without request",1,0);
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
static void load(unsigned a,unsigned n){for(unsigned k=0;k<n;k++){unsigned p=a+k;if(loaded.at(p))continue;loaded[p]=true;loaded_bytes++;d->dl_addr=p;d->dl_data=image.at(p);d->dl_we=1;unsigned held=(p%257==0)?3:1;tick(held);d->dl_we=0;tick(8-held);}}
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
    unsigned base=sprite?((mystic?0x340000:(profile>=2?0x400000:0x300000))+row*(mystic?5:4)):
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
    unsigned row=sprite?102:204;size_t restart=reads.size();unsigned wanted=sprite?(mystic?0x340000:(profile>=2?0x400000:0x300000))+row*(mystic?5:4):(row*(mystic?5:4))/2;
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
    d->test_start=1;tick(4);d->test_start=0;unsigned n=0;
    while(!d->test_done&&n++<12000000)tick();
    eq("memtest done",d->test_done,1);eq("memtest active mask",d->test_mask,profile==3?0x6f:0x67);
    eq("memtest original sum",d->test_ok,profile==3?0x6f:0x67);eq("memtest stable",d->test_stable,profile==3?0x6f:0x67);eq("memtest VRAM",d->vram_ok,1);
    printf("MEMTEST done=%u mask=%02x ok=%02x stable=%02x vram=%u clocks=%u\n",d->test_done,d->test_mask,d->test_ok,d->test_stable,d->vram_ok,n);
}
static void road_value(unsigned group){eq("road ROM original64",d->lvc_q,bytes(roadbase+group*8,8));road_checks++;}
static void road_burst(unsigned group,bool pins=true){
    size_t n=reads.size();d->lvc_req=1;d->lvc_addr=group;ack(d->lvc_ack,"road ROM timeout");road_value(group);
    if(pins){eq("road burst4 commands",reads.size()-n,4);for(unsigned k=0;k<4&&n+k<reads.size();k++)eq("road physical word",reads[n+k].word,0x800000+group*4+k);}
    d->lvc_req=0;tick(3);road_bursts++;
}
static void road_cancel(unsigned mode){
    size_t start=reads.size();d->lvc_req=1;d->lvc_addr=2;unsigned k=0;while(reads.size()==start&&k++<5000)tick();
    if(reads.size()==start){bad("road cancel no pin read",0,1);return;}
    if(mode!=2){d->lvc_req=0;tick(mode==0?1:100);}
    // mode0 withdraw/return same address: no ACK until a fresh4word burst.
    unsigned group=mode==0?2:217;size_t resume=reads.size();d->lvc_req=1;d->lvc_addr=group;ack(d->lvc_ack,"road restart timeout");road_value(group);
    // A withdrawn access finishes on the pins. For same-address ABA, its
    // remaining READs share the new group's range and must not be counted as
    // the fresh transaction. A fresh command begins at the observed base word.
    unsigned base=0x800000+group*4;size_t fresh=reads.size();
    for(size_t n=resume;n<reads.size();n++)if(reads[n].word==base){fresh=n;break;}
    eq("road restart new base READ observed",fresh<reads.size(),1);
    eq("cancelled old road burst finishes4words",fresh-start,4);
    eq("road restart complete fresh burst",reads.size()-fresh,4);
    for(unsigned n=0;n<4&&fresh+n<reads.size();n++)eq("road restart ordered pin READ",reads[fresh+n].word,base+n);
    if(!reads.empty()&&clocks-reads.back().clock<3)bad("road restart ACK before final CL3",clocks-reads.back().clock,3);
    printf("ROAD_CANCEL_PIN mode=%u rd_late=%u burst_slow=%u start=%zu resume=%zu fresh=%zu ack_clock=%llu",mode,d->rd_late,d->burst_slow,start,resume,fresh,(unsigned long long)clocks);
    for(size_t n=start;n<reads.size();n++)printf(" %llu:%06x",(unsigned long long)reads[n].clock,reads[n].word);
    printf("\n");d->lvc_req=0;tick(100);road_cancellations++;
}
static unsigned state_read(unsigned a){uint64_t start=clocks;d->road_req=1;d->road_we=0;d->road_addr=a;ack(d->road_ack,"road state read timeout");unsigned q=d->road_q;unsigned lat=clocks-start;state_read_min=std::min(state_read_min,lat);state_read_max=std::max(state_read_max,lat);d->road_req=0;tick(3);return q;}
static void state_write(unsigned a,unsigned v,unsigned be){
    uint64_t start=clocks;unsigned old=state_words[a],before=ps_commits;d->road_req=1;d->road_we=1;d->road_addr=a;d->road_be=be;d->road_wdata=v;
    ack(d->road_ack,"road state committed write timeout");unsigned lat=clocks-start;state_write_min=std::min(state_write_min,lat);state_write_max=std::max(state_write_max,lat);eq("road one committed transaction",ps_commits-before,1);
    eq("road write physical word",d->ps0_write_word,a);eq("road write physical lanes",d->ps0_write_be,be);eq("road write physical data",d->ps0_write_data,v);
    if(last_commit>=clocks)bad("road ACK before completed pin write",last_commit,clocks-1);
    state_words[a]=((be&2)?(v&0xff00):(old&0xff00))|((be&1)?(v&255):(old&255));
    // Hold the accepted transaction to check the bridge emits only oneACK.
    unsigned repeated=0;for(unsigned k=0;k<4;k++){tick();repeated+=d->road_ack;}eq("road held request one ACK",repeated,0);
    d->road_req=0;d->road_we=0;tick(3);road_writes++;
}
static void state_tests(){
    for(unsigned slow=0;slow<2;slow++){
        d->ps_slow=slow;
        for(unsigned a:{0u,1u,0x7ffu,0x800u,0x1fffu,0x2000u,0x27ffu,0x2800u,0x2fffu}){
            unsigned x=be16(roadbase+(a*2)%0x40000),y=be16(roadbase+((a+17)*2)%0x40000);
            state_write(a,x,3);eq("roadstate original write/read",state_read(a),x);
            state_write(a,y,2);eq("roadstate upperbyte",state_read(a),state_words[a]);state_write(a,x,1);eq("roadstate lowerbyte",state_read(a),state_words[a]);
        }
        // Actual DMA-page-sized mutable data using only original words, forward
        // write then reverse read, no hierarchical preload or favorable ACK stub.
        for(unsigned a=0;a<2048;a++)state_write(0x2000+a,be16(roadbase+a*2),3);
        for(unsigned a=2048;a-->0;)eq("roadstate page reverse",state_read(0x2000+a),be16(roadbase+a*2));
        // Withdrawed write still commits, but must not receive an orphanACK.
        unsigned a=0x2fff,v=be16(roadbase+0x222);unsigned before=ps_commits;d->road_req=1;d->road_we=1;d->road_addr=a;d->road_be=3;d->road_wdata=v;tick(4);d->road_req=0;
        unsigned orphan=0;for(unsigned k=0;k<80;k++){tick();orphan+=d->road_ack;}eq("cancelled state write noACK",orphan,0);eq("cancelled state write commits",ps_commits-before,1);eq("cancelled state write persists",state_read(a),v);d->road_we=0;
    }
}
static void fairness(){
    // Three continuously standing graphics consumers. On an ACK only that
    // address advances; requests remain high, so fixed tile priority starves.
    unsigned done[3]={},row[3]={3,9,17},gap[3]={};
    d->tile_req=d->spr_req=d->lvc_req=1;d->tile_addr=row[0];d->spr_addr=row[1];d->lvc_addr=row[2];
    for(unsigned n=0;n<200000;n++){
        tick();bool got[]={bool(d->tile_ack),bool(d->spr_ack),bool(d->lvc_ack)};
        for(unsigned k=0;k<3;k++){
            gap[k]++;max_gap[k]=std::max(max_gap[k],gap[k]);
            if(got[k]){
                if(k==0)tile_value(row[k]);else if(k==1)spr_value(row[k]);else road_value(row[k]);
                done[k]++;gap[k]=0;row[k]=(row[k]+1)%48;
                if(k==0)d->tile_addr=row[k];else if(k==1)d->spr_addr=row[k];else d->lvc_addr=row[k];
            }
        }
        if(done[0]>=256&&done[1]>=256&&done[2]>=256)break;
    }
    for(unsigned k=0;k<3;k++){if(done[k]<256)bad("continuous graphics starvation",done[k],256);if(max_gap[k]>1000)bad("continuous graphics latency bound",max_gap[k],1000);}
    d->tile_req=d->spr_req=d->lvc_req=0;tick(150);
    printf("FAIRNESS tile=%u sprite=%u road=%u maxgap=%u,%u,%u\n",done[0],done[1],done[2],max_gap[0],max_gap[1],max_gap[2]);
}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);if(argc!=3&&argc!=4)return 2;bool negative=argc==4&&std::string(argv[3])=="early-capture";profile=std::strtoul(argv[2],nullptr,0);if(profile>3)return 2;mystic=profile==1;
    std::ifstream in(argv[1],std::ios::binary);image.assign(std::istreambuf_iterator<char>(in),{});if(image.empty())return 2;loaded.resize(image.size(),false);
    prog=0;snd=profile==0?0x300000:0x200000;tile=snd+0x40000;
    pcm=profile==0?0x760000:(profile==1?0x4c0000:0x640000);spr=pcm+0x400000;end=image.size()-128;
    chr=0x540000;map=0x6c0000;roadbase=0x1240000;
    if(profile==3&&image.size()!=0x1280080)return 2;
    eep.fill(-1);d=new Vtb_m4_mem_top;d->mystic=mystic;d->violent=profile==2;d->metam=profile==3;d->rd_late=1;d->init=1;tick(8);d->init=0;
    unsigned w=0;while(!d->ready&&w++<100000)tick();eq("memory ready",d->ready,1);eq("profile memory mask",d->test_mask,profile==0?0x7f:(profile==3?0x6f:0x67));
    // Prefixes match the actual SHRINK9 built-in consumer. All loader bytes are
    // original, spaced8clocks; selectedWE pulses held3clocks, not doublecounted.
    load(prog,profile==0?6144:4096);load(snd,512);load(tile,profile>=2?8192:(mystic?5120:4096));load(pcm,8192);load(spr,mystic?10240:16384);
    if(profile==3)load(roadbase,512);tick(700);if(profile==3)memtest();
    unsigned starts[]={prog,snd,tile,pcm,spr},lens[]={snd,0x40000u,pcm-tile,0x400000u,end-spr};
    if(profile==3)lens[4]=0x800000;
    if(profile==0)lens[2]=chr-tile; // Gaia ROZ/map follow its2MiBtiles beforePCM.
    unsigned seed=0x550832;
    for(unsigned k=0;k<5;k++){
        load(starts[k]+lens[k]-1024,1024);
        for(unsigned j=0;j<12;j++){seed=seed*1664525u+1013904223u;unsigned unit=k==2?(mystic?5:4):(k==4?(mystic?10:8):2);unsigned a=((seed%(lens[k]-64))/unit)*unit;load(starts[k]+a,unit*2);}
    }
    if(profile==3)load(roadbase,0x40000);load(end,128);tick(800);
    eq("EEPROM128exact",eep_count,128);for(unsigned a=0;a<128;a++)eq("EEPROMoriginal",eep[a],image.at(end+a));
    // Ignore bytes past declared image end; never alias into EEPROM.
    d->dl_addr=end+128;d->dl_data=image[0];d->dl_we=1;tick(3);d->dl_we=0;tick(400);eq("beyondimage noEEPROM",eep_count,128);
    if(negative){
        d->rd_late=0;d->burst_slow=0;tick(10);
        for(unsigned group:{1u,31u,127u,4095u,32767u})road_burst(group);
        printf("RESULT_JSON {\"passed\":%s,\"errors\":%u,\"checks\":%u,\"negative\":\"early-capture\",\"physical_timing_qualified\":false}\n",errors?"false":"true",errors,checks);
        delete d;return errors?1:0;
    }
    for(unsigned mode=0;mode<2;mode++){
        d->rd_late=!mode;d->burst_slow=mode;d->ps_slow=mode;d->sram_slow=mode;d->sram_slow_wr=mode;tick(10);
        for(unsigned a:{0u,1u,2u,63u,1023u})eq("programoriginal",prog_read(a),be16(2*a));eq("programtail",prog_read((snd-2)/2),be16(snd-2));
        for(unsigned a:{0u,1u,255u,0x3ffffu})eq("soundoriginal",snd_read(a),image.at(snd+a));
        for(unsigned a:{0u,1u,511u,0x3fffffu})eq("PCMoriginal",pcm_read(a),image.at(pcm+a));
        for(unsigned a:{0u,1u,63u,101u}){burst(false,a);burst(true,a);}burst(false,(lens[2]/(mystic?5:4))-1);burst(true,(lens[4]/(mystic?10:8))-1);
        seed=0x550832;for(unsigned k=0;k<5;k++)for(unsigned j=0;j<12;j++){
            seed=seed*1664525u+1013904223u;unsigned unit=k==2?(mystic?5:4):(k==4?(mystic?10:8):2);unsigned a=((seed%(lens[k]-64))/unit)*unit;
            if(k==0)eq("randomprogram",prog_read(a/2),be16(a));if(k==1)eq("randomsound",snd_read(a),image.at(snd+a));if(k==2)burst(false,a/unit);if(k==3)eq("randomPCM",pcm_read(a),image.at(pcm+a));if(k==4)burst(true,a/unit);
        }
        unsigned x=be16(32),y=be16(34);vwrite(0x1234,x,3);vwrite(0x1234,y,2);eq("VRAMlanes",vread(0x1234),(y&0xff00)|(x&255));
        for(unsigned c=0;c<3;c++){cancel(false,c);cancel(true,c);}
        if(profile==3){for(unsigned c=0;c<3;c++)road_cancel(c);fairness();}
    }
    if(profile==3){
        // Exhaustively recover the complete original256KiBroad region in reverse
        // order through public64bit bursts, including bank/row/lastbyte boundaries.
        for(unsigned a=32768;a-->0;)road_burst(a);state_tests();
    }
    if(profile==0){load(map,4096);load(map+0x9fc00,1024);load(chr,256);load(chr+0x17ff80,128);tick(800);gaia_extra();}
    if(profile==3)printf("STATE_LATENCY read=%u..%u committed_write=%u..%u clocks\n",state_read_min,state_read_max,state_write_min,state_write_max);
    eq("SDRAMprotocol",d->sd_protocol_errors,0);
    printf("RESULT_JSON {\"passed\":%s,\"profile\":%u,\"errors\":%u,\"checks\":%u,\"cycles\":%llu,\"loaded_sample_bytes\":%u,\"cancellations\":%u,\"road_cancellations\":%u,\"road_bursts\":%u,\"road_checks\":%u,\"road_state_writes\":%u,\"psram_pin_commits\":%u,\"eeprom_bytes\":%u,\"physical_timing_qualified\":false}\n",errors?"false":"true",profile,errors,checks,(unsigned long long)clocks,loaded_bytes,cancellations,road_cancellations,road_bursts,road_checks,road_writes,ps_commits,eep_count);
    delete d;return errors?1:0;
}
