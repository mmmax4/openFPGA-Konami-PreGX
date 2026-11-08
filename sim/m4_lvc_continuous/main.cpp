// Lead continuous-raster derivative, original snapshot/reference attribution retained.
// Adapted by /root/verify_metam 2026-11-06 for original-ROM and captured-page replay.
// Original upstream driver and reference attribution retained below; this is a separate fixture.
// K053250 bench driver: random ROM, line RAM and registers over every control byte;
// the RTL's picture is compared pixel for pixel with lvc_ref.h (MAME's k053250.cpp).
//
//   tb_lvc [+seed=N] [+cases=N] [+lat=N] [+ctrl=0xNN] [+slow=1]
//   +slow=1: scan the finished row out at the real pixel rate while a DMA delays the next row (the banks must hold)
#include "Vtb_lvc_top.h"
#include "verilated.h"
#include "lvc_ref.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <fstream>
#include <iterator>
#include <string>

static Vtb_lvc_top *dut;
static void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); }
static std::mt19937 rng;
static unsigned rnd(unsigned n) { return rng() % n; }
static unsigned total_late=0;

static void cpu_write(unsigned waddr, unsigned data) {
    dut->cpu_we = 1; dut->cpu_addr = waddr; dut->cpu_be = 3; dut->cpu_wdata = data; tick();
    dut->cpu_we = 0;
}
static void set_regs(const uint8_t *r) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v |= (uint64_t)r[i] << (8 * i);
    dut->regs_flat = v;
}
static long arg(const char *name, long dflt) {
    const char *s = Verilated::commandArgsPlusMatch(name);
    if (s && *s) { const char *eq = strchr(s, '='); if (eq) return strtol(eq + 1, nullptr, 0); }
    return dflt;
}

