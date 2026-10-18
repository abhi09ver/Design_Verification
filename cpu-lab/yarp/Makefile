VERILATOR ?= verilator
RTL ?= orig
obj_$(RTL)/sim: $(RTL)/*.sv tb/tb_yarp.sv
	$(VERILATOR) --binary -j 8 -Wno-fatal -Wno-lint -Wno-style --timing -sv --top-module tb_yarp \
	  -CFLAGS "-std=c++20" --Mdir obj_$(RTL) $(RTL)/yarp_pkg.sv $(RTL)/yarp_pkg1.sv \
	  $(filter-out $(RTL)/yarp_pkg.sv $(RTL)/yarp_pkg1.sv $(RTL)/yarp_top1.sv,$(wildcard $(RTL)/*.sv)) tb/tb_yarp.sv -o sim
regress: obj_$(RTL)/sim     # make regress RTL=orig|fixed  [SIM_ARGS=+IMEM_ALWAYS]
	@mkdir -p build; for t in tests/*.s; do SIM_BIN=obj_$(RTL)/sim python3 tools/run_yarp.py $$t; done
clean:
	rm -rf obj_* build
