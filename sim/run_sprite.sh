#!/bin/sh
# Frozen-state gate for the K053247 sprite path: object list plus rasterizer,
# resolved to RGB and diffed against the reference renderer's sprite-only
# composite.
#   sim/run_sprite.sh <gaiapolis.rom> [state-name ...]
set -e
cd "$(dirname "$0")"
ROM="$1"; shift
[ -f "$ROM" ] || { echo "usage: $0 <gaiapolis.rom> [state ...]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac

verilator --cc --exe --build -j ${JOBS:-1} -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    --top-module tb_sprite_top -Mdir obj_sprite \
    ../rtl/k053247_objlist.sv ../rtl/pregx_sprite_line_queue.sv ../rtl/pregx_sprite_word_cache.sv ../rtl/k053247_draw.sv tb_sprite_top.sv tb_sprite.cpp \
    > obj_sprite.log 2>&1 || { tail -30 obj_sprite.log; exit 1; }

mkdir -p ../artifacts/rtl
if [ $# -gt 0 ]; then names="$@"; else
    names=$(cd ../artifacts/states && ls *.txt | sed 's/\.txt$//' \
            | grep -vE '_(tm|obj|roz|[A-D])$')
fi
fail=0
for n in $names; do
    printf '%-16s ' "$n"
    ./obj_sprite/Vtb_sprite_top ../artifacts/states/$n.txt "$ROM" \
        ../rtl/data/zoom.hex ../rtl/data/recip.hex ../artifacts/rtl/$n.rtl.rgb \
        > ../artifacts/rtl/$n.sprlog 2>&1 || { echo "BENCH FAILED"; cat ../artifacts/rtl/$n.sprlog; fail=1; continue; }
    python3 ../tools/render_model.py ../artifacts/states/$n.txt "$ROM" \
        --dump-obj-rgb=../artifacts/rtl/$n.model.rgb > /dev/null
    # backdrop = K054338 (BGC_R & 0xff) << 16 | BGC_GB, from the state itself
    bd=$(sed -n 's/^K38REGS \([0-9a-f]*\) \([0-9a-f]*\) .*/\1 \2/p' ../artifacts/states/$n.txt \
         | while read r gb; do printf '%06x' $(( (0x$r & 0xff) * 65536 + 0x$gb )); done)
    if python3 ../tools/diff_rgb.py ../artifacts/rtl/$n.rtl.rgb \
            ../artifacts/rtl/$n.model.rgb "$bd" > ../artifacts/rtl/$n.sprdiff 2>&1; then
        d=$(cat ../artifacts/rtl/$n.sprdiff)
        case "$d" in
            *"coverage 0.0%"*) echo "pass  (trivial: no sprites on screen)" ;;
            *) echo "PASS  $(grep -v warning ../artifacts/rtl/$n.sprlog | head -1) $d" ;;
        esac
    else
        echo FAIL; sed 's/^/    /' ../artifacts/rtl/$n.sprdiff; fail=1
    fi
done
[ $fail = 0 ] && echo "all states match the reference renderer" || { echo FAILURES; exit 1; }