static std::string patharg(const char *name) {
 const char* s=Verilated::commandArgsPlusMatch(name);
 if(!s || !*s || !strchr(s,'=')){fprintf(stderr,"missing path arg %s\n",name);exit(2);}
 return strchr(s,'=')+1;
}
static std::vector<uint8_t> bytesfile(const std::string& p,size_t n){
 std::ifstream f(p,std::ios::binary);if(!f){fprintf(stderr,"open failed %s\n",p.c_str());exit(2);}
 std::vector<uint8_t> b{std::istreambuf_iterator<char>(f),{}};
 if(b.size()!=n){fprintf(stderr,"size mismatch %s\n",p.c_str());exit(2);}return b;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    long seed = arg("seed", 1), cases = arg("cases", 20), lat = arg("lat", 6), ctrl_force = arg("ctrl", -1);
    bool slow = arg("slow", 0) != 0;
    rng.seed((unsigned)seed);
    dut = new Vtb_lvc_top;
    dut->reset = 1; dut->lat = (uint8_t)lat;
    for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;
    for (int i = 0; i < 700; i++) tick();                 // the group cache clears its valid bits

    // the ROM: 256 KB, random bytes, but with runs of zero nibbles so transparency is exercised
    std::vector<uint8_t> rom(0x40000);
    for (auto &b : rom) { b = rnd(256); if (rnd(4) == 0) b &= 0x0f; if (rnd(5) == 0) b &= 0xf0; if (rnd(9) == 0) b = 0; }
    rom=bytesfile(patharg("rom"),0x40000);
    for (unsigned g = 0; g < 32768; g++) {
        uint64_t v = 0;
        for (int b = 0; b < 8; b++) v = (v << 8) | rom[g * 8 + b];
        dut->rom_wd = v; dut->rom_wa = g; dut->rom_we = 1; tick();
    }
    dut->rom_we = 0;

    LvcRef ref;
    ref.set_rom(rom.data(), rom.size());

    int total_bad = 0, total_px = 0;
    static const uint8_t ctrls[] = { 0x82, 0x87, 0x02, 0x07, 0x00, 0x06, 0x86, 0x8a, 0x8f, 0x92, 0x97, 0x9a, 0x9f,
                                     0x22, 0x27, 0x42, 0x47, 0xc2, 0xc7, 0x0a, 0x0f, 0x12, 0x17, 0x1a, 0x1f, 0xa2, 0xa7 };
    for (int c = 0; c < cases; c++) {
        uint8_t ctrl = ctrl_force >= 0 ? (uint8_t)ctrl_force : ctrls[rnd(sizeof ctrls)];
        // line RAM A (the picture's) and B (a later DMA's, which must not be drawn)
        static uint16_t A[0x800], B[0x800];
        for (int e = 0; e < 512; e++) {
            for (int which = 0; which < 2; which++) {
                uint16_t *w = (which ? B : A) + e * 4;
                unsigned kind = rnd(16);
                if (kind == 0) { w[0] = 0xffff; w[1] = rnd(65536); w[2] = rnd(65536); w[3] = rnd(65536); continue; }
                if (kind == 1) { w[0] = rnd(256) << 8; w[1] = 0; w[2] = 0x40; w[3] = rnd(65536); continue; }   // colour & 0xff == 0 && offset == 0
                w[0] = (rnd(256) & 0xe0) << 0 | rnd(32) | (rnd(4) << 8);
                if ((w[0] & 0xff) == 0 && rnd(2)) w[0] |= 1;
                w[1] = rnd(0x7f0) | (rnd(8) == 0 ? (rnd(32) << 11) : 0);        // offsets past 0x7ff wrap (% size)
                switch (rnd(8)) {
                    case 0: w[2] = 0; break;
                    case 1: w[2] = 1 + rnd(31); break;
                    case 2: case 3: case 4: w[2] = 0x20 + rnd(0x40); break;       // around 1:1
                    case 5: w[2] = 0x60 + rnd(0x80); break;
                    case 6: w[2] = rnd(0x400); break;
                    default: w[2] = rnd(65536); break;
                }
                switch (rnd(6)) {
                    case 0: w[3] = (uint16_t)(rnd(0x700) - 0x100); break;
                    case 1: w[3] = 0x500 + rnd(0x300); break;                      // the wrap-at-0x500 range
                    case 2: w[3] = (uint16_t)(-(int)rnd(0x400)); break;
                    case 3: w[3] = rnd(65536); break;
                    default: w[3] = rnd(0x200); break;
                }
            }
        }
        uint8_t regs[8];
        regs[0] = rnd(256); regs[1] = rnd(256); regs[2] = rnd(256); regs[3] = rnd(256);
        if (rnd(3) == 0) { regs[0] = 0; regs[1] = rnd(64); regs[2] = 0; regs[3] = rnd(64); }
        regs[4] = ctrl; regs[5] = rnd(256); regs[6] = rnd(256); regs[7] = rnd(256);

        // Reconstruct the captured selected DMA page through public CPU writes and two DMAs.
        // This replays exact captured page/register bytes, not the original CPU timing.
        auto ram=bytesfile(patharg("ram"),0x6000);
        auto captured_regs=bytesfile(patharg("regs"),8);
        auto page=bytesfile(patharg("page"),1);
        if(page[0]>1)return 2;
        for(int i=0;i<0x800;i++){
         unsigned a=0x4000+page[0]*0x1000+2*i;
         unsigned b=0x4000+(page[0]^1)*0x1000+2*i;
         A[i]=ram[a]|(unsigned(ram[a+1])<<8);
         B[i]=ram[b]|(unsigned(ram[b+1])<<8);
        }
        memcpy(regs,captured_regs.data(),8); ctrl=regs[4];
        // DMA #1 with A: bit 1 of register 4 high, then low; a frame later DMA #2 with B
        dut->frame_tick = 1; tick(); dut->frame_tick = 0;
        uint8_t r1[8]; memcpy(r1, regs, 8); r1[4] = ctrl | 2;
        set_regs(r1);
        for (int i = 0; i < 0x800; i++) cpu_write(i, A[i]);
        for (int i = 0; i < 4; i++) tick();
        regs[4] = ctrl & ~2; set_regs(regs);
        for (int i = 0; i < 4; i++) tick();
        if (!dut->dma_busy) { fprintf(stderr, "case %d: the DMA did not hold the 68000\n", c); return 1; }
        for (int n = 0; n < 4000 && dut->dma_busy; n++) tick();
        dut->frame_tick = 1; tick(); dut->frame_tick = 0;
        for (int i = 0; i < 0x800; i++) cpu_write(i, B[i]);
        // an extra write outside the DMA'd words must be harmless
        cpu_write(0x1000 + rnd(0x1000), rnd(65536));
        regs[4] = ctrl | 2; set_regs(regs); for (int i = 0; i < 4; i++) tick();
        regs[4] = ctrl & ~2; set_regs(regs); for (int i = 0; i < 4; i++) tick();
        for (int n = 0; n < 4000 && dut->dma_busy; n++) tick();
        // the picture's instant
        regs[4] = ctrl; set_regs(regs);
        for (int i = 0; i < 4; i++) tick();
        dut->latch = 1; tick(); dut->latch = 0;
        long n = 0;
        for(n=0;n<6000;n++)tick(); // fixed vblank budget for picture latch/table
        dut->palbase = rnd(256);

        // the reference, drawn from A with the registers as latched
        memcpy(ref.regs, regs, 8);
        for (int i = 0; i < 0x800; i++) ref.line_ram[i] = A[i];
        ref.draw();
        unsigned active_desc=0,ref_opaque=0;
        for(unsigned i=0;i<512;i++)if(A[4*i]!=0xffff && ((A[4*i]&255)||A[4*i+1]))active_desc++;
        for(auto v:ref.bitmap)if(v)ref_opaque++;
        printf("ORIGINAL_SNAPSHOT page%u ctrl%02x active_descriptors%u reference_opaque%u\n",page[0],ctrl,active_desc,ref_opaque);


        if (arg("dbg", 0)) {
            int msx = (int16_t)(regs[0] << 8 | regs[1]) + 7, msy = (int16_t)(regs[2] << 8 | regs[3]);
            printf("REF ctrl %02x msx %d msy %d\n", ctrl, msx, msy);
            for (int yy = 15; yy < 17; yy++) {
                int e = (msy + ((ctrl & 0x10) ? 238 - (yy - 0) : yy)) & 0x1ff;
                printf("REF row %d entry %d: %04x %04x %04x %04x  first pixels:", yy, e, A[e*4], A[e*4+1], A[e*4+2], A[e*4+3]);
                for (int xx = 24; xx < 30; xx++) printf(" %03x", ref.bitmap[yy * ref.W() + xx]);
                printf("\n  rom nibbles from block %03x idx 206..215:", A[e*4+1] & 0x7ff);
                for (int k = 206; k < 216; k++) printf(" %x", ref.unpacked[((A[e*4+1] & 0x7ff) << 8) + k]);
                printf("\n");
            }
        }
        int bad=0;unsigned late=0;
        // Forecast row0 during vblank, then run exactly384*16clocks per row.
        // Both old and new get the same eight-line initial warmup; no waits
        // for renderer completion are allowed during the visible picture.
        dut->line=17;dut->line_start=1;tick();dut->line_start=0;
        for(unsigned t=1;t<8*6144;t++)tick();
        for(unsigned y=0;y<224;y++){
            if(dut->row_busy)late++;
            dut->line=18+y;dut->line_start=1;tick();dut->line_start=0;
            for(unsigned t=1;t<6144;t++){
                unsigned h=t/16;
                if(t%16==0)dut->px=(h>=24&&h<312)?h-24:0;
                tick();
                if(t%16==15&&h>=24&&h<312){
                    unsigned x=h-24,want=ref.bitmap[(15+y)*ref.W()+24+x];
                    bool wop=want!=0,op=dut->opaque;unsigned pe=dut->pix;
                    unsigned wpe=((dut->palbase<<8)+(want&0x1ff))&0x7ff;
                    total_px++;
                    if(op!=wop||(op&&pe!=wpe)){
                        if(bad<4)fprintf(stderr,"CONTINUOUS pixel mismatch row%u x%u got%03x op%d want%03x op%d\n",y,x,pe,op,wpe,wop);
                        bad++;
                    }
                }
            }
        }
        total_late+=late;
        printf("CONTINUOUS_JSON {\"control\":%u,\"pixel_errors\":%u,\"pixels_compared\":64512,\"deadline_checks\":224,\"deadline_failures\":%u,\"line_clocks\":6144,\"warmup_clocks\":49152}\n",ctrl,bad,late);
        total_bad += bad;

    }
    printf("%d pixels compared, %d differ\n", total_px, total_bad);
    delete dut;
    return (total_bad || total_late) ? 1 : 0;
}
