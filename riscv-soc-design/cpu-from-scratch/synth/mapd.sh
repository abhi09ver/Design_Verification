#!/bin/bash
# usage: mapd.sh <target_ps> <generic.il> <tag>   delay-driven ABC mapping (strash; dch; map -D; buffer; upsize; dnsize)
D=$1; G=$2; T=$3
printf 'strash\ndch -f\nmap -D %s\nbuffer -p\nupsize -D %s\ndnsize -D %s\n' $D $D $D > abc_${T}_$D.scr
cat > map_${T}_$D.ys <<EOY
read_rtlil $G
dfflibmap -liberty hd_tt.lib -dont_use *lpflow*
abc -liberty hd_tt.lib -dont_use *lpflow* -dont_use *clkbuf* -dont_use *clkinv* -constr abc.constr -D $D -script abc_${T}_$D.scr
opt_clean
setundef -zero
hilomap -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO
tee -q -o stat_${T}_$D.txt stat -liberty hd_tt.lib
write_json net_${T}_$D.json
write_verilog -noattr net_${T}_$D.v
EOY
timeout 1800 yowasp-yosys -q map_${T}_$D.ys > map_${T}_$D.log 2>&1
P=$(python3 -c "print($D/1000)")
python3 sta.py net_${T}_$D.json hd_tt.lib --period $P --json sum_${T}_$D.json > sta_${T}_$D.txt
