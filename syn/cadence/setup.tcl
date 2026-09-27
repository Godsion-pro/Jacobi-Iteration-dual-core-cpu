# Settings shared by genus.tcl / innovus.tcl / sta.tcl (plain Tcl, no tool commands).
# Defaults follow the Cadence GPDK045 standard-cell kit (gsclib045). Set GSCLIB, or override any
# single entry with an environment variable of the same name. syn/cadence/check_lib.sh verifies
# the names below against your copy of the library before a run.
proc cfg {name default} {
  if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
  return $default
}

set GSCLIB    [cfg GSCLIB    /path/to/gsclib045]
set LIB_SLOW  [cfg LIB_SLOW  $GSCLIB/timing/slow_vdd1v0_basicCells.lib]   ;# setup / synthesis corner
set LIB_FAST  [cfg LIB_FAST  $GSCLIB/timing/fast_vdd1v0_basicCells.lib]   ;# hold corner
set LEFS      [cfg LEFS      "$GSCLIB/lef/gsclib045_tech.lef $GSCLIB/lef/gsclib045_macro.lef"]
set QRC_TECH  [cfg QRC_TECH  $GSCLIB/qrc/qx/gpdk045.tch]                  ;# RC extraction (optional)

set SITE      [cfg SITE      CoreSite]
set TIEHI     [cfg TIEHI     TIEHI]
set TIELO     [cfg TIELO     TIELO]
set CTS_BUF   [cfg CTS_BUF   "CLKBUFX2 CLKBUFX4 CLKBUFX8 CLKBUFX12 CLKBUFX16 CLKBUFX20"]
set CTS_INV   [cfg CTS_INV   "CLKINVX2 CLKINVX4 CLKINVX8 CLKINVX12 CLKINVX16 CLKINVX20"]
set FILLERS   [cfg FILLERS   "FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1"]
set PWR       [cfg PWR       VDD]
set GND       [cfg GND       VSS]
set RING_H    [cfg RING_H    Metal11]
set RING_V    [cfg RING_V    Metal10]

set PERIOD    [cfg PERIOD    10]        ;# ns, setup target
set UTIL      [cfg UTIL      0.6]       ;# core utilization for the floorplan
set OUT       [cfg OUT       .]         ;# run directory (build/cadence/<variant>)
set SRC       [cfg SRC       $OUT/src]  ;# sources from syn/prepare_src.sh
