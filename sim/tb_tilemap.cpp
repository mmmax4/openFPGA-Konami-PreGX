// Frozen-state bench for the K056832 tilemap layers.
//
// Loads a state dumped by tools/dump_state.lua plus the built ROM image,
// renders every visible line through the RTL, and writes the four layers'
// palette indices so tools/diff_layers.py can compare them against the
// reference renderer (which is itself pixel-exact against MAME).
//
//   tb_tilemap <state.txt> <gaiapolis.rom> <out.layers>
#include "Vtb_tilemap_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>

static const int VIS_W = 376, VIS_H = 224, VIS_Y0 = 16;
static const long ROM_TILES = 0x0340000, ROM_TILES_LEN = 0x200000;

static Vtb_tilemap_top *dut;
static vluint64_t main_time = 0;

static void tick() {
    dut->clk = 0; dut->eval();
    dut->clk = 1; dut->eval();
    main_time++;
}

// --- state file -----------------------------------------------------------
struct State {
    std::map<std::string, std::vector<unsigned>> fields;
    std::vector<std::vector<unsigned>> vram;      // 17 pages
};

static bool load_state(const char *path, State &st) {
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); return false; }
    st.vram.resize(17);
    char *line = nullptr; size_t cap = 0; ssize_t n;
    while ((n = getline(&line, &cap, f)) > 0) {
        if (line[0] == '#') continue;
        char *save = nullptr;
        char *key = strtok_r(line, " \t\n", &save);
        if (!key) continue;
        std::vector<unsigned> vals;
        int page = -1;
        if (!strcmp(key, "VRAM")) {
            char *p = strtok_r(nullptr, " \t\n", &save);
            page = atoi(p);
        }
        char *tok;
        while ((tok = strtok_r(nullptr, " \t\n", &save)))
            vals.push_back((unsigned)strtoul(tok, nullptr, 16));
        if (page >= 0) st.vram[page] = vals;
        else st.fields[key] = vals;
    }
    free(line); fclose(f);
    return true;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: %s <state.txt> <rom> <out.layers>\n", argv[0]); return 2; }

    State st;
    if (!load_state(argv[1], st)) return 1;

    FILE *rf = fopen(argv[2], "rb");
    if (!rf) { fprintf(stderr, "cannot open %s\n", argv[2]); return 1; }
    std::vector<unsigned char> tiles(ROM_TILES_LEN);
    fseek(rf, ROM_TILES, SEEK_SET);
    if (fread(tiles.data(), 1, ROM_TILES_LEN, rf) != (size_t)ROM_TILES_LEN) {
        fprintf(stderr, "%s: short read of the tile region\n", argv[2]); return 1;
    }
    fclose(rf);

    dut = new Vtb_tilemap_top;
    dut->reset = 1;
    for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;

    // --- load registers, palette bases, tile RAM and tile ROM -------------
    auto &regs = st.fields["K56REGS"];
    for (size_t i = 0; i < regs.size() && i < 32; i++) {
        dut->reg_we = 1; dut->reg_addr = i; dut->reg_data = regs[i]; tick();
    }
    dut->reg_we = 0;

    // K055555 PALBASE_A..D are registers 23..26, shifted left 4 by the driver
    auto &k55 = st.fields["K55REGS"];
    for (int l = 0; l < 4; l++) {
        dut->cb_we = 1; dut->cb_addr = l; dut->cb_data = (k55[23 + l] << 4) & 0xff; tick();
    }
    dut->cb_we = 0;

    for (int page = 0; page < 16; page++) {
        auto &pg = st.vram[page];
        for (size_t i = 0; i < pg.size(); i++) {
            dut->vram_we = 1; dut->vram_waddr = (page << 12) | i; dut->vram_wdata = pg[i]; tick();
        }
    }
    dut->vram_we = 0;

    // rom_q[31:24] is the lowest of the four bytes, so pixel n is rom_q[31-4n-:4]
    for (long w = 0; w < ROM_TILES_LEN / 4; w++) {
        unsigned v = ((unsigned)tiles[w*4+0] << 24) | ((unsigned)tiles[w*4+1] << 16)
                   | ((unsigned)tiles[w*4+2] << 8)  |  (unsigned)tiles[w*4+3];
        dut->rom_we = 1; dut->rom_waddr = w; dut->rom_wdata = v; tick();
    }
    dut->rom_we = 0;

    // --- render ----------------------------------------------------------
    // The module double-buffers: line_start swaps banks and renders into the
    // new one while scan-out reads the other, so a completed line is only
    // readable after the *next* line_start. Prime with line 0, then for each y
    // start rendering y+1 and read y back.
    std::vector<unsigned short> out(4 * VIS_H * VIS_W, 0);
    long cycles_worst = 0;
    auto render_line = [&](int raster_y) -> long {
        dut->line_start = 1; dut->line = raster_y; tick();
        dut->line_start = 0;
        long c = 0;
        while (dut->busy) { tick(); if (++c > 200000) { fprintf(stderr, "line %d: hung\n", raster_y); exit(1); } }
        return c;
    };
    render_line(VIS_Y0);
    for (int y = 0; y < VIS_H; y++) {
        long c = render_line(VIS_Y0 + y + 1);
        if (c > cycles_worst) cycles_worst = c;
        for (int x = 0; x < VIS_W; x++) {
            dut->px = x; tick(); tick();     // registered read: two ticks to settle
            unsigned short o = dut->opaque;
            out[(0 * VIS_H + y) * VIS_W + x] = (o & 1) ? dut->pix0 : 0xffff;
            out[(1 * VIS_H + y) * VIS_W + x] = (o & 2) ? dut->pix1 : 0xffff;
            out[(2 * VIS_H + y) * VIS_W + x] = (o & 4) ? dut->pix2 : 0xffff;
            out[(3 * VIS_H + y) * VIS_W + x] = (o & 8) ? dut->pix3 : 0xffff;
        }
    }

    if (dut->unsupported) {
        fprintf(stderr, "RTL raised `unsupported`: this state uses a mode the module does not implement\n");
        return 1;
    }

    FILE *of = fopen(argv[3], "wb");
    if (!of) { fprintf(stderr, "cannot write %s\n", argv[3]); return 1; }
    fwrite(out.data(), sizeof(unsigned short), out.size(), of);
    fclose(of);
    printf("rendered %d lines, worst line %ld clocks (budget 6144)\n", VIS_H, cycles_worst);
    delete dut;
    return 0;
}
