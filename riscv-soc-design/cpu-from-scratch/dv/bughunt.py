#!/usr/bin/env python3
"""bughunt.py -- inject each known pipeline bug and record which tests catch it.

This is the experiment that justifies the whole methodology: a directed test that
passes on a buggy core is not evidence of correctness. For each bug we report
whether the book's test, our self-checking directed test, and constrained-random
lock-step catch it, plus the first divergence lock-step reports.

Usage: bughunt.py [--seeds N] [--len L]
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import regress  # noqa: E402

BUGS = ['BUG_OR_PLUS', 'BUG_FWD_PRIORITY', 'BUG_NO_FWD_W', 'BUG_FWD_X0', 'BUG_NO_LOAD_STALL', 'BUG_NO_FLUSH_E']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, default=20)
    ap.add_argument('--len', type=int, default=300)
    a = ap.parse_args()
    out = os.path.join(ROOT, 'build', 'tests')
    os.makedirs(out, exist_ok=True)

    # build the test programs once
    directed = regress.build_test(os.path.join(ROOT, 'tests/directed/rv32i_selfcheck.S'), out)
    rand = []
    for seed in range(1, a.seeds + 1):
        src = os.path.join(out, f'rand{seed}.S')
        regress.sh(f'python3 {HERE}/gen.py {seed} {a.len} {src}')
        rand.append(regress.build_test(src, out))

    rows = []
    for bug in BUGS:
        exe = regress.build_rtl('pipe', bug)
        book_ok, *_ = regress.run_one(exe, os.path.join(ROOT, 'tests/book/riscvtest.hex'), out, f'book_{bug}')
        dir_ok, *_ = regress.run_one(exe, directed, out, f'dir_{bug}')
        caught, first = 0, None
        for i, hx in enumerate(rand, 1):
            ok, status, cmp, _ = regress.run_one(exe, hx, out, f'r{i}_{bug}')
            if not ok:
                caught += 1
                if first is None:
                    first = (i, cmp)
        rows.append((bug, not book_ok, not dir_ok, caught, first))

    print(f'{"Injected bug":20s} {"book test":10s} {"directed":10s} random lock-step ({a.seeds} seeds x {a.len} insns)')
    for bug, b, d, c, _ in rows:
        print(f'{bug:20s} {"CAUGHT" if b else "missed":10s} {"CAUGHT" if d else "missed":10s} '
              f'{c}/{a.seeds} seeds fail')
    print()
    for bug, _, _, _, first in rows:
        if first:
            print(f'--- {bug}: first divergence (seed {first[0]}) ---')
            print(first[1])
            print()


if __name__ == '__main__':
    main()
