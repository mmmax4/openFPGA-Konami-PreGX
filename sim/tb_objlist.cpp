// Frozen-state bench for the K053247 object list.
//   tb_objlist <state.txt> <out.obj>
// Emits the same record format as render_model.py --dump-objlist so the two
// lists can be compared directly.
#include "Vtb_objlist_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>

static Vtb_objlist_top *dut;
static void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: %s <state.txt> <out.obj>\n", argv[0]); return 2; }

    std::map<std::string, std::vector<unsigned>> f;
    FILE *fp = fopen(argv[1], "r");
    if (!fp) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
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

    dut = new Vtb_objlist_top;
    dut->reset = 1; for (int i = 0; i < 8; i++) tick();
    dut->reset = 0;

    auto &sr = f["SPRITERAM"];
    for (size_t i = 0; i < sr.size() && i < 2048; i++) {
        dut->ram_we = 1; dut->ram_waddr = i; dut->ram_wdata = sr[i]; tick();
    }
    dut->ram_we = 0;

    // shadowon: a K054338 delta table is live only if some component exceeds +/-7
    auto &k38 = f["K38REGS"];
    unsigned shadowon = 0;
    for (int t = 0; t < 3; t++) {
        for (int c = 0; c < 3; c++) {
            int d = k38[2 + t * 3 + c] & 0x1ff;
            if (d >= 0x100) d -= 0x200;
            if (d < -7 || d > 7) { shadowon |= 1u << t; break; }
        }
    }
    auto &k55 = f["K55REGS"];
    dut->cfg_we = 1;
    dut->opset_i = f["K47REGS"][6];
    dut->objset1_i = f["K46REGS"][5] & 0xff;
    dut->shadowon_i = shadowon;
    dut->shdpri0_i = k55[37]; dut->shdpri1_i = k55[38]; dut->shdpri2_i = k55[39];
    tick(); dut->cfg_we = 0;

    dut->start = 1; tick(); dut->start = 0;
    long c = 0;
    while (!dut->done) { tick(); if (++c > 2000000) { fprintf(stderr, "objlist hung\n"); return 1; } }
    if (dut->overflow) { fprintf(stderr, "object list overflowed\n"); return 1; }
    long build_cycles = c;

    unsigned n = dut->count;
    std::vector<unsigned> orders(n);
    for (unsigned i = 0; i < n; i++) {
        dut->list_idx = i; tick(); tick();
        orders[i] = dut->list_q;
    }

    FILE *of = fopen(argv[2], "wb");
    if (!of) { fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
    fwrite(&n, 4, 1, of);
    fwrite(orders.data(), 4, n, of);
    fclose(of);
    printf("%u objects, %ld clocks (vblank budget ~245000)\n", n, build_cycles);
    delete dut;
    return 0;
}
