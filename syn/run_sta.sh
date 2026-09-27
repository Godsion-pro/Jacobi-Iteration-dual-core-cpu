#!/usr/bin/env bash
# Run syn/sta_mode.tcl over 3 corners x 7 modes on a synthesized netlist and tabulate T_min / Fmax.
# usage: syn/run_sta.sh <workdir>          (expects <workdir>/netlist.v)
# env:   TOOLS (default build/tools), PERIOD (default 10 ns)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(realpath "$1")
TOOLS=$(realpath -m "${TOOLS:-$ROOT/build/tools}")
STA=$TOOLS/OpenSTA/build/sta
LIBDIR=$TOOLS/OpenSTA/examples
PERIOD=${PERIOD:-10}
MODES=${MODES:-none div mul add lw sw beq}

out=$W/summary.txt
{
  echo "# T_min = PERIOD - worst setup slack (PERIOD=${PERIOD} ns, ideal clock, no wire parasitics)"
  echo "# T_direct: div/mul/add only, ALU result -> MemToReg mux -> RF (same bit), excludes merged address-path false paths"
  printf "%-5s %-5s %9s %9s %9s  %-6s -> %-6s  %s\n" corner mode T_min_ns Fmax_MHz T_direct start end "named nets on the worst path"
} > "$out"

for corner in typ slow fast; do
  for mode in $MODES; do
    rpt=$W/sta_${corner}_${mode}.rpt
    LIB=$LIBDIR/nangate45_${corner}.lib.gz NETLIST=$W/netlist.v PERIOD=$PERIOD MODE=$mode \
      "$STA" -no_splash -exit "$ROOT/syn/sta_mode.tcl" > "$rpt" 2>&1
    res=$(grep '^RESULT' "$rpt")
    slack=$(sed -E 's/.*slack=([-0-9.]+).*/\1/' <<< "$res")
    dslack=$(sed -E 's/.*direct=([-0-9.NA]+).*/\1/' <<< "$res")
    start=$(sed -E 's/.*start=([A-Za-z/]+).*/\1/' <<< "$res")
    end=$(sed -E 's/.*end=([A-Za-z/]+).*/\1/' <<< "$res")
    via=$(grep -E '\(net\)' "$rpt" | grep -v '_[0-9]*_ (net)' | awk '{print $1}' \
          | sed -E 's/\[.*//; s/^i[01]\.SCDP\.//; s/^i[01]\.//' | uniq | paste -sd'>' -)
    tmin=$(awk -v p="$PERIOD" -v s="$slack" 'BEGIN{printf "%.2f", p - s}')
    fmax=$(awk -v t="$tmin" 'BEGIN{printf "%.1f", 1000 / t}')
    if [ "$dslack" = NA ]; then tdir=-; else tdir=$(awk -v p="$PERIOD" -v s="$dslack" 'BEGIN{printf "%.2f", p - s}'); fi
    printf "%-5s %-5s %9s %9s %9s  %-6s -> %-6s  %s\n" "$corner" "$mode" "$tmin" "$fmax" "$tdir" "$start" "$end" "$via" >> "$out"
  done
done
cat "$out"
