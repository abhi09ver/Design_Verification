#!/usr/bin/env python3
"""genmmu.py -- Lab 8: constrained-random Sv32 / PMP stress test.

Random addresses into a 4 GiB virtual space would almost all fault in the same way, so the
constraints aim at where MMUs break:
  * a page table with 4 KiB pages in three level-0 tables (one read by the walker from the DTIM,
    one through the D-cache, one over the uncached bus) and 4 MiB megapages (cached and uncached)
  * PTE flags drawn from a mix: mostly good, plus each kind of bad PTE (V=0, W without R, U=0,
    read-only, execute-only, A=0, D=0, misaligned megapage)
  * more distinct pages than TLB entries -> replacement; re-use of recent pages -> hits
  * segments alternate between U-mode (mret to U, ecall back) and M-mode with MPRV=1, MPP=U
  * between segments M remaps random PTEs and reprograms PMP entries 0-2 (NA4 / NAPOT / TOR,
    random R/W), always followed by sfence.vma (the software rule that makes a TLB invisible)
  * a few misaligned accesses (misaligned beats page fault) and unmapped addresses
The handler logs nothing: every trap is in the trace, and lock-step checks cause and tval.
Register use: handler t3-t6; s0 address; s1..s11, a0..a7 data; t0-t2 M-mode scratch.
Usage: genmmu.py <seed> <num_ops> <out.S>
"""
import random
import sys

ROOT, TA, TB, TC = 0x80004000, 0x80005000, 0x90008000, 0x91009000
V, R, W, X, U, G, A, D = 1, 2, 4, 8, 0x10, 0x20, 0x40, 0x80
URW = D | A | U | W | R | V
# physical data pages (never the code, the tables, .data at 0x8000_8000 or TOHOST)
DTIM_PAGES = [0x80006, 0x80007, 0x80009, 0x8000A, 0x8000B]
CACHED_PAGES = [0x90000, 0x90001, 0x90002, 0x90003]
UNCACHED_PAGES = [0x9100C, 0x9100D]          # a different part of the RAM: no cached alias
DATA_REGS = ['s1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9', 's10', 's11', 'a0', 'a1', 'a2', 'a3', 'a4']


def flags(rnd):
    k = rnd.random()
    if k < 0.70: return URW
    return rnd.choice([A | U | R | V, URW & ~V, D | A | U | W | V, D | A | X | W | R | V,
                       A | U | X | V, U | W | R | V | D, A | U | W | R | V, URW | G])


