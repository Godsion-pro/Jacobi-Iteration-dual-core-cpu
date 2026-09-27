#!/usr/bin/env bash
# Collect the numbers of one run into a short text (no cell names, no path details), which is
# the only file meant to be copied off the server.
# usage: syn/cadence/summary.sh <run dir> <variant>
OUT=$1
VARIANT=$2
cd "$OUT" || exit 1
echo "# variant=$VARIANT  period=$(grep -o 'period [0-9.]*' base.sdc | cut -d' ' -f2) ns  $(date +%F)"
echo "# T_min = period - worst setup slack; synth = Genus netlist, ideal clock, no wire RC"
echo "#                                     routed = Innovus netlist + SPEF, propagated clock"
[ -f genus.log ] && grep -h "^GENUS" genus.log
[ -f innovus.log ] && grep -h "^STAGE\|^HOLD" innovus.log
[ -f innovus_drc.rpt ] && echo "DRC $(grep -ci 'violation' innovus_drc.rpt) lines mentioning violations"
printf "%-7s %-5s %-5s %8s %8s %9s  %-6s -> %-6s\n" stage corner mode T_min Fmax T_direct start end
for f in sta_synth.txt sta_routed.txt; do
  [ -f "$f" ] || continue
  grep "^RESULT" "$f" | while read -r line; do
    get() { sed -n "s/.* $1=\([^ ]*\).*/\1/p" <<< " $line"; }
    t=$(get T_min)
    printf "%-7s %-5s %-5s %8s %8.1f %9s  %-6s -> %-6s\n" \
      "$(get stage)" "$(get corner)" "$(get mode)" "$t" "$(echo "1000/$t" | bc -l)" "$(get T_direct)" "$(get start)" "$(get end)"
  done
done
grep -h "^WARN" sta_synth.txt sta_routed.txt genus.log 2>/dev/null | sort -u
