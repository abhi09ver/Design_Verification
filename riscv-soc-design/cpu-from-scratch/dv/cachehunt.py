#!/usr/bin/env python3
"""cachehunt.py -- Lab 7: inject D-cache bugs, see which check notices.

Four independent checks on every test:
  self   : the program's own pass/fail (directed test only)
  lock   : lock-step with the ISS, instruction by instruction (values in registers)
  mem    : end-of-test RAM image vs the ISS's memory (after the final fence.i)
  model  : transaction-level cache model (hit/miss, way, writebacks, fills, flush order)
Usage: cachehunt.py [--seeds N] [--ops N]
"""
import argparse
import contextlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import cachemodel  # noqa: E402
import compare     # noqa: E402
import gencache    # noqa: E402
import iss         # noqa: E402
import regress     # noqa: E402

BUGS = ['BUG_NO_WRITEBACK', 'BUG_DIRTY_ON_HIT', 'BUG_NO_MERGE', 'BUG_LRU_STUCK',
        'BUG_TAG_SHORT', 'BUG_FLUSH_SKIP_LAST']


def quiet(f, *a, **k):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        r = f(*a, **k)
    return r, buf.getvalue().strip()


def run_all(exe, hexfile, tag, cfg=(2, 8, 4)):
    out = os.path.join(ROOT, 'build', 'tests')
    b = os.path.join(out, tag)
    r = regress.sh(f'{exe} +HEX={hexfile} +TRACE={b}.dut +CACHELOG={b}.clog +RAMDUMP={b}.ram +MAXCYCLES=200000')
    status = next((l for l in r.stdout.splitlines() if l.startswith(('PASS', 'FAIL', 'DONE'))), r.stdout[-200:])
    iss.run(hexfile, f'{b}.iss', follow=f'{b}.dut', ramdump=f'{b}.iss.ram')
    lock, lmsg = quiet(compare.compare, f'{b}.iss', f'{b}.dut')
    mem_ok = open(f'{b}.ram').read() == open(f'{b}.iss.ram').read()
    model, mmsg = quiet(cachemodel.check, f'{b}.clog', *cfg)
    stats = next((l for l in r.stdout.splitlines() if l.startswith('CACHESTATS')), '')
    cyc = next((l for l in r.stdout.splitlines() if 'cycles' in l and l.startswith(('PASS', 'FAIL'))), '')
    return dict(self=status.startswith('PASS'), lock=lock == 0, mem=mem_ok, model=model == 0,
                lmsg=lmsg, mmsg=mmsg, status=status, stats=stats, cyc=cyc)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, default=10)
    ap.add_argument('--ops', type=int, default=300)
    a = ap.parse_args()
    out = os.path.join(ROOT, 'build', 'tests')
    os.makedirs(out, exist_ok=True)
    basic = regress.build_test(os.path.join(ROOT, 'tests/cache/cache_basic.S'), out)
    rands = []
    for s in range(1, a.seeds + 1):
        p = os.path.join(out, f'crand{s}.S')
        open(p, 'w').write(gencache.gen(s, a.ops))
        rands.append(regress.build_test(p, out))
    print(f'{"Injected bug":22s} {"cache_basic: self lock mem model":>34s}   {f"random x{a.seeds}: lock mem model (seeds failing)":>44s}')
    firsts = []
    for bug in [''] + BUGS:
        exe = regress.build_rtl('pipe', bug)
        d = run_all(exe, basic, f'cb_{bug or "base"}')
        mark = lambda ok: 'ok' if ok else 'FAIL'
        cell1 = f'{mark(d["self"]):>6s} {mark(d["lock"]):>5s} {mark(d["mem"]):>5s} {mark(d["model"]):>6s}'
        fails = {'lock': 0, 'mem': 0, 'model': 0}
        for i, h in enumerate(rands):
            r = run_all(exe, h, f'cr{i + 1}_{bug or "base"}')
            for k in fails:
                fails[k] += 0 if r[k] else 1
            if bug and not r['lock'] and not any(f[0] == bug and f[1] == 'lock' for f in firsts):
                firsts.append((bug, 'lock', f'random seed {i + 1}', r['lmsg']))
        for k, msg in (('lock', d['lmsg']), ('model', d['mmsg'])):
            if bug and not d[k]:
                firsts.append((bug, k, 'cache_basic', msg))
        cell2 = '   '.join(f'{fails[k]:>2d}/{a.seeds}' for k in ('lock', 'mem', 'model'))
        print(f'{bug or "(none)":22s} {cell1:>34s}   {cell2:>44s}')
        if not bug:
            print(f'{"":22s} basic: {d["cyc"]}  {d["stats"]}')
    print()
    seen = set()
    for bug, k, where, msg in firsts:
        if (bug, k) in seen:
            continue
        seen.add((bug, k))
        print(f'--- {bug}: first {k} failure ({where}) ---\n{msg[:700]}\n')


if __name__ == '__main__':
    main()
