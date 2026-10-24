// Frozen-state bench for the K053247 sprite path (object list + rasterizer).
//
// Resolves the line buffer the way the reference renderer composites: palette
// lookup for solid pixels, backdrop elsewhere, then the K054338 shadow table
// where the shadow flag is set. Output is RGB so it can be compared against
// render_model.py --dump-obj-rgb directly.
//
//   tb_sprite <state.txt> <gaiapolis.rom> <zoom.hex> <recip.hex> <out.rgb>
#include "Vtb_sprite_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>

static const int VIS_W = 376, VIS_H = 224, VIS_Y0 = 16;
static const long ROM_SPRITES = 0x0B60000, SPRITES_LEN = 0x800000;

static Vtb_sprite_top *dut;
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

static std::vector<unsigned> load_hex(const char *path) {
    std::vector<unsigned> v;
    FILE *fp = fopen(path, "r");
    if (!fp) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    char buf[64];
    while (fgets(buf, sizeof buf, fp)) v.push_back((unsigned)strtoul(buf, nullptr, 16));
    fclose(fp);
    return v;
}

static inline int clamp8(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }
static inline int pal5(int b) { b &= 0x1f; return (b << 3) | (b >> 2); }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 6) {
        fprintf(stderr, "usage: %s <state.txt> <rom> <zoom.hex> <recip.hex> <out.rgb>\n", argv[0]);
        return 2;
    }
    auto st = load_state(argv[1]);

    FILE *rf = fopen(argv[2], "rb");
    if (!rf) { fprintf(stderr, "cannot open %s\n", argv[2]); return 1; }
    std::vector<unsigned char> spr(SPRITES_LEN);
    fseek(rf, ROM_SPRITES, SEEK_SET);
    if (fread(spr.data(), 1, SPRITES_LEN, rf) != (size_t)SPRITES_LEN) {
        fprintf(stderr, "short read of the sprite region\n"); return 1;
    }
    fclose(rf);
    auto zoomtab = load_hex(argv[3]);
    auto reciptab = load_hex(argv[4]);

    dut = new Vtb_sprite_top;
    dut->reset = 1; for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;

    auto &sr = st["SPRITERAM"];
    for (size_t i = 0; i < sr.size() && i < 2048; i++) {
        dut->ram_we = 1; dut->ram_waddr = i; dut->ram_wdata = sr[i]; tick();
    }
    dut->ram_we = 0;

    // rom_q[63:56] is the lowest byte of the eight
    for (long w = 0; w < SPRITES_LEN / 8; w++) {
        unsigned long long v = 0;
        for (int b = 0; b < 8; b++) v = (v << 8) | spr[w * 8 + b];
        dut->rom_we = 1; dut->rom_waddr = w; dut->rom_wdata = v; tick();
    }
    dut->rom_we = 0;

    for (size_t i = 0; i < zoomtab.size(); i++) {
        dut->tab_we = 1; dut->tab_sel = 0; dut->tab_waddr = i; dut->tab_wdata = zoomtab[i]; tick();
    }
    for (size_t i = 0; i < reciptab.size(); i++) {
        dut->tab_we = 1; dut->tab_sel = 1; dut->tab_waddr = i; dut->tab_wdata = reciptab[i]; tick();
    }
    dut->tab_we = 0;

    auto &k38 = st["K38REGS"];
    auto &k55 = st["K55REGS"];
    auto &k46 = st["K46REGS"];
    int shd[3][3];
    unsigned shadowon = 0;
    for (int t = 0; t < 3; t++) {
        bool on = false;
        for (int c = 0; c < 3; c++) {
            int d = k38[2 + t * 3 + c] & 0x1ff;
            if (d >= 0x100) d -= 0x200;
            shd[t][c] = d;
            if (d < -7 || d > 7) on = true;
        }
        if (on) shadowon |= 1u << t;
    }
    bool noclip = (k38[15] & 0x20) != 0;

    dut->cfg_we = 1;
    dut->opset_i = st["K47REGS"][6];
    dut->objset1_i = k46[5] & 0xff;
    dut->shadowon_i = shadowon;
    dut->shdpri0_i = k55[37]; dut->shdpri1_i = k55[38]; dut->shdpri2_i = k55[39];
    dut->k46r5_i = k46[5] & 0xff;
    dut->k46offx_i = ((k46[0] & 0xff) << 8) | (k46[1] & 0xff);
    dut->k46offy_i = ((k46[2] & 0xff) << 8) | (k46[3] & 0xff);
    dut->colorbase_i = (k55[27] << 4) & 0x7f;      // sprite_colorbase
    tick(); dut->cfg_we = 0;

    dut->build = 1; tick(); dut->build = 0;
    long c = 0;
    while (!dut->build_done) { tick(); if (++c > 2000000) { fprintf(stderr, "objlist hung\n"); return 1; } }
    if (dut->overflow) { fprintf(stderr, "object list overflowed\n"); return 1; }

    auto &pal = st["PALETTE"];
    unsigned backdrop = ((k38[0] & 0xff) << 16) | k38[1];

    std::vector<unsigned> out(VIS_H * VIS_W, backdrop);
    long worst = 0;
    auto render_line = [&](int raster_y) -> long {
        dut->line_start = 1; dut->line = raster_y; tick();
        dut->line_start = 0;
        long n = 0;
        while (dut->busy) { tick(); if (++n > 2000000) { fprintf(stderr, "line %d hung\n", raster_y); exit(1); } }
        return n;
    };
    render_line(VIS_Y0);
    for (int y = 0; y < VIS_H; y++) {
        long n = render_line(VIS_Y0 + y + 1);
        if (n > worst) worst = n;
        for (int x = 0; x < VIS_W; x++) {
            dut->px = x; tick(); tick();
            unsigned rgb = backdrop;
            if (dut->out_opaque) {
                unsigned idx = dut->out_pen & 0x7ff;
                rgb = ((pal[idx * 2] & 0xff) << 16) | pal[idx * 2 + 1];
            }
            if (dut->out_shadow) {
                unsigned t = dut->out_shtab;
                int dr, dg, db;
                if (t == 3) { dr = dg = db = -80; }
                else { dr = shd[t][0]; dg = shd[t][1]; db = shd[t][2]; }
                int r = pal5((rgb >> 19) & 0x1f) + dr;
                int g = pal5((rgb >> 11) & 0x1f) + dg;
                int b = pal5((rgb >> 3) & 0x1f) + db;
                if (!noclip) { r = clamp8(r); g = clamp8(g); b = clamp8(b); }
                else { r &= 0xff; g &= 0xff; b &= 0xff; }
                rgb = (r << 16) | (g << 8) | b;
            }
            out[y * VIS_W + x] = rgb;
        }
    }
    if (dut->shadow_overlap)
        fprintf(stderr, "warning: a pixel was shadowed twice; the flag scheme loses one\n");

    FILE *of = fopen(argv[5], "wb");
    if (!of) { fprintf(stderr, "cannot write %s\n", argv[5]); return 1; }
    fwrite(out.data(), 4, out.size(), of);
    fclose(of);
    printf("%u objects, worst line %ld clocks (budget 6144)"
       " [objs=%u rows=%u cols=%u pxw=%u]\n",
       (unsigned)dut->count, worst,
       (unsigned)dut->dbg_objs, (unsigned)dut->dbg_rows,
       (unsigned)dut->dbg_cols, (unsigned)dut->dbg_pxw);
    delete dut;
    return 0;
}
