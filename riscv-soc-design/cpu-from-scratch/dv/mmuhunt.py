#!/usr/bin/env python3
"""mmuhunt.py -- Lab 8: inject MMU bugs, see which check notices.

Checks on every test:
  self  : the program's own pass/fail (directed test only)
  lock  : lock-step with the ISS (values, trap causes, tvals, store addresses)
  tlb   : transaction-level TLB model over +TLBLOG (hit/miss per look-up, replaced entry)
Usage: mmuhunt.py [--seeds N] [--ops N]
"""
import argparse
import contextlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import compare   # noqa: E402
import genmmu    # noqa: E402
import iss       # noqa: E402
import regress   # noqa: E402
import tlbmodel  # noqa: E402

BUGS = ['BUG_TLB_NO_FLUSH', 'BUG_TLB_USER_IGNORED', 'BUG_MEGA_OFFSET', 'BUG_NO_DIRTY_FAULT',
        'BUG_PMP_LAST_WINS', 'BUG_WALK_NO_PMP', 'BUG_TLB_VICTIM0']


def quiet(f, *a, **k):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        r = f(*a, **k)
    return r, buf.getvalue().strip()


def run_all(exe, hexfile, tag, entries=4):
    b = os.path.join(ROOT, 'build', 'mmu', tag)
    r = regress.sh(f'{exe} +HEX={hexfile} +TRACE={b}.dut +TLBLOG={b}.tlog +MAXCYCLES=300000')
    status = next((l for l in r.stdout.splitlines() if l.startswith(('PASS', 'FAIL', 'DONE'))), r.stdout[-200:])
    iss.run(hexfile, f'{b}.iss', follow=f'{b}.dut')
    lock, lmsg = quiet(compare.compare, f'{b}.iss', f'{b}.dut')
    tlb, tmsg = quiet(tlbmodel.check, f'{b}.tlog', entries)
    stats = next((l for l in r.stdout.splitlines() if l.startswith('TLBSTATS')), '')
    traps = sum(1 for l in open(f'{b}.dut') if l.startswith('trap'))
    return dict(self=status.startswith('PASS'), lock=lock == 0, tlb=tlb == 0, lmsg=lmsg, tmsg=tmsg,
                status=status, stats=stats, traps=traps)


def build_random(seeds, ops):
    out = os.path.join(ROOT, 'build', 'mmu')
    os.makedirs(out, exist_ok=True)
    hexes = []
    for s in range(1, seeds + 1):
        p = os.path.join(out, f'mrand{s}.S')
        open(p, 'w').write(genmmu.gen(s, ops))
        hexes.append(regress.build_test(p, out))
        words = open(hexes[-1]).read().split()
        assert not any(int(w, 16) for w in words[0x4000 // 4:0x8000 // 4]), 'code overlaps the page tables'
    return hexes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, default=10)
    ap.add_argument('--ops', type=int, default=300)
    a = ap.parse_args()
    out = os.path.join(ROOT, 'build', 'mmu')
    os.makedirs(out, exist_ok=True)
    basic = regress.build_test(os.path.join(ROOT, 'tests/mmu/mmu_basic.S'), out)
    rands = build_random(a.seeds, a.ops)
    print(f'{"Injected bug":22s} {"mmu_basic: self lock tlb":>26s}   {f"random x{a.seeds}: lock tlb (seeds failing)":>38s}')
    firsts = []
    for bug in [''] + BUGS:
        exe = regress.build_rtl('pipe', bug)
        d = run_all(exe, basic, f'mb_{bug or "base"}')
        mark = lambda ok: 'ok' if ok else 'FAIL'
        cell1 = f'{mark(d["self"]):>6s} {mark(d["lock"]):>5s} {mark(d["tlb"]):>5s}'
        fails = {'lock': 0, 'tlb': 0}
        tot = [0, 0]
        for i, h in enumerate(rands):
            r = run_all(exe, h, f'mr{i + 1}_{bug or "base"}')
            for k in fails:
                fails[k] += 0 if r[k] else 1
            if not bug:
                tot[0] += r['traps']
            for k, msg in (('lock', r['lmsg']), ('tlb', r['tmsg'])):
                if bug and not r[k] and not any(f[0] == bug and f[1] == k for f in firsts):
                    firsts.append((bug, k, f'random seed {i + 1}', msg))
        for k, msg in (('lock', d['lmsg']), ('tlb', d['tmsg'])):
            if bug and not d[k]:
                firsts.insert(0, (bug, k, 'mmu_basic', msg))
        cell2 = '   '.join(f'{fails[k]:>2d}/{a.seeds}' for k in ('lock', 'tlb'))
        print(f'{bug or "(none)":22s} {cell1:>26s}   {cell2:>38s}')
        if not bug:
            print(f'{"":22s} basic: {d["status"]}  {d["stats"]}; random: {tot[0]} traps in {a.seeds} seeds')
    print()
    seen = set()
    for bug, k, where, msg in firsts:
        if (bug, k) in seen:
            continue
        seen.add((bug, k))
        print(f'--- {bug}: first {k} failure ({where}) ---\n{msg[:600]}\n')


if __name__ == '__main__':
    main()
