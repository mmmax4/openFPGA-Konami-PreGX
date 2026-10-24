#!/bin/sh
# Frozen-state gate for the K056832 tilemap RTL: every state is rendered by
# both the RTL and the reference renderer and the four layers compared
# pixel for pixel. Zero differences on every state is the pass condition.
#   sim/run_tilemap.sh <gaiapolis.rom> [state-name ...]
set -e
cd "$(dirname "$0")"
ROM="$1"; shift
[ -f "$ROM" ] || { echo "usage: $0 <gaiapolis.rom> [state ...]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac

verilator --cc --exe --build -j 8 -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    --top-module tb_tilemap_top -Mdir obj_tilemap \
    ../rtl/k056832_tilemap.sv tb_tilemap_top.sv tb_tilemap.cpp \
    > obj_tilemap.log 2>&1 || { tail -30 obj_tilemap.log; exit 1; }

mkdir -p ../artifacts/rtl
if [ $# -gt 0 ]; then names="$@"; else
    # The _tm/_obj/_roz/_A..D captures differ only in how MAME rendered them;
    # the dumped machine state is byte-identical to the plain capture, so
    # gating the RTL on the plain states covers every distinct frame.
    names=$(cd ../artifacts/states && ls *.txt | sed 's/\.txt$//' \
            | grep -vE '_(tm|obj|roz|[A-D])$')
fi
fail=0
for n in $names; do
    printf '%-16s ' "$n"
    ./obj_tilemap/Vtb_tilemap_top ../artifacts/states/$n.txt "$ROM" ../artifacts/rtl/$n.rtl.layers ${LATARGS:-} \
        > ../artifacts/rtl/$n.log 2>&1 || { echo "BENCH FAILED"; cat ../artifacts/rtl/$n.log; fail=1; continue; }
    python3 ../tools/render_model.py ../artifacts/states/$n.txt "$ROM" \
        --dump-layers=../artifacts/rtl/$n.model.layers > /dev/null
    if python3 ../tools/diff_layers.py ../artifacts/rtl/$n.rtl.layers \
            ../artifacts/rtl/$n.model.layers > ../artifacts/rtl/$n.diff 2>&1; then
        echo "PASS  $(head -1 ../artifacts/rtl/$n.log)"
    else
        echo FAIL; sed 's/^/    /' ../artifacts/rtl/$n.diff; fail=1
    fi
done
[ $fail = 0 ] && echo "all states match the reference renderer" || { echo FAILURES; exit 1; }
