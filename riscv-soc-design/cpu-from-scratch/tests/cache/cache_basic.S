// cache_basic.S -- Lab 7 directed test for the D-cache (default: 2 ways x 8 sets x 16-byte lines).
//   0x9000_xxxx is cached, 0x9100_xxxx is the SAME RAM uncached. Lines that share a set are
//   0x80 bytes apart (8 sets x 16 B). Every scenario checks itself; lock-step, the end-of-test
//   RAM image and the transaction-level cache model check it again.
#define TOHOST 0x8000F000
#define C      0x90000000
#define U      0x91000000
#define CHECK(reg, val) li t6, val; bne reg, t6, fail
.section .text.init
.globl _start
_start:
  li    s0, C
  li    s1, U

  // 1) store miss (write-allocate + merge), then store hits, then load hits
  li    t1, 0x11111111
  sw    t1, 0(s0)              // miss: fetch line 0x000, merge, dirty
  li    t1, 0x22222222
  sw    t1, 4(s0)              // hit
  li    t1, 0x33333333
  sw    t1, 8(s0)
  li    t1, 0x44444444
  sw    t1, 12(s0)
  lw    t2, 0(s0)
  CHECK(t2, 0x11111111)
  lw    t2, 12(s0)
  CHECK(t2, 0x44444444)

  // 2) sub-word stores into a cached line
  li    t1, 0xAB
  sb    t1, 5(s0)
  li    t1, 0xBEEF
  sh    t1, 10(s0)
  lw    t2, 4(s0)
  CHECK(t2, 0x2222AB22)
  lw    t2, 8(s0)
  CHECK(t2, 0xBEEF3333)
  lbu   t2, 5(s0)
  CHECK(t2, 0xAB)

  // 3) conflict: three lines in set 0 of a 2-way cache -> a dirty line is evicted and written back
  li    t1, 0x55555555
  sw    t1, 0x80(s0)           // line 0x080: miss, way 1
  li    t1, 0x66666666
  sw    t1, 0x100(s0)          // line 0x100: miss, evicts LRU = line 0x000 (dirty -> writeback)
  lw    t2, 0(s0)              // line 0x000 again: miss, must come back from RAM intact
  CHECK(t2, 0x11111111)
  lw    t2, 8(s0)
  CHECK(t2, 0xBEEF3333)
  lw    t2, 0x100(s0)
  CHECK(t2, 0x66666666)

  // 4) store miss into a line that already has data in RAM: fetch + merge must keep the rest
  li    t1, 0xA0A0A0A0
  sw    t1, 0x200(s1)          // uncached writes straight to RAM
  li    t1, 0xA1A1A1A1
  sw    t1, 0x204(s1)
  li    t1, 0xA3A3A3A3
  sw    t1, 0x20C(s1)
  li    t1, 0x77777777
  sw    t1, 0x208(s0)          // cached store miss to the same line
  lw    t2, 0x200(s0)
  CHECK(t2, 0xA0A0A0A0)
  lw    t2, 0x204(s0)
  CHECK(t2, 0xA1A1A1A1)
  lw    t2, 0x208(s0)
  CHECK(t2, 0x77777777)
  lw    t2, 0x20C(s0)
  CHECK(t2, 0xA3A3A3A3)

  // 5) a line loaded CLEAN, then written by a store HIT, must be written back when evicted
  lw    t2, 0x300(s0)          // set 0, clean
  li    t1, 0x88888888
  sw    t1, 0x300(s0)          // hit: must set dirty
  lw    t2, 0x380(s0)          // set 0 again
  lw    t2, 0x400(s0)          // set 0 again: evicts line 0x300
  lw    t2, 0x300(s0)          // back from RAM
  CHECK(t2, 0x88888888)

  // 6) tag MSB: 0x9000_8010 differs from 0x9000_0010 only in address bit 15
  li    t1, 0xCAFE0001
  sw    t1, 0x10(s0)           // cached, set 1
  li    t3, 0x8010
  add   t3, s1, t3
  li    t1, 0xCAFE8000
  sw    t1, 0(t3)              // uncached write to RAM 0x8010
  li    t3, 0x8010
  add   t3, s0, t3
  lw    t2, 0(t3)              // cached load of 0x9000_8010: a different line, must miss
  CHECK(t2, 0xCAFE8000)

  // 7) fence.i flushes dirty lines, including one in the LAST set (set 7 = offset 0x70)
  li    t1, 0x99999999
  sw    t1, 0x70(s0)
  li    t1, 0x12345678
  sw    t1, 0x500(s0)
  fence.i
  lw    t2, 0x70(s1)           // uncached: sees RAM, so the flush must have written it
  CHECK(t2, 0x99999999)
  lw    t2, 0x500(s1)
  CHECK(t2, 0x12345678)
  lw    t2, 0x10(s1)
  CHECK(t2, 0xCAFE0001)

  li    a0, 1
  j     done
fail:
  li    a0, 3
done:
  fence.i                      // leave RAM up to date for the end-of-test memory compare
  li    a1, TOHOST
  sw    a0, 0(a1)
1:j     1b
