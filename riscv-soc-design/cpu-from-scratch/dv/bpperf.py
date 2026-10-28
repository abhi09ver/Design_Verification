#!/usr/bin/env python3
"""bpperf.py -- Lab 10: what branch prediction buys, measured on the RTL.

  1. predictor type on tests/bench (C: sort, CRC, list walk, search, fib): cycles, CPI, flushes
  2. book Code Example 13.1 (nested loops), per branch, with the ideal model: 1-bit vs 2-bit
  3. direction-table size sweep, bimodal vs gshare (book Fig. 13.6), RTL, bench + 5 genbp programs
  4. BTB size sweep (book Fig. 13.8)
  5. RAS depth sweep (returns mispredicted; bp_basic has a 6-deep call chain and fib(10))
Writes build/perf/bpperf.json for the notes' charts.
Usage: bpperf.py [--quick]
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import bpsim    # noqa: E402
import genbp    # noqa: E402
import iss      # noqa: E402
import regress  # noqa: E402

OUT = os.path.join(ROOT, 'build', 'perf')


def stats(exe, hx):
    r = regress.sh(f'{exe} +HEX={hx} +MAXCYCLES=800000')
    m = re.search(r'after (\d+) instructions, (\d+) cycles', r.stdout)
    assert m and 'PASS' in r.stdout, r.stdout[-300:]
    b = dict((k, int(v)) for k, v in re.findall(r'(\w+)=(\d+)', next(l for l in r.stdout.splitlines() if l.startswith('BPSTATS'))))
    b['insns'], b['cycles'] = int(m.group(1)), int(m.group(2))
    return b


def onebit_nested(hx):
    """the ideal model on Code Example 13.1, per branch: 1-bit (last outcome) vs 2-bit counter"""
    tr = os.path.join(OUT, 'nested.iss')
    iss.run(hx, tr)
    recs = [l.split() for l in open(tr) if l.startswith('pc=')]
    res = {}
    for bits in (1, 2):
        st, hit, tot = {}, {}, {}
        for i, t in enumerate(recs[:-1]):
            insn = int(t[1][5:], 16)
            if insn & 0x7F != 0x63:
                continue
            pc = int(t[0][3:], 16)
            taken = int(recs[i + 1][0][3:], 16) != pc + 4
            s = st.get(pc, 1 if bits == 2 else 0)
            pred = (s >= 2) if bits == 2 else bool(s)
            hit[pc] = hit.get(pc, 0) + (pred == taken)
            tot[pc] = tot.get(pc, 0) + 1
            st[pc] = (min(3, s + 1) if taken else max(0, s - 1)) if bits == 2 else int(taken)
        res[bits] = {f'{pc:x}': (hit[pc], tot[pc]) for pc in tot}
    return res


def main():
    os.makedirs(OUT, exist_ok=True)
    quick = '--quick' in sys.argv
    J = {}
    bench = os.path.join(ROOT, 'tests/bench/bench.hex')
    progs = [bench]
    for s in range(1, 6):
        p = os.path.join(OUT, f'bpp{s}.S')
        open(p, 'w').write(genbp.gen(s, 25))
        progs.append(regress.build_test(p, OUT))

    # ---- 1. predictor type ----
    names = ['0 static not taken', '1 static BTFN', '2 bimodal', '3 gshare, committed GHR', '4 gshare + GHR forwarding']
    print('1. predictor type on tests/bench (41,119 instructions, 6,158 branches, 659 jumps, 75 returns)')
    print(f'   {"type":28s} {"cycles":>8s} {"CPI":>6s} {"flushes":>8s} {"branch dir acc":>15s}')
    J['types'] = []
    for t, nm in enumerate(names):
        b = stats(regress.build_rtl('pipe', '', f'-GBP_TYPE={t}'), bench)
        acc = 100 * (1 - b['br_wrong'] / b['branches'])
        print(f'   {nm:28s} {b["cycles"]:8d} {b["cycles"] / b["insns"]:6.3f} {b["flushes"]:8d} {acc:14.1f}%')
        J['types'].append(dict(name=nm, cycles=b['cycles'], cpi=round(b['cycles'] / b['insns'], 3), flushes=b['flushes'], acc=round(acc, 1)))

    # ---- 2. nested loops ----
    src = os.path.join(OUT, 'nested.S')
    open(src, 'w').write('.section .text.init\n.globl _start\n_start:\n  li t0, 5\n  li t1, 10\n  li s0, 0\n'
                         'fori: li s1, 0\nforj: addi s1, s1, 1\n  blt s1, t1, forj\n  addi s0, s0, 1\n  blt s0, t0, fori\n'
                         '  li t0, 0x8000F000\n  li t1, 1\n  sw t1, 0(t0)\n9: j 9b\n')
    nb = onebit_nested(regress.build_test(src, OUT))
    print('\n2. book Code Example 13.1, nested loops (5 x 10), ideal per-branch accuracy')
    J['nested'] = {}
    for bits, d in nb.items():
        cells = []
        for pc, (h, n) in sorted(d.items()):
            cells.append(f'{"branch_j" if n == 50 else "branch_i"} {h}/{n} = {100 * h / n:.0f}%')
        print(f'   {bits}-bit: ' + ', '.join(cells))
        J['nested'][bits] = cells

    # ---- 3. direction-table size sweep ----
    sizes = [2, 4, 6, 8, 10, 12] if not quick else [4, 10]
    print('\n3. direction mispredictions per 100 branches vs table entries (bench + 5 genbp programs, RTL)')
    print(f'   {"entries":>8s} {"bimodal":>9s} {"gshare+fwd":>11s}')
    J['size'] = []
    for bits in sizes:
        row = {}
        for t in (2, 4):
            exe = regress.build_rtl('pipe', '', f'-GBP_TYPE={t} -GBHT_BITS={bits}')
            w = n = 0
            for h in progs:
                b = stats(exe, h)
                w += b['dir_wrong']; n += b['branches']
            row[t] = 100 * w / n
        print(f'   {2 ** bits:8d} {row[2]:9.2f} {row[4]:11.2f}')
        J['size'].append(dict(entries=2 ** bits, bimodal=round(row[2], 2), gshare=round(row[4], 2)))

    # ---- 4. BTB size ----
    print('\n4. BTB entries: flushes caused by a wrong/missing target or class (bench + 5 genbp, gshare+fwd)')
    J['btb'] = []
    for bits in ([2, 4, 6, 8, 10] if not quick else [4, 10]):
        exe = regress.build_rtl('pipe', '', f'-GBTB_BITS={bits}')
        tgt = fl = cf = 0
        for h in progs:
            b = stats(exe, h)
            tgt += b['flushes'] - b['dir_wrong']; fl += b['flushes']; cf += b['branches'] + b['jumps'] + b['returns']
        print(f'   {2 ** bits:6d} entries: {tgt:6d} target/class flushes, {fl:6d} flushes in all, {100 * (1 - tgt / cf):.2f}% of CFIs with the right target')
        J['btb'].append(dict(entries=2 ** bits, tgt=tgt, flushes=fl, hit=round(100 * (1 - tgt / cf), 2)))

    # ---- 5. RAS depth ----
    basic = regress.build_test(os.path.join(ROOT, 'tests/bp/bp_basic.S'), OUT)
    print('\n5. RAS entries: returns mispredicted (bp_basic: 195 returns, 6-deep chain, recursive fib(10))')
    J['ras'] = []
    for n in [2, 4, 8, 16]:
        b = stats(regress.build_rtl('pipe', '', f'-GRAS_SIZE={n}'), basic)
        print(f'   {n:3d} entries: {b["ret_wrong"]:4d} of {b["returns"]} returns')
        J['ras'].append(dict(entries=n, wrong=b['ret_wrong'], returns=b['returns']))
    json.dump(J, open(os.path.join(OUT, 'bpperf.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
