// bus_basic.S -- Lab 6 directed test: loads and stores over AHB to the uncore.
//   RAM 0x9000_0000 (ram_ahb), and behind the AHB-to-APB bridge:
//   RXFIFO 0x1000_0000 (read pops), GPIO 0x1006_0000 (OUT/EN/IN), CLINT 0x1020_0000.
// Self-checking, and lock-step compared with the ISS's model of the same devices.
#define TOHOST 0x8000F000
#define RAM    0x90000000
#define FIFO   0x10000000
#define GPIO   0x10060000
.section .text.init
.globl _start
_start:
  la    t0, handler
  csrw  mtvec, t0
  li    s6, 0                  // exceptions taken
  li    s0, RAM

  // 1) a word round trip
  li    t1, 0x11223344
  sw    t1, 0(s0)
  lw    t2, 0(s0)
  bne   t1, t2, fail

  // 2) sub-word stores land on the right byte lanes (HADDR[1:0] + HWSTRB)
  sw    zero, 4(s0)
  li    t1, 0xAB
  sb    t1, 5(s0)              // lane 1
  li    t1, 0xBEEF
  sh    t1, 6(s0)              // lanes 2-3
  lw    t2, 4(s0)
  li    t3, 0xBEEFAB00
  bne   t2, t3, fail
  lb    t2, 5(s0)              // 0xAB sign-extends
  li    t3, -85
  bne   t2, t3, fail
  lbu   t2, 5(s0)
  li    t3, 0xAB
  bne   t2, t3, fail
  lh    t2, 6(s0)              // 0xBEEF sign-extends
  li    t3, 0xFFFFBEEF
  bne   t2, t3, fail
  lhu   t2, 6(s0)
  li    t3, 0xBEEF
  bne   t2, t3, fail

  // 3) fill 32 words, then sum them back (store/load mix, every access a bus transfer)
  li    t0, 0
  li    t4, 0                  // expected sum
  li    t5, 0x01010101
  mv    t6, s0
1:addi  t6, t6, 4
  mv    t1, t0
  slli  t2, t0, 8
  or    t1, t1, t2
  slli  t2, t1, 16
  or    t1, t1, t2             // t1 = t0 * 0x01010101 for t0 < 256
  sw    t1, 64(t6)
  add   t4, t4, t1
  addi  t0, t0, 1
  li    t2, 32
  blt   t0, t2, 1b
  li    t0, 0
  li    t3, 0
  mv    t6, s0
2:addi  t6, t6, 4
  lw    t1, 64(t6)
  add   t3, t3, t1
  addi  t0, t0, 1
  li    t2, 32
  blt   t0, t2, 2b
  bne   t3, t4, fail

  // 4) GPIO (book Example 9.1): low 16 pins outputs, high 16 inputs from the board
  li    s1, GPIO
  li    t1, 0x0000FFFF
  sw    t1, 4(s1)              // GPIOEN
  li    t1, 0x12345678
  sw    t1, 0(s1)              // GPIOOUT
  lw    t2, 8(s1)              // GPIOIN = outputs read back | board pins
  li    t3, 0x5A5A5678
  bne   t2, t3, fail
  li    t1, 0x99
  sb    t1, 3(s1)              // byte write to OUT[31:24] via PSTRB
  lw    t2, 0(s1)
  li    t3, 0x99345678
  bne   t2, t3, fail

  // 5) RXFIFO: every read pops
  li    s2, FIFO
  lw    t1, 0(s2)
  lw    t2, 0(s2)
  lw    t3, 0(s2)
  li    t4, 0x100
  bne   t1, t4, fail
  addi  t4, t4, 1
  bne   t2, t4, fail
  addi  t4, t4, 1
  bne   t3, t4, fail
  li    t1, 0x500
  sw    t1, 0(s2)              // set the next value
  lw    t2, 0(s2)
  bne   t1, t2, fail

  // 6) a misaligned store to GPIO must trap BEFORE it reaches the bus
  li    t1, 0x7777
  sh    t1, 1(s1)              // odd address: store address misaligned (cause 6)
  li    t0, 1
  bne   s6, t0, fail
  lw    t2, 0(s1)
  li    t3, 0x99345678         // OUT unchanged
  bne   t2, t3, fail
  lw    t2, 4(s1)
  li    t3, 0x0000FFFF         // EN unchanged
  bne   t2, t3, fail

  li    t6, 1
  j     done
fail:
  li    t6, 3
done:
  li    a1, TOHOST
  sw    t6, 0(a1)
3:j     3b

.align 2
handler:                       // count the exception and skip the faulting instruction
  addi  s6, s6, 1
  csrr  t3, mepc
  addi  t3, t3, 4
  csrw  mepc, t3
  mret
