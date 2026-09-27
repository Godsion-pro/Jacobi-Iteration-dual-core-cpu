#!/usr/bin/env bash
# OpenROAD placement / repair / CTS on the Yosys netlist of a variant (run syn/flow.sh first).
# Keeps the STAGE lines, the area and the final worst-path report in syn/results/<variant>/.
# usage: PERIOD=<ns> syn/run_pnr.sh <variant>        env: TOOLS, BUILD, UTIL, REPAIR_TIMING
set -euo pipefail
VARIANT=${1:-baseline}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOLS=$(cd "${TOOLS:-$ROOT/build/tools}" && pwd)
BUILD=$(cd "${BUILD:-$ROOT/build}" && pwd)
PERIOD=${PERIOD:?set PERIOD (ns): the setup target repair_timing works towards}
NETLIST=$BUILD/syn/$VARIANT/netlist.v
[ -f "$NETLIST" ] || { echo "missing $NETLIST - run syn/flow.sh $VARIANT first" >&2; exit 1; }
W=$BUILD/pnr/$VARIANT/p$PERIOD
mkdir -p "$W"
( cd "$W" && NETLIST=$NETLIST PDK=$TOOLS/nangate45 PERIOD=$PERIOD \
    "$TOOLS/openroad-env/bin/openroad" -no_splash -exit "$ROOT/syn/pnr.tcl" > pnr.log 2>&1 )

R=$ROOT/syn/results/$VARIANT
mkdir -p "$R"
{
  echo "# OpenROAD $("$TOOLS/openroad-env/bin/openroad" -version 2>/dev/null | head -1), Nangate45 typ, target $PERIOD ns, utilization ${UTIL:-40} %"
  echo "# T_min = target - worst setup slack after each step"
  grep '^STAGE' "$W/pnr.log"
  grep -i 'design area' "$W/pnr.log" | tail -1
} | tee "$R/pnr_p$PERIOD.txt"
sed -n '/^Startpoint/,/slack/p' "$W/pnr.log" | tail -n +1 > "$R/pnr_p${PERIOD}_path.rpt"
