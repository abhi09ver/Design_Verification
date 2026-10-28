#!/usr/bin/env python3
"""pipeview.py -- print what is in each pipeline stage, cycle by cycle.

Builds the pipelined core, runs a test with +PIPEVIEW, and shows:
    cycle | F | D | E | M | W | what the hazard unit did

Usage: pipeview.py <test.S or test.hex> [max_cycles]
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import regress           # noqa: E402
from iss import decode   # noqa: E402

ABI = ['zero', 'ra', 'sp', 'gp', 'tp', 't0', 't1', 't2', 's0', 's1'] + [f'a{i}' for i in range(8)] + \
      [f's{i}' for i in range(2, 12)] + ['t3', 't4', 't5', 't6']


def dis(insn):
    d = decode(insn)
    n, rd, r1, r2 = d['name'], ABI[d['rd']], ABI[d['rs1']], ABI[d['rs2']]
    op = d['op']
    if op == 0x33: return f'{n} {rd},{r1},{r2}'
    if op == 0x13: return f'{n} {rd},{r1},{d["immI"] & 31 if n in ("slli", "srli", "srai") else d["immI"]}'
    if op == 0x03: return f'{n} {rd},{d["immI"]}({r1})'
    if op == 0x23: return f'{n} {r2},{d["immS"]}({r1})'
    if op == 0x63: return f'{n} {r1},{r2},{d["immB"]:+d}'
    if op in (0x37, 0x17): return f'{n} {rd},{d["immU"] >> 12:#x}'
    if n == 'jal': return f'jal {rd},{d["immJ"]:+d}'
    if n == 'jalr': return f'jalr {rd},{d["immI"]}({r1})'
    if n.startswith('csrr'):
        names = {0x300: 'mstatus', 0x304: 'mie', 0x305: 'mtvec', 0x340: 'mscratch', 0x341: 'mepc',
                 0x342: 'mcause', 0x343: 'mtval', 0x344: 'mip', 0xC01: 'time'}
        c = names.get(insn >> 20, f'{insn >> 20:#x}')
        return f'{n} {rd},{c},{d["rs1"] if n.endswith("i") else r1}'
    return n


def main():
    test = sys.argv[1]
    maxc = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    out = os.path.join(ROOT, 'build', 'tests')
    os.makedirs(out, exist_ok=True)
    hexfile = regress.build_test(test, out) if test.endswith('.S') else test
    exe = regress.build_rtl('pipe', '')
    r = subprocess.run([exe, f'+HEX={hexfile}', '+PIPEVIEW', f'+MAXCYCLES={maxc}'],
                       capture_output=True, text=True)
    W = 16
    print(f'{"cyc":>3} | {"F":{W}} | {"D":{W}} | {"E":{W}} | {"M":{W}} | {"W":{W}} | hazard unit')
    print('-' * (6 + 6 * (W + 3) + 10))
    fwdname = {0: '', 1: 'W', 2: 'M'}
    for line in r.stdout.splitlines():
        if not line.startswith('PV '):
            continue
        f = line.split()[1:]
        cyc = int(f[0])
        instr = [int(f[2], 16)] + [int(f[i], 16) for i in (4, 6, 8, 10)]
        valid = [1] + [int(f[i]) for i in (3, 5, 7, 9)]
        stallD, flushD, flushE, fa, fb = (int(x) for x in f[12:17])
        trap, ret, csrflush, csrstall = (int(x) for x in f[17:21]) if len(f) > 20 else (0, 0, 0, 0)
        cause = int(f[21], 16) if len(f) > 21 else 0
        cells = [dis(i)[:W] if v else '(bubble)' for i, v in zip(instr, valid)]
        notes = []
        if trap: notes.append(f'TRAP in M, cause {cause:#x}: flush M,E,D, W gets a bubble')
        elif ret: notes.append('MRET in M: PC <- mepc, flush E,D')
        elif csrflush: notes.append('CSR write in M: refetch, flush E,D')
        if stallD: notes.append('STALL F,D (' + ('CSR read-use' if csrstall else 'load-use') + ')')
        if trap or ret or csrflush: pass
        elif flushD and flushE: notes.append('FLUSH D,E (taken branch/jump)')
        elif flushE and not stallD: notes.append('FLUSH E')
        if fa: notes.append(f'fwd rs1 from {fwdname[fa]}')
        if fb: notes.append(f'fwd rs2 from {fwdname[fb]}')
        print(f'{cyc:>3} | ' + ' | '.join(f'{c:{W}}' for c in cells) + ' | ' + ', '.join(notes))
    print()
    print(next((l for l in r.stdout.splitlines() if l.startswith(('PASS', 'FAIL', 'DONE'))), ''))


if __name__ == '__main__':
    main()
