#!/bin/sh
# Frozen-state gate for the K053247 object list.
#   sim/run_objlist.sh <gaiapolis.rom> [state-name ...]
set -e
cd "$(dirname "$0")"
ROM="$1"; shift
[ -f "$ROM" ] || { echo "usage: $0 <gaiapolis.rom> [state ...]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac

verilator --cc --exe --build -j 8 -O2 -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
    --top-module tb_objlist_top -Mdir obj_objlist \
    ../rtl/k053247_objlist.sv tb_objlist_top.sv tb_objlist.cpp \
    > obj_objlist.log 2>&1 || { tail -30 obj_objlist.log; exit 1; }

mkdir -p ../artifacts/rtl
if [ $# -gt 0 ]; then names="$@"; else
    names=$(cd ../artifacts/states && ls *.txt | sed 's/\.txt$//' \
            | grep -vE '_(tm|obj|roz|[A-D])$')
fi
fail=0
for n in $names; do
    printf '%-16s ' "$n"
    ./obj_objlist/Vtb_objlist_top ../artifacts/states/$n.txt ../artifacts/rtl/$n.rtl.obj \
        > ../artifacts/rtl/$n.objlog 2>&1 || { echo "BENCH FAILED"; cat ../artifacts/rtl/$n.objlog; fail=1; continue; }
    python3 ../tools/render_model.py ../artifacts/states/$n.txt "$ROM" \
        --dump-objlist=../artifacts/rtl/$n.model.obj > /dev/null
    if python3 ../tools/diff_objlist.py ../artifacts/rtl/$n.rtl.obj \
            ../artifacts/rtl/$n.model.obj > ../artifacts/rtl/$n.objdiff 2>&1; then
        echo "PASS  $(head -1 ../artifacts/rtl/$n.objlog)"
    else
        echo FAIL; sed 's/^/    /' ../artifacts/rtl/$n.objdiff; fail=1
    fi
done
[ $fail = 0 ] && echo "all states match the reference renderer" || { echo FAILURES; exit 1; }
