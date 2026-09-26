# Simulation flow for the dual-core Jacobi CPU (Verilator 5.x)
#   make check        golden model + self-checking testbench (PASS/FAIL)
#   make check-random same, with randomized initial state over SEEDS
#   make sim          original course testbench (stimulus only, no checks)
#   make wave         self-check with VCD dump -> build/wave.vcd
#   make lint         verilator --lint-only -Wall on the RTL
#   make asm-check    re-assemble sw/*.s and compare against the ROM words in rtl/
#   make golden       print the golden-model convergence table
#   RTL_DIR=<dir>     run any target against another RTL tree (default: rtl)

VERILATOR ?= verilator
PYTHON    ?= python3
BUILD     ?= build
SEEDS     ?= 1 2 3 4 5
RTL_DIR   ?= rtl

# MODDUP: every processor `includes the shared leaf modules again (original structure).
VFLAGS = --binary --timing --assert -I$(RTL_DIR) -Itb -I$(BUILD) \
         -Wno-fatal -Wno-MODDUP -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
RTL    = $(wildcard $(RTL_DIR)/*.sv)

.PHONY: help check check-random sim wave lint asm-check golden clean

help:
	@sed -n '2,10p' Makefile | sed 's/^# //'

$(BUILD):
	@mkdir -p $@

$(BUILD)/golden_expected.svh: model/jacobi_golden.py | $(BUILD)
	$(PYTHON) $< --svh $@

golden:
	$(PYTHON) model/jacobi_golden.py

$(BUILD)/selfcheck/Vtop_tb_selfcheck: tb/top_tb_selfcheck.sv $(RTL) $(BUILD)/golden_expected.svh
	$(VERILATOR) $(VFLAGS) $< --top-module top_tb_selfcheck -Mdir $(BUILD)/selfcheck

check: $(BUILD)/selfcheck/Vtop_tb_selfcheck
	$<

$(BUILD)/random/Vtop_tb_selfcheck: tb/top_tb_selfcheck.sv $(RTL) $(BUILD)/golden_expected.svh
	$(VERILATOR) $(VFLAGS) --x-initial unique $< --top-module top_tb_selfcheck -Mdir $(BUILD)/random

check-random: $(BUILD)/random/Vtop_tb_selfcheck
	@for s in $(SEEDS); do \
	  echo "---- seed $$s"; \
	  $< +verilator+rand+reset+2 +verilator+seed+$$s | grep -E "RESULT|MISMATCH|ERROR|cycles to End" || exit 1; \
	done

$(BUILD)/orig/Vtop_tb: tb/top_tb.sv $(RTL)
	$(VERILATOR) $(VFLAGS) $< --top-module top_tb -Mdir $(BUILD)/orig

sim: $(BUILD)/orig/Vtop_tb
	$<

$(BUILD)/trace/Vtop_tb_selfcheck: tb/top_tb_selfcheck.sv $(RTL) $(BUILD)/golden_expected.svh
	$(VERILATOR) $(VFLAGS) --trace -DTRACE $< --top-module top_tb_selfcheck -Mdir $(BUILD)/trace

wave: $(BUILD)/trace/Vtop_tb_selfcheck
	$<
	@echo "waveform: $(BUILD)/wave.vcd"

lint:
	-$(VERILATOR) --lint-only -Wall -Wno-MODDUP -I$(RTL_DIR) $(RTL_DIR)/top.sv --top-module top

asm-check:
	$(PYTHON) sw/asm.py sw/core0.s --check $(RTL_DIR)/instruction_memory_0.sv
	$(PYTHON) sw/asm.py sw/core1.s --check $(RTL_DIR)/instruction_memory_1.sv

clean:
	rm -rf $(BUILD)
