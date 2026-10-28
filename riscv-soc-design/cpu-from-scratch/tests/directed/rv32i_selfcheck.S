// rv32i_selfcheck.S -- directed, self-checking test of every RV32I instruction
//
// Each CHECK compares a register with the value the ISA says it must hold.
// On the first mismatch the test writes its test number to TOHOST (a FAIL code);
// if everything passes it writes 1. This is riscv-arch-test's idea in miniature,
// but it checks in place instead of dumping a signature.
//
// Note what this test does NOT do: it rarely puts a consumer right after its
// producer, so it checks the ISA, not the pipeline. Hazards are the random
// generator's job -- Lab 3 shows why that distinction matters.

#define TOHOST 0x8000F000
#define CHECK(n, reg, val)  li t6, val; li t5, n; bne reg, t6, fail
#define CHECKR(n, ra, rb)   li t5, n; bne ra, rb, fail

.section .text.init
.globl _start
_start:
  la    s0, data

  // ---------------- U-type ----------------
  lui   a0, 0x12345
  CHECK(2, a0, 0x12345000)
1:auipc a1, 0
  la    a2, 1b
  CHECKR(3, a1, a2)

  // ---------------- register-immediate ----------------
  li    a0, -5
  addi  a1, a0, 7          ; CHECK(10, a1, 2)
  addi  a1, a0, -2048      ; CHECK(11, a1, -2053)
  slti  a1, a0, -4         ; CHECK(12, a1, 1)
  slti  a1, a0, -6         ; CHECK(13, a1, 0)
  sltiu a1, a0, 1          ; CHECK(14, a1, 0)          # -5 is huge unsigned
  sltiu a1, zero, 1        ; CHECK(15, a1, 1)          # seqz idiom
  xori  a1, a0, -1         ; CHECK(16, a1, 4)          # not
  ori   a1, a0, 0x70       ; CHECK(17, a1, -5 | 0x70)
  andi  a1, a0, 0x0F       ; CHECK(18, a1, 0x0B)
  li    a0, 0x80000001
  slli  a1, a0, 1          ; CHECK(19, a1, 2)
  srli  a1, a0, 31         ; CHECK(20, a1, 1)
  srai  a1, a0, 31         ; CHECK(21, a1, -1)
  srai  a1, a0, 0          ; CHECK(22, a1, 0x80000001)
  // addi with immediate bit 10 set must NOT become a subtract (bit 30 of the
  // instruction is part of the immediate here, unlike srai)
  li    a0, 100
  addi  a1, a0, 1024       ; CHECK(23, a1, 1124)

  // ---------------- register-register ----------------
  li    a2, 0x7FFFFFFF
  li    a3, 0x80000000
  add   a1, a2, a2         ; CHECK(30, a1, -2)         # overflow wraps, no trap
  sub   a1, a3, a2         ; CHECK(31, a1, 1)
  li    a4, 33
  sll   a1, a2, a4         ; CHECK(32, a1, 0xFFFFFFFE) # only low 5 bits of shift amount
  slt   a1, a3, a2         ; CHECK(33, a1, 1)          # signed: min < max
  sltu  a1, a3, a2         ; CHECK(34, a1, 0)          # unsigned: 0x80000000 > 0x7fffffff
  xor   a1, a2, a3         ; CHECK(35, a1, -1)
  srl   a1, a3, a4         ; CHECK(36, a1, 0x40000000)
  sra   a1, a3, a4         ; CHECK(37, a1, 0xC0000000)
  or    a1, a2, a3         ; CHECK(38, a1, -1)
  and   a1, a2, a3         ; CHECK(39, a1, 0)
  add   zero, a2, a2       ; CHECK(40, zero, 0)        # writes to x0 are discarded

  // ---------------- loads and stores ----------------
  li    a0, 0x8899AABB
  sw    a0, 0(s0)
  lw    a1, 0(s0)          ; CHECK(50, a1, 0x8899AABB)
  lb    a1, 0(s0)          ; CHECK(51, a1, 0xFFFFFFBB)  # sign-extend
  lbu   a1, 0(s0)          ; CHECK(52, a1, 0xBB)
  lb    a1, 2(s0)          ; CHECK(53, a1, 0xFFFFFF99)
  lh    a1, 2(s0)          ; CHECK(54, a1, 0xFFFF8899)
  lhu   a1, 2(s0)          ; CHECK(55, a1, 0x8899)
  li    a0, 0x11
  sb    a0, 1(s0)
  lw    a1, 0(s0)          ; CHECK(56, a1, 0x889911BB)  # only byte 1 changed
  li    a0, 0x2233
  sh    a0, 2(s0)
  lw    a1, 0(s0)          ; CHECK(57, a1, 0x223311BB)
  sw    a0, -4(s0)          # negative offset
  lw    a1, -4(s0)         ; CHECK(58, a1, 0x2233)

  // ---------------- branches: each taken and not taken ----------------
  li    a2, -1
  li    a3, 1
  li    t5, 60 ; beq  a2, a3, fail ; beq  a2, a2, 1f ; j fail
1:li    t5, 61 ; bne  a2, a2, fail ; bne  a2, a3, 1f ; j fail
1:li    t5, 62 ; blt  a3, a2, fail ; blt  a2, a3, 1f ; j fail   # signed -1 < 1
1:li    t5, 63 ; bge  a2, a3, fail ; bge  a3, a2, 1f ; j fail
1:li    t5, 64 ; bltu a2, a3, fail ; bltu a3, a2, 1f ; j fail   # unsigned 0xffffffff > 1
1:li    t5, 65 ; bgeu a3, a2, fail ; bgeu a2, a3, 1f ; j fail
1:
  // ---------------- jumps ----------------
  jal   ra, 2f
1:j     3f
2:la    a0, 1b
  CHECKR(70, ra, a0)        # ra = address after the jal
  jalr  t0, 0(ra)           # return to 1:
3:la    a0, 4f
  addi  a0, a0, 1           # odd address: jalr must clear bit 0
  jalr  zero, 0(a0)
  j     fail
4:
  // ---------------- all good ----------------
  li    t5, 1
fail:
  li    t6, TOHOST
  sw    t5, 0(t6)
5:j     5b

.section .data
.align 4
  .word 0
data:
  .word 0, 0, 0, 0
