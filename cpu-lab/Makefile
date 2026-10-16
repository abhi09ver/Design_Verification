# Lab Makefile  --  needs Verilator >= 5.026 (tested 5.048).  Set VERILATOR if not on PATH.
VERILATOR ?= verilator
RTL ?= rtl
OBJ ?= obj_$(RTL)
TESTS := $(sort $(wildcard tests/*.s))

sim: $(OBJ)/sim
SVA ?= 1
SVA_FILES := $(if $(filter 1,$(SVA)),tb/core_sva.sv --assert,)
$(OBJ)/sim: $(wildcard $(RTL)/*.sv) tb/tb_lab.sv tb/core_sva.sv
	$(VERILATOR) --binary -j 8 -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH --timing -sv \
	  --top-module tb_lab -O1 -CFLAGS "-std=c++20 -O1" --Mdir $(OBJ) -I$(RTL) $(RTL)/design.sv $(SVA_FILES) tb/tb_lab.sv -o sim

test: sim          # make test T=tests/b03_rob_tag0.s
	SIM_BIN=$(OBJ)/sim python3 tools/run_test.py $(T)

regress: sim
	@for t in $(TESTS); do SIM_BIN=$(OBJ)/sim python3 tools/run_test.py $$t; done

clean:
	rm -rf obj_* build
