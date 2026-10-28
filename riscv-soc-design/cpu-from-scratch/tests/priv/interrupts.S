// interrupts.S -- Lab 5 directed test: machine timer, software and external interrupts,
// vectored mtvec, global enable (mstatus.MIE) and per-source enables (mie).
// The testbench's CLINT-like block: mtimecmp at 0x8000F010/14, msip at 0x8000F020,
// external-interrupt line at 0x8000F024. Interrupt timing comes from the DUT; the ISS
// follows it but checks every interrupt was actually enabled when it was taken.
#define TOHOST   0x8000F000
#define MTIMECMP 0x8000F010
#define MSIP     0x8000F020
#define MEXT     0x8000F024
.section .text.init
.globl _start
_start:
  la    t0, vectors
  ori   t0, t0, 1             // mode 1 = vectored: interrupts jump to base + 4*cause
  csrw  mtvec, t0
  li    s3, 0                 // timer interrupts taken
  li    s4, 0                 // software interrupts taken
  li    s5, 0                 // external interrupts taken
  li    s6, 0                 // wrong-vector / exception count
  li    t0, MTIMECMP          // mtimecmp = time + 200 (high word first)
  sw    zero, 4(t0)
  csrr  t1, time
  addi  t1, t1, 200
  sw    t1, 0(t0)
  li    t0, 0x888             // MEIE | MTIE | MSIE
  csrw  mie, t0
  csrsi mstatus, 8            // MIE = 1: from the next instruction on, interrupts can be taken

wait_timer:                   // five timer interrupts, each re-arms mtimecmp
  wfi                         // a nop here (legal: wfi is a hint)
  li    t0, 5
  blt   s3, t0, wait_timer

  // software interrupt with MIE = 0: must NOT be taken until MIE is set again
  csrci mstatus, 8
  li    t0, MSIP
  li    t1, 1
  sw    t1, 0(t0)
  li    t2, 20
1: addi  t2, t2, -1           // spin with the interrupt pending but disabled
  bnez  t2, 1b
  bnez  s4, fail              // taken while disabled?
  csrsi mstatus, 8            // enable: taken right after this CSR write
  nop
  li    t0, 1
  bne   s4, t0, fail

  // external interrupt
  li    t0, MEXT
  li    t1, 1
  sw    t1, 0(t0)
2: beqz  s5, 2b

  li    t0, 5
  bne   s3, t0, fail
  bnez  s6, fail
  csrr  t0, mcause            // last trap was the external interrupt: 0x8000000b
  li    t1, 0x8000000b
  bne   t0, t1, fail
  li    t6, 1
  j     done
fail:
  li    t6, 3
done:
  li    a1, TOHOST
  sw    t6, 0(a1)
3: j     3b

.align 6                      // vector table must be 64-byte aligned
vectors:
  j     exc                   // 0: exceptions (and cause 0)
  j     exc                   // 1
  j     exc                   // 2
  j     msi                   // 3: machine software
  j     exc                   // 4
  j     exc                   // 5
  j     exc                   // 6
  j     mti                   // 7: machine timer
  j     exc                   // 8
  j     exc                   // 9
  j     exc                   // 10
  j     mei                   // 11: machine external

mti:
  addi  s3, s3, 1
  li    t3, MTIMECMP          // re-arm: mtimecmp = time + 150 clears the pending bit
  csrr  t4, time
  addi  t4, t4, 150
  sw    t4, 0(t3)
  li    t4, 5
  blt   s3, t4, 1f
  li    t4, -1                // after the fifth: mtimecmp = max, no more timer interrupts
  sw    t4, 4(t3)
1: mret
msi:
  addi  s4, s4, 1
  li    t3, MSIP
  sw    zero, 0(t3)           // clear the source, or it fires again right after mret
  mret
mei:
  addi  s5, s5, 1
  li    t3, MEXT
  sw    zero, 0(t3)
  mret
exc:
  addi  s6, s6, 1
  csrr  t3, mepc
  addi  t3, t3, 4
  csrw  mepc, t3
  mret
