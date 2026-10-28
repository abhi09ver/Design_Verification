// mmu_basic.S -- Lab 8 (book Ch 11): Sv32 translation, page faults, sfence.vma, MPRV, PMP.
//
// Physical memory used (DTIM aliases every 64 KB; 0x9000_xxxx is cacheable RAM, 0x9100_xxxx its
// uncached alias on the bus):
//   0x8000_4000  root (level-1) page table          satp.PPN = 0x80004
//   0x8000_5000  level-0 table A (VA 0x0000_0000 - 0x003F_FFFF), read from the DTIM
//   0x9000_8000  level-0 table B (VA 0x0040_0000 - 0x007F_FFFF), read THROUGH THE D-CACHE
//   0x9100_9000  level-0 table C (VA 0x0080_0000 - 0x00BF_FFFF), read over the uncached bus
//   megapages: VA 0x4000_0000 -> PA 0x9000_0000 (cached), VA 0x4100_0000 -> PA 0x9100_0000 (bus),
//              VA 0x4200_0000 -> PPN 0x90001 (misaligned: must fault)
// The trap handler uses only t3-t6. It logs (mcause, mtval), then:
//   ecall from U (8): return to M at the address in `cont`
//   fixpte != 0     : set A and D in that PTE, sfence.vma, retry the instruction (one shot)
//   otherwise       : skip the faulting instruction
// The test checks loaded values (kept in s-registers across the ecalls) and the whole log.
#define TOHOST 0x8000F000
#define ROOT   0x80004000
#define TA     0x80005000
#define TB     0x90008000
#define TC     0x91009000
#define V 0x01
#define R 0x02
#define W 0x04
#define X 0x08
#define U 0x10
#define A 0x40
#define D 0x80
#define URW  (D|A|U|W|R|V)
#define URO  (A|U|R|V)

.macro PTE tbl, idx, ppn, flags
  li t0, \tbl + 4 * (\idx)
  li t1, ((\ppn) << 10) | (\flags)
  sw t1, 0(t0)
.endm
.macro STW adr, val
  li t0, \adr
  li t1, \val
  sw t1, 0(t0)
.endm
.macro TO_U ulabel, mlabel            // run U-mode code at ulabel, come back at mlabel
  la t0, \mlabel
  la t1, cont
  sw t0, 0(t1)
  la t0, \ulabel
  csrw mepc, t0
  li t0, 0x1800
  csrc mstatus, t0                     // MPP = U
  mret
.endm

.section .text.init
.globl _start
_start:
  la   t0, handler
  csrw mtvec, t0
  la   t0, log
  la   t1, logp
  sw   t0, 0(t1)
  // PMP: entry 3 = everything RWX (U-mode needs a matching entry, M does not)
  li   t0, -1
  csrw pmpaddr3, t0
  li   t0, 0x1F000000                  // cfg3 = NAPOT | X | W | R
  csrw pmpcfg0, t0

  // ---- page tables ----
  PTE ROOT, 0, TA >> 12, V                     // pointers: only V
  PTE ROOT, 1, TB >> 12, V
  PTE ROOT, 2, TC >> 12, V
  PTE ROOT, 0x100, 0x90000, URW                // megapage, cached RAM
  PTE ROOT, 0x104, 0x91000, URW                // megapage, uncached RAM
  PTE ROOT, 0x108, 0x90001, URW                // misaligned megapage
  PTE TA, 5,  0x80006, URW                     // VA 0x5000  -> PA 0x8000_6000
  PTE TA, 6,  0x80007, URO                     // VA 0x6000  read-only
  PTE TA, 7,  0x80007, URW & ~V                // VA 0x7000  invalid
  PTE TA, 8,  0x80007, D|A|X|W|R|V             // VA 0x8000  supervisor page (U = 0)
  PTE TA, 9,  0x80007, D|A|U|W|V               // VA 0x9000  W without R: reserved
  PTE TA, 10, 0x80009, A|U|W|R|V               // VA 0xA000  D = 0
  PTE TA, 11, 0x80009, D|U|R|V                 // VA 0xB000  A = 0
  PTE TB, 3,  0x90001, URW                     // VA 0x0040_3000 -> PA 0x9000_1000
  PTE TC, 2,  0x80006, URW                     // VA 0x0080_2000 -> PA 0x8000_6000
  // ---- data the U-mode code expects ----
  STW 0x80006028, 0x11111111
  STW 0x90001010, 0x33333333
  STW 0x90001230, 0x44444444
  STW 0x91000040, 0x55555555                   // through the bus, uncached
  STW 0x80007028, 0x66666666
  STW 0x80006100, 0x77777777
  STW 0x80009050, 0x88888888
  li   t0, (1 << 31) | (ROOT >> 12)            // satp: MODE = Sv32
  csrw satp, t0
  sfence.vma
  TO_U u1, m1

