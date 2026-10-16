# AXI4 slave RAM - build & run with free iverilog
#   make            run default test (seed 1)
#   make sim SEED=7 NRAND=1000 BP=1
#   make regress    10 seeds, half with back-pressure; fails if any seed fails
#   make mutants    plant 3 bugs; each MUST be caught (proves the checker works)
#   make waves      open the VCD in GTKWave

SEED  ?= 1
NRAND ?= 300
BP    ?= 0
OUT   := out
SRCS  := rtl/axi4_slave_ram.v tb/tb_axi4_slave_ram.sv
PLUS  := +SEED=$(SEED) +NRAND=$(NRAND) $(if $(filter 1,$(BP)),+BP,)

.PHONY: all sim regress mutants waves clean
all: sim

$(OUT)/sim: $(SRCS)
	@mkdir -p $(OUT)
	iverilog -g2012 -o $@ $(SRCS)

sim: $(OUT)/sim
	cd $(OUT) && vvp -n sim $(PLUS)

regress: $(OUT)/sim
	@fail=0; for s in 1 2 3 4 5 6 7 8 9 10; do \
	  bp=$$( [ $$((s % 2)) -eq 0 ] && echo +BP ); \
	  if (cd $(OUT) && vvp -n sim +SEED=$$s +NRAND=$(NRAND) $$bp > seed_$$s.log 2>&1); \
	  then echo "PASS seed=$$s $$bp"; else echo "FAIL seed=$$s $$bp  (see $(OUT)/seed_$$s.log)"; fail=1; fi; \
	done; exit $$fail

mutants:
	@mkdir -p $(OUT); fail=0; \
	for m in BUG_IGNORE_WSTRB BUG_WRAP_AS_INCR BUG_RLAST_EARLY; do \
	  iverilog -g2012 -D$$m -o $(OUT)/mut_$$m $(SRCS) || exit 1; \
	  if (cd $(OUT) && vvp -n mut_$$m > mut_$$m.log 2>&1); \
	  then echo "NOT CAUGHT  $$m   <-- checker is too weak"; fail=1; \
	  else echo "caught      $$m   ($$(grep -m1 ERROR $(OUT)/mut_$$m.log | sed 's/.*ERROR: //'))"; fi; \
	done; exit $$fail

waves:
	gtkwave $(OUT)/tb_axi4_slave_ram.vcd &

clean:
	rm -rf $(OUT)
