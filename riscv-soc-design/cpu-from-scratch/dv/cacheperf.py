#!/usr/bin/env python3
"""cacheperf.py -- Lab 7: miss rate vs associativity at a fixed 256-byte capacity.

Kernels (all in the cacheable region, final fence.i excluded from the counts):
  copy  : b[i] = a[i], 64 words, with b exactly one cache size after a (book Code Example 10.2)
  sum2x : sum a 512-byte array twice (capacity: the array is 2x the cache)
  cyc3  : touch 3 lines that share a set, round-robin, 40 times (more lines than ways)
Configurations: 1-way x 16 sets, 2-way x 8, 4-way x 4 (16-byte lines), and 2-way with a stuck LRU.
Usage: cacheperf.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import regress  # noqa: E402

HEAD = '.section .text.init\n.globl _start\n_start:\n  li s0, 0x90000000\n'
TAIL = '  li a1, 0x8000F000\n  li a0, 1\n  sw a0, 0(a1)\n9: j 9b\n'
KERNELS = {
    'copy': HEAD + '''  li t0, 64
  mv t1, s0
  addi t2, s0, 256          # b = a + cache size: same set, different tag
1:lw t3, 0(t1)
  sw t3, 0(t2)
  addi t1, t1, 4
  addi t2, t2, 4
  addi t0, t0, -1
  bnez t0, 1b
''' + TAIL,
    'sum2x': HEAD + '''  li t4, 2
2:li t0, 128
  mv t1, s0
  li t3, 0
1:lw t2, 0(t1)
  add t3, t3, t2
  addi t1, t1, 4
  addi t0, t0, -1
  bnez t0, 1b
  addi t4, t4, -1
  bnez t4, 2b
''' + TAIL,
    'cyc3': HEAD + '''  li t0, 40
1:lw t1, 0(s0)
  lw t1, 0x100(s0)          # 3 lines 0x100 apart: same set in every config here
  lw t1, 0x200(s0)
  addi t0, t0, -1
  bnez t0, 1b
''' + TAIL,
}
CONFIGS = [('1-way x 16 sets', 1, 16, ''), ('2-way x 8 sets', 2, 8, ''), ('4-way x 4 sets', 4, 4, ''),
           ('2-way, stuck LRU', 2, 8, 'BUG_LRU_STUCK')]


def main():
    out = os.path.join(ROOT, 'build', 'perf')
    os.makedirs(out, exist_ok=True)
    hexes = {}
    for k, src in KERNELS.items():
        p = os.path.join(out, f'k_{k}.S')
        open(p, 'w').write(src)
        hexes[k] = regress.build_test(p, out)
    print(f'{"configuration":18s} ' + ' '.join(f'{k + " miss%":>12s} {k + " cyc":>10s}' for k in KERNELS))
    for name, w, s, bug in CONFIGS:
        exe = regress.build_rtl('pipe', bug, f'-GDC_WAYS={w} -GDC_SETS={s}')
        cells = []
        for k in KERNELS:
            r = regress.sh(f'{exe} +HEX={hexes[k]}')
            m = re.search(r'accesses=(\d+) misses=(\d+)', r.stdout)
            c = re.search(r'(\d+) cycles', r.stdout)
            acc, miss = int(m.group(1)), int(m.group(2))
            cells.append(f'{100 * miss / acc:11.1f}% {int(c.group(1)):10d}')
        print(f'{name:18s} ' + ' '.join(cells))


if __name__ == '__main__':
    main()
