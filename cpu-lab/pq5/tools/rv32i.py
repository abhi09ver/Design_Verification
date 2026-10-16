#!/usr/bin/env python3
"""
rv32i.py - assembler (with labels) + golden ISS for the full RV32I base ISA.

Assembler syntax (one instruction per line, '#' comments):
    loop:  addi x1, x1, -1        # labels end with ':'
           bne  x1, x0, loop      # branch/jal targets may be labels or numbers (byte offsets)
           lw   x2, 8(x3)
Pseudo-instructions: nop, mv rd,rs, li rd,imm (12-bit), j label, ret, halt
`halt` = `jal x0, 0` (jump to itself). The ISS and the testbench stop there.
"""
import re, sys

MASK = 0xFFFFFFFF
HALT = 0x0000006F

R = {'add': (0, 0), 'sub': (0x20, 0), 'sll': (0, 1), 'slt': (0, 2), 'sltu': (0, 3), 'xor': (0, 4),
     'srl': (0, 5), 'sra': (0x20, 5), 'or': (0, 6), 'and': (0, 7)}
I = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
SH = {'slli': (0, 1), 'srli': (0, 5), 'srai': (0x20, 5)}
LD = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
ST = {'sb': 0, 'sh': 1, 'sw': 2}
BR = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}


def sx(v, b):
    v &= (1 << b) - 1
    return v - (1 << b) if v >> (b - 1) else v


def reg(t):
    t = t.strip().lower()
    alias = {'zero': 0, 'ra': 1, 'sp': 2}
    if t in alias: return alias[t]
    m = re.fullmatch(r'x(\d+)', t)
    if not m or int(m[1]) > 31: raise ValueError(f'bad register "{t}"')
    return int(m[1])


def parse(lines):
    """first pass: strip comments, collect labels -> (list of (pc, mnemonic, args, source), labels)"""
    out, labels, pc = [], {}, 0
    for ln in lines:
        s = ln.split('#')[0].strip()
        while ':' in s:
            lab, s = s.split(':', 1)
            labels[lab.strip()] = pc
            s = s.strip()
        if not s: continue
        m = re.match(r'(\w+)\s*(.*)', s)
        op, rest = m[1].lower(), m[2]
        args = [a.strip() for a in rest.split(',')] if rest else []
        out.append((pc, op, args, s)); pc += 4
    return out, labels


