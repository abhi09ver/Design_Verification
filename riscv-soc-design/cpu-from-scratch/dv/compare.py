#!/usr/bin/env python3
"""compare.py -- compare DUT and reference-model traces, report the FIRST divergence.

This is lock-step compare done after the fact: both traces hold one line per
retired instruction (PC, instruction, register write, memory write). The first
differing line is the instruction where the bug became architecturally visible --
far more useful than "the final signature is wrong" (Chapter 5).

Usage: compare.py <iss.trace> <dut.trace>     exit code 0 = match
"""
import sys


def fields(line):
    out = {}
    for tok in line.split():
        if tok.startswith('pc='):     out['pc'] = tok[3:]
        elif tok.startswith('insn='): out['insn'] = tok[5:]
        elif tok.startswith('x'):     out['rd'] = tok
        elif tok.startswith('mem'):   out['mem'] = tok
    return out


def compare(ref_path, dut_path, context=4):
    ref = open(ref_path).read().splitlines()
    dut = open(dut_path).read().splitlines()
    for i, (r, d) in enumerate(zip(ref, dut)):
        if r != d:
            fr, fd = fields(r), fields(d)
            what = [k for k in ('pc', 'insn', 'rd', 'mem') if fr.get(k) != fd.get(k)]
            print(f'MISMATCH at retired instruction #{i}: differs in {", ".join(what)}')
            for j in range(max(0, i - context), i):
                print(f'   ok   {ref[j]}')
            print(f'   ref  {r}')
            print(f'   dut  {d}')
            return 1
    if len(ref) != len(dut):
        print(f'MISMATCH: reference retired {len(ref)} instructions, DUT retired {len(dut)}')
        return 1
    print(f'MATCH: {len(ref)} instructions compared, 0 mismatches')
    return 0


if __name__ == '__main__':
    sys.exit(compare(sys.argv[1], sys.argv[2]))
