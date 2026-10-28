#!/bin/bash
# Lab 4 (book Ch 6): synthesize core_pipe onto SKY130 HD with Yosys/ABC, time it with sta.py.
# Needs: pip install yowasp-yosys ; the SKY130 HD typical liberty as hd_tt.lib (see README)
set -e
cd "$(dirname "$0")"
[ -f hd_tt.lib ] || curl -sSL -o hd_tt.lib https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
yowasp-yosys -q pre.ys            # generic netlist, Yosys default adders (Brent-Kung $lcu)
yowasp-yosys -q pre_ks.ys         # same, Kogge-Stone carry network
for T in rc ks; do G=core_generic.il; [ $T = ks ] && G=core_generic_ks.il
  for D in 2500 3000 3500 4000 4500 5000 6000 8000 10000; do ./mapd.sh $D $G $T & done; wait; done
for f in sta_rc_*.txt sta_ks_*.txt; do echo "$f: $(tail -1 $f)"; done
python3 power.py net_ks_4000.json hd_tt.lib --freq-mhz 200
yowasp-yosys -q hier.ys && sed -n '/design hierarchy/,/^$/p' stat_hier.txt | head -3
