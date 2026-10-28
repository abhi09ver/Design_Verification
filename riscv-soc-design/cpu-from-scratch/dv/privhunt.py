#!/usr/bin/env python3
"""privhunt.py -- Lab 5: inject privileged-unit bugs, see which check notices.

For each bug, the two privileged directed tests are run and judged two ways:
  self-check : the program's own pass/fail (what a signature-style test sees)
  lock-step  : every retired instruction, CSR write and trap compared with the ISS
Usage: privhunt.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import regress  # noqa: E402

BUGS = ['BUG_MEPC_PLUS4', 'BUG_INT_BUBBLE', 'BUG_CSR_NOFLUSH', 'BUG_MRET_NOMIE']
TESTS = ['trap_basic', 'interrupts']


def main():
    out = os.path.join(ROOT, 'build', 'tests')
    os.makedirs(out, exist_ok=True)
    hexes = {t: regress.build_test(os.path.join(ROOT, 'tests/priv', t + '.S'), out) for t in TESTS}
    print(f'{"Injected bug":18s} ' + ' '.join(f'{t + " self":>18s} {t + " lockstep":>22s}' for t in TESTS))
    firsts = []
    for bug in [''] + BUGS:
        exe = regress.build_rtl('pipe', bug)
        cells = []
        for t in TESTS:
            ok, status, cmp, _ = regress.run_one(exe, hexes[t], out, f'{t}_{bug or "base"}')
            selfok = status.startswith('PASS')
            lsok = cmp.startswith('MATCH')
            cells.append(f'{"pass" if selfok else "FAIL (" + status.split(":")[0] + ")":>18s} '
                         f'{"match" if lsok else "MISMATCH":>22s}')
            if not lsok and bug:
                firsts.append((bug, t, cmp))
        print(f'{bug or "(none)":18s} ' + ' '.join(cells))
    print()
    seen = set()
    for bug, t, cmp in firsts:
        if bug in seen:
            continue
        seen.add(bug)
        print(f'--- {bug} ({t}) ---\n{cmp}\n')


if __name__ == '__main__':
    main()
