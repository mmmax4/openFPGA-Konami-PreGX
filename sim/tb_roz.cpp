// Frozen-state bench for the K053936 ROZ plane.
//   tb_roz <state.txt> <gaiapolis.rom> <out.roz>
#include "Vtb_roz_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>

static const int VIS_W = 376, VIS_H = 224, VIS_Y0 = 16;
static const long ROM_ROZCHAR = 0x0540000, ROZCHAR_LEN = 0x180000;
static const long ROM_ROZMAP  = 0x06C0000, ROZMAP_LEN  = 0x0A0000;

static Vtb_roz_top *dut;
static void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); }

static std::map<std::string, std::vector<unsigned>> load_state(const char *path) {
    std::map<std::string, std::vector<unsigned>> f;
    FILE *fp = fopen(path, "r");
    if (!fp) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    char *line = nullptr; size_t cap = 0;
    while (getline(&line, &cap, fp) > 0) {
        if (line[0] == '#') continue;
        char *save = nullptr;
        char *key = strtok_r(line, " \t\n", &save);
        if (!key || !strcmp(key, "VRAM")) continue;
        std::vector<unsigned> v; char *t;
        while ((t = strtok_r(nullptr, " \t\n", &save))) v.push_back((unsigned)strtoul(t, nullptr, 16));
        f[key] = v;
    }
    free(line); fclose(fp);
    return f;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: %s <state.txt> <rom> <out.roz>\n", argv[0]); return 2; }
    auto st = load_state(argv[1]);

    FILE *rf = fopen(argv[2], "rb");
    if (!rf) { fprintf(stderr, "cannot open %s\n", argv[2]); return 1; }
    std::vector<unsigned char> chr(ROZCHAR_LEN), mp(ROZMAP_LEN);
    fseek(rf, ROM_ROZCHAR, SEEK_SET);
    if (fread(chr.data(), 1, ROZCHAR_LEN, rf) != (size_t)ROZCHAR_LEN) { fprintf(stderr, "short read gfx3\n"); return 1; }
    fseek(rf, ROM_ROZMAP, SEEK_SET);
    if (fread(mp.data(), 1, ROZMAP_LEN, rf) != (size_t)ROZMAP_LEN) { fprintf(stderr, "short read gfx4\n"); return 1; }
    fclose(rf);

    dut = new Vtb_roz_top;
    dut->reset = 1; for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;

    auto &ct = st["ROZCT16"];
    for (int i = 0; i < 16; i++) { dut->ctrl_we = 1; dut->ctrl_addr = i; dut->ctrl_data = ct[i]; tick(); }
    dut->ctrl_we = 0;
    auto &cl = st["ROZCLIP"];
    for (int i = 0; i < 2; i++) { dut->clip_we = 1; dut->clip_addr = i; dut->clip_data = cl[i]; tick(); }
    dut->clip_we = 0;
    dut->cfg_we = 1;
    dut->roz_enable_i = (st["ROZCTRL"][0] >> 8) & 1;
    dut->palbase_i = st["K55REGS"][28] & 0xff;      // K55_PALBASE_SUB1
    tick(); dut->cfg_we = 0;

    // big-endian word order: byte 2n is the high half, matching the model
    for (long w = 0; w < ROZMAP_LEN / 2; w++) {
        dut->map_we = 1; dut->map_waddr = w;
        dut->map_wdata = ((unsigned)mp[w*2] << 8) | mp[w*2+1]; tick();
    }
    dut->map_we = 0;
    for (long w = 0; w < ROZCHAR_LEN / 2; w++) {
        dut->chr_we = 1; dut->chr_waddr = w;
        dut->chr_wdata = ((unsigned)chr[w*2] << 8) | chr[w*2+1]; tick();
    }
    dut->chr_we = 0;

    std::vector<unsigned short> out(VIS_H * VIS_W, 0xffff);
    long worst = 0; int min_lead = 99;
    auto render_line = [&](int raster_y) -> long {
        dut->line_start = 1; dut->line = raster_y; tick();
        dut->line_start = 0;
        long c = 0;
        while (dut->busy) { tick(); if (++c > 500000) { fprintf(stderr, "line %d hung\n", raster_y); exit(1); } }
        return c;
    };
    dut->prestart = 1; tick(); dut->prestart = 0;
    for (int k = 0; k < 5 * 512 * 12; k++) tick();     // five raster lines before the first pulse
    render_line(VIS_Y0);
    for (int y = 0; y < VIS_H; y++) {
        long c = render_line(VIS_Y0 + y + 1);
        if (c > worst) worst = c;
        if (y < VIS_H - 8 && dut->lead < min_lead) min_lead = dut->lead;
        for (int x = 0; x < VIS_W; x++) {
            // a 12-clock pixel as the display paces it (the run-ahead uses this time)
            dut->px = x; for (int k = 0; k < 12; k++) tick();
            out[y * VIS_W + x] = dut->opaque ? dut->pix : 0xffff;
        }
        for (int k = 0; k < (512 - VIS_W) * 12; k++) tick();    // the line's blanking
    }
    if (dut->unsupported) { fprintf(stderr, "RTL raised `unsupported`\n"); return 1; }

    FILE *of = fopen(argv[3], "wb");
    if (!of) { fprintf(stderr, "cannot write %s\n", argv[3]); return 1; }
    fwrite(out.data(), sizeof(unsigned short), out.size(), of);
    fclose(of);
    printf("rendered %d lines, worst wait %ld clocks past the pulse, lead min %d lines", VIS_H, worst, min_lead);
    printf("\n");
    delete dut;
    return 0;
}