// ======== U-mode part 1 (fetch is physical in this core; data is translated) ========
u1:
  li   t2, 0x5028
  lw   s0, 0(t2)                     // 0x11111111 (4 KiB page, table A in DTIM)
  li   t1, 0x22222222
  sw   t1, 4(t2)                     // PA 0x8000_602C
  li   t2, 0x00403010
  lw   s1, 0(t2)                     // 0x33333333 (table B, PTE read through the D-cache)
  li   t2, 0x40001230
  lw   s2, 0(t2)                     // 0x44444444 (megapage: PA[21:12] come from the VA)
  li   t2, 0x41000040
  lw   s3, 0(t2)                     // 0x55555555 (megapage on the uncached bus)
  li   t2, 0x00802100
  lw   s4, 0(t2)                     // 0x77777777 (table C, PTE read over the bus)
  // faults, logged and skipped
  li   t2, 0x6000
  sw   t1, 0(t2)                     // 15: store to a read-only page
  li   t2, 0x7000
  lw   s5, 0(t2)                     // 13: V = 0
  li   t2, 0x8000
  lw   s5, 0(t2)                     // 13: U-mode, U = 0
  li   t2, 0x42000000
  lw   s5, 0(t2)                     // 13: misaligned megapage
  li   t2, 0x9000
  lw   s5, 0(t2)                     // 13: W without R
  // Svade: A/D are software's job; the handler sets them and retries
  ecall                              // 8: ask M to arm the fixup for PTE TA[10] (see m1)
m1_back:
  li   t2, 0xA054
  li   t1, 0xAAAA5555
  sw   t1, 0(t2)                     // 15 (D = 0), fixed, retried: PA 0x8000_9054
  ecall                              // 8: arm the fixup for TA[11]
m1_back2:
  li   t2, 0xB050
  lw   s6, 0(t2)                     // 13 (A = 0), fixed, retried: 0x88888888
  li   t2, 0x5028
  lw   s7, 0(t2)                     // 0x11111111 again (TLB entry is now hot)
  ecall                              // 8: done

// M-mode dispatcher for the three ecalls of u1 (cont is advanced each time)
m1:
  la   t0, step
  lw   t1, 0(t0)
  addi t1, t1, 1
  sw   t1, 0(t0)
  li   t2, 1
  beq  t1, t2, m1_arm_d
  li   t2, 2
  beq  t1, t2, m1_arm_a
  j    m2
m1_arm_d:
  la   t0, fixpte
  li   t1, TA + 4 * 10
  sw   t1, 0(t0)
  TO_U m1_back, m1
m1_arm_a:
  la   t0, fixpte
  li   t1, TA + 4 * 11
  sw   t1, 0(t0)
  TO_U m1_back2, m1

// ======== sfence.vma: remap VA 0x5000 -> PA 0x8000_7000; the TLB must not keep the old one ========
m2:
  PTE TA, 5, 0x80007, URW
  sfence.vma
  TO_U u2, m3
u2:
  li   t2, 0x5028
  lw   s8, 0(t2)                     // 0x66666666
  ecall

// ======== MPRV: M-mode loads/stores translated as MPP = U ========
m3:
  li   t0, 0x1800
  csrc mstatus, t0                   // MPP = U
  li   t0, 1 << 17
  csrs mstatus, t0                   // MPRV = 1
  li   t2, 0x00403010
  lw   s9, 0(t2)                     // 0x33333333 through the TLB, from M-mode
  li   t2, 0x8000
  lw   s5, 0(t2)                     // 13: effective mode U, page has U = 0 (handler skips)
  li   t0, 1 << 17
  csrc mstatus, t0                   // MPRV = 0

// ======== PMP, phase 1: lowest-numbered matching entry wins ========
  li   t0, 0x80007028 >> 2
  csrw pmpaddr0, t0                  // entry 0: NA4 at PA 0x8000_7028, no permissions
  li   t0, (0x80007000 >> 2) | 0x1FF
  csrw pmpaddr1, t0                  // entry 1: NAPOT 4 KiB at PA 0x8000_7000, read-only
  li   t0, 0x1F001910                // cfg3 = NAPOT RWX, cfg1 = NAPOT R, cfg0 = NA4 ---
  csrw pmpcfg0, t0
  STW  0x80007028, 0x12345678        // M-mode, entry not locked: allowed
  TO_U u3, m4
u3:
  li   t2, 0x5028
  lw   s5, 0(t2)                     // 5: entry 0 denies (entry 3 would allow)
  lw   s10, 4(t2)                    // entry 1 allows reads: 0x00000000 (PA 0x8000_702C)
  sw   t2, 4(t2)                     // 7: entry 1 is read-only
  ecall

