#!/bin/bash
# Builds and runs every level. Usage: ./run_all.sh   (or ./run_all.sh 6  for one level)
V=${VERILATOR:-verilator}
declare -A FILES=( [01]="L01_adder.sv" [02]="L02_counter.sv" [03]="L03_alu.sv" [04]="L04_regfile.sv"
  [05]="L05_fifo.sv" [06]="L03_alu.sv L04_regfile.sv L06_tiny_cpu.sv" [07]="L07_scoreboard.sv"
  [08]="L08_rename.sv" [09]="L09_rs_cdb.sv" [10]="L10_rob.sv" [11]="L11_tiny_ooo.sv" )
for n in $(printf '%s\n' "${!FILES[@]}" | sort); do
  [ -n "$1" ] && [ "$((10#$1))" != "$((10#$n))" ] && continue
  $V --binary -Wno-fatal -Wno-lint -Wno-style --timing -sv --top-module tb_L$n \
     -CFLAGS "-std=c++20" --Mdir obj/L$n ${FILES[$n]} -o sim > obj_L$n.log 2>&1 \
     || { echo "L$n: BUILD FAILED (see obj_L$n.log)"; continue; }
  ./obj/L$n/sim | grep -v '^- '
done
