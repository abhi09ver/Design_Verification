// hazard_demo.S -- the book's Fig. 7.15 program, adapted to run here
//
// Watch it with:  python3 dv/pipeview.py tests/directed/hazard_demo.S
//   ori  needs t0 from addi one instruction earlier   -> forward from M
//   lb   needs t0 from addi two instructions earlier  -> forward from W
//   and  needs t2 from lb right before it             -> load-use STALL, then forward from W
//   beq  is taken                                     -> sb and xori are FLUSHED
// Self-checking: writes 1 to TOHOST if every value is right.

#define TOHOST 0x8000F000
.section .text.init
.globl _start
_start:
  la    s0, data
  addi  t0, zero, 42
  ori   t1, t0, 1          // RAW distance 1
  lb    t2, 0(s0)          // (book uses t0 as the base; ours points at data)
  and   t3, t2, t0         // load-use
  beq   t3, zero, else     // taken: data byte is 0, so t3 = 0
  sb    t3, 0(s0)          // wrong path
  xori  t4, t3, 1          // wrong path
else:
  sub   t5, t1, t4         // t4 was never written: 0
  li    a0, 43
  li    t6, 2
  bne   t1, a0, fail
  bne   t5, a0, fail
  li    t6, 1
fail:
  li    a1, TOHOST
  sw    t6, 0(a1)
1:j     1b

.section .data
.align 4
data: .word 0
