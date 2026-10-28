#!/usr/bin/env python3
"""gencache.py -- Lab 7: constrained-random D-cache stress test.

Random addresses would almost never collide in a cache, so the constraints aim at the
places caches break:
  * a small pool of hot LINES that share a few sets but differ in tag, including tags that
    differ only in the top tag bit (address bit 15) -> conflict misses, dirty evictions,
    pLRU decisions, tag-compare bugs
  * every access size (lb/lbu/lh/lhu/lw, sb/sh/sw) at random offsets within the line
  * occasional fence.i followed by uncached reads of the same RAM through 0x9100_xxxx
    (coherent only because of the flush) -> flush bugs become visible to lock-step
  * a final fence.i, so the end-of-test RAM image must equal the ISS's memory
Register use: x31 = cached base 0x9000_0000, x30 = uncached base 0x9100_0000,
x29 = scratch address, x1..x7 data.

Usage: gencache.py <seed> <num_ops> <out.S> [sets linebytes]
"""
import random
import sys


def gen(seed, n, sets=8, linebytes=16):
    rnd = random.Random(seed)
    stride = sets * linebytes                       # lines this far apart share a set
    hot_sets = rnd.sample(range(sets), k=min(3, sets))
    tags = [0, 1, 2, 3, 0x8000 // stride, 0x8000 // stride + 1]   # last two differ in bit 15
    lines = [t * stride + s * linebytes for t in tags for s in hot_sets]
    out = ['.section .text.init', '.globl _start', '_start:',
           '  li x31, 0x90000000', '  li x30, 0x91000000']
    for r in range(1, 8):
        out.append(f'  li x{r}, {rnd.getrandbits(32):#x}')
    for i in range(n):
        k = rnd.random()
        line = rnd.choice(lines)
        if k < 0.04:                               # flush, then look at memory directly
            out.append('  fence.i')
            for _ in range(rnd.randint(1, 3)):
                off = rnd.choice(lines) + 4 * rnd.randrange(linebytes // 4)
                out.append(f'  li x29, {off:#x}')
                out.append('  add x29, x29, x30')
                out.append(f'  lw x{rnd.randint(1, 7)}, 0(x29)')
            continue
        size = rnd.choice([1, 2, 4])
        off = line + rnd.randrange(0, linebytes, size)
        out.append(f'  li x29, {off:#x}')
        out.append('  add x29, x29, x31')
        rs = rnd.randint(1, 7)
        if k < 0.50:
            op = {1: rnd.choice(['lb', 'lbu']), 2: rnd.choice(['lh', 'lhu']), 4: 'lw'}[size]
            out.append(f'  {op} x{rs}, 0(x29)')
        else:
            if rnd.random() < 0.3:
                out.append(f'  addi x{rs}, x{rs}, {rnd.randint(-2048, 2047)}')
            op = {1: 'sb', 2: 'sh', 4: 'sw'}[size]
            out.append(f'  {op} x{rs}, 0(x29)')
    out += ['  fence.i', '  li x5, 0x8000F000', '  li x6, 1', '  sw x6, 0(x5)', '1: j 1b']
    return '\n'.join(out) + '\n'


if __name__ == '__main__':
    a = sys.argv[1:]
    extra = [int(x) for x in a[3:5]]
    open(a[2], 'w').write(gen(int(a[0]), int(a[1]), *extra))
