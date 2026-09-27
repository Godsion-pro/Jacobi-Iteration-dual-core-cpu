# OpenROAD: place the Yosys netlist, repair it the way a real flow would (fanout buffering,
# gate sizing, clock tree, setup repair) and report how the worst path changes at each step.
# env: NETLIST  PDK (dir with Nangate45_tech.lef / Nangate45_stdcell.lef / Nangate45_typ.lib)
#      PERIOD (ns, setup target used by repair_timing)  UTIL (core utilization %, default 40)
#      REPAIR_TIMING (1/0, default 1)
set pdk    $::env(PDK)
set period $::env(PERIOD)
set util   [expr {[info exists ::env(UTIL)] ? $::env(UTIL) : 40}]
set do_rt  [expr {[info exists ::env(REPAIR_TIMING)] ? $::env(REPAIR_TIMING) : 1}]

read_lef     $pdk/Nangate45_tech.lef
read_lef     $pdk/Nangate45_stdcell.lef
read_liberty $pdk/Nangate45_typ.lib
read_verilog $::env(NETLIST)
link_design syn_top
create_clock -name clk -period $period [get_ports clk]
set_input_delay  0 -clock clk [get_ports reset]
set_output_delay 0 -clock clk [all_outputs]

proc worst {} {
  set pe [lindex [find_timing_paths -path_delay max] 0]   ;# default: 1 path (flag name differs across OpenSTA versions)
  return [get_property $pe slack]
}
# DRV = max slew / max capacitance violations against the liberty limits: a netlist with many of
# them is timed by extrapolating the NLDM tables, so its delays are not trustworthy
proc stage {name} {
  global period
  set t [expr {$period - [worst]}]
  puts [format "STAGE %-14s T_min %8.3f ns  Fmax %7.1f MHz  instances %6d  DRV slew %4d cap %4d" \
          $name $t [expr {1000.0 / $t}] [llength [get_cells *]] \
          [sta::max_slew_violation_count] [sta::max_capacitance_violation_count]]
}

stage synth                                   ;# ideal clock, no wire load (= OpenSTA 'none')

initialize_floorplan -utilization $util -aspect_ratio 1 -core_space 2 -site FreePDK45_38x28_10R_NP_162NW_34O
make_tracks
place_pins -hor_layers metal3 -ver_layers metal2
global_placement -density 0.7
detailed_placement
set_wire_rc -signal -layer metal3
set_wire_rc -clock  -layer metal5
estimate_parasitics -placement
stage placed                                  ;# + wire RC from placement, no repair yet

repair_design                                 ;# max slew / cap / fanout: buffering and sizing
detailed_placement
estimate_parasitics -placement
stage repair_design

clock_tree_synthesis -root_buf BUF_X4 -buf_list BUF_X4
set_propagated_clock [all_clocks]
detailed_placement
estimate_parasitics -placement
stage cts                                     ;# real clock arrival (skew) instead of ideal

if {$do_rt} {
  repair_timing -setup
  detailed_placement
  estimate_parasitics -placement
  stage repair_timing                         ;# sizing / buffering on violating paths
}

report_design_area
report_checks -path_delay max -format full_clock_expanded -fields {net fanout slew cap} -digits 3
