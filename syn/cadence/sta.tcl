# Tempus: setup timing of one netlist, one corner, one instruction class (one run per mode, like
# syn/sta_mode.tcl for OpenSTA). Same method, but on the hierarchical Genus/Innovus netlist, so
# the constraints sit on module pins instead of kept nets.
# env: NETLIST  STAGE (synth|routed)  CORNER (slow|fast)  MODE (none|div|mul|add|lw|sw|beq)
#      SPEF (routed only)  PERIOD
source [file join [file dirname [info script]] setup.tcl]
set stage  $::env(STAGE)
set corner $::env(CORNER)
set mode   $::env(MODE)

read_lib [expr {$corner eq "fast" ? $LIB_FAST : $LIB_SLOW}]
read_verilog $::env(NETLIST)
set_top_module syn_top
read_sdc $OUT/base.sdc
if {$stage eq "routed"} {
  read_spef $::env(SPEF)
  set_propagated_clock [all_clocks]
}

# ---- flip-flop groups by instance name (Genus keeps the RTL register names: <array>_reg[i][j])
set GROUPS {
  RF     {*register_file/Registers_reg*}
  DMEM   {*data_memory/Memory_reg*}
  XBUF   {*buf0_to_1* *buf1_to_0*}
  IF/ID  {*/core/if_id_*}
  ID/EX  {*/core/id_ex_*}
  EX/MEM {*/core/ex_mem_*}
  MEM/WB {*/core/mem_wb_*}
}
proc cls {inst} {
  foreach {g pats} $::GROUPS { foreach p $pats { if {[string match $p $inst]} { return $g } } }
  return PC   ;# program counter and anything unnamed
}
set ff [dict create]
foreach_in_collection r [all_registers] {
  set n [get_object_name $r]
  dict lappend ff [cls $n] $n
}
puts -nonewline "FF groups:"
dict for {g l} $ff { puts -nonewline " $g=[llength $l]" }
puts ""
proc ffs {args} {
  set l {}
  foreach g $args { if {[dict exists $::ff $g]} { set l [concat $l [dict get $::ff $g]] } }
  if {$l eq {}} { error "no flip-flops in group(s) $args - check the name patterns in GROUPS" }
  return [get_cells $l]
}
proc pin_inst {p} { return [regsub {/[^/]+$} [get_object_name $p] {}] }

# ---- functional constraints (single-cycle core only; the pipelined core runs MODE=none)
proc need {pat} {
  set p [get_pins -quiet $pat]
  if {[sizeof_collection $p] == 0} { puts "WARN no pin $pat" }
  return $p
}
proc setc {val rel} {
  foreach c {i0 i1} { set p [need $c/$rel]; if {[sizeof_collection $p]} { set_case_analysis $val $p } }
}
proc aluop {bits} {
  foreach k {2 1 0} { setc [string index $bits [expr {2 - $k}]] "alu_control/ALUoperation\[$k\]" }
}
proc both {rel} { return [add_to_collection [need i0/$rel] [need i1/$rel]] }

switch $mode {
  none {}
  div - mul - add - lw - sw - beq {
    set MEMDATA [both {SCDP/data_memory/read_data[*]}]
    set ALUDATA [add_to_collection [both {SCDP/alu/result[*]}] [both SCDP/alu/zero]]
    set MEMFF   [ffs DMEM XBUF]
    set RFFF    [ffs RF]
    set PCFF    [ffs PC]
    switch $mode {
      div - mul - add {
        aluop [dict get {div 101 mul 011 add 010} $mode]
        setc 0 SCDP/instruction_fetch/branch
        set_false_path -through $MEMDATA            ;# memRead=0
        set_false_path -to $MEMFF                   ;# memWrite=0, rec=0
        set_false_path -through $ALUDATA -to $PCFF  ;# branch=0
      }
      lw {
        aluop 010; setc 0 SCDP/instruction_fetch/branch
        set_false_path -to $MEMFF
        set_false_path -through $ALUDATA -to $PCFF
      }
      sw {
        aluop 010; setc 0 SCDP/instruction_fetch/branch
        set_false_path -to $RFFF
        set_false_path -through $ALUDATA -to $PCFF
      }
      beq {
        aluop 110; setc 1 SCDP/instruction_fetch/branch
        set_false_path -to $RFFF
        set_false_path -to $MEMFF
      }
    }
  }
  default { error "unknown MODE $mode" }
}

proc worst {args} {
  set p [eval report_timing -collection -late -max_paths 1 $args]
  if {[sizeof_collection $p] == 0} { return {} }
  return [list [get_property $p slack] [pin_inst [get_property $p launching_point]] [pin_inst [get_property $p capturing_point]]]
}
lassign [worst] slack sp ep

# ALU result -> MemToReg mux -> register file, same bit (the path an arithmetic instruction
# actually uses). Hierarchy is kept, so every bit can be used (the Yosys flow skips bits 2..6).
set direct NA
if {[lsearch {div mul add} $mode] >= 0} {
  foreach c {i0 i1} {
    for {set k 0} {$k < 32} {incr k} {
      set a [get_pins -quiet "$c/SCDP/alu/result\[$k\]"]
      set m [get_pins -quiet "$c/SCDP/register_file/write_data\[$k\]"]
      if {[sizeof_collection $a] == 0 || [sizeof_collection $m] == 0} continue
      set w [worst -through $a -through $m]
      if {$w eq {}} continue
      set s [lindex $w 0]
      if {$direct eq "NA" || $s < $direct} { set direct $s }
    }
  }
  if {$direct ne "NA"} { set direct [format %.3f [expr {$PERIOD - $direct}]] }
}

puts [format "RESULT stage=%s corner=%s mode=%s period=%s slack=%.3f T_min=%.3f T_direct=%s start=%s end=%s" \
        $stage $corner $mode $PERIOD $slack [expr {$PERIOD - $slack}] $direct [cls $sp] [cls $ep]]
report_timing -late -max_paths 1 -path_type full_clock -net > $OUT/sta_${stage}_${corner}_${mode}.rpt
exit
