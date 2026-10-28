# cpu-from-scratch -- labs that build a RISC-V core the way the Wally book does
#
#   make book-single   Lab 1: run the book's riscvtest on the single-cycle core
#   make single        Lab 2: directed + constrained-random lock-step regression, single-cycle
#   make pipe          Lab 3: same regression on the 5-stage pipeline
#   make bugs          Lab 3: inject 5 pipeline bugs, see which tests catch them
#   make bus          Lab 6: regression incl. bus tests + block-level AHB bench
#   make bushunt      Lab 6: injected bus bugs vs which check catches them
#   make busperf      Lab 6: cost of a bus access
#   make cache        Lab 7: regression at 4 D-cache configurations
#   make cachehunt    Lab 7: injected cache bugs vs 4 checks
#   make cacheperf    Lab 7: miss rate vs associativity
#   make periph       Lab 11: block-level peripheral bench (GPIO, CLINT, PLIC, UART, SPI), 5 seeds x 2 plans
#   make periphhunt   Lab 11: 14 injected peripheral bugs vs full bench and book-style loopback plan
#   make wave          dump wave.vcd of the pipeline running the book test (open with gtkwave)
#   make clean
#
# Needs: verilator (5.x), python3, riscv64-unknown-elf-gcc (any RV32I-capable gcc)

SEEDS ?= 50
LEN   ?= 400
COMMON = rtl/common/generic.sv rtl/common/units.sv
VFLAGS = --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb

book-single:
	@mkdir -p build/single
	verilator $(VFLAGS) -Mdir build/single -o Vtb $(COMMON) rtl/single/core_single.sv tb/tb.sv
	./build/single/Vtb +HEX=tests/book/riscvtest.hex +TRACE=build/book_single.trace
	python3 dv/iss.py tests/book/riscvtest.hex build/book_iss.trace
	python3 dv/compare.py build/book_iss.trace build/book_single.trace

single:
	python3 dv/regress.py single --seeds $(SEEDS) --len $(LEN) --quiet

pipe:
	python3 dv/regress.py pipe --seeds $(SEEDS) --len $(LEN) --quiet

bugs:
	python3 dv/bughunt.py --seeds 20 --len 300

wave:
	@mkdir -p build/wave
	verilator $(VFLAGS) --trace -DPIPELINE -Mdir build/wave -o Vtb $(COMMON) rtl/pipe/hazard.sv rtl/pipe/priv.sv rtl/pipe/core_pipe.sv rtl/pipe/dcache.sv rtl/uncore/uncore.sv tb/tb.sv
	./build/wave/Vtb +HEX=tests/book/riscvtest.hex +VCD
	@echo "open with: gtkwave wave.vcd"

clean:
	rm -rf build wave.vcd

bus:
	python3 dv/regress.py pipe --seeds $(SEEDS) --len $(LEN) --quiet
	@mkdir -p build/ahb
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_ahb -Mdir build/ahb -o Vtb rtl/uncore/uncore.sv tb/tb_ahb.sv
	for s in 1 2 3 4 5; do ./build/ahb/Vtb +SEED=$$s +CYCLES=20000 | grep AHBTB; done

bushunt:
	python3 dv/bushunt.py --seeds 5 --cycles 20000

busperf:
	python3 dv/busperf.py

cache:
	python3 dv/regress.py pipe --seeds $(SEEDS) --len $(LEN) --quiet
	python3 dv/regress.py pipe --seeds 20 --len 300 --quiet --gparams="-GDC_WAYS=1 -GDC_SETS=16"
	python3 dv/regress.py pipe --seeds 20 --len 300 --quiet --gparams="-GRAM_WAIT=2 -GDC_WAYS=4 -GDC_SETS=4"
	python3 dv/regress.py pipe --seeds 20 --len 300 --quiet --gparams="-GDC_WAYS=8 -GDC_SETS=2 -GDC_LINEWORDS=8"

cachehunt:
	python3 dv/cachehunt.py --seeds 10 --ops 300

cacheperf:
	python3 dv/cacheperf.py

mmu:
	python3 dv/regress.py pipe --seeds $(SEEDS) --len $(LEN) --quiet
	python3 dv/regress.py pipe --seeds 10 --len 300 --quiet --gparams="-GTLB_ENTRIES=1"
	python3 dv/regress.py pipe --seeds 10 --len 300 --quiet --gparams="-GTLB_ENTRIES=8 -GRAM_WAIT=2"

mmuhunt:
	python3 dv/mmuhunt.py --seeds 10 --ops 300

mmuperf:
	python3 dv/mmuperf.py

lsu:
	python3 dv/regress.py pipe --seeds $(SEEDS) --len $(LEN) --quiet
	python3 dv/regress.py pipe --seeds 10 --len 300 --quiet --gparams="-GDC_SYNC=0"
	python3 dv/regress.py pipe --seeds 10 --len 300 --quiet --gparams="-GRAM_WAIT=2 -GDC_WAYS=4 -GDC_SETS=4"

lsuhunt:
	python3 dv/lsuhunt.py --seeds 10 --ops 300

lsuperf:
	python3 dv/lsuperf.py

bp:
	python3 dv/regress.py pipe --seeds $(SEEDS) --len $(LEN) --quiet
	python3 dv/regress.py pipe --seeds 10 --len 300 --quiet --gparams="-GBP_TYPE=0"
	python3 dv/regress.py pipe --seeds 10 --len 300 --quiet --gparams="-GBP_TYPE=1"
	python3 dv/regress.py pipe --seeds 10 --len 300 --quiet --gparams="-GBP_TYPE=2 -GBTB_BITS=4 -GBHT_BITS=6"

bphunt:
	python3 dv/bphunt.py --seeds 10 --blocks 25

bpperf:
	python3 dv/bpperf.py

.PHONY: book-single single pipe bugs wave clean bus bushunt busperf cache cachehunt cacheperf mmu mmuhunt mmuperf lsu lsuhunt lsuperf bp bphunt bpperf

periph:
	@mkdir -p build/periph
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_periph -Mdir build/periph -o Vtb rtl/uncore/periph.sv tb/tb_periph.sv
	for s in 1 2 3 4 5; do ./build/periph/Vtb +SEED=$$s +ITER=300 | grep -E "COVERAGE|PERIPH"; ./build/periph/Vtb +SEED=$$s +ITER=300 +BOOKPLAN | grep PERIPH; done

periphhunt:
	python3 dv/periphhunt.py --seeds 5 --iter 300

periphdemo:
	@mkdir -p build/demo
	verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module tb_periph_demo -Mdir build/demo -o Vtb rtl/uncore/periph.sv tb/tb_periph_demo.sv
	./build/demo/Vtb > build/demo.txt && grep -c "V " build/demo.txt
