#!/usr/bin/env bash
# STA re-analysis flow (open-source):  rtl/ -> sv2v -> Yosys (Nangate45 typ) -> OpenSTA
#
# usage: syn/flow.sh [baseline|zero_cmp]
# env:   TOOLS (default build/tools, see syn/setup_tools.sh), BUILD (default build)
#
# Outputs: $BUILD/syn/<variant>/{design.v, netlist.v, stat.txt, sta_*.rpt, summary.txt}
#          and a copy of summary.txt / stat.txt / key path reports in syn/results/<variant>/
set -euo pipefail
VARIANT=${1:-baseline}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOLS=$(realpath -m "${TOOLS:-$ROOT/build/tools}")
BUILD=$(realpath -m "${BUILD:-$ROOT/build}")
SV2V=$TOOLS/sv2v-Linux/sv2v
LIBDIR=$TOOLS/OpenSTA/examples
W=$BUILD/syn/$VARIANT

for t in "$SV2V" "$TOOLS/OpenSTA/build/sta" "$LIBDIR/nangate45_typ.lib.gz"; do
  [ -e "$t" ] || { echo "missing $t - run syn/setup_tools.sh first" >&2; exit 1; }
done
command -v yosys >/dev/null || { echo "yosys not found - run syn/setup_tools.sh first" >&2; exit 1; }

rm -rf "$W"; mkdir -p "$W/src"

# 1. The RTL pulls modules in with `include (and includes shared leaves twice); flatten that
#    into one file per module, then apply the variant patch if any.
for f in "$ROOT"/rtl/*.sv; do grep -v '^[[:space:]]*`include' "$f" > "$W/src/$(basename "$f")"; done
if [ "$VARIANT" != baseline ]; then patch -s -d "$W/src" -p1 < "$ROOT/syn/patches/$VARIANT.patch"; fi

# 2. SystemVerilog -> Verilog-2005. sv2v inlines modules with interface ports into syn_top and
#    refers to the interface buffers as syn_top.intf.*, which Yosys resolves as intf.*.
"$SV2V" "$W"/src/*.sv "$ROOT/syn/syn_top.sv" --top=syn_top > "$W/design.v"
sed -i 's/syn_top\.intf\./intf./g' "$W/design.v"

# 3. Synthesis (the combinational 64-bit divider makes ABC take 30-45 min).
gunzip -c "$LIBDIR/nangate45_typ.lib.gz" > "$W/lib_typ.lib"
( cd "$W" && yosys -q -l yosys.log -s "$ROOT/syn/syn.ys" )
echo "latches after proc: $(tail -1 "$W/latches.txt")"
grep -E "Number of cells|Chip area" "$W/stat.txt" | tail -2

# 4. STA: 3 corners x 7 instruction classes
TOOLS=$TOOLS "$ROOT/syn/run_sta.sh" "$W"

# 5. Keep the small artifacts in the repo
R=$ROOT/syn/results/$VARIANT
mkdir -p "$R"
cp "$W/summary.txt" "$W/stat.txt" "$R/"
for m in none div beq; do cp "$W/sta_typ_$m.rpt" "$R/path_typ_$m.rpt"; done
echo "results copied to syn/results/$VARIANT/"
