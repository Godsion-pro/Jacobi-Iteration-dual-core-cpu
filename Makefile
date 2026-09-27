# Simulation flow for the dual-core Jacobi CPU (Verilator 5.x)
#   make check        golden model + self-checking testbench (PASS/FAIL)
#   make check-random same, with randomized initial state over SEEDS
#   make sim          original course testbench (stimulus only, no checks)
#   make wave         self-check with VCD dump -> build/wave.vcd
#   make lint         verilator --lint-only -Wall on the RTL
#   make asm-check    re-assemble sw/*.s and compare against the ROM words in rtl/
#   make golden       print the golden-model convergence table
#   make sta-tools    install yosys / sv2v / OpenSTA into $(TOOLS)   (see syn/setup_tools.sh)
#   make sta          synthesize (Nangate45) + OpenSTA  (~45 min with the divider)
#   VARIANT=<v>       apply variants/<v>.patch (join with +), e.g. recip, zero_cmp, recip+zero_cmp
#   RTL_DIR=<dir>     run a target against another RTL tree (default: rtl or the patched variant)

VERILATOR ?= verilator
PYTHON    ?= python3
BUILD     ?= build
SEEDS     ?= 1 2 3 4 5
TOOLS     ?= $(BUILD)/tools
VARIANT   ?= baseline

ifeq ($(VARIANT),baseline)
RTL_DIR   ?= rtl
VBUILD    := $(BUILD)
RTL        = $(wildcard $(RTL_DIR)/*.sv)
else
RTL_DIR   ?= $(BUILD)/rtl_$(VARIANT)
VBUILD    := $(BUILD)/$(VARIANT)
RTL        = $(RTL_DIR)/.stamp
PATCHES   := $(foreach p,$(subst +, ,$(VARIANT)),variants/$(p).patch)
endif
GOLDEN_FLAGS := $(if $(findstring recip,$(VARIANT)),--recip,)

# MODDUP: every processor `includes the shared leaf modules again (original structure).
VFLAGS = --binary --timing --assert -I$(RTL_DIR) -Itb -I$(VBUILD) \
         -Wno-fatal -Wno-MODDUP -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC

.PHONY: help check check-random sim wave lint asm-check golden sta-tools sta clean

help:
	@sed -n '2,13p' Makefile | sed 's/^# //'

$(VBUILD):
	@mkdir -p $@

ifneq ($(VARIANT),baseline)
# patched copy of rtl/ for a variant
$(RTL_DIR)/.stamp: $(wildcard rtl/*.sv) $(PATCHES)
	rm -rf $(RTL_DIR) && mkdir -p $(RTL_DIR) && cp rtl/*.sv $(RTL_DIR)/
	for p in $(PATCHES); do patch -s -d $(RTL_DIR) -p1 < $$p; done
	touch $@
endif

$(VBUILD)/golden_expected.svh: model/jacobi_golden.py | $(VBUILD)
	$(PYTHON) $< $(GOLDEN_FLAGS) --svh $@

golden:
	$(PYTHON) model/jacobi_golden.py $(GOLDEN_FLAGS)

$(VBUILD)/selfcheck/Vtop_tb_selfcheck: tb/top_tb_selfcheck.sv $(RTL) $(VBUILD)/golden_expected.svh
	$(VERILATOR) $(VFLAGS) $< --top-module top_tb_selfcheck -Mdir $(VBUILD)/selfcheck

check: $(VBUILD)/selfcheck/Vtop_tb_selfcheck
	$<

$(VBUILD)/random/Vtop_tb_selfcheck: tb/top_tb_selfcheck.sv $(RTL) $(VBUILD)/golden_expected.svh
	$(VERILATOR) $(VFLAGS) --x-initial unique $< --top-module top_tb_selfcheck -Mdir $(VBUILD)/random

check-random: $(VBUILD)/random/Vtop_tb_selfcheck
	@for s in $(SEEDS); do \
	  echo "---- seed $$s"; \
	  $< +verilator+rand+reset+2 +verilator+seed+$$s | grep -E "RESULT|MISMATCH|ERROR|cycles to End" || exit 1; \
	done

$(VBUILD)/orig/Vtop_tb: tb/top_tb.sv $(RTL)
	$(VERILATOR) $(VFLAGS) $< --top-module top_tb -Mdir $(VBUILD)/orig

sim: $(VBUILD)/orig/Vtop_tb
	$<

$(VBUILD)/trace/Vtop_tb_selfcheck: tb/top_tb_selfcheck.sv $(RTL) $(VBUILD)/golden_expected.svh
	$(VERILATOR) $(VFLAGS) --trace -DTRACE $< --top-module top_tb_selfcheck -Mdir $(VBUILD)/trace

wave: $(VBUILD)/trace/Vtop_tb_selfcheck
	$<
	@echo "waveform: $(BUILD)/wave.vcd"

lint: $(RTL)
	-$(VERILATOR) --lint-only -Wall -Wno-MODDUP -I$(RTL_DIR) $(RTL_DIR)/top.sv --top-module top

asm-check:
	$(PYTHON) sw/asm.py sw/core0.s --check $(RTL_DIR)/instruction_memory_0.sv
	$(PYTHON) sw/asm.py sw/core1.s --check $(RTL_DIR)/instruction_memory_1.sv

sta-tools:
	syn/setup_tools.sh $(TOOLS)

sta:
	TOOLS=$(TOOLS) BUILD=$(BUILD) syn/flow.sh $(VARIANT)

clean:
	rm -rf $(BUILD)
