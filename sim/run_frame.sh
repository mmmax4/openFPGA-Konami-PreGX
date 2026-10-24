#!/bin/sh
# Full-frame gate: every video block plus the mixer, one whole frame per state,
# diffed as RGB against the reference renderer's complete composite. The model
# is run with --roz-exact: it otherwise reproduces MAME's one-line ROZ shift,
# which the RTL deliberately does not (see rtl/k053936_roz.sv).
#   sim/run_frame.sh <gaiapolis.rom> [state-name ...]
# LATARGS="+LAT_VRAM=5 +LAT_TROM=12 +LAT_MROM=12 +LAT_SROM=14 +LAT_BLK=14" models
# the Pocket memories' latencies (default: every memory answers the clock after).
set -e
cd "$(dirname "$0")"
ROM="$1"; shift
[ -f "$ROM" ] || { echo "usage: $0 <gaiapolis.rom> [state ...]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac

verilator --cc --exe --build -j ${JOBS:-1} -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    --top-module tb_frame_top -Mdir obj_frame \
    ../rtl/k056832_tilemap.sv ../rtl/k053936_roz.sv ../rtl/k053247_objlist.sv \
    ../rtl/pregx_sprite_line_queue.sv ../rtl/pregx_sprite_word_cache.sv ../rtl/k053247_draw.sv ../rtl/k055555_mixer.sv tb_frame_top.sv tb_frame.cpp \
    > obj_frame.log 2>&1 || { tail -30 obj_frame.log; exit 1; }

mkdir -p ../artifacts/rtl
if [ $# -gt 0 ]; then names="$@"; else
    names=$(cd ../artifacts/states && ls *.txt | sed 's/\.txt$//' \
            | grep -vE '_(tm|obj|roz|[A-D])$')
fi
fail=0
for n in $names; do
    printf '%-16s ' "$n"
    ./obj_frame/Vtb_frame_top ../artifacts/states/$n.txt "$ROM" \
        ../rtl/data/zoom.hex ../rtl/data/recip.hex ../artifacts/rtl/$n.rtl.frame.rgb ${LATARGS:-} \
        > ../artifacts/rtl/$n.framelog 2>&1 || { echo "BENCH FAILED"; cat ../artifacts/rtl/$n.framelog; fail=1; continue; }
    python3 ../tools/render_model.py ../artifacts/states/$n.txt "$ROM" \
        --roz-exact --dump-rgb=../artifacts/rtl/$n.model.frame.rgb > /dev/null
    bd=$(sed -n 's/^K38REGS \([0-9a-f]*\) \([0-9a-f]*\) .*/\1 \2/p' ../artifacts/states/$n.txt \
         | while read r gb; do printf '%06x' $(( (0x$r & 0xff) * 65536 + 0x$gb )); done)
    if python3 ../tools/diff_rgb.py ../artifacts/rtl/$n.rtl.frame.rgb \
            ../artifacts/rtl/$n.model.frame.rgb "$bd" > ../artifacts/rtl/$n.framediff 2>&1; then
        echo "PASS  $(grep -v warning ../artifacts/rtl/$n.framelog | head -1) $(cat ../artifacts/rtl/$n.framediff)"
    else
        echo FAIL; sed 's/^/    /' ../artifacts/rtl/$n.framediff; fail=1
    fi
done
[ $fail = 0 ] && echo "all full frames match the reference renderer" || { echo FAILURES; exit 1; }
