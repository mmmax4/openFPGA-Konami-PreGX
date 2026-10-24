// Full-frame bench: every video block plus the mixer, one whole frame from a
// frozen state, out as RGB for comparison against render_model.py --dump-rgb.
//
//   tb_frame <state.txt> <gaiapolis.rom> <zoom.hex> <recip.hex> <out.rgb>
#include "Vtb_frame_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>

static const int VIS_W = 376, VIS_H = 224, VIS_Y0 = 16;
static const long ROM_TILES = 0x0340000, TILES_LEN = 0x200000;
static const long ROM_ROZCHAR = 0x0540000, ROZCHAR_LEN = 0x180000;
static const long ROM_ROZMAP = 0x06C0000, ROZMAP_LEN = 0x0A0000;
static const long ROM_SPRITES = 0x0B60000, SPRITES_LEN = 0x800000;

static Vtb_frame_top *dut;
static void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); }

struct State {
    std::map<std::string, std::vector<unsigned>> f;
    std::vector<std::vector<unsigned>> vram;
};

static State load_state(const char *path) {
    State st; st.vram.resize(17);
    FILE *fp = fopen(path, "r");
    if (!fp) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    char *line = nullptr; size_t cap = 0;
    while (getline(&line, &cap, fp) > 0) {
        if (line[0] == '#') continue;
        char *save = nullptr;
        char *key = strtok_r(line, " \t\n", &save);
        if (!key) continue;
        int page = -1;
        if (!strcmp(key, "VRAM")) page = atoi(strtok_r(nullptr, " \t\n", &save));
        std::vector<unsigned> v; char *t;
        while ((t = strtok_r(nullptr, " \t\n", &save))) v.push_back((unsigned)strtoul(t, nullptr, 16));
        if (page >= 0) st.vram[page] = v; else st.f[key] = v;
    }
    free(line); fclose(fp);
    return st;
}

static std::vector<unsigned> load_hex(const char *path) {
    std::vector<unsigned> v; char buf[64];
    FILE *fp = fopen(path, "r");
    if (!fp) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    while (fgets(buf, sizeof buf, fp)) v.push_back((unsigned)strtoul(buf, nullptr, 16));
    fclose(fp); return v;
}

