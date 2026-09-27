#!/usr/bin/env bash
# Cadence flow for one design variant: Genus -> Tempus (synth) -> Innovus -> Tempus (routed).
# Everything is written to build/cadence/<variant>/ (gitignored). Only summary.txt is meant to
# leave the server; the netlists, DEF, SPEF and full reports stay there (library licence).
#
# usage: GSCLIB=/path/to/gsclib045 PERIOD=<ns> syn/cadence/run.sh <variant> [steps]
#   variant : baseline | recip | zero_cmp | recip+zero_cmp | recip+pipe | ...
#   steps   : any of "src genus sta_synth innovus sta_routed summary" (default: all, in order)
#   env     : CORNERS (default "slow"), MODES (default: 7 classes, "none" for *pipe*),
#             GENUS / INNOVUS / TEMPUS to override the tool command lines
set -euo pipefail
VARIANT=${1:?variant}
STEPS=${2:-src genus sta_synth innovus sta_routed summary}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$ROOT/syn/cadence
export OUT=$ROOT/build/cadence/$VARIANT
export SRC=$OUT/src
export PERIOD=${PERIOD:?set PERIOD (ns) - see syn/cadence/README.md}
CORNERS=${CORNERS:-slow}
MODES=${MODES:-$([[ $VARIANT == *pipe* ]] && echo none || echo "none div mul add lw sw beq")}
GENUS=${GENUS:-genus -batch}
INNOVUS=${INNOVUS:-innovus -no_gui}
TEMPUS=${TEMPUS:-tempus -no_gui}
mkdir -p "$OUT"
cd "$OUT"

sta() {   # sta <stage> <netlist> [spef]
  for c in $CORNERS; do for m in $MODES; do
    STAGE=$1 NETLIST=$2 SPEF=${3:-} CORNER=$c MODE=$m \
      $TEMPUS -files "$HERE/sta.tcl" -log "tempus_$1_${c}_$m" > /dev/null 2>&1 || true
    grep -h "^RESULT\|^WARN\|^FF groups" "tempus_$1_${c}_$m.log" | sed "s/^WARN/WARN [$1 $c $m]/" | sort -u \
      || echo "no RESULT for $1 $c $m - see $OUT/tempus_$1_${c}_$m.log"
  done; done
}

for s in $STEPS; do
  echo "== $s"
  case $s in
    src)
      "$ROOT/syn/prepare_src.sh" "$VARIANT" "$SRC"
      cat > base.sdc <<EOF
create_clock -name clk -period $PERIOD [get_ports clk]
set_input_delay  0 -clock clk [get_ports reset]
set_output_delay 0 -clock clk [all_outputs]
EOF
      ;;
    genus)      $GENUS -files "$HERE/genus.tcl" -log genus > /dev/null; grep "^GENUS\|^WARN" genus.log ;;
    sta_synth)  sta synth "$OUT/genus.v" | tee sta_synth.txt ;;
    innovus)    $INNOVUS -files "$HERE/innovus.tcl" -log innovus > /dev/null; grep "^STAGE\|^HOLD" innovus.log ;;
    sta_routed) sta routed "$OUT/innovus.v" "$OUT/innovus.spef" | tee sta_routed.txt ;;
    summary)    "$HERE/summary.sh" "$OUT" "$VARIANT" > summary.txt; cat summary.txt ;;
    *) echo "unknown step $s" >&2; exit 1 ;;
  esac
done
