#!/bin/sh
# Full-system simulation: the whole machine from reset with the real program.
#   sim/run_system.sh <gaiapolis.rom> [frames] [out-name]
# Writes artifacts/system/<name>.rgb, .png and .trace.
# Environment: JOBS=n (parallel C++ compile jobs, default 8), SNAPEVERY=n (a PNG every n frames), AUDIO=1 (write <name>.wav),
# LAT=pocket (the Pocket memories' latencies) or LAT="+LAT_PROG=12 ..." verbatim,
# OBJ=dir (build directory, for parallel builds), PACE="-GSTEP_COST_BUS=n -GSTEP_COST_INT=m"
# (68000 pacing overrides for calibration against MAME), MEM=pocket (the Pocket
# memory subsystem, target/pocket/gaia_mem.sv, with behavioural chips in the
# loop instead of the ideal ROM ports; LAT is then ignored).
set -e
cd "$(dirname "$0")"
ROM="$1"; FRAMES="${2:-4}"; NAME="${3:-sys}"
[ -f "$ROM" ] || { echo "usage: $0 <gaiapolis.rom> [frames] [name]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac

case "${MEM:-}" in
    pocket) TOP="--top-module tb_pocket_top --prefix Vtb_system_top"; OBJ="${OBJ:-obj_pocket}"
            SRC="../target/pocket/gaia_mem.sv ../target/pocket/sdram_ctrl.sv ../target/pocket/psram.sv sdram_model.sv psram_model.sv sram_model.sv tb_pocket_top.sv"
            EXTRA="waivers_platform.vlt waivers_models.vlt -CFLAGS -DPOCKET_TOP" ;;
    *)      TOP="--top-module tb_system_top"; SRC="tb_system_top.sv"; EXTRA="" ;;
esac
verilator --cc --exe --build -j ${JOBS:-8} -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY \
    +1364-2005ext+v waivers.vlt $EXTRA $TOP -Mdir ${OBJ:-obj_system} ${PACE:-} \
    ../rtl/*.sv ../modules/cpu-tg68k/gen/tg68k.v ../modules/cpu-tv80/*.v $SRC tb_system.cpp \
    > ${OBJ:-obj_system}.log 2>&1 || { tail -30 ${OBJ:-obj_system}.log; exit 1; }

mkdir -p ../artifacts/system
# ZLOG is given relative to the repository root
case "${ZLOG:-}" in "") ;; /*) ;; *) ZLOG="../$ZLOG"; export ZLOG ;; esac
case "${LAT:-}" in
    pocket) LATARGS="+LAT_PROG=12 +LAT_TILE=12 +LAT_MAP=12 +LAT_SPR=14 +LAT_BLK=14 +LAT_SROM=12 +LAT_PCM=10 +LAT_VRAM=5" ;;
    *)      LATARGS="${LAT:-}" ;;
esac
./${OBJ:-obj_system}/Vtb_system_top "$ROM" "$FRAMES" ../artifacts/system/$NAME.rgb ../artifacts/system/$NAME.trace $LATARGS
# periodic frames (SNAPEVERY=n) become <name>.f<n>.png as well
for f in ../artifacts/system/$NAME.rgb.f*; do
    [ -f "$f" ] || continue
    python3 ../tools/rgb2png.py "$f" "${f%.rgb.f*}.f${f##*.f}.png" >/dev/null
done
python3 - <<PY
import sys, struct; sys.path.insert(0,'../tools')
import pngio
VIS_W,VIS_H=376,224
d=open('../artifacts/system/$NAME.rgb','rb').read(); buf=struct.unpack('<%dI'%(VIS_W*VIS_H), d)
w,h=VIS_H,VIS_W; out=bytearray(w*h*3)
for y in range(VIS_H):
    for x in range(VIS_W):
        v=buf[y*VIS_W+x]; o=(x*w+(VIS_H-1-y))*3
        out[o]=(v>>16)&0xff; out[o+1]=(v>>8)&0xff; out[o+2]=v&0xff
pngio.write('../artifacts/system/$NAME.png',w,h,out)
nz=sum(1 for v in buf if v)
print('wrote artifacts/system/$NAME.png  non-black pixels: %d (%.1f%%)'%(nz,100*nz/(VIS_W*VIS_H)))
PY
