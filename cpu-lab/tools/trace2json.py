#!/usr/bin/env python3
"""trace2json.py <program.s> <sim log with +TRACE> -> JSON for the course cycle-stepper"""
import json, re, sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
from rv import assemble
words, text = assemble(open(sys.argv[1]).read().splitlines())
real = [t for t in text if not t.startswith('nop (pad)')]
last_pc = 4 * (len(real) - 1)
log = open(sys.argv[2]).read().splitlines()
cyc = {}
def C(c): return cyc.setdefault(c, {'c': c, 'dec': [], 'rob': [], 'rat': {}, 'rs': [], 'cdb': [], 'commit': []})
robpc = {}
for ln in log:
    p = ln.split()
    if ln.startswith('TR '):
        c = int(p[1]); k = p[2]; d = C(c)
        if k == 'ROB':
            pc = int(p[4], 16); robpc[int(p[3])] = pc
            if pc <= last_pc: d['rob'].append({'i': int(p[3]), 'pc': pc, 'rdy': int(p[5]), 'rd': int(p[6]), 'v': int(p[7], 16)})
        elif k == 'RAT': d['rat'][int(p[3])] = int(p[4])
        elif k == 'RS':
            d['rs'].append({'t': p[3], 'k': int(p[4]), 'rob': int(p[5]), 'rdy': int(p[6]),
                            's1v': int(p[7]), 's1t': int(p[8]), 's2v': int(p[9]), 's2t': int(p[10])})
        elif k == 'CDB': d['cdb'].append({'rob': int(p[4]), 'v': int(p[5], 16)})
        elif k == 'DEC':
            pc = int(p[4], 16)
            if pc <= last_pc: d['dec'].append(pc)
        elif k == 'PTR': d['tail'], d['head'], d['stall'] = int(p[3]), int(p[4]), int(p[5])
    m = re.match(r'COMMIT cyc=(\d+) slot=\d+ rob=(\d+) pc=(\w+) rd=(\d+) val=(\w+)', ln)
    if m and int(m[3], 16) <= last_pc:
        C(int(m[1]))['commit'].append({'rob': int(m[2]), 'pc': int(m[3], 16), 'rd': int(m[4]), 'v': int(m[5], 16)})
# keep only ROB-tag -> real instruction info for RS rows
cs = sorted(cyc)
last_commit = max(c for c in cs if cyc[c]['commit'] and cyc[c]['commit'][-1]['pc'] == last_pc)
first = min(c for c in cs if cyc[c]['dec'])
out = []
for c in range(first, last_commit + 2):
    d = cyc[c]
    d['rs'] = [r for r in d['rs'] if robpc.get(r['rob'], 1 << 30) <= last_pc]
    d['cdb'] = [x for x in d['cdb'] if robpc.get(x['rob'], 1 << 30) <= last_pc]
    d['rat'] = {r: t for r, t in d['rat'].items() if robpc.get(t, 1 << 30) <= last_pc}
    out.append(d)
json.dump({'asm': real, 'cycles': out}, sys.stdout, separators=(',', ':'))
