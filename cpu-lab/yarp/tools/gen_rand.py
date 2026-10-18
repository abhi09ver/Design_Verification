#!/usr/bin/env python3
"""gen_rand.py <seed> <out.s> : constrained-random RV32I program that always reaches halt.
Hazard-dense on purpose: 6 data registers, an 8-word memory window, dependent chains,
loads followed by uses, forward branches, small counted loops, jalr skips."""
import random, sys
def gen(seed):
    r = random.Random(seed); R = lambda: f'x{r.randint(1, 6)}'
    D = lambda: 'x0' if r.random() < 0.1 else R()     # destinations: x0 sometimes (writes must vanish)
    out = [f'# random seed {seed}'] + [f'li x{i}, {r.choice([-2048,-1,0,1,5,77,2047])}' for i in range(1, 7)]
    lab = 0
    def body(n):
        lines = []
        for _ in range(n):
            k = r.choices(['alu', 'imm', 'sh', 'ld', 'st', 'lui'], [30, 20, 8, 18, 18, 6])[0]
            if k == 'alu': lines.append(f"{r.choice(['add','sub','and','or','xor','slt','sltu','sll','srl','sra'])} {D()}, {R()}, {R()}")
            elif k == 'imm': lines.append(f"{r.choice(['addi','andi','ori','xori','slti','sltiu'])} {D()}, {R()}, {r.randint(-2048,2047)}")
            elif k == 'sh': lines.append(f"{r.choice(['slli','srli','srai'])} {D()}, {R()}, {r.randint(0,31)}")
            elif k == 'lui': lines.append(f"{r.choice(['lui','auipc'])} {D()}, {r.randint(0, 0xFFFFF)}")
            elif k == 'ld':
                op, al = r.choice([('lw',4),('lh',2),('lhu',2),('lb',1),('lbu',1)])
                lines.append(f'{op} {D()}, {r.randrange(0, 32, al)}(x0)')
            else:
                op, al = r.choice([('sw',4),('sh',2),('sb',1)])
                lines.append(f'{op} {R()}, {r.randrange(0, 32, al)}(x0)')
        return lines
    for _ in range(r.randint(4, 8)):
        kind = r.choice(['plain', 'fwd', 'loop', 'jalr'])
        if kind == 'plain': out += body(r.randint(2, 6))
        elif kind == 'fwd':
            lab += 1; out.append(f"{r.choice(['beq','bne','blt','bge','bltu','bgeu'])} {R()}, {R()}, skip{lab}")
            out += body(r.randint(1, 4)); out.append(f'skip{lab}:')
        elif kind == 'loop':
            lab += 1; out.append(f'li x31, {r.randint(1, 5)}'); out.append(f'loop{lab}:')
            out += body(r.randint(1, 5)); out += ['addi x31, x31, -1', f'bne x31, x0, loop{lab}']
        else:
            n = r.randint(0, 3); out.append('auipc x29, 0'); out.append(f'jalr x28, {8 + 4*n}(x29)')
            out += body(n)
    out.append('halt')
    return '\n'.join(out) + '\n'
if __name__ == '__main__':
    open(sys.argv[2], 'w').write(gen(int(sys.argv[1])))
