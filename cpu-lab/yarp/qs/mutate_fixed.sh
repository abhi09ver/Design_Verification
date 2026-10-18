#!/bin/bash
# Fixed course TB, final regression per mutant: tests default+mem+cmp x 3 seeds = 9 runs
Q=$(cd "$(dirname "$0")" && pwd)   # needs verilator + z3 on PATH
cd $Q; mkdir -p mrun3; OUT=$Q/mutation_fixed_final.txt; : > $OUT
NAMES=(clean Y1_slt_magnitude Y2_branch_signedness Y3_jalr_phantom_load P1_no_instr_latch P2_fetch_while_pending P3_pc_ignores_ready P4_load_no_wait P5_sub_as_add P6_lbu_sign_extends)
for n in $(seq 0 9); do
  det=0; per=""
  for t in default mem cmp; do k=0; for s in 1 2 3; do L=mrun3/f$n.$t.$s.log
    timeout 150 obj_mf3/Vyarp_tb_top +MUT=$n +verilator+seed+$s +TEST=$t +NUM_TR=500 > $L 2>&1
    if ! grep -q "PASS, 500 instructions" $L || grep -qE "Fatal|\[SVA\]" $L; then det=$((det+1)); k=$((k+1)); fi
  done; per="$per $t=$k/3"; done
  why=$(grep -hoE "\[SVA\] R[0-9-]+|\[MODEL\] [a-z0-9]+ mismatch|\[MODEL\] mem mismatch|INCOMPLETE|WATCHDOG" mrun3/f$n.*.log | sed 's/x[0-9]* mismatch/reg mismatch/' | sort | uniq -c | sort -rn | head -1 | tr -s ' ')
  holes=$(grep -h "HOLE" mrun3/f$n.*.log | wc -l)
  printf "%-3s %-24s fixed TB %d/9  (%s) |%s | runs with coverage holes: %d\n" $n ${NAMES[$n]} $det "$per" "$why" $holes | tee -a $OUT
done
echo DONE | tee -a $OUT
