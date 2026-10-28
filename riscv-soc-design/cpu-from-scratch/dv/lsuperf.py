#!/usr/bin/env python3
"""lsuperf.py -- Lab 9: what a synchronous-read D-cache costs, kernel by kernel.

Each kernel runs on a warm cached array (one untimed pass first), timed with mcycle:
  loads   : 64 back-to-back lw (unrolled), no stores, sequential words (4 loads per line)
  stride  : 64 back-to-back lw, 16-byte stride, so every load is in a different set
  copy    : lw/sw pairs, a[i] -> b[i] in the same lines, so every load follows a store (store->load)
  rmw     : lw, addi, sw per word (the store is never directly followed by a load... except the next lw)
Configurations: Lab 7 combinational read, Lab 9 synchronous read, and the SelAdr performance bug.
Usage: lsuperf.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import regress  # noqa: E402


def kernel(body, n):
    o = ['.section .text.init', '.globl _start', '_start:', '  li s0, 0x90000000', '  li s1, 0x90000080',
         '  li a2, 2', '0:', '  csrr a0, mcycle']
    o += body
    o += ['  csrr a1, mcycle', '  addi a2, a2, -1', '  bnez a2, 0b',      # 2 passes: report the warm one
          '  li t0, 0x8000F000', '  li t1, 1', '  sw t1, 0(t0)', '9: j 9b']
    return '\n'.join(o) + '\n', n


KERNELS = {
    'loads': kernel([f'  lw t{i % 3}, {4 * (i % 32)}(s0)' for i in range(64)], 64),
    'stride': kernel([f'  lw t{i % 3}, {16 * (i % 8)}(s0)' for i in range(64)], 64),
    'copy': kernel([x for i in range(32) for x in (f'  lw t0, {4 * i}(s0)', f'  sw t0, {4 * i}(s1)')], 64),
    'rmw': kernel([x for i in range(32) for x in (f'  lw t0, {4 * i}(s0)', '  addi t0, t0, 1', f'  sw t0, {4 * i}(s0)')], 64),
}
CONFIGS = [('Lab 7: combinational read', '', '-GDC_SYNC=0'), ('Lab 9: synchronous read', '', ''),
           ('Lab 9 + BUG_SELADR_ON_HIT', 'BUG_SELADR_ON_HIT', '')]


def main():
    out = os.path.join(ROOT, 'build', 'perf')
    os.makedirs(out, exist_ok=True)
    hexes = {}
    for k, (src, n) in KERNELS.items():
        p = os.path.join(out, f'l_{k}.S')
        open(p, 'w').write(src)
        hexes[k] = (regress.build_test(p, out), n)
    print(f'{"configuration":28s} ' + ' '.join(f'{k + " cyc/op":>14s}' for k in KERNELS) + '   (16-byte lines, 2 x 8 sets; all hits)')
    for name, bug, gp in CONFIGS:
        exe = regress.build_rtl('pipe', bug, gp)
        cells = []
        for k, (hx, n) in hexes.items():
            tr = os.path.join(out, f'l_{k}_{bug or gp or "base"}.dut'.replace('=', ''))
            regress.sh(f'{exe} +HEX={hx} +TRACE={tr}')
            a0 = a1 = None
            for line in open(tr):
                m = re.search(r'insn=(\w+) x(1[01])=(\w+)', line)
                if m and int(m.group(1), 16) & 0x7F == 0x73:
                    if m.group(2) == '10': a0 = int(m.group(3), 16)
                    else: a1 = int(m.group(3), 16)
            cells.append(f'{(a1 - a0) / n:14.2f}')
        print(f'{name:28s} ' + ' '.join(cells))


if __name__ == '__main__':
    main()
