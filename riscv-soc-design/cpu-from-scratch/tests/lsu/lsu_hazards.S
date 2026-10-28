// lsu_hazards.S -- Lab 9 (book Ch 12): back-to-back LSU cases for a D-cache whose data array is
// read one cycle early (synchronous SRAM, set from IEUAdrE). Every case is a pair or short run of
// memory instructions with NO instruction between them, because that is where the early read
// can be stale. Self-checking: a0 = the number of the first failing check.
//   x31 = cached base 0x9000_0000, x30 = uncached alias 0x9100_0000
#define TOHOST 0x8000F000
.macro CHECK reg, val, n
  li   gp, \val
  li   a0, \n
  bne  \reg, gp, fail
.endm

.section .text.init
.globl _start
_start:
  li   x31, 0x90000000
  li   x30, 0x91000000
  li   t0, 0x11111111
  li   t1, 0x22222222
  li   t2, 0x33333333
  li   t3, 0x44444444

  // 1. like book Fig. 12.16: load, store, load, load to one line
  sw   t0, 0x10(x31)            // warm the line (miss, fill)
  sw   t3, 0x1C(x31)
  lw   s0, 0x10(x31)            // hit
  sw   t1, 0x18(x31)            // store hit: writes the array this cycle
  lw   s1, 0x18(x31)            // load right behind it: the early read saw the OLD line -> re-read
  lw   s2, 0x1C(x31)            // and the next load
  CHECK s0, 0x11111111, 1
  CHECK s1, 0x22222222, 2
  CHECK s2, 0x44444444, 3

  // 2. store byte then load word of the same word, back to back
  sb   t2, 0x11(x31)
  lw   s3, 0x10(x31)
  CHECK s3, 0x11113311, 4

  // 3. load miss, then a load from the same line: the fill wrote the array
  lw   s4, 0x40(x31)            // miss (line 0x40 never touched)
  lw   s5, 0x44(x31)            // hit on the line just filled
  CHECK s4, 0, 5
  CHECK s5, 0, 6
  sw   t0, 0x44(x31)
  lw   s6, 0x44(x31)            // store then load, same word, after a fill
  CHECK s6, 0x11111111, 7

  // 4. two lines in one set (2 ways, 8 sets x 16 B: 0x10 and 0x90 are both set 1): the miss fills
  //    way 1, and the very next load hits way 0
  sw   t1, 0x90(x31)
  lw   s8, 0x10(x31)            // back to back with the fill
  lw   s7, 0x90(x31)
  CHECK s7, 0x22222222, 8
  CHECK s8, 0x11113311, 9

  // 5. a third line in set 1 evicts the dirty 0x10 line; reload everything back to back
  sw   t3, 0x110(x31)           // victim = line 0x00 (least recently used), written back
  lw   s9, 0x110(x31)
  lw   s10, 0x18(x31)           // miss: evicts line 0x80, line 0x00 comes back from RAM
  lw   s11, 0x90(x31)           // miss again
  CHECK s9, 0x44444444, 10
  CHECK s10, 0x22222222, 11
  CHECK s11, 0x22222222, 12

  // 6. an uncached bus load (pipeline stalled 2 cycles), then a cached load
  sw   t2, 0x200(x31)
  fence.i                       // flush so the uncached alias sees it
  lw   a1, 0x200(x30)           // bus: the next lw sits in E during the stall
  lw   a2, 0x200(x31)           // cached: miss again after the flush
  lw   a3, 0x204(x31)
  CHECK a1, 0x33333333, 13
  CHECK a2, 0x33333333, 14
  CHECK a3, 0, 15

  // 7. store / load / store / load ping-pong on two sets
  sw   t0, 0x300(x31)
  lw   a4, 0x300(x31)
  sw   t1, 0x310(x31)
  lw   a5, 0x310(x31)
  lw   a6, 0x300(x31)
  CHECK a4, 0x11111111, 16
  CHECK a5, 0x22222222, 17
  CHECK a6, 0x11111111, 18

  // 8. halfword and byte loads right after word stores (subword read from DataOut)
  li   t4, 0x8899AABB
  sw   t4, 0x320(x31)
  lh   a7, 0x322(x31)
  lbu  t5, 0x321(x31)
  CHECK a7, 0xFFFF8899, 19
  CHECK t5, 0xAA, 20

  fence.i
  li   a0, 1
fail:
  li   t0, TOHOST
  sw   a0, 0(t0)
1:j    1b
