#!/usr/bin/env python3
"""mmuperf.py -- Lab 8: what a TLB miss costs, and what TLB reach means.

All kernels run in M-mode with MPRV = 1, MPP = U, so every load is translated. Cycles are
measured with mcycle around the loop and divided by the number of loads.
  walk   : sfence.vma before every load (every load walks). Level-0 table in the DTIM, in
           the cacheable RAM (walker reads hit the D-cache after the first walk), or on the
           uncached bus. Baseline: the same loop with satp off.
  reach  : P distinct 4 KiB pages touched round-robin, 4-entry TLB; then the same addresses
           through ONE megapage.
Usage: mmuperf.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import regress  # noqa: E402

ROOT_T = 0x80004000
TABLES = {'DTIM': 0x80005000, 'D-cache': 0x90008000, 'bus': 0x91009000}


def prog(table, pages, sfence, satp_on=True, mega=False, iters=16):
    o = ['.section .text.init', '.globl _start', '_start:',
         '  li t0, -1', '  csrw pmpaddr3, t0', '  li t0, 0x1F000000', '  csrw pmpcfg0, t0']
    st = lambda a, v: o.extend([f'  li t0, {a:#x}', f'  li t1, {v:#x}', '  sw t1, 0(t0)'])
    st(ROOT_T, ((table >> 12) << 10) | 1)
    st(ROOT_T + 4 * 0x100, (0x80000 << 10) | 0xD7)            # megapage VA 0x4000_0000 -> PA 0x8000_0000
    for p in range(pages):
        st(table + 4 * (16 + p), ((0x80006 + (p % 2)) << 10) | 0xD7)   # VA 0x10000 + p*4K -> PA 0x8000_6000/7000
    if satp_on:
        o += [f'  li t0, {(1 << 31) | (ROOT_T >> 12):#x}', '  csrw satp, t0']
    o += ['  sfence.vma', '  li t0, 0x1800', '  csrc mstatus, t0', '  li t0, 0x20000', '  csrs mstatus, t0',
          f'  li a2, {iters}', '  csrr a0, mcycle', '1:']
    for p in range(pages):
        va = (0x40006000 + 0x1000 * (p % 2) + 0x10000 * 0 if mega else 0x10000 + 0x1000 * p) if satp_on else 0x80006000 + 0x1000 * (p % 2)
        if mega and satp_on:
            va = 0x40006000 + 0x1000 * (p % 2) + 0x100000 * (p // 2)   # same pages, spread over the megapage
        if sfence:
            o.append('  sfence.vma')
        o += [f'  li s0, {va:#x}', '  lw s1, 0(s0)']
    o += ['  addi a2, a2, -1', '  bnez a2, 1b', '  csrr a1, mcycle', '  li t0, 0x20000', '  csrc mstatus, t0',
          '  csrw satp, zero', '  li t0, 0x8000F000', '  li t1, 1', '  sw t1, 0(t0)', '9: j 9b']
    return '\n'.join(o) + '\n', pages * iters


def measure(exe, src, n, name):
    out = os.path.join(ROOT, 'build', 'perf')
    os.makedirs(out, exist_ok=True)
    p = os.path.join(out, f'{name}.S')
    open(p, 'w').write(src)
    hx = regress.build_test(p, out)
    tr = os.path.join(out, f'{name}.dut')
    r = regress.sh(f'{exe} +HEX={hx} +TRACE={tr}')
    vals = {}
    for line in open(tr):
        m = re.search(r'insn=(\w+) x(1[01])=(\w+)', line)
        if m and int(m.group(1), 16) & 0x7F == 0x73:
            vals[m.group(2)] = int(m.group(3), 16)
    assert r.stdout.find('PASS') >= 0, r.stdout
    return (vals['11'] - vals['10']) / n


def main():
    exe = regress.build_rtl('pipe', '')
    base = measure(exe, *prog(TABLES['DTIM'], 1, True, satp_on=False), 'w_base')
    print('walk cost (sfence.vma before every load; cycles per load, including the sfence and loop)')
    print(f'  {"no translation":26s} {base:6.2f}')
    for k, t in TABLES.items():
        c = measure(exe, *prog(t, 1, True), f'w_{k.replace("-", "")}')
        print(f'  {"level-0 table in " + k:26s} {c:6.2f}   (+{c - base:.2f} for the walk)')
    print('TLB reach (4 entries; cycles per load, round-robin over P pages)')
    print(f'  {"P":>3s} {"4 KiB pages":>12s} {"one megapage":>13s}')
    for P in (1, 2, 4, 5, 8):
        a = measure(exe, *prog(TABLES['DTIM'], P, False), f'r4k_{P}')
        b = measure(exe, *prog(TABLES['DTIM'], P, False, mega=True), f'rmp_{P}')
        print(f'  {P:3d} {a:12.2f} {b:13.2f}')


if __name__ == '__main__':
    main()