def gen(seed, n):
    rnd = random.Random(seed)
    o = ['.section .text.init', '.globl _start', '_start:',
         '  la t0, handler', '  csrw mtvec, t0',
         '  li t0, -1', '  csrw pmpaddr3, t0', '  li t0, 0x1F000000', '  csrw pmpcfg0, t0']

    def st(adr, val):
        o.extend([f'  li t0, {adr:#x}', f'  li t1, {val:#x}', '  sw t1, 0(t0)'])

    def pte(ppn, fl):
        return (ppn << 10) | fl

    # ---- virtual pages ----
    pages = []                                   # (va, size, pte address, offset lo, offset hi, table)
    st(ROOT + 0, pte(TA >> 12, V)); st(ROOT + 4, pte(TB >> 12, V)); st(ROOT + 8, pte(TC >> 12, V))
    for tbl, vpn1 in ((TA, 0), (TB, 1), (TC, 2)):
        for vpn0 in rnd.sample(range(16, 1024), 4):
            pages.append([(vpn1 << 22) | (vpn0 << 12), 4096, tbl + 4 * vpn0, 0, 4096])
    for vpn1 in rnd.sample(range(0x100, 0x200), 4):
        cached = rnd.random() < 0.6
        lo, hi = (0, 0x4000) if cached else (0xC000, 0xE000)
        pages.append([vpn1 << 22, 1 << 22, ROOT + 4 * vpn1, lo, hi, 0x90000 if cached else 0x91000])

    def mapping(p):
        if p[1] == 4096:
            return pte(rnd.choice(DTIM_PAGES + CACHED_PAGES + UNCACHED_PAGES), flags(rnd))
        ppn = p[5] + (1 if rnd.random() < 0.08 else 0)          # sometimes a misaligned megapage
        return pte(ppn, flags(rnd))

    for p in pages:
        st(p[2], mapping(p))
    for r in DATA_REGS:
        o.append(f'  li {r}, {rnd.getrandbits(32):#x}')
    o += [f'  li t0, {(1 << 31) | (ROOT >> 12):#x}', '  csrw satp, t0', '  sfence.vma']

    hot = []

    def access():
        k = rnd.random()
        if k < 0.04:
            va = (3 << 22) | (rnd.randrange(1024) << 12)          # root PTE 3 is 0: unmapped
        else:
            p = rnd.choice(hot) if hot and rnd.random() < 0.5 else rnd.choice(pages)
            if p not in hot:
                hot.append(p)
                if len(hot) > 3: hot.pop(0)
            va = p[0] + rnd.randrange(p[3], p[4])
        size = rnd.choice([1, 2, 4])
        if rnd.random() > 0.04:
            va &= ~(size - 1)                                     # 4%: misaligned
        o.append(f'  li s0, {va:#x}')
        r = rnd.choice(DATA_REGS)
        if rnd.random() < 0.5:
            o.append(f'  {dict([(1, rnd.choice(["lb", "lbu"])), (2, rnd.choice(["lh", "lhu"])), (4, "lw")])[size]} {r}, 0(s0)')
        else:
            o.append(f'  {dict([(1, "sb"), (2, "sh"), (4, "sw")])[size]} {r}, 0(s0)')

    seg = 0
    i = 0
    while i < n:
        seg += 1
        # M-mode maintenance: remap some PTEs, maybe reprogram PMP, then sfence.vma
        for p in rnd.sample(pages, rnd.randint(0, 3)):
            st(p[2], mapping(p))
        if rnd.random() < 0.4:
            cfg = 0x1F000000
            for e in range(3):
                kind = rnd.choice(['off', 'na4', 'napot', 'tor'])
                pg = rnd.choice(DTIM_PAGES + CACHED_PAGES)
                perm = rnd.choice([0, 1, 3])                      # ---, R, RW
                if kind == 'na4':
                    adr = ((pg << 12) + 4 * rnd.randrange(1024)) >> 2; a = 2
                elif kind == 'napot':
                    sz = rnd.choice([8, 64, 4096])
                    adr = (((pg << 12) + rnd.randrange(0, 4096, sz)) >> 2) | (sz // 8 - 1); a = 3
                elif kind == 'tor':
                    adr = ((pg << 12) + 4096) >> 2; a = 1                # [previous pmpaddr, end of page)
                else:
                    adr = (pg << 12) >> 2; a = 0
                o += [f'  li t0, {adr:#x}', f'  csrw pmpaddr{e}, t0']
                cfg |= ((a << 3) | perm) << (8 * e)
            o += [f'  li t0, {cfg:#x}', '  csrw pmpcfg0, t0']
        o.append('  sfence.vma')
        k = rnd.randint(5, 25)
        if seg % 2:                                               # U-mode segment
            o += [f'  la t0, m{seg}', '  la t1, cont', '  sw t0, 0(t1)', f'  la t0, u{seg}', '  csrw mepc, t0',
                  '  li t0, 0x1800', '  csrc mstatus, t0', '  mret', f'u{seg}:']
            for _ in range(k): access()
            o += ['  ecall', f'm{seg}:']
        else:                                                     # M-mode, MPRV = 1, MPP = U
            o += ['  li t0, 0x1800', '  csrc mstatus, t0', '  li t0, 0x20000', '  csrs mstatus, t0']
            for _ in range(k): access()
            if rnd.random() < 0.3:
                o.append('  sfence.vma')                          # sfence in the middle of use
                for _ in range(3): access()
            o += ['  li t0, 0x20000', '  csrc mstatus, t0']
        i += k
    o += ['  csrw satp, zero', '  fence.i', '  li t0, 0x8000F000', '  li t1, 1', '  sw t1, 0(t0)', '9: j 9b',
          '.align 2', 'handler:',
          '  csrr t3, mcause', '  li t4, 8', '  beq t3, t4, 1f',
          '  csrr t3, mepc', '  addi t3, t3, 4', '  csrw mepc, t3', '  mret',
          '1:la t5, cont', '  lw t3, 0(t5)', '  csrw mepc, t3', '  li t3, 0x1800', '  csrs mstatus, t3', '  mret',
          '.data', 'cont: .word 0']
    return '\n'.join(o) + '\n'


if __name__ == '__main__':
    open(sys.argv[3], 'w').write(gen(int(sys.argv[1]), int(sys.argv[2])))
