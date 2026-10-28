#!/usr/bin/env python3
"""sta.py -- a small static timing analyzer, written from first principles.

What a real STA tool (PrimeTime, OpenSTA, Design Compiler's report_timing) does,
reduced to the essentials so every number can be traced by hand:

  1. Read the cell library (.lib): for every timing arc A->Y of every cell, a
     2-D lookup table delay(input_slew, output_load) and slew(input_slew, load),
     separately for rising and falling outputs, plus the arc's unateness.
  2. Read the mapped netlist (Yosys JSON).  Load on a net = sum of the input-pin
     capacitances it drives (ideal wires, like the book's "Wire Load Model: top"
     with zero wire cap; real flows add wire RC).
  3. Launch: every flop Q starts at t = clk->Q (looked up at the Q load).
     Primary inputs start at t = 0 (an "input delay" of 0).
  4. Propagate in topological order: arrival(out) = max over inputs of
     arrival(in) + delay(arc), tracking rise and fall separately.
  5. Capture: every flop D/DE must arrive by  T - setup(D)  (and an uncertainty).
     slack = required - arrival.  Worst slack (WNS), total negative slack (TNS).

Usage: python3 sta.py net.json hd_tt.lib --period 3.0 [--uncertainty 0.1] [--paths 1]
"""
import argparse, json, re, sys, bisect
from collections import defaultdict

# ---------------------------------------------------------------- liberty
def extract_cells(libtext, names):
    """Pull the cell("name"){...} blocks we need out of the 13 MB library."""
    out = {}
    for n in names:
        i = libtext.find('cell ("%s")' % n)
        if i < 0:
            i = libtext.find('cell (%s)' % n)
        if i < 0:
            raise SystemExit("cell %s not in library" % n)
        j = libtext.index('{', i); depth = 0
        for k in range(j, len(libtext)):
            c = libtext[k]
            if c == '{': depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0: break
        out[n] = libtext[i:k+1]
    return out

num = re.compile(r'[-+0-9.eE]+')
def table(block, kind):
    """kind = cell_rise / rise_transition / rise_constraint ... -> (idx1, idx2, values)"""
    m = re.search(kind + r'\s*\("[^"]*"\)\s*\{(.*?)\}', block, re.S)
    if not m: return None
    body = m.group(1)
    def arr(key):
        mm = re.search(key + r'\s*\(\s*"([^)]*)"\s*\)', body, re.S)
        return [float(x) for x in num.findall(mm.group(1))] if mm else None
    i1 = arr('index_1'); i2 = arr('index_2')
    vm = re.search(r'values\s*\((.*?)\)\s*;', body, re.S)
    rows = [[float(x) for x in num.findall(r)] for r in re.findall(r'"([^"]*)"', vm.group(1))]
    return (i1, i2, rows)

def lookup(t, x, y):
    """Bilinear interpolation (extrapolates linearly at the edges, like STA tools)."""
    i1, i2, v = t
    if i2 is None or len(v) == 1:            # 1-D table
        xs = i1 if len(v) == 1 else i1
        row = v[0] if len(v) == 1 else [r[0] for r in v]
        key = y if len(v) == 1 else x
        return interp1(xs if len(v) > 1 else (i2 or i1), row, key)
    def seg(a, q):
        k = min(max(bisect.bisect_left(a, q) - 1, 0), len(a) - 2)
        return k, (q - a[k]) / (a[k+1] - a[k])
    a, fa = seg(i1, x); b, fb = seg(i2, y)
    v00, v01, v10, v11 = v[a][b], v[a][b+1], v[a+1][b], v[a+1][b+1]
    return (v00*(1-fa)*(1-fb) + v01*(1-fa)*fb + v10*fa*(1-fb) + v11*fa*fb)

def interp1(xs, ys, q):
    k = min(max(bisect.bisect_left(xs, q) - 1, 0), len(xs) - 2)
    f = (q - xs[k]) / (xs[k+1] - xs[k])
    return ys[k] + f * (ys[k+1] - ys[k])

