# Innovus (legacy UI): floorplan -> place -> CTS -> route -> post-route optimization on the Genus
# netlist, printing the worst setup path after every step (same STAGE lines as syn/pnr.tcl for
# OpenROAD). Writes the routed netlist and SPEF for sta.tcl.
source [file join [file dirname [info script]] setup.tcl]

# ---- MMMC: setup at slow/rc-worst, hold at fast/rc-best
set mmmc [open $OUT/mmmc.tcl w]
puts $mmmc "create_library_set -name libs_slow -timing {$LIB_SLOW}"
puts $mmmc "create_library_set -name libs_fast -timing {$LIB_FAST}"
set qx [expr {[file exists $QRC_TECH] ? "-qx_tech_file {$QRC_TECH}" : ""}]
puts $mmmc "create_rc_corner -name rc_worst -T 125 $qx"
puts $mmmc "create_rc_corner -name rc_best  -T 0   $qx"
puts $mmmc "create_delay_corner -name dc_slow -library_set libs_slow -rc_corner rc_worst"
puts $mmmc "create_delay_corner -name dc_fast -library_set libs_fast -rc_corner rc_best"
puts $mmmc "create_constraint_mode -name func -sdc_files {$OUT/base.sdc}"
puts $mmmc "create_analysis_view -name setup -constraint_mode func -delay_corner dc_slow"
puts $mmmc "create_analysis_view -name hold  -constraint_mode func -delay_corner dc_fast"
puts $mmmc "set_analysis_view -setup {setup} -hold {hold}"
close $mmmc

set init_verilog   $OUT/genus.v
set init_top_cell  syn_top
set init_lef_file  $LEFS
set init_mmmc_file $OUT/mmmc.tcl
set init_pwr_net   $PWR
set init_gnd_net   $GND
init_design
setDesignMode -process 45

proc stage {name} {
  set p [report_timing -collection -late -max_paths 1]
  set s [get_property $p slack]
  set t [expr {$::PERIOD - $s}]
  puts [format "STAGE %-14s T_min %8.3f ns  Fmax %7.1f MHz  instances %6d" $name $t [expr {1000.0 / $t}] [llength [dbGet top.insts]]]
}

# ---- floorplan and power
floorPlan -site $SITE -r 1.0 $UTIL 10 10 10 10
globalNetConnect $PWR -type pgpin -pin $PWR -inst * -override
globalNetConnect $GND -type pgpin -pin $GND -inst * -override
globalNetConnect $PWR -type tiehi -inst * -override
globalNetConnect $GND -type tielo -inst * -override
addRing -nets [list $PWR $GND] -type core_rings -follow core \
        -layer [list top $RING_H bottom $RING_H left $RING_V right $RING_V] -width 2 -spacing 1 -offset 1
addStripe -nets [list $PWR $GND] -layer $RING_V -direction vertical -width 1 -spacing 1 -set_to_set_distance 40
sroute -connect {corePin} -nets [list $PWR $GND]

# ---- placement
setPlaceMode -place_global_place_io_pins true
placeDesign
setTieHiLoMode -cell [list $TIEHI $TIELO] -maxFanout 8
addTieHiLo
stage placed                                   ;# placement + trial-route RC, no optimization
optDesign -preCTS
stage preCTS_opt                               ;# buffering / sizing / restructuring

# ---- clock tree
set_ccopt_property buffer_cells   $CTS_BUF
set_ccopt_property inverter_cells $CTS_INV
create_ccopt_clock_tree_spec
ccopt_design
stage cts                                      ;# propagated clock (skew) instead of ideal
optDesign -postCTS
optDesign -postCTS -hold
stage postCTS_opt

# ---- route
setNanoRouteMode -routeWithTimingDriven true
routeDesign
if {[file exists $QRC_TECH]} { setExtractRCMode -engine postRoute -effortLevel medium } \
else                         { setExtractRCMode -engine postRoute -effortLevel low }
setAnalysisMode -analysisType onChipVariation -cppr both
stage routed
optDesign -postRoute
optDesign -postRoute -hold
stage postRoute_opt

addFiller -cell $FILLERS -prefix FILLER
verify_drc -limit 10000 -report $OUT/innovus_drc.rpt
verifyConnectivity -report $OUT/innovus_conn.rpt
report_area > $OUT/innovus_area.rpt
report_timing -late  -max_paths 1 -path_type full_clock -net > $OUT/innovus_setup.rpt
report_timing -early -max_paths 1 -path_type full_clock -net > $OUT/innovus_hold.rpt
set hp [report_timing -collection -early -max_paths 1]
puts [format "HOLD worst_slack %.3f ns" [get_property $hp slack]]

saveNetlist $OUT/innovus.v
rcOut -spef $OUT/innovus.spef -rc_corner rc_worst
defOut -floorplan -netlist -routing $OUT/innovus.def
exit
