#!/bin/sh
# Frozen-state gate for the K053936 ROZ RTL: every state is rendered by both
# the RTL and the reference renderer and compared pixel for pixel (with the
# one-line offset explained in tools/diff_roz.py).
#   sim/run_roz.sh <gaiapolis.rom> [state-name ...]
set -e
cd "$(dirname "$0")"
ROM="$1"; shift
[ -f "$ROM" ] || { echo "usage: $0 <gaiapolis.rom> [state ...]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac

verilator --cc --exe --build -j ${JOBS:-8} -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    --top-module tb_roz_top -Mdir obj_roz \
    ../rtl/k053936_roz.sv tb_roz_top.sv tb_roz.cpp \
    > obj_roz.log 2>&1 || { tail -30 obj_roz.log; exit 1; }

mkdir -p ../artifacts/rtl
if [ $# -gt 0 ]; then names="$@"; else
    names=$(cd ../artifacts/states && ls *.txt | sed 's/\.txt$//' \
            | grep -vE '_(tm|obj|roz|[A-D])$')
fi
fail=0
for n in $names; do
    printf '%-16s ' "$n"
    ./obj_roz/Vtb_roz_top ../artifacts/states/$n.txt "$ROM" ../artifacts/rtl/$n.rtl.roz \
        > ../artifacts/rtl/$n.rozlog 2>&1 || { echo "BENCH FAILED"; cat ../artifacts/rtl/$n.rozlog; fail=1; continue; }
    python3 ../tools/render_model.py ../artifacts/states/$n.txt "$ROM" \
        --dump-roz=../artifacts/rtl/$n.model.roz > /dev/null
    if python3 ../tools/diff_roz.py ../artifacts/rtl/$n.rtl.roz \
            ../artifacts/rtl/$n.model.roz > ../artifacts/rtl/$n.rozdiff 2>&1; then
        d=$(cat ../artifacts/rtl/$n.rozdiff)
        case "$d" in
            *"coverage 0.0%"*) echo "pass  $(head -1 ../artifacts/rtl/$n.rozlog)  (trivial: ROZ disabled)" ;;
            *) echo "PASS  $(head -1 ../artifacts/rtl/$n.rozlog) $d" ;;
        esac
    else
        echo FAIL; sed 's/^/    /' ../artifacts/rtl/$n.rozdiff; fail=1
    fi
done
[ $fail = 0 ] && echo "all states match the reference renderer" || { echo FAILURES; exit 1; }
