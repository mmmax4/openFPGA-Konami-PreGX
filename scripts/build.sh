#!/bin/bash
set -euo pipefail
pregx_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
quartus_dir=${QUARTUS_BIN:-/opt/intelFPGA_lite/21.1/quartus/bin}
mkdir -p "$pregx_root/build/verification"
exec 9>"$pregx_root/build/quartus.lock"
flock -n 9 || { echo 'A Quartus build already owns this project.' >&2; exit 1; }
cd "$pregx_root"
python3 scripts/build_manifest.py begin "${1:-compile}"
trap 'result=$?; cd "$pregx_root"; python3 scripts/build_manifest.py end "$result"; exit "$result"' EXIT
cd projects
case "${1:-compile}" in
    compile) "$quartus_dir/quartus_sh" --flow compile gaia_pocket.qpf ;;
    map) "$quartus_dir/quartus_map" gaia_pocket --read_settings_files=on --write_settings_files=off ;;
    sta) "$quartus_dir/quartus_sta" gaia_pocket --do_report_timing ;;
    audit-sdram) "$quartus_dir/quartus_sta" -t ../scripts/report_sdram_timing.tcl ;;
    *) echo 'usage: bash scripts/build.sh [compile|map|sta|audit-sdram]' >&2; exit 2 ;;
esac