static std::vector<unsigned char> load_region(FILE *rf, long off, long len, const char *what) {
    std::vector<unsigned char> d(len);
    fseek(rf, off, SEEK_SET);
    if (fread(d.data(), 1, len, rf) != (size_t)len) { fprintf(stderr, "short read of %s\n", what); exit(1); }
    return d;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 6) { fprintf(stderr, "usage: %s <state.txt> <rom> <zoom.hex> <recip.hex> <out.rgb>\n", argv[0]); return 2; }
    State st = load_state(argv[1]);
    FILE *rf = fopen(argv[2], "rb");
    if (!rf) { fprintf(stderr, "cannot open %s\n", argv[2]); return 1; }
    auto tiles = load_region(rf, ROM_TILES, TILES_LEN, "tiles");
    auto rchr  = load_region(rf, ROM_ROZCHAR, ROZCHAR_LEN, "gfx3");
    auto rmap  = load_region(rf, ROM_ROZMAP, ROZMAP_LEN, "gfx4");
    auto spr   = load_region(rf, ROM_SPRITES, SPRITES_LEN, "sprites");
    fclose(rf);
    auto zoomtab = load_hex(argv[3]), reciptab = load_hex(argv[4]);

    dut = new Vtb_frame_top;
    dut->reset = 1; for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;

    auto &k56 = st.f["K56REGS"]; auto &k55 = st.f["K55REGS"]; auto &k38 = st.f["K38REGS"];
    auto &k46 = st.f["K46REGS"]; auto &k47 = st.f["K47REGS"];
    for (int i = 0; i < 32; i++) { dut->k56_we = 1; dut->k56_addr = i; dut->k56_data = k56[i]; tick(); }
    dut->k56_we = 0;
    for (int i = 0; i < 48; i++) { dut->k55_we = 1; dut->k55_addr = i; dut->k55_data = k55[i] & 0xff; tick(); }
    dut->k55_we = 0;
    for (int i = 0; i < 16; i++) { dut->k38_we = 1; dut->k38_addr = i; dut->k38_data = k38[i]; tick(); }
    dut->k38_we = 0;
    auto &ct = st.f["ROZCT16"];
    for (int i = 0; i < 16; i++) { dut->rozc_we = 1; dut->rozc_addr = i; dut->rozc_data = ct[i]; tick(); }
    dut->rozc_we = 0;
    auto &cl = st.f["ROZCLIP"];
    for (int i = 0; i < 2; i++) { dut->clip_we = 1; dut->clip_addr = i; dut->clip_data = cl[i]; tick(); }
    dut->clip_we = 0;
    dut->cfg_we = 1;
    dut->roz_enable_i = (st.f["ROZCTRL"][0] >> 8) & 1;
    dut->opset_i = k47[6];
    dut->k46r5_i = k46[5] & 0xff;
    dut->k46offx_i = ((k46[0] & 0xff) << 8) | (k46[1] & 0xff);
    dut->k46offy_i = ((k46[2] & 0xff) << 8) | (k46[3] & 0xff);
    tick(); dut->cfg_we = 0;

    for (int page = 0; page < 16; page++)
        for (size_t i = 0; i < st.vram[page].size(); i++) {
            dut->vram_we = 1; dut->vram_waddr = (page << 12) | i; dut->vram_wdata = st.vram[page][i]; tick();
        }
    dut->vram_we = 0;
    auto &pal = st.f["PALETTE"];
    for (int i = 0; i < 2048; i++) {
        dut->pal_we = 1; dut->pal_waddr = i;
        dut->pal_wdata = ((pal[i*2] & 0xff) << 16) | pal[i*2+1]; tick();
    }
    dut->pal_we = 0;
    auto &sr = st.f["SPRITERAM"];
    for (size_t i = 0; i < sr.size() && i < 2048; i++) { dut->sram_we = 1; dut->sram_waddr = i; dut->sram_wdata = sr[i]; tick(); }
    dut->sram_we = 0;
    for (long w = 0; w < TILES_LEN / 4; w++) {
        dut->trom_we = 1; dut->trom_waddr = w;
        dut->trom_wdata = ((unsigned)tiles[w*4] << 24) | ((unsigned)tiles[w*4+1] << 16)
                        | ((unsigned)tiles[w*4+2] << 8) | tiles[w*4+3];
        tick();
    }
    dut->trom_we = 0;
    for (long w = 0; w < ROZMAP_LEN / 2; w++) { dut->mrom_we = 1; dut->mrom_waddr = w; dut->mrom_wdata = ((unsigned)rmap[w*2] << 8) | rmap[w*2+1]; tick(); }
    dut->mrom_we = 0;
    for (long w = 0; w < ROZCHAR_LEN / 2; w++) { dut->crom_we = 1; dut->crom_waddr = w; dut->crom_wdata = ((unsigned)rchr[w*2] << 8) | rchr[w*2+1]; tick(); }
    dut->crom_we = 0;
    for (long w = 0; w < SPRITES_LEN / 8; w++) {
        unsigned long long v = 0;
        for (int b = 0; b < 8; b++) v = (v << 8) | spr[w*8+b];
        dut->srom_we = 1; dut->srom_waddr = w; dut->srom_wdata = v; tick();
    }
    dut->srom_we = 0;
    for (size_t i = 0; i < zoomtab.size(); i++) { dut->tab_we = 1; dut->tab_sel = 0; dut->tab_waddr = i; dut->tab_wdata = zoomtab[i]; tick(); }
    for (size_t i = 0; i < reciptab.size(); i++) { dut->tab_we = 1; dut->tab_sel = 1; dut->tab_waddr = i; dut->tab_wdata = reciptab[i]; tick(); }
    dut->tab_we = 0;

    // build the object list, as the vblank pass would
    dut->build = 1; tick(); dut->build = 0;
    long c = 0;
    while (!dut->build_done) { tick(); if (++c > 2000000) { fprintf(stderr, "objlist hung\n"); return 1; } }

    std::vector<unsigned> out(VIS_H * VIS_W, 0);
    long worst = 0, worst_tm = 0, worst_roz = 0, worst_dr = 0;
    int min_lead = 99;
    auto render_line = [&](int raster_y) -> long {
        dut->line_start = 1; dut->line = raster_y; tick(); dut->line_start = 0;
        long n = 0;
        long n_tm = 0, n_roz = 0, n_dr = 0;
        while (dut->busy) {
            tick(); if (++n > 2000000) { fprintf(stderr, "line %d hung\n", raster_y); exit(1); }
            if (dut->busy_src & 4) n_tm = n; if (dut->busy_src & 2) n_roz = n; if (dut->busy_src & 1) n_dr = n;
        }
        if (n_tm > worst_tm) worst_tm = n_tm; if (n_roz > worst_roz) worst_roz = n_roz; if (n_dr > worst_dr) worst_dr = n_dr;
        return n;
    };
    // the frame's pre-start, as gaia_video gives it a few raster lines early
    dut->prestart = 1; tick(); dut->prestart = 0;
    for (int k = 0; k < 5 * 512 * 12; k++) tick();     // five raster lines before the first pulse
    render_line(VIS_Y0);
    for (int y = 0; y < VIS_H; y++) {
        long n = render_line(VIS_Y0 + y + 1);
        if (n > worst) worst = n;
        // after the wait: lines in hand beyond the one due (1 = just in time); the
        // frame's last lines are left out, there is nothing left to run ahead into
        if (y < VIS_H - 8 && dut->roz_lead < min_lead) min_lead = dut->roz_lead;
        for (int x = 0; x < VIS_W; x++) {
            // a 12-clock pixel as gaia_video paces it: px changes on the tick,
            // the encoder and colour stages latch at fixed phases after it
            dut->px = x; dut->cen_pix = 1; tick(); dut->cen_pix = 0;
            for (int k = 0; k < 11; k++) tick();
            out[y * VIS_W + x] = dut->rgb;
        }
        for (int k = 0; k < (512 - VIS_W) * 12; k++) tick();    // the line's blanking: 6144 clocks a line in all
    }
    if (dut->unsupported) { fprintf(stderr, "RTL raised `unsupported` (or the object list overflowed)\n"); return 1; }
    if (dut->shadow_overlap) fprintf(stderr, "warning: a pixel was shadowed twice\n");

    FILE *of = fopen(argv[5], "wb");
    if (!of) { fprintf(stderr, "cannot write %s\n", argv[5]); return 1; }
    fwrite(out.data(), 4, out.size(), of); fclose(of);
    printf("worst line %ld clocks (budget 6144; tilemap %ld, ROZ %ld late, sprites %ld); ROZ lead min %d\n", worst, worst_tm, worst_roz, worst_dr, min_lead);
    delete dut;
    return 0;
}
