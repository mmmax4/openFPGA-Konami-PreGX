#!/bin/sh
# The pixel-phase pin (rtl/clk_enables.sv pix_sync, target/pocket/core_top.sv):
# with the 8 MHz video clock rising half a system cycle after a system edge,
# cen_8m and the mixer's colour latch must fall where the hand-over counts on.
set -e
cd "$(dirname "$0")"
verilator --cc --exe --build -j "${JOBS:-1}" -Wall -Wno-DECLFILENAME --top-module tb_pixsync_top -Mdir obj_pixsync \
    ../rtl/clk_enables.sv tb_pixsync_top.sv tb_pixsync.cpp > obj_pixsync.log 2>&1 || { tail -20 obj_pixsync.log; exit 1; }
./obj_pixsync/Vtb_pixsync_top
