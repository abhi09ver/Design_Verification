#!/usr/bin/env python3
"""cachemodel.py -- Lab 7: a transaction-level reference model of the D-cache.

The ISS knows nothing about caches: it can only tell whether a load got the right VALUE.
This model knows nothing about values: it only knows WHAT A CORRECT CACHE MUST DO with the
access stream the DUT saw -- hit or miss, which way, which dirty line gets written back,
which line gets filled, and what a fence.i flush writes back, in which order.

Input: the DUT's +CACHELOG file. The model reads only the inputs from it (ACC address and
read/write, FLUSH markers), predicts every event, and compares with what the DUT logged.
A cache can be functionally correct and still fail here (a stuck LRU), and a lost writeback
fails here at the eviction itself, long before any load notices.

Usage: cachemodel.py <cachelog> [ways sets linewords]      exit 0 = match
"""
import sys


class PLRU:
    """Tree pLRU, bit index = (N-2) - heap index, exactly like book Fig. 10.20 / dcache.sv."""
    def __init__(self, n):
        self.n, self.bits = n, [0] * max(n - 1, 1)
        self.levels = n.bit_length() - 1

    def victim(self):
        h, way = 0, 0
        for _ in range(self.levels):
            b = self.bits[self.n - 2 - h]
            way = (way << 1) | b
            h = 2 * h + 1 + b
        return way

    def touch(self, way):
        h = 0
        for lvl in range(self.levels - 1, -1, -1):
            d = (way >> lvl) & 1
            self.bits[self.n - 2 - h] = 1 - d       # point away from the way just used
            h = 2 * h + 1 + d


class CacheModel:
    def __init__(self, ways=2, sets=8, linewords=4):
        self.W, self.S, self.L = ways, sets, linewords
        self.ob, self.sb = (linewords.bit_length() - 1), max(sets.bit_length() - 1, 1) if sets > 1 else 1
        self.lines = [[dict(v=0, d=0, tag=0) for _ in range(ways)] for _ in range(sets)]
        self.lru = [PLRU(ways) for _ in range(sets)]

    def split(self, a):
        s = (a >> (2 + self.ob)) & (self.S - 1) if self.S > 1 else 0
        t = (a & 0xFFFF) >> (2 + self.ob + self.sb)
        return s, t

    def line_adr(self, s, t):
        return 0x9000_0000 | (t << (2 + self.ob + self.sb)) | (s << (2 + self.ob))

    def access(self, a, write):
        """returns the list of events a correct cache produces for this access"""
        s, t = self.split(a)
        ways = self.lines[s]
        for w, ln in enumerate(ways):
            if ln['v'] and ln['tag'] == t:
                if write: ln['d'] = 1
                self.lru[s].touch(w)
                return [f"ACC {a:08x} {'W' if write else 'R'} HIT way={w}"]
        inval = [w for w, ln in enumerate(ways) if not ln['v']]
        w = inval[0] if inval else self.lru[s].victim()
        ev = [f"ACC {a:08x} {'W' if write else 'R'} MISS way={w}"]
        ln = ways[w]
        if ln['v'] and ln['d']:
            ev.append(f"WB {self.line_adr(s, ln['tag']):08x}")
        ev.append(f"FILL {self.line_adr(s, t):08x}")
        ln.update(v=1, d=1 if write else 0, tag=t)
        self.lru[s].touch(w)
        return ev

    def flush(self):
        ev = ['FLUSH']
        for s in range(self.S):
            for w in range(self.W):
                ln = self.lines[s][w]
                if ln['v'] and ln['d']:
                    ev.append(f"WB {self.line_adr(s, ln['tag']):08x}")
                    ln['d'] = 0
        return ev


def check(logfile, ways=2, sets=8, linewords=4, context=3):
    dut = [' '.join(l.split()) for l in open(logfile) if l.strip()]
    m = CacheModel(ways, sets, linewords)
    exp = []
    for line in dut:                         # the model consumes only the stimulus...
        f = line.split()
        if f[0] == 'ACC':
            exp += m.access(int(f[1], 16), f[2] == 'W')
        elif f[0] == 'FLUSH':
            exp += m.flush()
    for i, (e, d) in enumerate(zip(exp, dut)):   # ...and predicts every event
        if e != d:
            print(f'CACHE MODEL MISMATCH at event #{i}')
            for j in range(max(0, i - context), i):
                print(f'   ok    {dut[j]}')
            print(f'   model {e}')
            print(f'   dut   {d}')
            return 1
    if len(exp) != len(dut):
        print(f'CACHE MODEL MISMATCH: model expects {len(exp)} events, DUT logged {len(dut)}')
        return 1
    acc = sum(1 for l in dut if l.startswith('ACC'))
    miss = sum(1 for l in dut if 'MISS' in l)
    wb = sum(1 for l in dut if l.startswith('WB'))
    print(f'CACHE MODEL MATCH: {acc} accesses, {miss} misses, {wb} writebacks')
    return 0


if __name__ == '__main__':
    a = sys.argv[1:]
    sys.exit(check(a[0], *(int(x) for x in a[1:4])))