// ======== PMP, phase 2 (TOR): the walker's PTE reads are checked too ========
m4:
  li   t0, TA >> 2
  csrw pmpaddr0, t0                  // entry 0: OFF, only the TOR base
  li   t0, (TA + 0x1000) >> 2
  csrw pmpaddr1, t0                  // entry 1: TOR [table A, table A + 4 KiB), no permissions
  li   t0, 0x1F000800
  csrw pmpcfg0, t0
  sfence.vma                         // the VA 0x6000 entry must be walked again
  TO_U u4, m5
u4:
  li   t2, 0x6000
  lw   s5, 0(t2)                     // 5: the level-0 PTE read hits entry 1
  li   t2, 0x00403010
  lw   s11, 0(t2)                    // table B is fine: 0x33333333
  ecall

// ======== PMP lock: applies to M-mode, and cannot be undone until reset ========
m5:
  li   t0, 0x80007028 >> 2
  csrw pmpaddr0, t0
  li   t0, 0x1F000090                // cfg0 = L | NA4, no permissions; cfg1 = OFF
  csrw pmpcfg0, t0
  li   t2, 0x80007028
  sw   t2, 0(t2)                     // 7: locked entry applies to M
  lw   a5, 0(t2)                     // 5
  csrw pmpcfg0, zero                 // ignored for entry 0 (locked)
  csrw pmpaddr0, zero                // ignored
  csrr a6, pmpcfg0
  csrr a7, pmpaddr0
  csrw satp, zero

// ======== checks ========
  li   a0, 3                         // fail code
  li   t0, 0x11111111
  bne  s0, t0, fail
  bne  s7, t0, fail
  li   t0, 0x33333333
  bne  s1, t0, fail
  bne  s9, t0, fail
  bne  s11, t0, fail
  li   t0, 0x44444444
  bne  s2, t0, fail
  li   t0, 0x55555555
  bne  s3, t0, fail
  li   t0, 0x77777777
  bne  s4, t0, fail
  li   t0, 0x88888888
  bne  s6, t0, fail
  li   t0, 0x66666666
  bne  s8, t0, fail
  bnez s10, fail
  li   a0, 4
  li   t0, 0x80006028 + 4
  lw   t1, 0(t0)
  li   t0, 0x22222222
  bne  t1, t0, fail
  li   t0, 0x80009054
  lw   t1, 0(t0)
  li   t0, 0xAAAA5555
  bne  t1, t0, fail
  li   a0, 5
  li   t0, 0x00000090
  andi t1, a6, 0xFF
  bne  t1, t0, fail                  // cfg0 still locked
  li   t0, 0x80007028 >> 2
  bne  a7, t0, fail
  // the log
  li   a0, 6
  la   t0, log
  la   t1, expect
  la   t2, expect_end
1:lw   a1, 0(t0)
  lw   a2, 0(t1)
  bne  a1, a2, fail
  addi t0, t0, 4
  addi t1, t1, 4
  bltu t1, t2, 1b
  la   t1, logp                      // and no extra entries
  lw   t1, 0(t1)
  bne  t0, t1, fail
  li   a0, 1
fail:
  li   t0, TOHOST
  sw   a0, 0(t0)
9:j    9b

// ======== trap handler (t3-t6 only) ========
.align 2
handler:
  csrr t3, mcause
  csrr t4, mtval
  la   t5, logp
  lw   t6, 0(t5)
  sw   t3, 0(t6)
  sw   t4, 4(t6)
  addi t6, t6, 8
  sw   t6, 0(t5)
  li   t5, 8
  beq  t3, t5, h_ecall
  la   t5, fixpte
  lw   t6, 0(t5)
  beqz t6, h_skip
  sw   zero, 0(t5)
  lw   t4, 0(t6)
  ori  t4, t4, A | D
  sw   t4, 0(t6)
  sfence.vma
  mret                               // retry
h_skip:
  csrr t3, mepc
  addi t3, t3, 4
  csrw mepc, t3
  mret
h_ecall:
  la   t5, cont
  lw   t3, 0(t5)
  csrw mepc, t3
  li   t3, 0x1800
  csrs mstatus, t3                   // MPP = M
  mret

.data
.align 4
cont:     .word 0
logp:     .word 0
fixpte:   .word 0
step:     .word 0
expect:
  .word 15, 0x6000,  13, 0x7000,  13, 0x8000,  13, 0x42000000,  13, 0x9000
  .word 8, 0,  15, 0xA054,  8, 0,  13, 0xB050,  8, 0       // u1
  .word 8, 0                                               // u2
  .word 13, 0x8000                                         // MPRV
  .word 5, 0x5028,  7, 0x502C,  8, 0                       // PMP phase 1
  .word 5, 0x6000,  8, 0                                   // PMP phase 2 (walker)
  .word 7, 0x80007028,  5, 0x80007028                      // lock
expect_end:
log: .space 256
