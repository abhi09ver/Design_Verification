#!/usr/bin/env python3
"""bphunt.py -- Lab 10: inject branch-predictor bugs, see which check notices.

Checks on every test:
  self  : the program's own pass/fail (directed test only)
  lock  : lock-step with the ISS (a wrong-path instruction that commits changes some value)
  model : mispredictions counted by the RTL vs the ideal predictor model (dv/bpsim.py): with GHR
          forwarding they must be EQUAL (performance bugs: the core is right, the predictor is not)
Suites: tests/bp/bp_basic.S, and genbp random programs at the default 1024-entry BTB and at a
16-entry BTB (-GBTB_BITS=4), where unrelated instructions alias in the tagless BTB.
Usage: bphunt.py [--seeds N] [--blocks N]
"""
import argparse
import contextlib
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import bpsim     # noqa: E402
import compare   # noqa: E402
import genbp     # noqa: E402
import iss       # noqa: E402
import regress   # noqa: E402

BUGS = ['BUG_BP_PRIORITY', 'BUG_BP_CFI_ONLY', 'BUG_BP_DIR_ONLY', 'BUG_RAS_NO_REPAIR', 'BUG_PHT_NO_SAT']


def run_all(exe, hexfile, tag, btb=10):
    b = os.path.join(ROOT, 'build', 'bp', tag)
    r = regress.sh(f'{exe} +HEX={hexfile} +TRACE={b}.dut +MAXCYCLES=600000')
    status = next((l for l in r.stdout.splitlines() if l.startswith(('PASS', 'FAIL', 'DONE'))), r.stdout[-200:].strip())
    iss.run(hexfile, f'{b}.iss', follow=f'{b}.dut')
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        lock = compare.compare(f'{b}.iss', f'{b}.dut') == 0
    m = re.search(r'flushes=(\d+)', r.stdout)
    st = next((l for l in r.stdout.splitlines() if l.startswith('BPSTATS')), '')
    if m and lock:
        ok, model, mmsg = bpsim.check(f'{b}.iss', int(m.group(1)), 4, 10, btb, 4)
    else:
        ok, model, mmsg = (True, 0, 'not checked (no counters, or lock-step already failed)')
    return dict(self=status.startswith('PASS'), lock=lock, model=ok, lmsg=buf.getvalue().strip(), mmsg=mmsg,
                status=status, stats=st, flushes=int(m.group(1)) if m else -1, mod=model)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, default=10)
    ap.add_argument('--blocks', type=int, default=25)
    a = ap.parse_args()
    out = os.path.join(ROOT, 'build', 'bp')
    os.makedirs(out, exist_ok=True)
    basic = regress.build_test(os.path.join(ROOT, 'tests/bp/bp_basic.S'), out)
    rands = []
    for s in range(1, a.seeds + 1):
        p = os.path.join(out, f'bprand{s}.S')
        open(p, 'w').write(genbp.gen(s, a.blocks))
        rands.append(regress.build_test(p, out))
    print(f'{"Injected bug":20s} {"bp_basic: self lock model":>26s}  {f"random x{a.seeds}, BTB 1024: lock model":>36s}  {"random, BTB 16: lock model":>27s}  flushes (model)')
    firsts = []
    for bug in [''] + BUGS:
        row, tot = [], [0, 0]
        exe = regress.build_rtl('pipe', bug)
        exe16 = regress.build_rtl('pipe', bug, '-GBTB_BITS=4')
        d = run_all(exe, basic, f'hb_{bug or "base"}')
        mk = lambda ok: 'ok' if ok else 'FAIL'
        row.append(f'{mk(d["self"]):>6s} {mk(d["lock"]):>5s} {mk(d["model"]):>6s}')
        for k in ('lock', 'model'):
            if bug and not d[k]:
                firsts.append((bug, k, 'bp_basic', d['lmsg'] if k == 'lock' else d['mmsg']))
        for e, btb, name in ((exe, 10, '1024'), (exe16, 4, '16')):
            f = {'lock': 0, 'model': 0}
            for i, h in enumerate(rands):
                r = run_all(e, h, f'hr{i + 1}_{btb}_{bug or "base"}', btb)
                for k in f:
                    f[k] += 0 if r[k] else 1
                if btb == 10:
                    tot[0] += r['flushes']; tot[1] += r['mod']
                for k in f:
                    if bug and not r[k] and not any(x[0] == bug and x[1] == k for x in firsts):
                        firsts.append((bug, k, f'random seed {i + 1}, BTB {name}', r['lmsg'] if k == 'lock' else r['mmsg']))
            row.append(f'{f["lock"]:>2d}/{a.seeds} {f["model"]:>5d}/{a.seeds}')
        print(f'{bug or "(none)":20s} {row[0]:>26s}  {row[1]:>36s}  {row[2]:>27s}  {tot[0]} ({tot[1]})')
    print()
    seen = set()
    for bug, k, where, msg in firsts:
        if (bug, k) in seen:
            continue
        seen.add((bug, k))
        print(f'--- {bug}: first {k} failure ({where}) ---\n{msg[:600]}\n')


if __name__ == '__main__':
    main()
