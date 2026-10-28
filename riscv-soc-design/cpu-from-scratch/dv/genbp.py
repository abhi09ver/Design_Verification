#!/usr/bin/env python3
"""genbp.py -- Lab 10: constrained-random CONTROL FLOW for the branch predictor.

Earlier generators emit straight-line code (gen.py) or memory runs (gencache, genlsu), where a
predictor has nothing to learn and nothing to get wrong. This one emits structured programs:
  * counted loops (1-12 trips), nested up to two deep: backward branches that are mostly taken
  * if/else on a xorshift pseudo-random value (unpredictable) or on loop-counter bits
    (periodic patterns: what gshare's global history is for)
  * calls into a DAG of functions f0..fN (fi only calls fj, j > i), with ra saved on the stack,
    direct (jal ra) or indirect through a table (jalr ra; the target changes from call to call)
  * occasionally `csrw mscratch` right before a call or a return: the CSR write flushes the
    instruction behind it after the RAS has already acted for it (exercises RAS repair)
  * every block changes s-register state differently, so a wrong-path instruction that commits
    shows up in lock-step
Code size is a few KiB: with a small BTB (e.g. -GBTB_BITS=4) unrelated instructions alias.
Usage: genbp.py <seed> <blocks> <out.S>
"""
import random
import sys

ACC = ['s0', 's1', 's2', 's3', 's4', 's5', 's6', 's7']


class G:
    def __init__(self, seed, nfunc=6):
        self.r = random.Random(seed)
        self.n = 0
        self.nfunc = nfunc

    def lbl(self, p):
        self.n += 1
        return f'{p}{self.n}'

    def stmt(self, o):
        a, b = self.r.choice(ACC), self.r.choice(ACC)
        op = self.r.choice(['addi', 'xori', 'add', 'xor', 'slli'])
        if op in ('add', 'xor'):
            o.append(f'  {op} {a}, {a}, {b}')
        elif op == 'slli':
            o.append(f'  slli {a}, {a}, {self.r.randint(1, 3)}')
            o.append(f'  addi {a}, {a}, {self.r.randint(1, 99)}')
        else:
            o.append(f'  {op} {a}, {a}, {self.r.randint(-500, 500)}')

    def rnd(self, o):                          # xorshift32 on s11
        o += ['  slli t0, s11, 13', '  xor s11, s11, t0', '  srli t0, s11, 17', '  xor s11, s11, t0',
              '  slli t0, s11, 5', '  xor s11, s11, t0']

    def block(self, o, depth, fidx, counters):
        k = self.r.random()
        if k < 0.30 and depth < 2:                                  # counted loop
            c = ['s9', 's10'][depth]
            top = self.lbl('L')
            o += [f'  li {c}, {self.r.randint(1, 12)}', f'{top}:']
            for _ in range(self.r.randint(1, 3)):
                self.block(o, depth + 1, fidx, counters + [c])
            o += [f'  addi {c}, {c}, -1', f'  bnez {c}, {top}']
        elif k < 0.55:                                              # if / else
            els, end = self.lbl('E'), self.lbl('J')
            if counters and self.r.random() < 0.6:                  # pattern from a loop counter
                o.append(f'  andi t1, {self.r.choice(counters)}, {self.r.choice([1, 2, 3])}')
            else:                                                   # pseudo-random
                self.rnd(o)
                o.append(f'  andi t1, s11, {self.r.choice([1, 3, 7])}')
            o.append(f'  {self.r.choice(["beqz", "bnez"])} t1, {els}')
            self.stmt(o)
            o += [f'  j {end}', f'{els}:']
            self.stmt(o)
            o.append(f'{end}:')
        elif k < 0.80 and fidx < self.nfunc - 1:                    # call
            callee = self.r.randint(fidx + 1, self.nfunc - 1)
            if self.r.random() < 0.15:
                o.append(f'  csrw mscratch, {self.r.choice(ACC)}')   # flushes the call behind it
            if fidx < self.nfunc - 4 and self.r.random() < 0.35:    # indirect, via table (only callers below it)
                o += [f'  andi t1, s11, 3', '  slli t1, t1, 2', '  la t2, ftab', '  add t2, t2, t1',
                      '  lw t2, 0(t2)', '  jalr ra, 0(t2)']
            else:
                o.append(f'  call f{callee}')
        else:
            self.stmt(o)

    def func(self, i):
        o = [f'f{i}:', '  addi sp, sp, -12', '  sw ra, 0(sp)', '  sw s9, 4(sp)', '  sw s10, 8(sp)']
        for _ in range(self.r.randint(1, 3)):
            self.block(o, 1, i, [])
        o += ['  lw ra, 0(sp)', '  lw s9, 4(sp)', '  lw s10, 8(sp)', '  addi sp, sp, 12']
        if self.r.random() < 0.15:
            o.append(f'  csrw mscratch, {self.r.choice(ACC)}')       # flushes the ret behind it
        o.append('  ret')
        return o


def gen(seed, nblocks):
    g = G(seed)
    o = ['.section .text.init', '.globl _start', '_start:', '  li sp, 0x8000EFF0',
         f'  li s11, {g.r.getrandbits(31) | 1:#x}']
    for r in ACC:
        o.append(f'  li {r}, {g.r.getrandbits(16)}')
    for _ in range(nblocks):
        g.block(o, 0, -1, [])
    o += ['  li t0, 0x8000F000', '  li t1, 1', '  sw t1, 0(t0)', '9: j 9b']
    for i in range(g.nfunc):
        o += g.func(i)
    # indirect-call table: the last four functions (leaves or near-leaves)
    o += ['.data', '.align 2', 'ftab: ' + '.word ' + ', '.join(f'f{i}' for i in range(g.nfunc - 4, g.nfunc))]
    return '\n'.join(o) + '\n'


if __name__ == '__main__':
    open(sys.argv[3], 'w').write(gen(int(sys.argv[1]), int(sys.argv[2])))
