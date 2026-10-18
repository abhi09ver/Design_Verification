#!/bin/bash
# One build per TB; the bug is chosen at run time with +MUT=n (rtl_mut/).
# Original course TB: 50 tr x 10 seeds. Failures split into
#   REAL  = scoreboard mismatch      FALSE = misalignment $fatal (TB bug)
#   HUNG  = never finished; the original TB has no watchdog, killed by timeout
# Fixed course TB: 500 tr, tests default+mem, 3 seeds each (6 runs).
Q=$(cd "$(dirname "$0")" && pwd)   # needs verilator + z3 on PATH
cd $Q; mkdir -p mrun; OUT=$Q/mutation.txt; : > $OUT
NAMES=(clean Y1_slt_magnitude Y2_branch_signedness Y3_jalr_phantom_load P1_no_instr_latch P2_fetch_while_pending P3_pc_ignores_ready P4_load_no_wait P5_sub_as_add P6_lbu_sign_extends)
printf "%-3s %-24s | %-30s | %s\n" n mutant "ORIGINAL TB real/false/hung" "FIXED TB detected  (why)" | tee -a $OUT
for n in $(seq 0 9); do
  real=0; fa=0; hung=0
  for s in $(seq 1 10); do L=mrun/c$n.$s.log
    timeout 20 obj_mc/Vyarp_tb_top +MUT=$n +verilator+seed+$s +NUM_TR=50 > $L 2>&1; rc=$?
    if grep -q "Mismatch" $L; then real=$((real+1))
    elif [ $rc = 124 ]; then hung=$((hung+1))
    elif ! grep -q "Finished running" $L; then fa=$((fa+1)); fi
  done
  det=0
  for t in default mem; do for s in 1 2 3; do L=mrun/f$n.$t.$s.log
    timeout 120 obj_mf/Vyarp_tb_top +MUT=$n +verilator+seed+$s +TEST=$t +NUM_TR=500 > $L 2>&1
    if ! grep -q "PASS, 500 instructions" $L || grep -q "Fatal" $L; then det=$((det+1)); fi
  done; done
  why=$(grep -hoE "\[MODEL\] [a-z0-9]+ mismatch|INCOMPLETE|WATCHDOG" mrun/f$n.*.log | sed 's/x[0-9]* mismatch/reg mismatch/' | sort | uniq -c | sort -rn | head -1 | tr -s ' ')
  printf "%-3s %-24s | real %2d  false %2d  hung %2d  /10 | %d/6 %s\n" $n ${NAMES[$n]} $real $fa $hung $det "$why" | tee -a $OUT
done
echo DONE | tee -a $OUT
