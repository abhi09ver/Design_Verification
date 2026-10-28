// bp_basic.S -- Lab 10 (book Ch 13): control flow that a branch predictor can get wrong.
// Every case changes architectural state differently if a wrong-path instruction survives,
// so the self-check (and lock-step) see functional predictor bugs; performance is read from
// the testbench's BPSTATS line. Self-checking: a0 = number of the first failing check.
//   1  book Code Example 13.1: nested loops (i < 5, j < 10)
//   2  book Code Example 13.2: eqntott-style correlated branches
//   3  calls nested 6 deep (deeper than a 4-entry RAS) and a recursive fib(10)
//   4  indirect calls through a table: the jalr target changes every time
//   5  BTB aliasing: a plain addi sits exactly 4 KiB after a trained jump (tagless BTB,
//      1024 entries x 4 B), so the BTB predicts it as a taken jump
//   6  a loop exit mispredicts while the instruction in Fetch is a predicted-taken jump
//   7  csrw right before a call: the call is flushed after the RAS already pushed for it
#define TOHOST 0x8000F000
.macro CHECK reg, val, n
  li   t6, \val
  li   a0, \n
  bne  \reg, t6, fail
.endm

.option norelax              // keep .org offsets exact (the linker must not shrink call/la)
.section .text.init
.globl _start
_start:
  li   sp, 0x8000EFF0
  // ---- 1. nested loops ----
  li   t0, 5
  li   t1, 10
  li   s0, 0
  li   s2, 0                   // count dostuff executions
fori:
  li   s1, 0
forj:
  addi s2, s2, 1               // dostuff
  addi s1, s1, 1
  blt  s1, t1, forj            // branch_j
  addi s0, s0, 1
  blt  s0, t0, fori            // branch_i
  CHECK s2, 50, 1

  // ---- 2. correlated branches: (aa, bb) cycles through 4 patterns, 40 times ----
  li   s3, 0                   // times dostuff ran
  li   s4, 0                   // loop counter
corr:
  andi t2, s4, 3               // pattern
  srli s0, t2, 1               // aa = 0/0/1/1 ... scaled to 0 or 2
  slli s0, s0, 1
  andi s1, t2, 1               // bb = 0/2/0/2
  slli s1, s1, 1
  li   t0, 2
  bne  s0, t0, skipaa          // branch_aa
  li   s0, 0
skipaa:
  bne  s1, t0, skipbb          // branch_bb
  li   s1, 0
skipbb:
  beq  s0, s1, skipaabb        // branch_aabb: always equal here (both end up 0)
  addi s3, s3, 1
skipaabb:
  addi s4, s4, 1
  li   t0, 40
  blt  s4, t0, corr
  CHECK s3, 0, 2

  // ---- 3. deep calls and recursion ----
  li   a1, 0
  call f1                      // f1..f6 each add their number: 21
  CHECK a1, 21, 3
  li   a0, 10
  call fib
  mv   s5, a0
  CHECK s5, 55, 4

  // ---- 4. indirect calls, target changes every time ----
  li   s6, 0                   // accumulator
  li   s7, 0                   // i
  la   s8, ftab
ind:
  li   t0, 3
  remu_loop:                   // t1 = i % 3 without M extension
  mv   t1, s7
1:blt  t1, t0, 2f
  sub  t1, t1, t0
  j    1b
2:slli t1, t1, 2
  add  t1, t1, s8
  lw   t2, 0(t1)
  jalr ra, 0(t2)               // add 1, 10 or 100
  addi s7, s7, 1
  li   t0, 9
  blt  s7, t0, ind
  CHECK s6, 333, 5

  // ---- 5. BTB aliasing (see alias_far below) ----
  li   s9, 0                   // how often the trained branch's target ran
  li   s10, 4
train:
  j    br_target               // br_alias: a jump (always taken whatever the direction predictor
                               // says) trains BTB entry (PC >> 2) % 1024
br_alias = train
back:
  addi s10, s10, -1
  bnez s10, train
  li   s11, 0
  j    alias_far               // the addi there has the same BTB index as br_alias
alias_back:
  CHECK s9, 4, 6               // the target ran exactly 4 times (not on the wrong path)
  CHECK s11, 3, 7              // both addis ran

  // ---- 6. loop exit while Fetch holds a predicted-taken jump ----
  li   t3, 0
  li   t4, 6
loop6:
  j    body6                   // a jump at the loop head: predicted taken from the 2nd time
body6:
  addi t3, t3, 1
  blt  t3, t4, loop6           // trained taken; mispredicts at the exit
  CHECK t3, 6, 8

  // ---- 7. csrw right before a call (Memory flushes the call in Execute) ----
  li   a1, 0
  li   t5, 3
csrloop:
  csrw mscratch, t5
  call f6                      // pushed in Decode, then flushed and refetched
  addi t5, t5, -1
  bnez t5, csrloop
  CHECK a1, 18, 9

  li   a0, 1
fail:
  li   t0, TOHOST
  sw   a0, 0(t0)
9:j    9b

// ---- functions ----
f1: addi sp, sp, -4
    sw   ra, 0(sp)
    addi a1, a1, 1
    call f2
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
f2: addi sp, sp, -4
    sw   ra, 0(sp)
    addi a1, a1, 2
    call f3
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
f3: addi sp, sp, -4
    sw   ra, 0(sp)
    addi a1, a1, 3
    call f4
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
f4: addi sp, sp, -4
    sw   ra, 0(sp)
    addi a1, a1, 4
    call f5
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
f5: addi sp, sp, -4
    sw   ra, 0(sp)
    addi a1, a1, 5
    call f6
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
f6: addi a1, a1, 6
    ret
fib:                           // a0 = fib(a0), recursive
    li   t0, 2
    blt  a0, t0, 3f
    addi sp, sp, -8
    sw   ra, 4(sp)
    sw   a0, 0(sp)
    addi a0, a0, -1
    call fib
    lw   t0, 0(sp)
    sw   a0, 0(sp)
    addi a0, t0, -2
    call fib
    lw   t0, 0(sp)
    add  a0, a0, t0
    lw   ra, 4(sp)
    addi sp, sp, 8
3:  ret
add1:   addi s6, s6, 1
        ret
add10:  addi s6, s6, 10
        ret
add100: addi s6, s6, 100
        ret
br_target:
    addi s9, s9, 1
    j    back

// ---- the aliasing block: exactly 4096 bytes after br_alias ----
.org (br_alias - _start) + 0x1000
alias_far:
    addi s11, s11, 1           // same BTB index as br_alias: predicted "taken branch to br_target"
    addi s11, s11, 2
    j    alias_back

.data
.align 2
ftab: .word add1, add10, add100
