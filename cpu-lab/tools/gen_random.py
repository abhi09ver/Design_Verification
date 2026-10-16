#!/usr/bin/env python3
"""
gen_random.py <seed> [out.s]  -- constrained-random RV32IM program generator
==========================================================================
Directed tests find the bugs you THOUGHT of.  Constrained-random finds the ones
you didn't.  The constraints are what make it useful:
  * few registers (x1..x7)      -> lots of RAW / WAR / WAW hazards & renaming
  * tiny memory window (8 words) -> lots of store/load ALIASING
  * mixed latencies (ALU 1c, MUL 3c, DIV ~12c, LD/ST) -> lots of out-of-order completion
  * aligned addresses only       -> stays inside the legal ISA space the core supports
"""
import random, sys

def gen(seed, n=33):
    r = random.Random(seed)
    regs = [f'x{i}' for i in range(1, 8)]
    R = lambda: r.choice(regs)
    out = [f'# random program, seed={seed}']
    # seed registers with interesting values (negative, zero, large, small)
    for reg in regs[:4]:
        out.append(f'addi {reg}, x0, {r.choice([-2048, -7, -1, 0, 1, 3, 100, 2047])}')
    while len(out) - 1 < n:
        k = r.choices(['alu', 'imm', 'shift', 'mul', 'div', 'ld', 'st'], [25, 15, 8, 10, 7, 18, 17])[0]
        if k == 'alu':
            out.append(f"{r.choice(['add','sub','and','or','xor','slt','sltu','sll','srl','sra'])} {R()}, {R()}, {R()}")
        elif k == 'imm':
            out.append(f"{r.choice(['addi','andi','ori','xori','slti','sltiu'])} {R()}, {R()}, {r.randint(-2048, 2047)}")
        elif k == 'shift':
            out.append(f"{r.choice(['slli','srli','srai'])} {R()}, {R()}, {r.randint(0, 31)}")
        elif k == 'mul':
            out.append(f"{r.choice(['mul','mulh','mulhsu','mulhu'])} {R()}, {R()}, {R()}")
        elif k == 'div':
            out.append(f"{r.choice(['div','divu','rem','remu'])} {R()}, {R()}, {R()}")
        elif k == 'ld':
            op, al = r.choice([('lw', 4), ('lh', 2), ('lhu', 2), ('lb', 1), ('lbu', 1)])
            out.append(f'{op} {R()}, {64 + r.randrange(0, 32, al)}(x0)')
        else:
            op, al = r.choice([('sw', 4), ('sh', 2), ('sb', 1)])
            out.append(f'{op} {R()}, {64 + r.randrange(0, 32, al)}(x0)')
    return '\n'.join(out[:n + 1]) + '\n'

if __name__ == '__main__':
    s = int(sys.argv[1])
    txt = gen(s)
    if len(sys.argv) > 2:
        open(sys.argv[2], 'w').write(txt)
    else:
        print(txt, end='')
