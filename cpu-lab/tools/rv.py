#!/usr/bin/env python3
"""
rv.py - tiny RV32IM assembler + golden Instruction-Set Simulator (ISS)
=======================================================================
The ISS is the "reference model" of CPU verification: it executes the program
in strict program order, one instruction at a time, with the ISA-spec semantics.
Whatever the out-of-order core does internally, its COMMITTED stream must equal
this model's stream instruction-for-instruction.  (Spike / Sail / Imperas play
this role in real RISC-V DV flows.)

Memory model matches lab RTL data_mem: word i is initialised to i
(data_mem.sv:  mem[m] <= m;), word-indexed by addr[31:2] % 1024.
"""
import re, sys

MASK = 0xFFFFFFFF
NOP = 0x00000013  # addi x0, x0, 0

R_OPS = {  # name: (funct7, funct3)
    'add': (0x00, 0), 'sub': (0x20, 0), 'sll': (0x00, 1), 'slt': (0x00, 2),
    'sltu': (0x00, 3), 'xor': (0x00, 4), 'srl': (0x00, 5), 'sra': (0x20, 5),
    'or': (0x00, 6), 'and': (0x00, 7),
    'mul': (0x01, 0), 'mulh': (0x01, 1), 'mulhsu': (0x01, 2), 'mulhu': (0x01, 3),
    'div': (0x01, 4), 'divu': (0x01, 5), 'rem': (0x01, 6), 'remu': (0x01, 7)}
I_OPS = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
SH_OPS = {'slli': (0x00, 1), 'srli': (0x00, 5), 'srai': (0x20, 5)}
LD_OPS = {'lb': 0, 'lh': 1, 'lw': 2, 'lbu': 4, 'lhu': 5}
ST_OPS = {'sb': 0, 'sh': 1, 'sw': 2}
BR_OPS = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}


def reg(t):
    t = t.strip().lower()
    if not re.fullmatch(r'x([0-9]|[12][0-9]|3[01])', t):
        raise ValueError(f'bad register {t}')
    return int(t[1:])


