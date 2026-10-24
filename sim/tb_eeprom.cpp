// ER5911 gate: replay MAME's EEPROM pin traffic (tools/probe_late.lua) through
// rtl/er5911.sv and compare DO/READY with what the 68000 read in MAME.
//   tb_eeprom <gaiapolis.rom> <mame_late.txt>
#include "Ver5911.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

static Ver5911 *dut;
static void tick(int n = 1) { while (n--) { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); } }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: %s <rom> <mame_late.txt>\n", argv[0]); return 2; }
    FILE *rf = fopen(argv[1], "rb");
    if (!rf) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
    unsigned char eep[128];
    fseek(rf, 0x1360000, SEEK_SET);
    if (fread(eep, 1, 128, rf) != 128) { fprintf(stderr, "short rom\n"); return 1; }
    fclose(rf);

    dut = new Ver5911;
    // the image loads while the part is held in reset, as the system bench
    // and the Pocket do it
    dut->reset = 1; dut->cs = 0; dut->sclk = 0; dut->di = 0; dut->ld_we = 0;
    tick(4);
    for (int i = 0; i < 128; i++) { dut->ld_we = 1; dut->ld_addr = i; dut->ld_wdata = eep[i]; tick(); }
    dut->ld_we = 0; tick(4);
    dut->reset = 0; tick(4);

    FILE *tf = fopen(argv[2], "r");
    if (!tf) { fprintf(stderr, "cannot open %s\n", argv[2]); return 1; }
    char line[128]; unsigned reads = 0, bad = 0;
    while (fgets(line, sizeof line, tf)) {
        int frame; char kind[4]; unsigned addr, val;
        if (sscanf(line, "%d %3s %x %x", &frame, kind, &addr, &val) != 4) continue;
        if (kind[0] == 'W' && addr == 0x6a0000) {
            dut->di = val & 1; dut->cs = (val >> 1) & 1; dut->sclk = (val >> 2) & 1;
            tick(24);                                   // a few 68000 bus cycles apart
        } else if (kind[0] == 'R' && addr == 0x48e020) {
            if ((val >> 8) == 0) continue;              // low-byte access: the P2 port
            reads++;
            int mdo = (val >> 8) & 1, mrdy = (val >> 9) & 1;
            if (mdo != dut->dout || mrdy != dut->ready) {
                bad++;
                if (bad <= 10) printf("mismatch #%u read %u frame %d: mame do=%d rdy=%d rtl do=%d rdy=%d\n",
                                      bad, reads, frame, mdo, mrdy, (int)dut->dout, (int)dut->ready);
            }
        }
    }
    fclose(tf);
    printf("%u reads, %u mismatches\n", reads, bad);
    delete dut;
    return bad ? 1 : 0;
}
