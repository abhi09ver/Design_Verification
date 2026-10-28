#!/usr/bin/env python3
"""iss.py -- a tiny RV32I instruction-set simulator (the "reference model").

This plays the role Sail, Spike or ImperasDV play for Wally (Chapter 5): it knows
nothing about pipelines, it just executes one instruction at a time exactly as the
ISA says. The DUT's trace must match this trace line for line.

Written independently of the RTL on purpose: if the same person writes both from
the same misunderstanding, both agree and both are wrong.

Lab 5 (Ch 8) adds machine-mode Zicsr, ecall/ebreak/mret and traps. Two things a
reference model cannot know on its own are taken from the DUT's trace, exactly as
ImperasDV/RVVI lock-step does (Ch 5.6): WHEN an interrupt arrives, and the values of
free-running or pin-driven CSRs (mcycle/cycle/time and mip). Everything else -- whether
the interrupt was enabled, mcause/mtval/mepc, mstatus updates -- the ISS computes itself.

Lab 8 (Ch 11) adds U-mode, mstatus.MPP/MPRV, satp (Sv32), PMP (4 entries) and data page /
access faults. The ISS has no TLB: it walks the page table on every access, which is the
architectural meaning of a TLB when software follows the rule "sfence.vma after changing a
PTE". A DUT whose TLB keeps a stale entry after sfence.vma therefore diverges here.

Usage:  iss.py <program.hex> <trace.out> [max_instructions] [dut_trace_to_follow]
"""
import sys

BASE   = 0x8000_0000
TOHOST = 0x8000_F000
MEMSZ  = 64 * 1024          # aliases every 64 KB, same as the testbench
M32    = 0xFFFF_FFFF


def sx(v, bits):
    """sign-extend the low `bits` of v"""
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def s32(v):
    return sx(v, 32)


