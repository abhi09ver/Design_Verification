#!/usr/bin/env python3
"""periphhunt.py -- Lab 11: inject peripheral bugs, see which verification style notices.

Two ways to check the same RTL (tb/tb_periph.sv):
  full     : cycle-exact reference models for GPIO/CLINT/PLIC, plus independent UART and SPI
             agents on the pins (a frame decoder, a remote UART with baud error and injected
             errors, an SPI peripheral for all four modes)
  bookplan : what the book's test plan describes -- UART and SPI only in internal loopback,
             GPIO read only after the inputs settled (+BOOKPLAN)
Usage: periphhunt.py [--seeds N] [--iter N]
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BUGS = ['BUG_GPIO_NOT_STICKY', 'BUG_GPIO_W1C_ALL', 'BUG_GPIO_NO_SYNC',
        'BUG_CLINT_GT', 'BUG_CLINT_NO_CARRY',
        'BUG_PLIC_TIE_HIGH_ID', 'BUG_PLIC_THRESH_GE', 'BUG_PLIC_NO_GATEWAY',
        'BUG_UART_PARITY_INV', 'BUG_UART_SAMPLE_EARLY', 'BUG_UART_NO_OVERRUN',
        'BUG_SPI_IGNORE_PHASE', 'BUG_SPI_IGNORE_ENDIAN', 'BUG_SPI_TXWM_LE']


def build(bug):
    d = os.path.join(ROOT, 'build', 'periph', bug or 'base')
    exe = os.path.join(d, 'Vtb')
    src = [os.path.join(ROOT, p) for p in ('rtl/uncore/periph.sv', 'tb/tb_periph.sv')]
    if os.path.exists(exe) and all(os.path.getmtime(exe) > os.path.getmtime(s) for s in src):
        return exe
    cmd = ['verilator', '--binary', '--timing', '-Wno-fatal', '-Wno-lint', '-Wno-style', '-CFLAGS', '-O0', '--build-jobs', '2',
           '--top-module', 'tb_periph', '-Mdir', d, '-o', 'Vtb'] + ([f'-D{bug}'] if bug else []) + src
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    return exe


def run(exe, seed, it, extra):
    r = subprocess.run([exe, f'+SEED={seed}', f'+ITER={it}'] + extra, capture_output=True, text=True, timeout=900)
    ok = re.search(r'PERIPH PASS', r.stdout) is not None
    first = next((l for l in r.stdout.splitlines() if l.startswith('ERROR')), '')
    return ok, first


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, default=5)
    ap.add_argument('--iter', type=int, default=300)
    a = ap.parse_args()
    print(f'{"Injected bug":24s} {"full bench":>12s} {"book plan":>12s}   first error (full bench, else book plan)')
    rows = []
    for bug in [''] + BUGS:
        exe = build(bug)
        res = {}
        for mode, extra in (('full', []), ('book', ['+BOOKPLAN'])):
            fails, first = 0, ''
            for s in range(1, a.seeds + 1):
                ok, f = run(exe, s, a.iter, extra)
                if not ok:
                    fails += 1
                    first = first or f
            res[mode] = (fails, first)
        msg = res['full'][1] or res['book'][1]
        msg = re.sub(r'^ERROR @\d+: ', '', msg)[:90]
        print(f'{bug or "(none)":24s} {res["full"][0]:>6d}/{a.seeds:<5d} {res["book"][0]:>6d}/{a.seeds:<5d}  {msg}')
        rows.append((bug, res))
    missed = [b for b, r in rows if b and r['full'][0] == 0]
    loop_only = [b for b, r in rows if b and r['full'][0] > 0 and r['book'][0] == 0]
    print()
    print('missed by the full bench :', ', '.join(missed) or 'none')
    print('missed by the book plan  :', ', '.join(loop_only) or 'none')


if __name__ == '__main__':
    main()
