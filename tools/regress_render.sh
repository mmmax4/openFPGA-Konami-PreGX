#!/bin/sh
# Frozen-state gate for the reference renderer.
#
# Every state in artifacts/states/<name>.txt has a matching MAME snapshot in
# artifacts/states/<name>/gaiapols/0000.png. States whose name ends in a layer
# tag were captured with that layer isolated via FORCE_ENABLE, so the model is
# asked for the same layers. Zero differing pixels is the pass condition.
#
# Usage: tools/regress_render.sh [rom-image]
set -e
ROM="${1:-gaiapolis.rom}"
[ -f "$ROM" ] || { echo "usage: $0 <gaiapolis.rom>" >&2; exit 2; }
mkdir -p artifacts/render

fail=0
checked=0
skipped=0
for st in artifacts/states/*.txt; do
    name=$(basename "$st" .txt)
    ref="artifacts/states/$name/gaiapols/0000.png"
    if [ ! -f "$ref" ]; then
        skipped=$((skipped + 1))
        continue
    fi
    checked=$((checked + 1))
    case "$name" in
        *_A) layers=A ;; *_B) layers=B ;; *_C) layers=C ;; *_D) layers=D ;;
        *_tm) layers=A,B,C,D ;;
        *_roz) layers=SUB1 ;;
        *_obj) layers=OBJ ;;
        *) layers=A,B,C,D,OBJ,SUB1 ;;   # full frame through the mixer
    esac
    out=$(python3 tools/render_model.py "$st" "$ROM" --layers="$layers" \
            --out="artifacts/render/$name.png" --ref="$ref" \
            --diff="artifacts/render/${name}_diff.png" | grep differing)
    n=$(echo "$out" | sed 's/.*differing pixels: \([0-9]*\) .*/\1/')
    cov=$(echo "$out" | sed 's/.*coverage //')
    if [ "$n" = "0" ]; then
        case "$cov" in
            0.0%) printf '  pass  %-16s %-8s (trivial: layer blank)\n' "$name" "$layers" ;;
            *)    printf '  PASS  %-16s %-8s coverage %s\n' "$name" "$layers" "$cov" ;;
        esac
    else
        printf '  FAIL  %-16s %-8s %s\n' "$name" "$layers" "$out"
        fail=1
    fi
done
if [ "$checked" -eq 0 ]; then
    echo "ERROR: zero MAME comparisons executed ($skipped states lack snapshots)" >&2
    exit 2
fi
echo "MAME comparisons: $checked executed, $skipped skipped"
[ $fail = 0 ] && echo "compared states match MAME" || echo "FAILURES"
exit $fail
