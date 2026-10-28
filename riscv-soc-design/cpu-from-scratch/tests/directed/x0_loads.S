// x0_loads.S -- loads to x0 followed by instructions that read x0 (li = addi rd, x0, imm).
// Architecturally identical with or without the RdE != 0 term in MatchDE; only cycles differ.
#define TOHOST 0x8000F000
.section .text.init
.globl _start
_start:
  la   s0, data
  li   s1, 100
loop:
  lw   x0, 0(s0)        // load to x0: result discarded
  addi t0, x0, 5        // reads x0 right after
  lw   x0, 4(s0)
  add  t1, x0, t0       // reads x0 right after
  addi s1, s1, -1
  bnez s1, loop
  li   t6, 1
  li   a1, TOHOST
  sw   t6, 0(a1)
1: j   1b
.section .data
.align 4
data: .word 7, 9
