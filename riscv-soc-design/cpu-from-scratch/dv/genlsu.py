#!/usr/bin/env python3
"""genlsu.py -- Lab 9: constrained-random LSU stress with BACK-TO-BACK memory instructions.

dv/gencache.py computes every address with `li` + `add`, so two memory instructions are never
adjacent: it can never put a load in Execute while a store is in Memory. A cache whose data array
is read one cycle early breaks exactly there. This generator:
  * addresses with base + immediate only (x31 = cached RAM, x30 = an uncached RAM region the cache
    never touches), so runs of 1-8 loads and stores sit next to each other in the pipeline
  * a small pool of lines that share sets (16 tags x 3 sets): store->load to the same word, the same
    line, the same set in another way; misses that evict dirty lines right before a dependent load
  * every access size, occasional uncached accesses (bus stalls) inside a run, occasional ALU ops
    and taken branches between runs, and a final fence.i so the RAM image can be compared
Usage: genlsu.py <seed> <num_ops> <out.S> [sets linebytes]
"""
import random
import sys


def gen(seed, n, sets=8, linebytes=16):
    rnd = random.Random(seed)
    stride = sets * linebytes
    hot_sets = rnd.sample(range(sets), k=min(3, sets))
    tags = rnd.sample(range(2048 // stride), k=min(6, 2048 // stride))
    lines = [t * stride + s * linebytes for t in tags for s in hot_sets]
    o = ['.section .text.init', '.globl _start', '_start:', '  li x31, 0x90000000', '  li x30, 0x91008000']
    for r in range(1, 8):
        o.append(f'  li x{r}, {rnd.getrandbits(32):#x}')
    i, lbl = 0, 0
    last = None
    while i < n:
        for _ in range(rnd.randint(1, 8)):
            i += 1
            size = rnd.choice([1, 2, 4])
            if rnd.random() < 0.08:                          # uncached, inside the run
                base, off = 'x30', rnd.randrange(0, 256, size)
            else:
                base = 'x31'
                if last is not None and rnd.random() < 0.45:     # same line as the previous access
                    off = (last & ~(linebytes - 1)) + rnd.randrange(0, linebytes, size)
                else:
                    off = rnd.choice(lines) + rnd.randrange(0, linebytes, size)
                last = off
            r = rnd.randint(1, 7)
            if rnd.random() < 0.5:
                op = {1: rnd.choice(['lb', 'lbu']), 2: rnd.choice(['lh', 'lhu']), 4: 'lw'}[size]
            else:
                op = {1: 'sb', 2: 'sh', 4: 'sw'}[size]
            o.append(f'  {op} x{r}, {off}({base})')
        k = rnd.random()
        if k < 0.3:
            o.append(f'  addi x{rnd.randint(1, 7)}, x{rnd.randint(1, 7)}, {rnd.randint(-2048, 2047)}')
        elif k < 0.4:
            lbl += 1
            o += [f'  beq x0, x0, 1f', '  addi x1, x1, 1', '1:']      # a taken branch: flushes E and D
    o += ['  fence.i', '  li x5, 0x8000F000', '  li x6, 1', '  sw x6, 0(x5)', '1: j 1b']
    return '\n'.join(o) + '\n'


if __name__ == '__main__':
    a = sys.argv[1:]
    extra = [int(x) for x in a[3:5]]
    open(a[2], 'w').write(gen(int(a[0]), int(a[1]), *extra))
