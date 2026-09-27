#!/usr/bin/env bash
# Check the library settings of syn/cadence/setup.tcl against the files on this server before a
# run: files exist, and the site / tie / clock / filler cell names are defined in the LEF.
# usage: GSCLIB=/path/to/gsclib045 syn/cadence/check_lib.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
eval "$(HERE=$HERE tclsh <<'EOF'
source $env(HERE)/setup.tcl
foreach v {LIB_SLOW LIB_FAST LEFS QRC_TECH SITE TIEHI TIELO CTS_BUF CTS_INV FILLERS} {
  puts "$v=\"[set $v]\""
}
EOF
)"
ok=1
for f in $LIB_SLOW $LIB_FAST $LEFS; do
  if [ -r "$f" ]; then echo "ok    $f"; else echo "MISS  $f"; ok=0; fi
done
[ -r "$QRC_TECH" ] && echo "ok    $QRC_TECH" || echo "none  QRC_TECH ($QRC_TECH): Innovus falls back to its default RC model"
lef=$(cat $LEFS 2>/dev/null)
grep -q "^SITE $SITE\b" <<< "$lef" && echo "ok    site $SITE" || { echo "MISS  site $SITE (sites: $(grep -o '^SITE [^ ]*' <<< "$lef" | cut -d' ' -f2 | tr '\n' ' '))"; ok=0; }
for c in $TIEHI $TIELO $CTS_BUF $CTS_INV $FILLERS; do
  grep -q "^MACRO $c\s*$" <<< "$lef" && echo "ok    cell $c" || { echo "MISS  cell $c"; ok=0; }
done
echo "clock buffers/inverters in the LEF: $(grep -o '^MACRO CLK[A-Z0-9]*' <<< "$lef" | cut -d' ' -f2 | tr '\n' ' ')"
echo "fillers / tie cells in the LEF:     $(grep -oE '^MACRO (FILL|TIE)[A-Z0-9]*' <<< "$lef" | cut -d' ' -f2 | tr '\n' ' ')"
echo "routing layers: $(grep -A1 '^LAYER ' <<< "$lef" | grep -B1 'TYPE ROUTING' | grep -o '^LAYER [^ ]*' | cut -d' ' -f2 | tr '\n' ' ')"
[ $ok = 1 ] && echo "RESULT: settings match the library" || echo "RESULT: fix the MISS entries (env vars or setup.tcl)"
