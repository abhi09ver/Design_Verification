// trap_basic.S -- Lab 5 directed test: every M-mode exception, mret, and the Zicsr forms.
// The handler records (mcause, mtval, mepc) into a log; main checks each entry, then
// writes 1 to TOHOST. Lock-step with the ISS checks every CSR write and trap on top.
#define TOHOST 0x8000F000
.section .text.init
.globl _start
_start:
  la    t0, handler
  csrw  mtvec, t0              // direct mode
  la    s1, log                // s1 = log pointer, advanced by the handler
  li    s2, 0                  // s2 = error count

  // ---- Zicsr: write / set / clear, register and immediate forms, on mscratch ----
  li    t0, 0x12345678
  csrrw t1, mscratch, t0       // t1 = old (0), mscratch = 0x12345678
  bnez  t1, err
  csrrsi t2, mscratch, 0x5     // read, then set bits 0 and 2
  bne   t2, t0, err
  csrr  t3, mscratch           // csrrs x0 form: read only, no write
  li    t4, 0x1234567d
  bne   t3, t4, err
  li    t5, 0xF0
  csrrc t6, mscratch, t5       // clear bits 7:4
  csrr  t3, mscratch           // CSR read followed immediately by a use (CSRRdStallD)
  addi  t3, t3, 1
  li    t4, 0x1234560e
  bne   t3, t4, err
  csrr  t0, misa               // read-only: 0x40100100 (RV32I + U-mode, since Lab 8)
  li    t1, 0x40100100
  bne   t0, t1, err
  csrr  t0, mhartid
  bnez  t0, err

  // ---- exceptions: each one traps, the handler logs it and skips the instruction ----
  ecall                        // cause 11, tval 0
ebr: ebreak                    // cause 3, tval = pc
ill: .word 0x00000000          // cause 2, tval = 0
il2: csrw mvendorid, t0        // write to a read-only CSR: cause 2, tval = the instruction
il3: csrr t0, 0x7c0            // unimplemented CSR: cause 2
  la    t0, data
  lw    t1, 1(t0)              // cause 4, tval = address
  sh    t1, 3(t0)              // cause 6, tval = address
  lh    t1, 2(t0)              // aligned halfword: no trap
  la    t2, misal
  jalr  ra, 2(t2)              // jump to misal+2: cause 0, tval = target, ra NOT written
  bnez  ra, err                // ra must still be 0 (the faulting jalr never retired)
  j     check
misal: nop
  nop

check:
  // expected log: (cause, tval) pairs, compared word by word; mepc checked below
  la    a0, log
  la    a1, expect
  li    a2, 8                  // eight traps
1: lw    t0, 0(a0)
  lw    t1, 0(a1)
  bne   t0, t1, err
  lw    t0, 4(a0)
  lw    t1, 4(a1)
  bne   t0, t1, err
  addi  a0, a0, 12
  addi  a1, a1, 8
  addi  a2, a2, -1
  bnez  a2, 1b
  // the ebreak entry (2nd) must have mepc = ebr
  la    a0, log
  lw    t0, 20(a0)
  la    t1, ebr
  bne   t0, t1, err
  // mret restored MIE <- MPIE (0), set MPIE = 1, and set MPP to U (00, Lab 8): mstatus = 0x0080
  csrr  t0, mstatus
  li    t1, 0x0080
  bne   t0, t1, err
  bnez  s2, err
  li    t6, 1
  j     done
err:
  li    t6, 3
done:
  li    a1, TOHOST
  sw    t6, 0(a1)
2: j     2b

.align 2
handler:                       // log mcause, mtval, mepc; resume after the faulting instruction
  csrr  t5, mcause
  sw    t5, 0(s1)
  csrr  t5, mtval
  sw    t5, 4(s1)
  csrr  t5, mepc
  sw    t5, 8(s1)
  addi  s1, s1, 12
  addi  t5, t5, 4
  csrw  mepc, t5
  mret

.section .data
.align 4
data:   .word 0x11223344, 0x55667788
log:    .space 120
expect: // (mcause, mtval) for each trap in program order; tvals filled by the linker
  .word 11, 0
  .word 3, ebr
  .word 2, 0
  .word 2, 0xf1129073          // csrw mvendorid, t0 = csrrw x0, 0xf11, t0
  .word 2, 0x7c0022f3          // csrr t0, 0x7c0  = csrrs t0, 0x7c0, x0
  .word 4, data + 1
  .word 6, data + 3
  .word 0, misal + 2