def parse_cell(text):
    """-> {'pins': {pin: {'dir','cap','arcs':[...]}}, 'area': a}"""
    cell = {'pins': {}, 'area': float(re.search(r'area\s*:\s*([0-9.]+)', text).group(1))}
    # walk pin("X") { ... } blocks at depth 1 inside the cell
    for m in re.finditer(r'\bpin\s*\("?(\w+)"?\)\s*\{', text):
        s = m.end(); depth = 1; k = s
        while depth:
            c = text[k]
            depth += (c == '{') - (c == '}'); k += 1
        body = text[s:k-1]
        name = m.group(1)
        d = re.search(r'direction\s*:\s*"?(\w+)', body)
        cap = re.search(r'\n\s*capacitance\s*:\s*([0-9.]+)', body)
        pin = {'dir': d.group(1) if d else '?', 'cap': float(cap.group(1)) if cap else 0.0, 'arcs': []}
        for tm in re.finditer(r'\btiming\s*\(\s*\)\s*\{', body):
            s2 = tm.end(); depth = 1; k2 = s2
            while depth:
                c = body[k2]; depth += (c == '{') - (c == '}'); k2 += 1
            tb = body[s2:k2-1]
            rp = re.search(r'related_pin\s*:\s*"(\w+)"', tb).group(1)
            ty = re.search(r'timing_type\s*:\s*"?(\w+)', tb)
            se = re.search(r'timing_sense\s*:\s*"?(\w+)', tb)
            arc = {'from': rp, 'type': ty.group(1) if ty else 'combinational',
                   'sense': se.group(1) if se else 'non_unate'}
            for k_ in ('cell_rise', 'cell_fall', 'rise_transition', 'fall_transition',
                       'rise_constraint', 'fall_constraint'):
                arc[k_] = table(tb, k_)
            pin['arcs'].append(arc)
        cell['pins'][name] = pin
    return cell