def enc(pc, op, a, labels):
    def target(t):
        return (labels[t] - pc) if t in labels else int(t, 0)
    def imm(t): return int(t, 0)
    if op == 'nop':  return 0x13
    if op == 'halt': return HALT
    if op == 'mv':   op, a = 'addi', [a[0], a[1], '0']
    if op == 'li':   op, a = 'addi', [a[0], 'x0', a[1]]
    if op == 'j':    op, a = 'jal', ['x0', a[0]]
    if op == 'ret':  op, a = 'jalr', ['x0', '0(x1)']
    if op in R:
        f7, f3 = R[op]; return (f7 << 25) | (reg(a[2]) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x33
    if op in I:
        i = imm(a[2]); assert -2048 <= i < 2048, f'immediate {i} out of range'
        return ((i & 0xFFF) << 20) | (reg(a[1]) << 15) | (I[op] << 12) | (reg(a[0]) << 7) | 0x13
    if op in SH:
        f7, f3 = SH[op]; return (f7 << 25) | ((imm(a[2]) & 31) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x13
    if op in LD or op in ST or op == 'jalr':
        if op == 'jalr' and len(a) == 3: off, base = imm(a[2]), reg(a[1])
        else:
            m = re.fullmatch(r'(-?\w*)\((\w+)\)', a[1].replace(' ', ''))
            off, base = imm(m[1] or '0'), reg(m[2])
        if op in ST:
            o = off & 0xFFF
            return ((o >> 5) << 25) | (reg(a[0]) << 20) | (base << 15) | (ST[op] << 12) | ((o & 31) << 7) | 0x23
        f3, opc = (LD[op], 0x03) if op in LD else (0, 0x67)
        return ((off & 0xFFF) << 20) | (base << 15) | (f3 << 12) | (reg(a[0]) << 7) | opc
    if op in BR:
        o = target(a[2]) & 0x1FFF
        return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (reg(a[1]) << 20) | (reg(a[0]) << 15) | \
               (BR[op] << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0x63
    if op == 'jal':
        if len(a) == 1: a = ['x1', a[0]]
        o = target(a[1]) & 0x1FFFFF
        return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) | \
               (((o >> 12) & 0xFF) << 12) | (reg(a[0]) << 7) | 0x6F
    if op in ('lui', 'auipc'):
        return ((imm(a[1]) & 0xFFFFF) << 12) | (reg(a[0]) << 7) | (0x37 if op == 'lui' else 0x17)
    raise ValueError(f'unknown instruction "{op}"')


def assemble(lines):
    prog, labels = parse(lines)
    words = [enc(pc, op, a, labels) for pc, op, a, _ in prog]
    text = [s for _, _, _, s in prog]
    return words, text


class ISS:
    """Executes in program order, one instruction at a time. Data memory starts at 0."""
    def __init__(self):
        self.x = [0] * 32
        self.mem = [0] * 1024

    def ld(self, a, f3):
        w = self.mem[(a >> 2) % 1024] >> (8 * (a & 3))
        return {0: sx(w, 8), 1: sx(w, 16), 2: w, 4: w & 0xFF, 5: w & 0xFFFF}[f3] & MASK

    def st(self, a, f3, v):
        i, o = (a >> 2) % 1024, 8 * (a & 3)
        m = {0: 0xFF, 1: 0xFFFF, 2: MASK}[f3] << o
        self.mem[i] = ((self.mem[i] & ~m) | ((v << o) & m)) & MASK

    def run(self, words, max_steps=100000):
        trace, pc = [], 0
        for _ in range(max_steps):
            ins = words[pc // 4] if pc // 4 < len(words) else 0x13
            if ins == HALT: return trace
            opc, rd, f3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
            a, b = self.x[(ins >> 15) & 31], self.x[(ins >> 20) & 31]
            sa, sb_ = sx(a, 32), sx(b, 32)
            i_imm = sx(ins >> 20, 12)
            res, npc = None, pc + 4
            if opc == 0x33:
                alt = (ins >> 30) & 1
                res = {0: (a - b) if alt else (a + b), 1: a << (b & 31), 2: int(sa < sb_), 3: int(a < b),
                       4: a ^ b, 5: (sa >> (b & 31)) if alt else (a >> (b & 31)), 6: a | b, 7: a & b}[f3]
            elif opc == 0x13:
                sh = (ins >> 20) & 31
                res = {0: a + i_imm, 1: a << sh, 2: int(sa < i_imm), 3: int(a < (i_imm & MASK)),
                       4: a ^ (i_imm & MASK), 5: (sa >> sh) if (ins >> 30) & 1 else (a >> sh),
                       6: a | (i_imm & MASK), 7: a & (i_imm & MASK)}[f3]
            elif opc == 0x03:
                res = self.ld((a + i_imm) & MASK, f3)
            elif opc == 0x23:
                self.st((a + sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)) & MASK, f3, b)
            elif opc == 0x63:
                off = sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 0x3F) << 5) |
                         (((ins >> 8) & 0xF) << 1), 13)
                if {0: a == b, 1: a != b, 4: sa < sb_, 5: sa >= sb_, 6: a < b, 7: a >= b}[f3]: npc = pc + off
            elif opc == 0x6F:
                off = sx((((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xFF) << 12) | (((ins >> 20) & 1) << 11) |
                         (((ins >> 21) & 0x3FF) << 1), 21)
                res, npc = pc + 4, pc + off
            elif opc == 0x67:
                res, npc = pc + 4, (a + i_imm) & ~1 & MASK
            elif opc == 0x37:
                res = ins & 0xFFFFF000
            elif opc == 0x17:
                res = pc + (ins & 0xFFFFF000)
            if res is not None and rd != 0:
                self.x[rd] = res & MASK
                trace.append((pc, rd, res & MASK))
            else:
                trace.append((pc, 0, 0))
            pc = npc & MASK
        raise RuntimeError('program did not reach halt')


if __name__ == '__main__':
    w, _ = assemble(open(sys.argv[1]).read().splitlines())
    print('\n'.join(f'{x:08x}' for x in w))
