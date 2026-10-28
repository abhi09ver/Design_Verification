// bus_irq.S -- Lab 6: timer interrupts from the CLINT on the APB bus, arriving while the
// core is busy reading the RXFIFO (a device whose reads pop). An interrupt that lands in
// the middle of a bus read must wait until the read completes (Committed); otherwise the
// load is flushed after the FIFO already popped, re-executed after mret, and one value is lost.
#define TOHOST   0x8000F000
#define FIFO     0x10000000
#define MTIMECMP 0x10200004
.section .text.init
.globl _start
_start:
  la    t0, handler
  csrw  mtvec, t0
  li    s3, 0                  // timer interrupts taken
  li    s1, 0x100              // next value the FIFO should return
  li    s2, FIFO
  li    a2, MTIMECMP
  sw    zero, 4(a2)            // mtimecmp hi = 0
  csrr  t1, time
  addi  t1, t1, 60
  sw    t1, 0(a2)              // first interrupt in 60 cycles
  li    t0, 0x80               // MTIE
  csrw  mie, t0
  csrsi mstatus, 8
  li    s4, 400                // FIFO reads
1:lw    t1, 0(s2)
  bne   t1, s1, fail           // every value exactly once, in order
  addi  s1, s1, 1
  addi  s4, s4, -1
  bnez  s4, 1b
  li    t0, 10
  blt   s3, t0, fail           // the interrupts really happened
  li    t6, 1
  j     done
fail:
  li    t6, 3
done:
  csrci mstatus, 8
  li    a1, TOHOST
  sw    t6, 0(a1)
3:j     3b

.align 2
handler:                       // timer: re-arm 37 cycles later (odd, so it lands everywhere)
  addi  s3, s3, 1
  csrr  t4, time
  addi  t4, t4, 37
  sw    t4, 0(a2)
  li    t5, 40
  blt   s3, t5, 1f
  li    t4, -1
  sw    t4, 4(a2)              // after 40: no more
1:mret
