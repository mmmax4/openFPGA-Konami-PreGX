#!/bin/sh
# Pocket memory-subsystem gate: target/pocket/gaia_mem.sv with behavioural
# SDRAM, PSRAM and SRAM chips; samples of every ROM region through the
# download port and back through every core port, plus the tile RAM.
#   sim/run_mem.sh <gaiapolis.rom> [load gap in clocks, default 8 = the APF loader maximum]
set -e
cd "$(dirname "$0")"
ROM="$1"; [ -f "$ROM" ] || { echo "usage: $0 <gaiapolis.rom>" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
verilator --cc --exe --build -j ${JOBS:-8} -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Wno-UNOPTFLAT \
    waivers_platform.vlt waivers_models.vlt --top-module tb_mem_top -Mdir obj_mem \
    ../target/pocket/gaia_mem.sv ../target/pocket/sdram_ctrl.sv ../target/pocket/psram.sv \
    sdram_model.sv psram_model.sv sram_model.sv tb_mem_top.sv tb_mem.cpp > obj_mem.log 2>&1 || { tail -30 obj_mem.log; exit 1; }
./obj_mem/Vtb_mem_top "$ROM" ${2:-8} $3 $PLUS