def decode(insn):
    """Split an instruction into fields and immediates, and name it."""
    d = dict(insn=insn,
             op=insn & 0x7F, rd=(insn >> 7) & 31, f3=(insn >> 12) & 7,
             rs1=(insn >> 15) & 31, rs2=(insn >> 20) & 31, f7=insn >> 25)
    d['immI'] = sx(insn >> 20, 12)
    d['immS'] = sx(((insn >> 25) << 5) | ((insn >> 7) & 31), 12)
    d['immB'] = sx((((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11) |
                   (((insn >> 25) & 0x3F) << 5) | (((insn >> 8) & 0xF) << 1), 13)
    d['immJ'] = sx((((insn >> 31) & 1) << 20) | (((insn >> 12) & 0xFF) << 12) |
                   (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3FF) << 1), 21)
    d['immU'] = insn & 0xFFFF_F000
    d['name'] = mnemonic(d)
    return d


R_NAMES = {(0, 0): 'add', (0, 0x20): 'sub', (1, 0): 'sll', (2, 0): 'slt', (3, 0): 'sltu',
           (4, 0): 'xor', (5, 0): 'srl', (5, 0x20): 'sra', (6, 0): 'or', (7, 0): 'and'}
I_NAMES = {0: 'addi', 2: 'slti', 3: 'sltiu', 4: 'xori', 6: 'ori', 7: 'andi', 1: 'slli'}
LD_NAMES = {0: 'lb', 1: 'lh', 2: 'lw', 4: 'lbu', 5: 'lhu'}
ST_NAMES = {0: 'sb', 1: 'sh', 2: 'sw'}
BR_NAMES = {0: 'beq', 1: 'bne', 4: 'blt', 5: 'bge', 6: 'bltu', 7: 'bgeu'}


def mnemonic(d):
    op, f3, f7 = d['op'], d['f3'], d['f7']
    if op == 0x33: return R_NAMES.get((f3, f7), 'illegal')
    if op == 0x13:
        if f3 == 5: return {0: 'srli', 0x20: 'srai'}.get(f7, 'illegal')
        if f3 == 1 and f7 != 0: return 'illegal'
        return I_NAMES[f3]
    if op == 0x03: return LD_NAMES.get(f3, 'illegal')
    if op == 0x23: return ST_NAMES.get(f3, 'illegal')
    if op == 0x63: return BR_NAMES.get(f3, 'illegal')
    if op == 0x6F: return 'jal'
    if op == 0x67: return 'jalr' if f3 == 0 else 'illegal'
    if op == 0x37: return 'lui'
    if op == 0x17: return 'auipc'
    if op == 0x0F: return 'fence'
    if op == 0x73:
        if f3 in (1, 2, 3, 5, 6, 7): return ['', 'csrrw', 'csrrs', 'csrrc', '', 'csrrwi', 'csrrsi', 'csrrci'][f3]
        if f3 == 0 and d['rd'] == 0 and d['f7'] == 0x09:
            return 'sfence.vma'
        if f3 == 0 and d['rd'] == 0 and d['rs1'] == 0:
            return {0x000: 'ecall', 0x001: 'ebreak', 0x302: 'mret', 0x105: 'wfi'}.get(d['insn'] >> 20, 'illegal')

    return 'illegal'


# ---------------- Lab 6 (Ch 9): what lives on the bus (rtl/uncore/uncore.sv) ----------------
PADS_IN = 0x5A5A_0F0F         # what the "board" drives onto GPIO pins that are inputs (tb.sv)


def is_bus(a):
    return (a >> 28) in (0x1, 0x9)


class Uncore:
    """Architectural model of the uncore devices: what a load returns, what a store changes.
    No phases, no wait states -- only what software can observe."""
    def __init__(self):
        self.ram = bytearray(MEMSZ)
        self.gpio_out = self.gpio_en = 0
        self.fifo_head = 0x100
        self.msip = self.mext = 0
        self.mtimecmp = (1 << 64) - 1

    def read(self, a):
        if a >> 16 in (0x9000, 0x9100):        # 0x9100 = same RAM, uncached alias (Ch 10)
            o = a & (MEMSZ - 4)
            return int.from_bytes(self.ram[o:o + 4], 'little')
        if a >> 24 == 0x10:
            dev, reg = (a >> 16) & 0xFF, (a >> 2) & 7
            if dev == 0x06:                                    # GPIO: OUT, EN, IN
                return [self.gpio_out, self.gpio_en,
                        (self.gpio_en & self.gpio_out) | (~self.gpio_en & PADS_IN & M32), 0][reg & 3]
            if dev == 0x00:                                    # RXFIFO: a read pops
                v = self.fifo_head
                self.fifo_head = (self.fifo_head + 1) & M32
                return v
            if dev == 0x20:                                    # CLINT (mtime is not modelled)
                return {0: self.msip, 1: self.mtimecmp & M32, 2: self.mtimecmp >> 32, 4: self.mext}.get(reg, 0)
        return 0                                               # default subordinate

    def write(self, a, data, mask):
        if a >> 16 in (0x9000, 0x9100):
            o = a & (MEMSZ - 4)
            for b in range(4):
                if mask >> b & 1:
                    self.ram[o + b] = (data >> (8 * b)) & 0xFF
        elif a >> 24 == 0x10:
            dev, reg = (a >> 16) & 0xFF, (a >> 2) & 7
            lanes = sum(0xFF << (8 * b) for b in range(4) if mask >> b & 1)
            if dev == 0x06 and (reg & 3) in (0, 1):
                if reg & 3 == 0: self.gpio_out = (self.gpio_out & ~lanes | data & lanes) & M32
                else:            self.gpio_en = (self.gpio_en & ~lanes | data & lanes) & M32
            elif dev == 0x00:
                self.fifo_head = data & M32                    # PWDATA, whatever the strobes
            elif dev == 0x20:
                if reg == 0 and mask & 1: self.msip = data & 1
                elif reg == 1: self.mtimecmp = (self.mtimecmp & ~M32) | data
                elif reg == 2: self.mtimecmp = (self.mtimecmp & M32) | (data << 32)
                elif reg == 4 and mask & 1: self.mext = data & 1


class ISS:
    def __init__(self, hexfile):
        self.mem = bytearray(MEMSZ)
        with open(hexfile) as f:
            words = [int(w, 16) for line in f for w in line.split()
                     if w and not w.startswith('//') and not w.startswith('@')]
        for i, w in enumerate(words):
            self.mem[4 * i:4 * i + 4] = w.to_bytes(4, 'little')
        self.x = [0] * 32
        self.pc = BASE
        # machine-mode CSR state (reset values per the privileged spec / priv.sv)
        self.mie_bit = self.mpie_bit = 0
        self.csr = {0x304: 0, 0x305: 0, 0x340: 0, 0x341: 0, 0x342: 0, 0x343: 0}
        self.minstret = 0
        self.follow = []          # DUT trace lines, for interrupts and nondeterministic CSRs
        self.nlines = 0
        self.bus = Uncore()       # Lab 6: devices on the AHB/APB bus
        # Lab 8: privilege, translation, protection
        self.mode, self.mpp, self.mprv, self.satp = 3, 3, 0, 0
        self.pmpcfg, self.pmpaddr = [0] * 4, [0] * 4

    # memory aliases every 64 KB, exactly like the testbench -- except the Lab 6 bus regions
    def rd_word(self, a):
        if is_bus(a):
            return self.bus.read(a)
        a &= MEMSZ - 4
        return int.from_bytes(self.mem[a:a + 4], 'little')

    def wr_bytes(self, a, data, mask):
        if is_bus(a):
            return self.bus.write(a, data, mask)
        base = a & (MEMSZ - 4)
        for b in range(4):
            if mask >> b & 1:
                self.mem[base + b] = (data >> (8 * b)) & 0xFF

    # ---------------- privileged helpers ----------------
    FOLLOW_CSRS = {0xB00, 0xB80, 0xC00, 0xC01, 0xC80, 0xC81, 0x344}   # mcycle, cycle, time, mip
    LEGAL = {0x180, 0x306, 0x3A0, 0x3A1, 0x3A2, 0x3A3} | set(range(0x3B0, 0x3C0)) | {0x300, 0x301, 0x304, 0x305, 0x340, 0x341, 0x342, 0x343, 0x344,
             0xB00, 0xB02, 0xB80, 0xB82, 0xC00, 0xC01, 0xC02, 0xC80, 0xC81, 0xC82,
             0xF11, 0xF12, 0xF13, 0xF14}

    def peek(self):
        return self.follow[self.nlines] if self.nlines < len(self.follow) else ''

    def csr_read(self, a, pc, insn):
        if a in self.FOLLOW_CSRS:          # take the DUT's value (it depends on time / pins)
            line = self.peek()
            if line.startswith(f"pc={pc:08x} insn={insn:08x}"):
                for tok in line.split():
                    if tok.startswith('x') and '=' in tok:
                        return int(tok.split('=')[1], 16)
            return 0
        if a == 0x300: return (self.mprv << 17) | (self.mpp << 11) | (self.mpie_bit << 7) | (self.mie_bit << 3)
        if a == 0x301: return 0x4010_0100
        if a == 0x180: return self.satp
        if a == 0x306: return 0
        if a == 0x3A0: return sum(c << (8 * i) for i, c in enumerate(self.pmpcfg))
        if 0x3B0 <= a <= 0x3B3: return self.pmpaddr[a - 0x3B0]
        if 0x3A1 <= a <= 0x3BF: return 0
        if a in (0xB02, 0xC02): return self.minstret & M32
        if a in (0xB82, 0xC82): return self.minstret >> 32
        if a >= 0xF11: return 0
        return self.csr[a]

    def csr_write(self, a, v):
        if a == 0x300:
            self.mie_bit, self.mpie_bit = (v >> 3) & 1, (v >> 7) & 1
            self.mprv = (v >> 17) & 1
            self.mpp = 3 if (v >> 11) & 3 == 3 else 0
        elif a == 0x180: self.satp = v & 0x803F_FFFF
        elif a == 0x3A0:
            for i in range(4):
                if not self.pmpcfg[i] >> 7:
                    c = (v >> (8 * i)) & 0x9F
                    if not c & 1: c &= ~2
                    self.pmpcfg[i] = c
        elif 0x3B0 <= a <= 0x3B3:
            i = a - 0x3B0
            locked_tor_above = i < 3 and self.pmpcfg[i + 1] >> 7 and (self.pmpcfg[i + 1] >> 3) & 3 == 1
            if not self.pmpcfg[i] >> 7 and not locked_tor_above:
                self.pmpaddr[i] = v & M32
        elif a == 0x304: self.csr[a] = v & 0x888
        elif a == 0x305: self.csr[a] = v & ~2 & M32
        elif a == 0x341: self.csr[a] = v & ~3 & M32
        elif a in (0x340, 0x342, 0x343): self.csr[a] = v & M32
        elif a == 0xB02: self.minstret = (self.minstret & ~M32) | v; return 'noinc'
        elif a == 0xB82: self.minstret = (self.minstret & M32) | (v << 32); return 'noinc'
        # mcycle writes: reads follow the DUT anyway; misa/mip: WARL, ignored

    # ---------------- Lab 8: PMP and Sv32 (privileged spec 3.7, 4.3) ----------------
    def pmp_ok(self, pa, mode, acc):
        """acc in 'r', 'w'. pa is up to 34 bits. Lowest-numbered matching entry decides."""
        if pa >> 32:
            return False                       # beyond our 32-bit physical bus
        w = pa >> 2
        for i in range(4):
            c, adr = self.pmpcfg[i], self.pmpaddr[i]
            a = (c >> 3) & 3
            if a == 1:   hit = (self.pmpaddr[i - 1] if i else 0) <= w < adr
            elif a == 2: hit = w == adr
            elif a == 3:
                m = adr ^ ((adr + 1) & M32)
                hit = (w & ~m) == (adr & ~m)
            else:        hit = False
            if hit:
                if mode == 3 and not c >> 7:
                    return True
                return bool(c & (1 if acc == 'r' else 2))
        return mode == 3

    def translate(self, va, acc):
        """returns (pa, None) or (None, cause)"""
        mode = self.mpp if self.mprv else self.mode
        pf, af = (13, 5) if acc == 'r' else (15, 7)
        if mode == 3 or not self.satp >> 31:
            return (va, None) if self.pmp_ok(va, mode, acc) else (None, af)
        base = (self.satp & 0x3F_FFFF) << 12
        for level in (1, 0):
            vpn = (va >> (12 + 10 * level)) & 0x3FF
            pte_a = base + 4 * vpn
            if not self.pmp_ok(pte_a, 1, 'r'):          # implicit reads are checked like S-mode
                return None, af
            pte = self.rd_word(pte_a)
            v, r, w, x, u, a_, d = [(pte >> b) & 1 for b in (0, 1, 2, 3, 4, 6, 7)]
            if not v or (w and not r):
                return None, pf
            if r or x:                                  # leaf
                ppn = pte >> 10
                if level == 1 and ppn & 0x3FF:
                    return None, pf                     # misaligned megapage
                if mode == 0 and not u: return None, pf
                if acc == 'r' and not r: return None, pf
                if acc == 'w' and not w: return None, pf
                if not a_ or (acc == 'w' and not d): return None, pf   # Svade
                pa = ((ppn >> 10) << 22 | (va & 0x3F_FFFF)) if level == 1 else (ppn << 12 | (va & 0xFFF))
                return (pa, None) if self.pmp_ok(pa, mode, acc) else (None, af)
            if level == 0 or (pte >> 4) & 1 or a_ or d:
                return None, pf                         # pointer at level 0, or reserved bits
            base = (pte >> 10) << 12
        return None, pf

    def trap(self, pc, cause, tval):
        self.csr[0x341], self.csr[0x342], self.csr[0x343] = pc, cause, tval & M32
        self.mpie_bit, self.mie_bit = self.mie_bit, 0
        self.mpp, self.mode = self.mode, 3
        tvec = self.csr[0x305]
        base = tvec & ~3 & M32
        self.pc = (base + 4 * (cause & 0x7FFF_FFFF)) & M32 if (tvec & 1 and cause >> 31) else base
        return f"trap pc={pc:08x} cause={cause:08x} tval={tval & M32:08x}"

    def step(self):
        """Execute one instruction (or take an interrupt). Returns (trace_line, done)."""
        line, done = self._step()
        self.nlines += 1
        return line, done

    def _step(self):
        pc, x = self.pc, self.x
        # interrupt? Only the DUT knows when its pins rose; the ISS checks it was allowed.
        nxt = self.peek()
        if nxt.startswith('trap') and 'cause=8' in nxt:
            cause = int(nxt.split('cause=')[1].split()[0], 16)
            code = cause & 0x7FFF_FFFF
            enabled = self.mie_bit and (self.csr[0x304] >> code) & 1
            line = self.trap(pc, cause, 0)
            return (line if enabled else line + ' ILLEGAL-INTERRUPT(disabled in ISS)'), None
        insn = self.rd_word(pc)
        d = decode(insn)
        n = d['name']
        rs1, rs2 = x[d['rs1']], x[d['rs2']]
        rd_val = None            # value written to rd (if any)
        st = None                # (aligned addr, aligned data, mask)
        nextpc = (pc + 4) & M32

        umode = self.mode == 0
        if n == 'illegal' or (umode and (n in ('mret', 'sfence.vma', 'wfi') or n.startswith('csrr'))):
            return self.trap(pc, 2, insn), None
        if n == 'ecall':  return self.trap(pc, 8 if umode else 11, 0), None
        if n == 'ebreak': return self.trap(pc, 3, pc), None
        csrw = None
        if n == 'mret':
            nextpc = self.csr[0x341]
            self.mie_bit, self.mpie_bit = self.mpie_bit, 1
            self.mode, self.mpp = self.mpp, 0
            if self.mode != 3:
                self.mprv = 0
        elif n.startswith('csrr'):
            a = insn >> 20
            src = d['rs1'] if n.endswith('i') else rs1
            writes = n in ('csrrw', 'csrrwi') or d['rs1'] != 0
            if a not in self.LEGAL or (writes and (a >> 10) == 3):
                return self.trap(pc, 2, insn), None
            old = self.csr_read(a, pc, insn)
            rd_val = old
            if writes:
                new = src if n in ('csrrw', 'csrrwi') else (old | src if n in ('csrrs', 'csrrsi') else old & ~src & M32)
                csrw = (a, new & M32)
        if d['op'] == 0x33:
            sh = rs2 & 31
            rd_val = {'add': rs1 + rs2, 'sub': rs1 - rs2, 'sll': rs1 << sh,
                      'slt': int(s32(rs1) < s32(rs2)), 'sltu': int(rs1 < rs2),
                      'xor': rs1 ^ rs2, 'srl': rs1 >> sh, 'sra': s32(rs1) >> sh,
                      'or': rs1 | rs2, 'and': rs1 & rs2}[n]
        elif d['op'] == 0x13:
            imm = d['immI']
            sh = imm & 31
            rd_val = {'addi': rs1 + imm, 'slti': int(s32(rs1) < imm),
                      'sltiu': int(rs1 < (imm & M32)), 'xori': rs1 ^ (imm & M32),
                      'ori': rs1 | (imm & M32), 'andi': rs1 & (imm & M32),
                      'slli': rs1 << sh, 'srli': rs1 >> sh, 'srai': s32(rs1) >> sh}[n]
        elif d['op'] == 0x03:
            a = (rs1 + d['immI']) & M32
            if (n in ('lh', 'lhu') and a & 1) or (n == 'lw' and a & 3):
                return self.trap(pc, 4, a), None
            pa, cause = self.translate(a, 'r')
            if cause:
                return self.trap(pc, cause, a), None
            w = self.rd_word(pa)
            off = a & 3
            if n == 'lw':  rd_val = w
            elif n in ('lb', 'lbu'):
                b = (w >> (8 * off)) & 0xFF
                rd_val = sx(b, 8) if n == 'lb' else b
            else:
                h = (w >> (16 * (off >> 1))) & 0xFFFF
                rd_val = sx(h, 16) if n == 'lh' else h
        elif d['op'] == 0x23:
            a = (rs1 + d['immS']) & M32
            if (n == 'sh' and a & 1) or (n == 'sw' and a & 3):
                return self.trap(pc, 6, a), None
            off = a & 3
            if n == 'sb':   data, mask = (rs2 & 0xFF) << (8 * off), 1 << off
            elif n == 'sh': data, mask = (rs2 & 0xFFFF) << (16 * (off >> 1)), 0b1100 if off & 2 else 0b0011
            else:           data, mask = rs2, 0xF
            pa, cause = self.translate(a, 'w')
            if cause:
                return self.trap(pc, cause, a), None
            st = (pa & ~3 & M32, data & M32, mask)
            self.wr_bytes(pa, data, mask)
        elif d['op'] == 0x63:
            a, b = rs1, rs2
            taken = {'beq': a == b, 'bne': a != b, 'blt': s32(a) < s32(b), 'bge': s32(a) >= s32(b),
                     'bltu': a < b, 'bgeu': a >= b}[n]
            if taken: nextpc = (pc + d['immB']) & M32
        elif n == 'jal':
            rd_val, nextpc = pc + 4, (pc + d['immJ']) & M32
        elif n == 'jalr':
            rd_val, nextpc = pc + 4, (rs1 + d['immI']) & M32 & ~1
        elif n == 'lui':
            rd_val = d['immU']
        elif n == 'auipc':
            rd_val = pc + d['immU']
        # fence, wfi: nothing to do
        if nextpc != (pc + 4) & M32 and nextpc & 2 and n != 'mret':   # no C extension
            return self.trap(pc, 0, nextpc), None

        line = f"pc={pc:08x} insn={insn:08x}"
        if rd_val is not None and d['rd'] != 0:
            x[d['rd']] = rd_val & M32
            line += f" x{d['rd']}={x[d['rd']]:08x}"
        if st:
            line += f" mem[{st[0]:08x}]={st[1]:08x}/{st[2]:x}"
        noinc = None
        if csrw:
            line += f" csr[{csrw[0]:03x}]={csrw[1]:08x}"
            noinc = self.csr_write(*csrw)
        if noinc is None:
            self.minstret += 1
        self.pc = nextpc

        if st and st[0] == TOHOST:
            return line, 'tohost'
        if nextpc == pc:
            return line, 'selfloop'
        return line, None


def run(hexfile, tracefile, maxinsn=200000, follow=None, ramdump=None):
    iss = ISS(hexfile)
    if follow:
        iss.follow = open(follow).read().splitlines()
    res = 'timeout'
    with open(tracefile, 'w') as f:
        for _ in range(maxinsn):
            line, done = iss.step()
            f.write(line + '\n')
            if done:
                res = done
                break
    if ramdump:                    # Lab 7: final bus-RAM image, same format as tb.sv +RAMDUMP
        with open(ramdump, 'w') as f:
            for o in range(0, MEMSZ, 4):
                w = int.from_bytes(iss.bus.ram[o:o + 4], 'little')
                if w:
                    f.write(f'{o:04x} {w:08x}\n')
    return res


if __name__ == '__main__':
    res = run(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 200000,
              sys.argv[4] if len(sys.argv) > 4 else None)
    print(f"ISS finished: {res}")
