// crt0.S -- minimal C runtime for the labs: stack, zero .bss, call main, report to TOHOST
#define TOHOST 0x8000F000
.section .text.init
.globl _start
_start:
  li   sp, 0x8000EFF0
  la   t0, __bss_start
  la   t1, __bss_end
1: bgeu t0, t1, 2f
  sw   zero, 0(t0)
  addi t0, t0, 4
  j    1b
2: call main            // main returns 1 for pass, anything else for fail
  li   t0, TOHOST
  sw   a0, 0(t0)
3: j   3b
