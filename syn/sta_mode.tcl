# OpenSTA: setup timing of the synthesized dual-core netlist, per instruction class.
# env: LIB (liberty, .lib or .lib.gz)  NETLIST  PERIOD (ns)  MODE (none|div|mul|add|lw|sw|beq)
#
# MODE none : no functional constraints -> structural worst path (what plain STA reports)
# other     : case analysis on the decoded ALU operation / branch nets, plus false paths for
#             the storage an instruction of that class cannot write in this cycle
read_liberty $::env(LIB)
read_verilog $::env(NETLIST)
link_design syn_top
create_clock -name clk -period $::env(PERIOD) [get_ports clk]
set_input_delay  0 -clock clk [get_ports reset]
set_output_delay 0 -clock clk [all_outputs]

# ---- flip-flop groups, identified by the name of the net on the Q pin
proc ff_names {pat} {
  set names {}
  foreach n [get_nets -quiet $pat] {
    foreach p [get_pins -quiet -of_objects $n -filter "direction == output"] {
      lappend names [get_full_name [get_cells -of_objects $p]]
    }
  }
  return [lsort -unique $names]
}
set RF   [ff_names {i*.*register_file.Registers*}]
set DMEM [ff_names {i*.*data_memory.Memory*}]
set XBUF [ff_names {intf.buf*}]
# pipeline registers of variants/pipe (empty for the single-cycle core)
set IFID  [ff_names {i*.core.if_id_*}]
set IDEX  [ff_names {i*.core.id_ex_*}]
set EXMEM [ff_names {i*.core.ex_mem_*}]
set MEMWB [ff_names {i*.core.mem_wb_*}]
# PC bits: every remaining flop (some PC Q nets lose their names in synthesis)
set PC {}
set named [lsort [concat $RF $DMEM $XBUF $IFID $IDEX $EXMEM $MEMWB]]
foreach reg [all_registers -cells] {
  set c [get_full_name $reg]
  if {[lsearch -sorted $named $c] < 0} { lappend PC $c }
}
puts "FF groups: RF=[llength $RF] DMEM=[llength $DMEM] XBUF=[llength $XBUF] PC=[llength $PC] IF/ID=[llength $IFID] ID/EX=[llength $IDEX] EX/MEM=[llength $EXMEM] MEM/WB=[llength $MEMWB]"

proc cls {cellname} {
  global RF DMEM XBUF PC IFID IDEX EXMEM MEMWB
  foreach g {RF DMEM XBUF IFID IDEX EXMEM MEMWB PC} {
    if {[lsearch -exact [set $g] $cellname] >= 0} { return [string map {IFID IF/ID IDEX ID/EX EXMEM EX/MEM MEMWB MEM/WB} $g] }
  }
  return port
}

# ---- functional constraints
proc drv {name} { return [get_pins -quiet -of_objects [get_nets -quiet $name] -filter "direction == output"] }
proc setc {val name} {
  foreach c {i0 i1} {
    set p [drv "$c.$name"]
    if {[llength $p] == 0} { puts "WARN no driver for $c.$name" } else { set_case_analysis $val $p }
  }
}
proc aluop {bits} {
  setc [string index $bits 0] {alu_control.ALUoperation[2]}
  setc [string index $bits 1] {alu_control.ALUoperation[1]}
  setc [string index $bits 2] {alu_control.ALUoperation[0]}
}
set MEMDATA [get_nets -quiet {i*.SCDP.MemData*}]
set ALUDATA [get_nets -quiet {i*.SCDP.AluData*}]
set MEMFF   [get_cells [concat $DMEM $XBUF]]
set RFFF    [get_cells $RF]
set PCFF    [get_cells $PC]

set mode $::env(MODE)
switch $mode {
  none {}
  div - mul - add {
    aluop [dict get {div 101 mul 011 add 010} $mode]
    setc 0 SCDP.instruction_fetch.branch
    set_false_path -through $MEMDATA          ;# memRead=0: load data not used
    set_false_path -to $MEMFF                 ;# memWrite=0, rec=0: DMEM / exchange buffer hold
    set_false_path -through $ALUDATA -to $PCFF ;# branch=0: ALU result never steers the PC
  }
  lw {
    aluop 010; setc 0 SCDP.instruction_fetch.branch
    set_false_path -to $MEMFF
    set_false_path -through $ALUDATA -to $PCFF
  }
  sw {
    aluop 010; setc 0 SCDP.instruction_fetch.branch
    set_false_path -to $RFFF                  ;# RegWrite=0
    set_false_path -through $ALUDATA -to $PCFF
  }
  beq {
    aluop 110; setc 1 SCDP.instruction_fetch.branch
    set_false_path -to $RFFF
    set_false_path -to $MEMFF
  }
  default { error "unknown MODE $mode" }
}

set pe [lindex [find_timing_paths -path_delay max -group_path_count 1 -endpoint_path_count 1] 0]
set sp [get_full_name [get_cells -quiet -of_objects [get_property $pe startpoint]]]
set ep [get_full_name [get_cells -quiet -of_objects [get_property $pe endpoint]]]
set worst [get_property $pe slack]
unset pe   ;# path-end objects are freed by the next find_timing_paths call

# ALU -> write-back through the MemToReg mux only (same bit in and out). Address bits 2..6 are
# skipped: from those bits a path can also run through the DMEM read mux, which ABC merged so
# that it escapes the MemData false path above.
set direct NA
if {[lsearch {div mul add} $mode] >= 0} {
  set best {}
  foreach c {i0 i1} {
    for {set k 0} {$k < 32} {incr k} {
      if {$k >= 2 && $k <= 6} continue
      set a [get_nets -quiet "$c.SCDP.AluData\[$k\]"]
      set m [get_nets -quiet "$c.SCDP.Mem_or_ALU\[$k\]"]
      if {[llength $a] == 0 || [llength $m] == 0} continue
      set p [find_timing_paths -path_delay max -through $a -through $m -group_path_count 1]
      if {[llength $p] == 0} continue
      set s [get_property [lindex $p 0] slack]
      if {$best eq {} || $s < $best} { set best $s }
    }
  }
  if {$best ne {}} { set direct [format %.3f $best] }
}
puts [format "RESULT mode=%s slack=%.3f direct=%s start=%s end=%s" $mode $worst $direct [cls $sp] [cls $ep]]
report_checks -path_delay max -format full -fields {net fanout} -digits 3
