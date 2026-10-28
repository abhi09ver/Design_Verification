#!/usr/bin/env python3
"""minperiod.py net.json lib -> smallest clock period (ns) with WNS >= 0 (bisection over sta.py).
Needed because half-cycle (negedge) paths scale with T/2, so T - WNS is not exact."""
import subprocess, sys, json, tempfile, os
net, lib = sys.argv[1], sys.argv[2]
def wns(T):
    f = tempfile.mktemp(suffix='.json')
    subprocess.run([sys.executable, 'sta.py', net, lib, '--period', str(T), '--json', f], capture_output=True, check=True)
    w = json.load(open(f))['wns']; os.remove(f); return w
lo, hi = 1.0, 20.0
for _ in range(14):
    mid = (lo + hi) / 2
    (hi := mid) if wns(mid) >= 0 else (lo := mid)
print('%.3f' % hi)
