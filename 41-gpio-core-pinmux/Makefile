# -----------------------------------------------------------------------------
# GPIO v1.0 verification : build and run
#
# Free tools (no licence needed)
#   make smoke        directed self-checking test + SVA        (Verilator 5.x)
#   make smoke4       same test, 4-state, incl. Hi-Z pad check (Icarus 12)
#   make bugs         prove the checkers fail on 4 injected bugs (Verilator)
#   make lint         lint the reference DUT for 3 configs     (Verilator)
#   make elab         elaborate the full UVM TB + UVM library  (pyslang)
#
# UVM regression (commercial simulator)
#   make vcs   TEST=gpio_full_test SEED=1
#   make xrun  TEST=gpio_glitch_test
#   make questa TEST=gpio_w1c_race_test
#   Add RTL=chipmunk RTL_DIR=<path>/gpio_v1_0/src to run on the real gpio_top.
#   Add WIDTH=32 (or WIDTH=1) and NOGLF=1 for other builds.
#   Any sequence: TEST=gpio_base_test PLUSARGS=+GPIO_VSEQ=gpio_glitch_vseq
# -----------------------------------------------------------------------------

TEST    ?= gpio_full_test
SEED    ?= 1
WIDTH   ?= 8
RTL     ?= ref
RTL_DIR ?= ../gpio_v1_0/src
UVM_HOME ?= $(abspath uvm-core/src)
BUILD   ?= build
PLUSARGS ?=

DEFS :=
ifeq ($(WIDTH),32)
  DEFS += +define+GPIO_W_32
endif
ifeq ($(WIDTH),1)
  DEFS += +define+GPIO_W_1
endif
ifeq ($(NOGLF),1)
  DEFS += +define+NO_GLF
endif

ifeq ($(RTL),chipmunk)
  DEFS     += +define+USE_CHIPMUNK_RTL +define+EN_TRISTATE_BUFF +define+EN_INTR_IF
  DUT_SRCS := $(RTL_DIR)/areset_sync.sv $(RTL_DIR)/tristate_buff.sv \
              $(RTL_DIR)/irq_sync.sv $(RTL_DIR)/intr_gateway.sv \
              $(RTL_DIR)/intr_gen.sv $(RTL_DIR)/gpio_top.sv
  DUT_INC  := +incdir+$(RTL_DIR)
else
  DUT_SRCS := rtl/gpio_ref_dut.sv tb/gpio_ref_wb_sva.sv
  DUT_INC  :=
endif

TB_SRCS := tb/gpio_if.sv tb/gpio_sva.sv tb/gpio_tb_pkg.sv tb/tb_top.sv
SMOKE   := rtl/gpio_ref_dut.sv tb/gpio_sva.sv tb/gpio_ref_wb_sva.sv tb/directed/tb_smoke.sv
VFLAGS  := --binary --timing --assert -Wno-fatal -Wno-lint -Wno-style --top-module tb_smoke

.PHONY: smoke smoke4 bugs lint elab vcs xrun questa clean

smoke:
	@mkdir -p $(BUILD)
	verilator $(VFLAGS) -Mdir $(BUILD)/smoke $(SMOKE)
	$(BUILD)/smoke/Vtb_smoke

smoke4:
	@mkdir -p $(BUILD)
	iverilog -g2012 -DNO_SVA -o $(BUILD)/smoke4 rtl/gpio_ref_dut.sv tb/directed/tb_smoke.sv
	vvp $(BUILD)/smoke4

# Each injected bug must make the run fail (a FAIL line or an assertion).
BUGS := BUG_W1C_WINS BUG_NO_RD_WAIT BUG_IE_NO_CLEAR BUG_MASK_DROPS
bugs:
	@mkdir -p $(BUILD)
	@for b in $(BUGS); do \
	  verilator $(VFLAGS) -D$$b -Mdir $(BUILD)/$$b $(SMOKE) >/dev/null 2>&1; \
	  if $(BUILD)/$$b/Vtb_smoke 2>&1 | grep -qE "FAIL|Assertion failed"; then \
	    echo "caught   $$b"; else echo "MISSED   $$b"; fi; \
	done

lint:
	verilator --lint-only -Wall rtl/gpio_ref_dut.sv
	verilator --lint-only -Wall -GGPIO_WIDTH=32 -GDEF_IO_DIR="32'hFFFFFFFF" \
	  -GEN_SYNC="32'hFFFFFFFF" -GEN_GLF="32'h0000FFFF" rtl/gpio_ref_dut.sv
	verilator --lint-only -Wall -GGPIO_WIDTH=1 -GDEF_IO_DIR="1'b1" -GEN_SYNC="1'b1" -GEN_GLF="1'b0" \
	  rtl/gpio_ref_dut.sv

# Needs: pip install pyslang ; git clone https://github.com/accellera-official/uvm-core
elab:
	python3 scripts/slang_elab.py --timescale 1ns/1ps -Wno-unknown-escape-code \
	  -Wno-width-expand -Wno-width-trunc -Wno-sign-conversion -Wno-sign-compare \
	  -Wno-arith-op-mismatch -Wno-int-float-conv -Wno-bitwise-op-mismatch \
	  $(subst +define+,-D ,$(DEFS)) --top tb_top -I $(UVM_HOME) -I tb \
	  $(UVM_HOME)/uvm_pkg.sv rtl/gpio_ref_dut.sv tb/gpio_ref_wb_sva.sv $(TB_SRCS)

vcs:
	vcs -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps -assert svaext \
	  +incdir+tb $(DUT_INC) $(DEFS) $(DUT_SRCS) $(TB_SRCS) \
	  -cm line+cond+fsm+tgl+assert -o $(BUILD)/simv
	$(BUILD)/simv +UVM_TESTNAME=$(TEST) +ntb_random_seed=$(SEED) $(PLUSARGS) -cm line+cond+fsm+tgl+assert

xrun:
	xrun -uvm -sv -timescale 1ns/1ps -access +r -coverage all \
	  +incdir+tb $(DUT_INC) $(DEFS) $(DUT_SRCS) $(TB_SRCS) \
	  +UVM_TESTNAME=$(TEST) -svseed $(SEED) $(PLUSARGS)

questa:
	vlog -sv -timescale 1ns/1ps +incdir+tb $(DUT_INC) $(DEFS) $(DUT_SRCS) $(TB_SRCS)
	vsim -c tb_top +UVM_TESTNAME=$(TEST) -sv_seed $(SEED) $(PLUSARGS) -do "coverage save -onexit cov.ucdb; run -all; quit"

clean:
	rm -rf $(BUILD) csrc simv* *.vcd *.ucdb xcelium.d work transcript
