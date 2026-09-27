#!/usr/bin/env bash
# STA re-analysis flow (open-source):  rtl/ -> sv2v -> Yosys (Nangate45 typ) -> OpenSTA
#
# usage: syn/flow.sh [baseline|<part>[+<part>...]]   parts: variants/<p>.patch or variants/<p>/ overlay
#        e.g. zero_cmp, recip, recip+zero_cmp, recip+pipe
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

rm -rf "$W"; mkdir -p "$W"

# 1. The RTL pulls modules in with `include (and includes shared leaves twice): flatten that
#    into one file per module and apply the variant parts (shared with the Cadence scripts).
"$ROOT/syn/prepare_src.sh" "$VARIANT" "$W/src"

# 2. SystemVerilog -> Verilog-2005. sv2v inlines modules with interface ports into syn_top and
#    refers to the interface buffers as syn_top.intf.*, which Yosys resolves as intf.*.
"$SV2V" $(cat "$W/src/files.f") --top=syn_top > "$W/design.v"
sed -i 's/syn_top\.intf\./intf./g' "$W/design.v"

# 3. Synthesis (the combinational 64-bit divider makes ABC take 30-45 min).
gunzip -c "$LIBDIR/nangate45_typ.lib.gz" > "$W/lib_typ.lib"
( cd "$W" && yosys -q -l yosys.log -s "$ROOT/syn/syn.ys" )
echo "latches after proc: $(tail -1 "$W/latches.txt")"
grep -E "Number of cells|Chip area" "$W/stat.txt" | tail -2

# 4. STA: 3 corners x 7 instruction classes
# the per-instruction modes rely on the single-cycle datapath's net names; the pipelined
# core gets the structural analysis only
MODES=${MODES:-$([[ $VARIANT == *pipe* ]] && echo none || echo "none div mul add lw sw beq")}
TOOLS=$TOOLS MODES="$MODES" "$ROOT/syn/run_sta.sh" "$W"

# 5. Keep the small artifacts in the repo
R=$ROOT/syn/results/$VARIANT
mkdir -p "$R"
cp "$W/summary.txt" "$W/stat.txt" "$R/"
for m in none div beq; do [ ! -f "$W/sta_typ_$m.rpt" ] || cp "$W/sta_typ_$m.rpt" "$R/path_typ_$m.rpt"; done
echo "results copied to syn/results/$VARIANT/"