def imm(t):
    return int(t.strip(), 0)


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def assemble_line(line):
    line = line.split('#')[0].split('//')[0].strip()
    if not line:
        return None
    m = re.match(r'(\w+)\s*(.*)', line)
    op, rest = m.group(1).lower(), m.group(2)
    a = [x.strip() for x in rest.split(',')] if rest else []
    if op == 'nop':
        return NOP
    if op in R_OPS:
        f7, f3 = R_OPS[op]
        return (f7 << 25) | (reg(a[2]) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x33
    if op in I_OPS:
        i = imm(a[2]); assert -2048 <= i < 2048
        return ((i & 0xFFF) << 20) | (reg(a[1]) << 15) | (I_OPS[op] << 12) | (reg(a[0]) << 7) | 0x13
    if op in SH_OPS:
        f7, f3 = SH_OPS[op]
        return (f7 << 25) | ((imm(a[2]) & 31) << 20) | (reg(a[1]) << 15) | (f3 << 12) | (reg(a[0]) << 7) | 0x13
    if op in LD_OPS or op in ST_OPS:
        mm = re.fullmatch(r'(-?\w+)\((x\d+)\)', a[1].replace(' ', ''))
        off, base = imm(mm.group(1)), reg(mm.group(2))
        if op in LD_OPS:
            return ((off & 0xFFF) << 20) | (base << 15) | (LD_OPS[op] << 12) | (reg(a[0]) << 7) | 0x03
        o = off & 0xFFF
        return ((o >> 5) << 25) | (reg(a[0]) << 20) | (base << 15) | (ST_OPS[op] << 12) | ((o & 31) << 7) | 0x23
    if op in BR_OPS:
        o = imm(a[2]) & 0x1FFF
        return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (reg(a[1]) << 20) | (reg(a[0]) << 15) | \
               (BR_OPS[op] << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0x63
    raise ValueError(f'unsupported op {op}')


def assemble(src_lines, pad_to=33):
    words, text = [], []
    for ln in src_lines:
        w = assemble_line(ln)
        if w is not None:
            words.append(w); text.append(ln.split('#')[0].strip())
    if len(words) > pad_to:
        raise ValueError(f'program has {len(words)} instructions, max {pad_to}')
    while len(words) < pad_to:
        words.append(NOP); text.append('nop (pad)')
    return words, text


class ISS:
    def __init__(self):
        self.x = [0] * 32
        self.mem = {i: i for i in range(1024)}          # word index -> value (matches data_mem reset)
        self.misaligned = []                            # (pc, kind, addr): spec says trap; lab RTL ignores
        self.pc = 0

    def ld(self, addr, size, uns):
        if (size == 1 and addr & 1) or (size == 2 and addr & 3):
            self.misaligned.append((self.pc, 'load', addr)); return MASK   # mirror RTL (returns all-ones)
        w = self.mem[(addr >> 2) % 1024]; off = addr & 3
        if size == 0:
            b = (w >> (8 * off)) & 0xFF;  return b if uns else sx(b, 8) & MASK
        if size == 1:
            h = (w >> (8 * off)) & 0xFFFF; return h if uns else sx(h, 16) & MASK
        return w

    def st(self, addr, size, val):
        if (size == 1 and addr & 1) or (size == 2 and addr & 3):
            self.misaligned.append((self.pc, 'store', addr)); return          # mirror RTL (dropped)
        i = (addr >> 2) % 1024; off = addr & 3; w = self.mem[i]
        if size == 0:
            m = 0xFF << (8 * off); w = (w & ~m) | ((val & 0xFF) << (8 * off))
        elif size == 1:
            m = 0xFFFF << (8 * off); w = (w & ~m) | ((val & 0xFFFF) << (8 * off))
        else:
            w = val
        self.mem[i] = w & MASK

    def run(self, words, n):
        """Execute n instructions sequentially (branches only fall through / taken supported).
        Returns commit trace [(pc, rd, value)] (rd=0 for stores/branches)."""
        trace, pc = [], 0
        for _ in range(n):
            ins = words[pc // 4]; self.pc = pc
            opc, rd, f3 = ins & 0x7F, (ins >> 7) & 31, (ins >> 12) & 7
            rs1, rs2, f7 = (ins >> 15) & 31, (ins >> 20) & 31, ins >> 25
            a, b = self.x[rs1], self.x[rs2]
            sa, sb_ = sx(a, 32), sx(b, 32)
            res, wr, npc = None, False, pc + 4
            if opc == 0x33:
                wr = True
                if f7 == 1:
                    if f3 == 0: res = (sa * sb_) & MASK
                    elif f3 == 1: res = ((sa * sb_) >> 32) & MASK
                    elif f3 == 2: res = ((sa * b) >> 32) & MASK
                    elif f3 == 3: res = ((a * b) >> 32) & MASK
                    elif f3 == 4:  # div (RISC-V: /0 -> -1, overflow -> dividend)
                        if b == 0: res = MASK
                        elif sa == -2**31 and sb_ == -1: res = a
                        else: res = int(sa / sb_) & MASK
                    elif f3 == 5: res = MASK if b == 0 else (a // b)
                    elif f3 == 6:
                        if b == 0: res = a
                        elif sa == -2**31 and sb_ == -1: res = 0
                        else: res = (sa - sb_ * int(sa / sb_)) & MASK
                    elif f3 == 7: res = a if b == 0 else a % b
                else:
                    res = {0: (a - b) if f7 == 0x20 else (a + b), 1: a << (b & 31), 2: int(sa < sb_),
                           3: int(a < b), 4: a ^ b, 5: (sa >> (b & 31)) if f7 == 0x20 else (a >> (b & 31)),
                           6: a | b, 7: a & b}[f3]
            elif opc == 0x13:
                wr = True; i = sx(ins >> 20, 12); sh = (ins >> 20) & 31
                res = {0: a + i, 2: int(sa < i), 3: int(a < (i & MASK)), 4: a ^ (i & MASK), 6: a | (i & MASK),
                       7: a & (i & MASK), 1: a << sh, 5: (sa >> sh) if f7 == 0x20 else (a >> sh)}[f3]
            elif opc == 0x03:
                wr = True; res = self.ld((a + sx(ins >> 20, 12)) & MASK, f3 & 3, f3 >= 4)
            elif opc == 0x23:
                self.st((a + sx(((ins >> 25) << 5) | ((ins >> 7) & 31), 12)) & MASK, f3, b)
            elif opc == 0x63:
                off = sx((((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 0x3F) << 5) |
                         (((ins >> 8) & 0xF) << 1), 13)
                tk = {0: a == b, 1: a != b, 4: sa < sb_, 5: sa >= sb_, 6: a < b, 7: a >= b}[f3]
                if tk: npc = pc + off
            if wr and rd != 0:
                self.x[rd] = res & MASK
            trace.append((pc, rd if wr else 0, (res & MASK) if (wr and rd != 0) else 0))
            pc = npc
        return trace


if __name__ == '__main__':
    src = open(sys.argv[1]).read().splitlines()
    words, _ = assemble(src)
    for w in words:
        print(f'{w:08x}')
