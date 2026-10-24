#include "Vtb_pixsync_top.h"
#include "verilated.h"
#include <cstdio>
// half-steps of the 96 MHz clock: clk rises on even steps; clk_vid rises on an
// odd step (half a cycle after a system edge) every 24 half-steps
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_pixsync_top *d = new Vtb_pixsync_top;
    d->reset = 1; d->clk = 0; d->clk_vid = 0;
    int last_vid_edge_cycle = -1, cycle = 0, errors = 0, checks = 0;
    for (int step = 0; step < 24 * 400; step++) {
        bool rise = (step % 2) == 0;
        d->clk = rise; if (rise) cycle++;
        if (step % 24 == 7) d->clk_vid = 1; if (step % 24 == 19) d->clk_vid = 0;   // rising edge at step 7: half a cycle after edge 3
        if (step == 24 * 5 + 3) d->reset = 0;                                       // release at an odd, unrelated moment
        d->eval();
        if (step % 24 == 7) last_vid_edge_cycle = cycle;                          // the system edge just before it
        if (rise && step > 24 * 50) {
            // after settling, with E the system edge half a cycle before a clk_vid edge: cen_8m is high in the
            // cycle E+11 (one before the next E), and the mixer's phase-9 cycle is E+9, so its colour register
            // updates at edge E+10 -- two clocks and a half before the clk_vid edge at E+12.5 that samples it
            int rel = cycle - last_vid_edge_cycle;         // 0 in the cycle that starts at E
            if (d->cen_8m)  { checks++; if (rel != 11) { errors++; if (errors < 5) printf("cen_8m at E+%d (expect 11)\n", rel); } }
            if (d->cen_rgb) { checks++; if (rel != 9)  { errors++; if (errors < 5) printf("colour latch cycle at E+%d (expect 9)\n", rel); } }
        }
    }
    printf("%s: %d checks, %d errors\n", errors ? "FAIL" : "PASS", checks, errors);
    delete d; return errors ? 1 : 0;
}
