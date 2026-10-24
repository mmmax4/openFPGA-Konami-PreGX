#!/bin/sh
# ER5911 gate: MAME's EEPROM pin traffic replayed through rtl/er5911.sv, every
# DO/READY read compared. Needs artifacts/system/mame_late.txt from
# tools/probe_late.lua (docs/hardware.md section 10).
#   sim/run_eeprom.sh <gaiapolis.rom> [mame_late.txt]
set -e
cd "$(dirname "$0")"
ROM="$1"; TRACE="${2:-../artifacts/system/mame_late.txt}"
[ -f "$ROM" ] || { echo "usage: $0 <gaiapolis.rom> [mame_late.txt]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
[ -f "$TRACE" ] || { echo "missing $TRACE: run tools/probe_late.lua under MAME first" >&2; exit 2; }

verilator --cc --exe --build -j "${JOBS:-1}" -O2 -Wall -Wno-DECLFILENAME \
    --top-module er5911 -Mdir obj_eeprom \
    ../rtl/er5911.sv tb_eeprom.cpp > obj_eeprom.log 2>&1 || { tail -30 obj_eeprom.log; exit 1; }
./obj_eeprom/Ver5911 "$ROM" "$TRACE"
