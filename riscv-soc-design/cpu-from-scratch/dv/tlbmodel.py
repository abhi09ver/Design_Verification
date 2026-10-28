#!/usr/bin/env python3
"""tlbmodel.py -- Lab 8: transaction-level model of the DTLB, checked against tb.sv's +TLBLOG.

Lock-step only sees architectural results. A TLB can be wrong without changing any result
(a stale entry that happens to translate the same way, a replacement policy that thrashes,
an entry that is never hit), so this model replays the log and predicts, for every look-up,
HIT or MISS, and for every fill, which entry is replaced:
  * fully associative, TLB_ENTRIES entries, 4 KiB pages and 4 MiB megapages
  * replacement: first entry whose recently-used (RU) bit is clear; a hit or a fill sets the
    entry's RU bit, and when all would be set, all are cleared except that one (Wally tlblru)
  * sfence.vma invalidates everything and clears the RU bits
Usage: tlbmodel.py <tlblog> [entries]
"""
import sys


def check(path, entries=4, verbose=False):
    valid, vpn, mega, ru = [0] * entries, [0] * entries, [0] * entries, [0] * entries
    errors = 0

    def match(va):
        for i in range(entries):
            if valid[i] and (vpn[i] >> 10) == (va >> 22) and (mega[i] or vpn[i] == (va >> 12)):
                return i
        return None

    def touch(i):
        new = [r | (j == i) for j, r in enumerate(ru)]
        ru[:] = [int(j == i) for j in range(entries)] if all(new) else [int(x) for x in new]

    for n, line in enumerate(open(path), 1):
        t = line.split()
        if not t:
            continue
        if t[0] == 'SFENCE':
            valid[:] = [0] * entries
            ru[:] = [0] * entries
        elif t[0] == 'ACC':
            va = int(t[1], 16)
            m = match(va)
            exp = 'HIT' if m is not None else 'MISS'
            if exp != t[2]:
                errors += 1
                if errors <= 5:
                    print(f'line {n}: {line.strip()}: model expects {exp}'
                          + (f' (entry {m}: vpn {vpn[m]:05x})' if m is not None else ''))
            if m is not None:
                touch(m)
        elif t[0] == 'FILL':
            va, idx, mg = int(t[1], 16), int(t[2]), int(t[3])
            exp = next((i for i in range(entries) if not ru[i]), 0)
            if idx != exp:
                errors += 1
                if errors <= 5:
                    print(f'line {n}: {line.strip()}: model replaces entry {exp} (RU={ru})')
            valid[idx], vpn[idx], mega[idx] = 1, va >> 12, mg
            touch(idx)
    if verbose or errors:
        print(f'tlbmodel: {errors} mismatch(es)')
    return errors


if __name__ == '__main__':
    sys.exit(1 if check(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 4, True) else 0)
