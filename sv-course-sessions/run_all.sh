#!/usr/bin/env bash
# Compile and run every solution with Verilator, saving outputs to logs/.
#
# Requirements:
#   - Verilator >= 5.030 (constraints and covergroups need a recent version;
#     verified with 5.052) and z3 on PATH for randomize()
#   - For session 2 only: the Accellera UVM library
#       git clone --depth 1 https://github.com/accellera-official/uvm-core.git
#     then set UVM_HOME=/path/to/uvm-core
#
# Usage:  ./run_all.sh            # all sessions
#         ./run_all.sh 3          # just session 3
set -u
cd "$(dirname "$0")"
OUT=logs
BUILD=${BUILD:-/tmp/sv_course_build}
VFLAGS="--binary -Wno-fatal -Wno-lint -Wno-style -j 2"
mkdir -p "$OUT" "$BUILD"
want() { [ $# -eq 0 ] || [ -z "${SEL:-}" ] || [ "$SEL" = "$1" ]; }
SEL=${1:-}

run() {   # run <name> <top-file> [extra verilator args...] -- [sim args...]
  local name=$1 file=$2; shift 2
  local vargs=() sargs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do vargs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  sargs=("$@")
  echo "=== $name"
  rm -rf "$BUILD/$name"
  if ! verilator $VFLAGS "${vargs[@]}" --Mdir "$BUILD/$name" "$file" --top-module tb \
        > "$BUILD/$name.compile.log" 2>&1; then
    echo "    compile FAILED - see $BUILD/$name.compile.log"; return 1
  fi
  (cd "$BUILD/$name" && ./Vtb "${sargs[@]}") 2>&1 | grep -v "^- " | tee "$OUT/$name.log" | tail -3
}

if [ -z "$SEL" ] || [ "$SEL" = 1 ]; then
  run s1_data_structures code/session1_data_structures/sv_ds_solutions.sv
  run s1_slide52_array_ops code/session1_data_structures/slide52_array_ops.sv
fi
if [ -z "$SEL" ] || [ "$SEL" = 2 ]; then
  if [ -n "${UVM_HOME:-}" ]; then
    for p in AXI AHB; do
      run "s2_layered_agent_$p" code/session2_layered_uvm_agent/session2_layered_axi_ahb_agent.sv \
        --timing -Wno-SYMRSVDWORD -Wno-ZERODLY +define+UVM_NO_DPI \
        +define+UVM_REPORT_DISABLE_FILE_LINE "+incdir+$UVM_HOME/src" "$UVM_HOME/src/uvm_pkg.sv" \
        -- "+PROTO=$p" +UVM_NO_RELNOTES
    done
  else
    echo "=== session 2 skipped: set UVM_HOME to an Accellera uvm-core checkout"
  fi
fi
if [ -z "$SEL" ] || [ "$SEL" = 3 ]; then
  run s3_apb_tb_clean code/session3_apb_dual_port_tb/session3_apb_dual_port_tb.sv --timing
  run s3_apb_tb_bug   code/session3_apb_dual_port_tb/session3_apb_dual_port_tb.sv --timing -- +BUG
fi
if [ -z "$SEL" ] || [ "$SEL" = 4 ]; then
  run s4_constraints code/session4_constraints/session4_constraints.sv
fi
if [ -z "$SEL" ] || [ "$SEL" = 5 ]; then
  run s5_apb_coverage code/session5_apb_coverage/session5_apb_coverage.sv --coverage
fi
