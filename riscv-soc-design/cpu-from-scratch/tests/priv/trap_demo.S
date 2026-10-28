// trap_demo.S -- a short program to watch a trap and mret move through the pipeline:
//   python3 dv/pipeview.py tests/priv/trap_demo.S 30
#define TOHOST 0x8000F000
.section .text.init
.globl _start
_start:
  la    t0, handler
  csrw  mtvec, t0
  la    s0, data
  addi  a0, zero, 7
  lw    a1, 2(s0)          // misaligned load: trap in M, cause 4
  addi  a2, a0, 1          // younger: flushed, then re-executed after mret
  addi  a3, a2, 1
  li    t6, 1
  li    a4, TOHOST
  sw    t6, 0(a4)
1: j     1b
.align 2
handler:
  csrr  t1, mepc           // CSR read, then an immediate use: CSR read-use stall
  addi  t1, t1, 4          // skip the faulting load
  csrw  mepc, t1           // CSR write: younger instructions are refetched
  mret
.section .data
.align 4
data: .word 0x11223344, 0x55667788
