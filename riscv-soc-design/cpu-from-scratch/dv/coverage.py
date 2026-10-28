#!/usr/bin/env python3
"""coverage.py -- functional coverage from retirement traces (a miniature riscvISACOV).

Code coverage tells you which RTL lines ran. This tells you which SCENARIOS ran --
and the scenarios below are the ones that break pipelines, so they are written
with the bugs in mind (Chapter 5: "coverage that catches hard bugs takes thought").

Coverpoints
  insn          every RV32I instruction executed
  branch        every branch type both taken and not taken
  raw           read-after-write distance 1/2/3, by producer kind (alu/load/link)
                  -> distance 1 = forward from M, 2 = forward from W, 3 = register file;
                     load at distance 1 = the load-use stall
  x0_fwd        an instruction "writes" x0, the next one reads x0 (must read 0)
  fwd_priority  r written twice in a row, then read: newest value must win
  br_src_hazard branch / jalr whose source was produced by the previous instruction
  st_ld_alias   load from a word stored 1-3 instructions earlier
  wrong_path    taken branch/jump that skipped at least one fetched instruction

Usage: coverage.py <trace> [<trace> ...]   (several traces = merged, like vcover merge)
"""
import sys
from iss import decode

INSNS = ['lui', 'auipc', 'jal', 'jalr', 'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu',
         'lb', 'lh', 'lw', 'lbu', 'lhu', 'sb', 'sh', 'sw',
         'addi', 'slti', 'sltiu', 'xori', 'ori', 'andi', 'slli', 'srli', 'srai',
         'add', 'sub', 'sll', 'slt', 'sltu', 'xor', 'srl', 'sra', 'or', 'and']
BRANCHES = ['beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu']
LOADS = {'lb', 'lh', 'lw', 'lbu', 'lhu'}


def all_bins():
    bins = [f'insn.{n}' for n in INSNS]
    bins += [f'branch.{b}.{t}' for b in BRANCHES for t in ('taken', 'not_taken')]
    bins += [f'raw.{k}.dist{d}' for k in ('alu', 'load', 'link') for d in (1, 2, 3)]
    bins += ['x0_fwd', 'fwd_priority', 'br_src_hazard.branch', 'br_src_hazard.jalr',
             'st_ld_alias', 'wrong_path']
    return bins


def writes_rd(d):
    return d['op'] in (0x33, 0x13, 0x03, 0x37, 0x17, 0x6F, 0x67)


def reads(d):
    if d['op'] in (0x33, 0x23, 0x63): return [d['rs1'], d['rs2']]
    if d['op'] in (0x13, 0x03, 0x67): return [d['rs1']]
    return []


def kind(d):
    if d['name'] in LOADS: return 'load'
    if d['name'] in ('jal', 'jalr'): return 'link'
    return 'alu'


def sample(trace_path, hit):
    rows = []
    for line in open(trace_path):
        if line.startswith('trap'):          # trap records carry no instruction
            continue
        f = dict(t.split('=', 1) for t in line.split() if t.startswith(('pc=', 'insn=')))
        d = decode(int(f['insn'], 16))
        d['pc'] = int(f['pc'], 16)
        d['mem'] = next((t for t in line.split() if t.startswith('mem[')), None)
        rows.append(d)

    for i, d in enumerate(rows):
        n = d['name']
        if n in INSNS: hit.add(f'insn.{n}')
        nxt = rows[i + 1]['pc'] if i + 1 < len(rows) else None
        redirected = nxt is not None and nxt != d['pc'] + 4
        if n in BRANCHES:
            hit.add(f'branch.{n}.{"taken" if redirected else "not_taken"}')
        if (n in BRANCHES or n in ('jal', 'jalr')) and redirected and nxt > d['pc'] + 4:
            hit.add('wrong_path')

        # read-after-write: nearest earlier producer of each source register
        for r in set(reads(d)):
            if r == 0:
                prev = rows[i - 1] if i >= 1 else None
                if prev and writes_rd(prev) and prev['rd'] == 0:
                    hit.add('x0_fwd')
                continue
            for dist in (1, 2, 3):
                if i - dist < 0: break
                p = rows[i - dist]
                if writes_rd(p) and p['rd'] == r:
                    hit.add(f'raw.{kind(p)}.dist{dist}')
                    if dist == 1 and n in BRANCHES: hit.add('br_src_hazard.branch')
                    if dist == 1 and n == 'jalr':   hit.add('br_src_hazard.jalr')
                    if dist == 1 and i >= 2:
                        pp = rows[i - 2]
                        if writes_rd(pp) and pp['rd'] == r: hit.add('fwd_priority')
                    break

        if n in LOADS:
            for dist in (1, 2, 3):
                if i - dist >= 0 and rows[i - dist]['op'] == 0x23:
                    # same base register + same word offset = same word (base is fixed in tests)
                    st = rows[i - dist]
                    if st['rs1'] == d['rs1'] and (st['immS'] & ~3) == (d['immI'] & ~3):
                        hit.add('st_ld_alias')
    return len(rows)


def report(paths, verbose=True):
    hit = set()
    total = sum(sample(p, hit) for p in paths)
    bins = all_bins()
    covered = [b for b in bins if b in hit]
    pct = 100.0 * len(covered) / len(bins)
    if verbose:
        groups = {}
        for b in bins:
            g = b.split('.')[0]
            groups.setdefault(g, [0, 0])
            groups[g][1] += 1
            groups[g][0] += b in hit
        print(f'Functional coverage over {len(paths)} trace(s), {total} instructions: '
              f'{len(covered)}/{len(bins)} bins = {pct:.1f}%')
        for g, (h, t) in groups.items():
            print(f'  {g:14s} {h:3d}/{t:<3d} {100.0 * h / t:5.1f}%')
        missing = [b for b in bins if b not in hit]
        if missing:
            print('  uncovered: ' + ', '.join(missing))
    return pct, hit


if __name__ == '__main__':
    report(sys.argv[1:])
