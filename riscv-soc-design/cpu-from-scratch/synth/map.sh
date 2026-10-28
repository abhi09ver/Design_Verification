#!/bin/bash
# usage: map.sh <target_ps> [generic.il] [tag]
D=$1; G=${2:-core_generic.il}; T=${3:-rc}
cat > map_${T}_$D.ys <<EOY
read_rtlil $G
dfflibmap -liberty hd_tt.lib -dont_use *lpflow*
abc -liberty hd_tt.lib -dont_use *lpflow* -dont_use *clkbuf* -dont_use *clkinv* -constr abc.constr -D $D
opt_clean
setundef -zero
hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO
tee -q -o stat_${T}_$D.txt stat -liberty hd_tt.lib
write_json net_${T}_$D.json
write_verilog -noattr net_${T}_$D.v
EOY
timeout 1200 yowasp-yosys -q map_${T}_$D.ys > map_${T}_$D.log 2>&1
