VERILATOR ?= verilator
obj/sim: rtl/pq5.sv tb/tb_pq5.sv
	$(VERILATOR) --binary -j 8 -Wno-fatal -Wno-lint -Wno-style --timing --assert -sv --top-module tb_pq5 \
	  -CFLAGS "-std=c++20" --Mdir obj rtl/pq5.sv tb/tb_pq5.sv -o sim
test: obj/sim      # make test T=tests/p04_loop_sum.s
	python3 tools/run_pq5.py $(T)
regress: obj/sim
	@for t in tests/*.s; do python3 tools/run_pq5.py $$t; done
pipe: obj/sim      # make pipe T=tests/p03_load_use.s   -> cycle-by-cycle pipeline picture
	@python3 tools/rv32i.py $(T) > build/pipe.hex && obj/sim +PROG=$(CURDIR)/build/pipe.hex +PIPE | grep PIPE
clean:
	rm -rf obj build
