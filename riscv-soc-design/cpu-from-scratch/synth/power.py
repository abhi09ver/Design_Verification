#!/usr/bin/env python3
"""power.py -- first-principles power estimate of a mapped netlist (vectorless, like DC's default).

  switching energy per cycle  = sum over nets of  alpha * C_net * VDD^2
        alpha = 1.0 for the clock (it rises once every cycle), 0.1 for every other net
        (Design Compiler's default activity), C_net = sum of driven input-pin caps.
  internal energy per cycle   = flop clock-pin internal energy (rise + fall, from the .lib
        internal_power tables) + alpha * output-pin internal energy of logic cells
  leakage power               = sum of cell_leakage_power (state-averaged in the .lib)

  P = E_cycle * f + P_leak      E_cycle is independent of f -- the book's point that
  energy per cycle is the better metric.
Usage: python3 power.py net.json hd_tt.lib --freq-mhz 250
"""
import argparse, json, re
from collections import defaultdict
from sta import extract_cells

def first_vals(block, kind):
    m = re.search(kind + r'\s*\("[^"]*"\)\s*\{.*?values\s*\(\s*"([^"]*)"', block, re.S)
    if not m: return None
    v = [float(x) for x in m.group(1).split(',')]
    return v[len(v)//3]                     # a mid-table entry: typical slew/load

def pins(text):
    out = {}
    for m in re.finditer(r'\bpin\s*\("?(\w+)"?\)\s*\{', text):
        s = m.end(); d = 1; k = s
        while d: d += (text[k] == '{') - (text[k] == '}'); k += 1
        out[m.group(1)] = text[s:k-1]
    return out

ap = argparse.ArgumentParser()
ap.add_argument('net'); ap.add_argument('lib'); ap.add_argument('--freq-mhz', type=float, required=True)
ap.add_argument('--alpha', type=float, default=0.1); ap.add_argument('--vdd', type=float, default=1.8)
a = ap.parse_args()
mod = next(iter(json.load(open(a.net))['modules'].values()))
cells = {n: c for n, c in mod['cells'].items() if not c['type'].startswith('$')}
lib = extract_cells(open(a.lib).read(), sorted({c['type'] for c in cells.values()}))
info = {}
for t, txt in lib.items():
    P = pins(txt); d = {'leak': float(re.search(r'cell_leakage_power\s*:\s*([0-9.eE+-]+)', txt).group(1)),
                       'cap': {}, 'dir': {}, 'clk_int': 0.0, 'out_int': 0.0}
    for p, b in P.items():
        dr = re.search(r'direction\s*:\s*"?(\w+)', b); d['dir'][p] = dr.group(1) if dr else '?'
        c = re.search(r'\n\s*capacitance\s*:\s*([0-9.]+)', b); d['cap'][p] = float(c.group(1)) if c else 0.0
        rp, fp = first_vals(b, 'rise_power'), first_vals(b, 'fall_power')
        if p == 'CLK' and rp is not None: d['clk_int'] = rp + fp
        elif d['dir'][p] == 'output' and rp is not None: d['out_int'] = (rp + fp) / 2
    info[t] = d

clk_bits = set(b for b in mod['ports']['clk']['bits'])
grew = True                      # the clock tree: every buffer/inverter net fed from clk
while grew:
    grew = False
    for c in cells.values():
        A = c['connections'].get('A', [None])[0]
        if A in clk_bits and ('__buf' in c['type'] or '__inv' in c['type']):
            o = (c['connections'].get('X') or c['connections'].get('Y'))[0]
            if o not in clk_bits: clk_bits.add(o); grew = True
netcap = defaultdict(float)
for c in cells.values():
    d = info[c['type']]
    for p, bits in c['connections'].items():
        if d['dir'][p] == 'input':
            for b in bits:
                if isinstance(b, int): netcap[b] += d['cap'][p]
V2 = a.vdd ** 2
E_clk_sw = sum(C for b, C in netcap.items() if b in clk_bits) * V2          # pF*V^2 = pJ
E_dat_sw = sum(C for b, C in netcap.items() if b not in clk_bits) * V2 * a.alpha
E_clk_int = sum(info[c['type']]['clk_int'] for c in cells.values())
def on_clock(c):
    return any(b in clk_bits for p_, bits in c['connections'].items() for b in bits if info[c['type']]['dir'][p_] == 'output')
E_clktree_int = sum(info[c['type']]['out_int'] for c in cells.values() if on_clock(c))   # alpha = 1
E_log_int = sum(info[c['type']]['out_int'] for c in cells.values() if not info[c['type']]['clk_int'] and not on_clock(c)) * a.alpha
leak_nW = sum(info[c['type']]['leak'] for c in cells.values())
E = E_clk_sw + E_dat_sw + E_clk_int + E_log_int + E_clktree_int
f = a.freq_mhz * 1e6
print('energy per cycle (pJ): clock-net switching %.1f, clock-buffer internal %.1f, flop clock internal %.1f, data switching %.1f, logic internal %.1f  -> total %.1f'
      % (E_clk_sw, E_clktree_int, E_clk_int, E_dat_sw, E_log_int, E))
print('clock tree: %d nets' % len(clk_bits))
print('at %.0f MHz: dynamic %.2f mW, leakage %.1f nW (%.4f%% of dynamic)'
      % (a.freq_mhz, E * 1e-12 * f * 1e3, leak_nW, leak_nW * 1e-9 / (E * 1e-12 * f) * 100))