# ---------------------------------------------------------------- netlist
def load_netlist(path):
    j = json.load(open(path))
    mod = next(iter(j['modules'].values()))
    names = {}
    for n, d in mod['netnames'].items():
        for i, b in enumerate(d['bits']):
            if isinstance(b, int) and (b not in names or not n.startswith('$')):
                names[b] = n if len(d['bits']) == 1 else '%s[%d]' % (n, i)
    return mod, names

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('net'); ap.add_argument('lib')
    ap.add_argument('--period', type=float, required=True, help='ns')
    ap.add_argument('--uncertainty', type=float, default=0.0)
    ap.add_argument('--input-slew', type=float, default=0.05)
    ap.add_argument('--paths', type=int, default=1)
    ap.add_argument('--json', help='write summary JSON here')
    a = ap.parse_args()

    mod, names = load_netlist(a.net)
    cells = {n: c for n, c in mod['cells'].items() if not c['type'].startswith('$')}
    used = sorted({c['type'] for c in cells.values()})
    libtext = open(a.lib).read()
    lib = {n: parse_cell(t) for n, t in extract_cells(libtext, used).items()}

    # net -> driver (cell, pin) and sinks
    driver, sinks = {}, defaultdict(list)
    for cn, c in cells.items():
        L = lib[c['type']]
        for p, bits in c['connections'].items():
            for b in bits:
                if not isinstance(b, int): continue
                if L['pins'][p]['dir'] == 'output': driver[b] = (cn, p)
                else: sinks[b].append((cn, p))
    load = defaultdict(float)
    for b, ss in sinks.items():
        for cn, p in ss:
            load[b] += lib[cells[cn]['type']]['pins'][p]['cap']
    for p, d in mod['ports'].items():           # output ports: assume 1 fF-ish load
        if d['direction'] == 'output':
            for b in d['bits']:
                if isinstance(b, int): load[b] += 0.002

    # timing state per net: arrival / slew for rise (0) and fall (1), plus back-pointer
    INF = -1e9
    arr = defaultdict(lambda: [INF, INF]); slew = defaultdict(lambda: [a.input_slew]*2)
    prev = {}
    def isflop(t): return any(arc['type'].startswith('rising_edge') for p in lib[t]['pins'].values() for arc in p['arcs'])

    # clock phase per flop: a flop whose CLK pin is driven by an inverter of the clk port is a
    # negedge flop (e.g. the register file, written on the falling edge like Wally). It launches
    # at T/2 and, when it captures, its data is required by T/2 - setup.
    # walk the clock tree forward from the clk port through buffers/inverters, tracking polarity
    clkpol = {b: 0 for b in (mod['ports']['clk']['bits'] if 'clk' in mod['ports'] else [])}
    changed = True
    while changed:
        changed = False
        for cn, c in cells.items():
            t = c['type']; A = c['connections'].get('A', [None])[0]
            if A in clkpol and ('__buf' in t or '__inv' in t or '__clkbuf' in t or '__clkinv' in t):
                o = (c['connections'].get('X') or c['connections'].get('Y'))[0]
                if o not in clkpol:
                    clkpol[o] = clkpol[A] ^ ('inv' in t); changed = True
    negclk = {b for b, p in clkpol.items() if p}
    phase = {cn: (a.period / 2 if c['connections'].get('CLK', [None])[0] in negclk else 0.0)
             for cn, c in cells.items() if 'CLK' in c['connections']}
    if negclk: print('negedge flops: %d (launch at T/2, capture by T/2 - setup)' % sum(1 for v in phase.values() if v))

    # launch points
    for p, d in mod['ports'].items():
        if d['direction'] == 'input' and p not in ('clk',):
            for b in d['bits']:
                if isinstance(b, int): arr[b] = [0.0, 0.0]; prev[(b, 0)] = prev[(b, 1)] = None
    for cn, c in cells.items():
        L = lib[c['type']]
        if not isflop(c['type']):
            # tie cells (conb) drive constants: no transition, arrival 0
            if all(not pin['arcs'] for pin in L['pins'].values() if pin['dir'] == 'output'):
                for p, bits in c['connections'].items():
                    if L['pins'][p]['dir'] == 'output':
                        for b in bits: arr[b] = [0.0, 0.0]; prev[(b,0)] = prev[(b,1)] = None
            continue
        for p, bits in c['connections'].items():
            pin = L['pins'][p]
            if pin['dir'] != 'output': continue
            for arc in pin['arcs']:
                if arc['type'] == 'rising_edge':
                    b = bits[0]
                    r = lookup(arc['cell_rise'], a.input_slew, load[b])
                    f = lookup(arc['cell_fall'], a.input_slew, load[b])
                    arr[b] = [r + phase.get(cn, 0.0), f + phase.get(cn, 0.0)]
                    slew[b] = [lookup(arc['rise_transition'], a.input_slew, load[b]),
                               lookup(arc['fall_transition'], a.input_slew, load[b])]
                    prev[(b, 0)] = prev[(b, 1)] = ('LAUNCH', cn, c['type'], p)

    # topological propagation through combinational cells (Kahn's algorithm)
    comb = [cn for cn, c in cells.items() if not isflop(c['type'])]
    indeg = {}
    users = defaultdict(list)
    for cn in comb:
        c = cells[cn]; L = lib[c['type']]; n = 0
        for p, bits in c['connections'].items():
            if L['pins'][p]['dir'] == 'output': continue
            for b in bits:
                if isinstance(b, int) and b in driver and not isflop(cells[driver[b][0]]['type']):
                    n += 1; users[driver[b][0]].append(cn)
        indeg[cn] = n
    ready = [cn for cn in comb if indeg[cn] == 0]
    order = []
    while ready:
        cn = ready.pop(); order.append(cn)
        for u in users[cn]:
            indeg[u] -= 1
            if indeg[u] == 0: ready.append(u)
    if len(order) != len(comb):
        print('warning: combinational loop? %d of %d cells ordered' % (len(order), len(comb)))

    for cn in order:
        c = cells[cn]; L = lib[c['type']]
        for p, bits in c['connections'].items():
            pin = L['pins'][p]
            if pin['dir'] != 'output' or not pin['arcs']: continue
            ob = bits[0]
            best = [INF, INF]; bslew = [0.0, 0.0]; bp = [None, None]
            for arc in pin['arcs']:
                if arc['type'] != 'combinational': continue
                ib = c['connections'][arc['from']][0]
                if not isinstance(ib, int): continue
                for oe in (0, 1):                     # 0 = output rises, 1 = output falls
                    srcs = {'positive_unate': [oe], 'negative_unate': [1-oe]}.get(arc['sense'], [0, 1])
                    tab = arc['cell_rise' if oe == 0 else 'cell_fall']
                    ttab = arc['rise_transition' if oe == 0 else 'fall_transition']
                    if tab is None: continue
                    for ie in srcs:
                        if arr[ib][ie] <= INF/2: continue
                        d = lookup(tab, slew[ib][ie], load[ob])
                        t = arr[ib][ie] + d
                        if t > best[oe]:
                            best[oe] = t; bslew[oe] = lookup(ttab, slew[ib][ie], load[ob])
                            bp[oe] = (ib, ie, cn, c['type'], arc['from'], p, d)
            arr[ob] = best; slew[ob] = bslew
            prev[(ob, 0)], prev[(ob, 1)] = bp

    # capture: setup checks at flop data pins
    ends = []
    for cn, c in cells.items():
        if not isflop(c['type']): continue
        T = (a.period / 2 if phase.get(cn, 0.0) else a.period) - a.uncertainty
        L = lib[c['type']]
        for p, bits in c['connections'].items():
            pin = L['pins'][p]
            for arc in pin['arcs']:
                if arc['type'] != 'setup_rising': continue
                b = bits[0]
                if not isinstance(b, int) or arr[b][0] <= INF/2: continue
                for e in (0, 1):
                    tab = arc['rise_constraint' if e == 0 else 'fall_constraint']
                    su = lookup(tab, slew[b][e], a.input_slew)   # (data slew, clock slew)
                    req = T - su
                    ends.append((req - arr[b][e], b, e, cn, p, su, req))
    ends.sort()
    wns = ends[0][0]
    tns = sum(min(0, s) for s, *_ in {(cn, p): (s,) for s, b, e, cn, p, su, rq in ends[::-1]}.values())
    # one endpoint per flop pin for TNS / violators
    worst_per = {}
    for s, b, e, cn, p, su, rq in ends:
        worst_per.setdefault((cn, p), s)
    tns = sum(min(0, s) for s in worst_per.values())
    nviol = sum(1 for s in worst_per.values() if s < 0)

    def trace(b, e):
        pts = []
        while True:
            pv = prev.get((b, e))
            if pv is None: pts.append(('input', names.get(b, b), arr[b][e], 0.0, e)); break
            if pv[0] == 'LAUNCH':
                pts.append(('%s/%s (%s)' % (pv[1], pv[3], pv[2]), names.get(b, b), arr[b][e], arr[b][e], e)); break
            ib, ie, cn, ty, fp, op, d = pv
            pts.append(('%s/%s->%s (%s)' % (cn, fp, op, ty), names.get(b, b), arr[b][e], d, e))
            b, e = ib, ie
        return pts[::-1]

    shown = set(); n = 0
    for s, b, e, cn, p, su, req in ends:
        if (cn, p) in shown: continue
        shown.add((cn, p)); n += 1
        pts = trace(b, e)
        print('Startpoint: %s' % pts[0][0])
        qn = names.get(cells[cn]['connections'].get('Q', [None])[0], '?')
        print('Endpoint:   %s/%s (%s)  -> flop output net %s' % (cn, p, cells[cn]['type'], qn))
        print('%-58s %-28s %8s %8s' % ('Point', 'net', 'Incr', 'Path'))
        for pt, net, t, d, ed in pts:
            print('%-58s %-28s %8.3f %8.3f %s' % (pt[:58], str(net)[:28], d, t, 'rf'[ed]))
        print('%-87s %8.3f' % ('data arrival time', arr[b][e]))
        print('%-87s %8.3f' % ('capture edge' + (' (negedge flop)' if phase.get(cn) else ''), a.period / 2 if phase.get(cn) else a.period))
        if a.uncertainty: print('%-87s %8.3f' % ('clock uncertainty', -a.uncertainty))
        print('%-87s %8.3f' % ('library setup time', -su))
        print('%-87s %8.3f' % ('data required time', req))
        print('%-87s %8.3f  (%s)\n' % ('slack', s, 'MET' if s >= 0 else 'VIOLATED'))
        if n >= a.paths: break
    area = sum(lib[c['type']]['area'] for c in cells.values())
    nseq = sum(1 for c in cells.values() if isflop(c['type']))
    print('WNS %.3f ns  TNS %.3f ns  violating endpoints %d  cells %d (seq %d)  area %.0f um^2  levels %d'
          % (wns, tns, nviol, len(cells), nseq, area, len(trace(ends[0][1], ends[0][2])) - 1))
    # min period per path class (launch edge -> capture edge); only pos->pos scales as T - slack
    cls = {}
    for s_, b, e, cn, p, su, req in ends:
        pv = trace(b, e)[0][0]
        src = pv.split('/')[0]
        k = ('neg' if phase.get(src) else 'pos') + '->' + ('neg' if phase.get(cn) else 'pos')
        if k not in cls: cls[k] = (s_, src, cn, names.get(cells[cn]['connections'].get('Q',[None])[0], '?'))
    for k, (s_, src, cn, qn) in sorted(cls.items()):
        print('worst %s path: slack %.3f ns, ends at %s' % (k, s_, qn))
    if a.json:
        json.dump({'classes': {k: [v[0], v[3]] for k, v in cls.items()},'period': a.period, 'wns': wns, 'tns': tns, 'nviol': nviol, 'cells': len(cells),
                   'seq': nseq, 'area': area, 'arrival': arr[ends[0][1]][ends[0][2]],
                   'setup': ends[0][5], 'endpoint': names.get(cells[ends[0][3]]['connections'].get('Q',[None])[0],'?'), 'path': [(pt, str(net), t, d) for pt, net, t, d, ed in trace(ends[0][1], ends[0][2])]},
                  open(a.json, 'w'), indent=1)

if __name__ == '__main__':
    main()
