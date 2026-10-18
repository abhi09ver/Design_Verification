#!/bin/bash
# usage: build.sh <tbdir> <objdir> [extra verilator args]
Q=$(cd "$(dirname "$0")" && pwd)
# Needs a recent Verilator 5.x (constrained randomize) with z3 on PATH; tested with the pip build here
VERILATOR=${VERILATOR:-verilator}
TB=$1; OBJ=$2; shift 2
R=${RTLDIR:-$Q/rtl_vr}
$VERILATOR --binary --timing --assert -j 4 -Wno-fatal -Wno-lint -Wno-style -Wno-UNOPTFLAT \
  +define+QS_VCD_DUMP_NAME=\"$OBJ/dump.vcd\" +define+YARP_REGFILE=yarp_tb_top.YARP.u_yarp_regfile \
  -CFLAGS -DYARP_RESET_PC=0x1000u --top-module yarp_tb_top -Mdir $OBJ -I$TB \
  $R/yarp_pkg.sv $R/yarp_pkg1.sv $R/yarp_decode.sv $R/yarp_control.sv $R/yarp_execute.sv $R/yarp_branch_control.sv \
  $R/yarp_regfile.sv $R/yarp_data_mem.sv $R/yarp_top.sv \
  $TB/riscv_pkg.sv $TB/yarp_tb_pkg.sv $TB/yarp_tb_top.sv $Q/model/yarp_model.cpp "$@"
