// bus_unmapped.S -- Lab 6: loads and stores to bus addresses nobody owns. The default
// subordinate must still complete them (HREADY = 1, read data 0), or the SoC hangs.
// Written AFTER the bug hunt showed no system test ever touched unmapped space.
#define TOHOST 0x8000F000
.section .text.init
.globl _start
_start:
  li    s0, 0x98000000         // bus region, not RAM
  li    t1, 0x1234
  sw    t1, 0(s0)              // goes nowhere
  lw    t2, 0(s0)
  bnez  t2, fail
  li    s0, 0x10F00000         // behind the bridge, no APB device
  sw    t1, 0(s0)
  lw    t2, 0(s0)
  bnez  t2, fail
  li    t6, 1
  j     done
fail:
  li    t6, 3
done:
  li    a1, TOHOST
  sw    t6, 0(a1)
3:j     3b
