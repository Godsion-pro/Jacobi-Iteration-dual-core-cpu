# Genus: RTL -> gate netlist at the slow corner. Hierarchy is kept (no auto-ungroup, no boundary
# optimization) so that sta.tcl can put the per-instruction case analysis on module pins such as
# i0/alu_control/ALUoperation, as the OpenSTA flow does on the kept nets of the Yosys netlist.
source [file join [file dirname [info script]] setup.tcl]

set_db information_level 7
read_libs $LIB_SLOW

set fh [open $SRC/files.f]; set files [split [string trim [read $fh]] "\n"]; close $fh
read_hdl -language sv $files
elaborate syn_top
check_design -unresolved

set_db auto_ungroup none
if {[catch {set_db [get_db modules] .boundary_opto false} e]} { puts "WARN boundary_opto not set: $e" }
catch {set_db use_tiehilo_for_const unique}

read_sdc $OUT/base.sdc

set_db syn_generic_effort medium
set_db syn_map_effort     medium
set_db syn_opt_effort     medium
syn_generic
syn_map
syn_opt

# the ALU is written as always_comb with defaults: confirm no latch was inferred
set latches [llength [get_db insts -if {.is_latch}]]
set ninst   [llength [get_db insts]]
set area 0.0
foreach i [get_db insts] { set area [expr {$area + [get_db $i .area]}] }
puts [format "GENUS cells=%d area_um2=%.1f latches=%d period=%s" $ninst $area $latches $PERIOD]

report_timing -max_paths 1 > $OUT/genus_timing.rpt
report_area                > $OUT/genus_area.rpt
report_qor                 > $OUT/genus_qor.rpt
report_gates               > $OUT/genus_gates.rpt

write_hdl > $OUT/genus.v
write_sdc > $OUT/genus.sdc
exit
