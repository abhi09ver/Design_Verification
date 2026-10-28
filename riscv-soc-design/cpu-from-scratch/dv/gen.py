#!/usr/bin/env python3
"""gen.py -- constrained-random RV32I test generator (a miniature riscv-dv).

Pure random instructions would crash, loop forever or never create the cases that
break pipelines. The constraints below are what make random useful:

  * Small register pool (mostly x1..x7, sometimes x0) so instructions keep reading
    what the previous 1-3 instructions wrote -> RAW hazards, forwarding, load-use.
  * x0 as a destination sometimes: writes must be ignored and never forwarded.
  * Corner values (0, 1, -1, 0x7fffffff, 0x80000000) for operands and immediates.
  * Loads and stores in a 256-byte window off x31, so stores and loads alias.
  * Branches and jumps only go FORWARD 1-4 instructions: no infinite loops, and
    the instructions they skip are exactly the "wrong path" a pipeline must flush.
  * Reserved: x31 = data base pointer, x30 = jalr target scratch.

Usage: gen.py <seed> <num_instructions> <out.S>
"""
import random
import sys

CORNERS = [0, 1, 2, -1, -2, 0x7FFFFFFF, -0x80000000, 0x80000001, 0x0000FFFF, 0x00008000]
R_OPS = ['add', 'sub', 'sll', 'slt', 'sltu', 'xor', 'srl', 'sra', 'or', 'and']
I_OPS = ['addi', 'slti', 'sltiu', 'xori', 'ori', 'andi']
SH_OPS = ['slli', 'srli', 'srai']
LOADS = [('lb', 1), ('lh', 2), ('lw', 4), ('lbu', 1), ('lhu', 2)]
STORES = [('sb', 1), ('sh', 2), ('sw', 4)]
BRANCHES = ['beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu']


def gen(seed, n):
    rnd = random.Random(seed)
    recent = []                                  # destinations of the last few instructions

    def dst():
        r = rnd.random()
        if r < 0.08: return 0                    # x0: must be discarded
        if r < 0.85: return rnd.randint(1, 7)
        return rnd.randint(8, 29)

    def src():
        # half the time read something written in the last 3 instructions
        if recent and rnd.random() < 0.5:
            return rnd.choice(recent[-3:])
        return rnd.randint(0, 7) if rnd.random() < 0.85 else rnd.randint(8, 29)

    def imm12():
        return rnd.choice([0, 1, -1, 2047, -2048, rnd.randint(-2048, 2047), rnd.randint(-16, 16)])

    lines = ['.section .text.init', '.globl _start', '_start:',
             '  la x31, data']
    for r in range(1, 30):                       # interesting starting values
        v = rnd.choice(CORNERS) if rnd.random() < 0.5 else rnd.getrandbits(32)
        lines.append(f'  li x{r}, {v & 0xFFFFFFFF:#x}')

    for i in range(n):
        lines.append(f'L{i}:')
        k = rnd.random()
        rd = dst()
        fwd = min(n, i + rnd.randint(1, 4))      # forward target label
        if k < 0.30:
            ins = f'{rnd.choice(R_OPS)} x{rd}, x{src()}, x{src()}'
        elif k < 0.48:
            ins = f'{rnd.choice(I_OPS)} x{rd}, x{src()}, {imm12()}'
        elif k < 0.54:
            ins = f'{rnd.choice(SH_OPS)} x{rd}, x{src()}, {rnd.choice([0, 1, 31, rnd.randint(0, 31)])}'
        elif k < 0.58:
            ins = f'{rnd.choice(["lui", "auipc"])} x{rd}, {rnd.getrandbits(20):#x}'
        elif k < 0.70:
            op, sz = rnd.choice(LOADS)
            ins = f'{op} x{rd}, {rnd.randrange(0, 256, sz)}(x31)'
        elif k < 0.80:
            op, sz = rnd.choice(STORES)
            rd = None
            ins = f'{op} x{src()}, {rnd.randrange(0, 256, sz)}(x31)'
        elif k < 0.92:
            rd = None
            ins = f'{rnd.choice(BRANCHES)} x{src()}, x{src()}, L{fwd}'
        elif k < 0.96:
            ins = f'jal x{rd}, L{fwd}'
        else:
            lines.append(f'  la x30, L{fwd}')
            ins = f'jalr x{rd}, 0(x30)'
        lines.append('  ' + ins)
        if rd is not None:
            recent.append(rd)

    lines += [f'L{n}:',
              '  li x30, 0x8000F000',            # TOHOST
              '  li x29, 1',
              '  sw x29, 0(x30)',
              '1: j 1b',
              '.section .data', '.align 4', 'data:']
    lines += [f'  .word {rnd.getrandbits(32):#010x}' for _ in range(64)]
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    seed, n, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    with open(out, 'w') as f:
        f.write(gen(seed, n))
