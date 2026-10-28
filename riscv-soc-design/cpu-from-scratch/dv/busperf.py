#!/usr/bin/env python3
"""busperf.py -- Lab 6: what a bus costs. (Since Lab 7, 0x9000_xxxx is cached; this uses the
uncached alias 0x9100_xxxx of the same RAM so the numbers stay those of the bare bus.) The same loop (write 64 words, then sum them)
runs on the in-core DTIM and on the bus RAM, with 0..4 extra RAM wait states.
Usage: busperf.py"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import regress  # noqa: E402

SRC = """
.section .text.init
.globl _start
_start:
  li    s0, {base}
  li    t0, 0
  li    t2, 64
  mv    t6, s0
1:sw    t0, 0(t6)
  addi  t6, t6, 4
  addi  t0, t0, 1
  blt   t0, t2, 1b
  li    t0, 0
  li    t3, 0
  mv    t6, s0
2:lw    t1, 0(t6)
  addi  t6, t6, 4
  add   t3, t3, t1
  addi  t0, t0, 1
  blt   t0, t2, 2b
  li    t4, 2016
  li    t6, 1
  beq   t3, t4, 3f
  li    t6, 3
3:li    a1, 0x8000F000
  sw    t6, 0(a1)
4:j     4b
"""


def main():
    out = os.path.join(ROOT, 'build', 'perf')
    os.makedirs(out, exist_ok=True)
    rows = []
    for name, base in [('DTIM (in core)', '0x80009000'), ('bus RAM', '0x91000000')]:
        src = os.path.join(out, f'sum_{base}.S')
        open(src, 'w').write(SRC.format(base=base))
        hx = regress.build_test(src, out)
        waits = [0] if base.startswith('0x8') else [0, 1, 2, 4]
        for w in waits:
            exe = regress.build_rtl('pipe', '', f'-GRAM_WAIT={w}')
            r = regress.sh(f'{exe} +HEX={hx}')
            m = re.search(r'after (\d+) instructions, (\d+) cycles', r.stdout)
            st = re.search(r'stall_cycles=(\d+)', r.stdout)
            n, c = int(m.group(1)), int(m.group(2))
            rows.append((name, w if base.startswith('0x91') else '-', n, c, c / n, int(st.group(1))))
    print(f'{"memory":16s} {"RAM wait":>8s} {"instr":>6s} {"cycles":>7s} {"CPI":>5s} {"bus stall cycles":>17s}')
    for r in rows:
        print(f'{r[0]:16s} {str(r[1]):>8s} {r[2]:6d} {r[3]:7d} {r[4]:5.2f} {r[5]:17d}')


if __name__ == '__main__':
    main()
