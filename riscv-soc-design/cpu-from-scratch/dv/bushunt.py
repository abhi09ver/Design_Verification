#!/usr/bin/env python3
"""bushunt.py -- Lab 6: inject bus bugs, see which kind of verification notices.

Two benches:
  system : the CPU runs the bus directed tests; judged by self-check and by lock-step vs the ISS
  block  : tb_ahb.sv, a constrained-random pipelined AHB manager + scoreboard on the uncore alone
Usage: bushunt.py [--seeds N] [--cycles N]
"""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import regress  # noqa: E402

CORE_BUGS = ['BUG_NO_COMMIT', 'BUG_BUS_NO_CANCEL']
UNCORE_BUGS = ['BUG_HSEL_NOT_DELAYED', 'BUG_RAM_NO_RAW_WAIT', 'BUG_DEFAULT_HANG', 'BUG_APB_EARLY_WDATA']
TESTS = ['bus_basic', 'bus_irq', 'bus_unmapped']


def build_block(bug):
    mdir = os.path.join(ROOT, 'build', 'ahb' + (f'_{bug}' if bug else ''))
    os.makedirs(mdir, exist_ok=True)
    d = f'-D{bug}' if bug else ''
    r = subprocess.run(f'verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style {d} --top-module tb_ahb '
                       f'-Mdir {mdir} -o Vtb rtl/uncore/uncore.sv tb/tb_ahb.sv',
                       shell=True, cwd=ROOT, capture_output=True, text=True)
    exe = os.path.join(mdir, 'Vtb')
    if not os.path.exists(exe):
        sys.exit(r.stderr[-2000:])
    return exe


def run_block(exe, seeds, cycles):
    fails, first = 0, ''
    for s in range(1, seeds + 1):
        out = subprocess.run(f'{exe} +SEED={s} +CYCLES={cycles}', shell=True, capture_output=True, text=True).stdout
        if 'AHBTB PASS' not in out:
            fails += 1
            if not first:
                first = next((l for l in out.splitlines() if l.startswith('ERROR')), out.strip()[-200:])
    return fails, first


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, default=5)
    ap.add_argument('--cycles', type=int, default=20000)
    a = ap.parse_args()
    out = os.path.join(ROOT, 'build', 'tests')
    os.makedirs(out, exist_ok=True)
    hexes = {t: regress.build_test(os.path.join(ROOT, 'tests/bus', t + '.S'), out) for t in TESTS}
    hdr = ' '.join(f'{t:>22s}' for t in TESTS)
    print(f'{"Injected bug":22s} {hdr} {"block-level random":>26s}')
    notes = []
    for bug in [''] + CORE_BUGS + UNCORE_BUGS:
        exe = regress.build_rtl('pipe', bug)
        cells = []
        for t in TESTS:
            ok, status, cmp, _ = regress.run_one(exe, hexes[t], out, f'{t}_{bug or "base"}')
            selfc = 'pass' if status.startswith('PASS') else ('HANG' if 'hang' in status else 'FAIL')
            ls = 'match' if cmp.startswith('MATCH') else 'MISMATCH'
            cells.append(f'{selfc + " / " + ls:>22s}')
            if bug and (selfc != 'pass' or ls != 'match') and not any(n[0] == bug for n in notes):
                notes.append((bug, t, status, cmp))
        if bug in CORE_BUGS:
            blk = 'n/a (no CPU)'
        else:
            bexe = build_block(bug)
            f, first = run_block(bexe, a.seeds, a.cycles)
            blk = f'{f}/{a.seeds} seeds fail' if f else (f'0/{a.seeds} (missed)' if bug else f'0/{a.seeds} fail (clean)')
            if f:
                notes.append((bug, 'block', first, ''))
        print(f'{bug or "(none)":22s} ' + ' '.join(cells) + f' {blk:>26s}')
    print('\ncells: self-check / lock-step')
    for bug, t, status, cmp in notes:
        print(f'--- {bug} ({t}) ---\n{status}\n{cmp[:600]}\n')


if __name__ == '__main__':
    main()
