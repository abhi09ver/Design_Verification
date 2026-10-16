#!/usr/bin/env python3
"""
cache_sim.py - a small, readable set-associative cache model.

Covers Levels 2-5 of the beginner guide:
  * address split into tag / index / offset
  * N-way set-associative lookup (ways=1 -> direct-mapped)
  * LRU replacement
  * write-back + write-allocate with a dirty bit (or write-through)
  * hit / miss / eviction / writeback statistics and the 3 C's

Run:
    python3 cache_sim.py            # runs the built-in demos
    python3 cache_sim.py --selftest # runs the self-checks

No dependencies beyond the Python 3 standard library.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field


def log2(n: int) -> int:
    assert n > 0 and n & (n - 1) == 0, f"{n} is not a power of two"
    return n.bit_length() - 1


@dataclass
class Line:
    valid: bool = False
    dirty: bool = False
    tag: int = 0
    data: bytearray = field(default_factory=bytearray)


@dataclass
class Stats:
    reads: int = 0
    writes: int = 0
    hits: int = 0
    misses: int = 0
    evictions: int = 0
    writebacks: int = 0
    compulsory: int = 0
    conflict_or_capacity: int = 0

    @property
    def hit_rate(self) -> float:
        total = self.hits + self.misses
        return self.hits / total if total else 0.0


class Cache:
    """Set-associative cache in front of a flat backing memory (a dict)."""

    def __init__(self, size: int, ways: int, line: int, addr_bits: int = 32,
                 write_back: bool = True, memory: dict[int, int] | None = None):
        self.size, self.ways, self.line = size, ways, line
        self.sets = size // (ways * line)
        assert self.sets >= 1, "cache smaller than one set"
        self.off_bits = log2(line)
        self.idx_bits = log2(self.sets)
        self.tag_bits = addr_bits - self.idx_bits - self.off_bits
        self.write_back = write_back
        self.mem = memory if memory is not None else {}
        # arrays[set][way]
        self.arrays = [[Line(data=bytearray(line)) for _ in range(ways)] for _ in range(self.sets)]
        # LRU order per set: list of way numbers, most-recent last
        self.lru = [list(range(ways)) for _ in range(self.sets)]
        self.seen_lines: set[int] = set()  # for compulsory-miss classification
        self.stats = Stats()

    # ---------- address helpers ----------
    def split(self, addr: int) -> tuple[int, int, int]:
        off = addr & (self.line - 1)
        idx = (addr >> self.off_bits) & (self.sets - 1)
        tag = addr >> (self.off_bits + self.idx_bits)
        return tag, idx, off

    def line_addr(self, tag: int, idx: int) -> int:
        return (tag << (self.off_bits + self.idx_bits)) | (idx << self.off_bits)

    # ---------- memory helpers ----------
    def _mem_read_line(self, base: int) -> bytearray:
        return bytearray(self.mem.get(base + i, 0) for i in range(self.line))

    def _mem_write_line(self, base: int, data: bytearray) -> None:
        for i, b in enumerate(data):
            self.mem[base + i] = b

    # ---------- core logic ----------
    def _touch(self, idx: int, way: int) -> None:
        self.lru[idx].remove(way)
        self.lru[idx].append(way)

    def _lookup(self, tag: int, idx: int) -> int | None:
        for w, ln in enumerate(self.arrays[idx]):
            if ln.valid and ln.tag == tag:
                return w
        return None

    def _fill(self, tag: int, idx: int) -> int:
        """Bring a line in, evicting the LRU way if needed. Returns the way."""
        ways = self.arrays[idx]
        free = next((w for w, ln in enumerate(ways) if not ln.valid), None)
        if free is None:
            victim = self.lru[idx][0]
            v = ways[victim]
            self.stats.evictions += 1
            if v.dirty:
                self.stats.writebacks += 1
                self._mem_write_line(self.line_addr(v.tag, idx), v.data)
            free = victim
        base = self.line_addr(tag, idx)
        ln = ways[free]
        ln.valid, ln.dirty, ln.tag, ln.data = True, False, tag, self._mem_read_line(base)
        return free

    def _access(self, addr: int) -> tuple[Line, int, bool]:
        tag, idx, off = self.split(addr)
        way = self._lookup(tag, idx)
        hit = way is not None
        if hit:
            self.stats.hits += 1
        else:
            self.stats.misses += 1
            la = addr >> self.off_bits
            if la in self.seen_lines:
                self.stats.conflict_or_capacity += 1
            else:
                self.stats.compulsory += 1
                self.seen_lines.add(la)
            way = self._fill(tag, idx)
        self._touch(idx, way)
        return self.arrays[idx][way], off, hit

    def read(self, addr: int) -> tuple[int, bool]:
        self.stats.reads += 1
        ln, off, hit = self._access(addr)
        return ln.data[off], hit

    def write(self, addr: int, value: int) -> bool:
        self.stats.writes += 1
        ln, off, hit = self._access(addr)  # write-allocate
        ln.data[off] = value & 0xFF
        if self.write_back:
            ln.dirty = True
        else:
            self.mem[addr] = value & 0xFF  # write-through
        return hit

    def flush(self) -> None:
        """Write back every dirty line (end-of-test drain)."""
        for idx, ways in enumerate(self.arrays):
            for ln in ways:
                if ln.valid and ln.dirty:
                    self._mem_write_line(self.line_addr(ln.tag, idx), ln.data)
                    self.stats.writebacks += 1
                    ln.dirty = False

    def describe(self) -> str:
        return (f"{self.size} B, {self.ways}-way, {self.line} B lines -> {self.sets} sets | "
                f"tag {self.tag_bits}b, index {self.idx_bits}b, offset {self.off_bits}b")


# ---------------------------------------------------------------- demos
def demo() -> None:
    print("=== 1. Address split (32 KiB, 8-way, 64 B, 48-bit PA) ===")
    c = Cache(32 * 1024, 8, 64, addr_bits=48)
    print(c.describe())
    for a in (0x0, 0x1234, 0xDEADBEEF):
        t, i, o = c.split(a)
        print(f"  addr {a:#012x} -> tag {t:#x}, set {i}, byte {o}")

    print("\n=== 2. Spatial locality: sequential bytes ===")
    c = Cache(1024, 2, 64)
    for a in range(256):
        c.read(a)
    print(f"  256 sequential reads: {c.stats.misses} misses (one per 64 B line), "
          f"hit rate {c.stats.hit_rate:.1%}")

    print("\n=== 3. Conflict misses: direct-mapped vs 2-way ===")
    for ways in (1, 2):
        c = Cache(256, ways, 64)  # 4 lines total
        stride = c.sets * 64       # same set every time
        for _ in range(8):
            c.read(0)
            c.read(stride)
        print(f"  {ways}-way: A,B,A,B... -> hits {c.stats.hits}, misses {c.stats.misses} "
              f"(compulsory {c.stats.compulsory}, conflict/capacity {c.stats.conflict_or_capacity})")

    print("\n=== 4. Write-back vs write-through traffic ===")
    for wb in (True, False):
        mem: dict[int, int] = {}
        c = Cache(256, 2, 64, write_back=wb, memory=mem)
        for v in range(100):
            c.write(8, v)
        mem_writes = c.stats.writebacks if wb else c.stats.writes
        print(f"  {'write-back ' if wb else 'write-through'}: 100 stores to one byte -> "
              f"{mem_writes} memory writes before flush")

    print("\n=== 5. AMAT ===")
    hit_t, penalty = 4, 300
    for mr in (0.01, 0.05, 0.10):
        print(f"  miss rate {mr:.0%}: AMAT = {hit_t} + {mr} x {penalty} = {hit_t + mr * penalty:.0f} cycles")


# ---------------------------------------------------------------- self-test
def selftest() -> None:
    import random
    rng = random.Random(1)
    for ways, wb in ((1, True), (4, True), (2, False)):
        golden: dict[int, int] = {}
        mem: dict[int, int] = {}
        c = Cache(512, ways, 32, write_back=wb, memory=mem)
        for _ in range(20000):
            a = rng.randrange(4096)
            if rng.random() < 0.4:
                v = rng.randrange(256)
                c.write(a, v)
                golden[a] = v
            else:
                got, _ = c.read(a)
                assert got == golden.get(a, 0), f"data mismatch at {a:#x}"
        c.flush()
        for a, v in golden.items():
            assert mem.get(a, 0) == v, f"memory mismatch after flush at {a:#x}"
    # split / rebuild round-trip
    c = Cache(32 * 1024, 8, 64, addr_bits=48)
    assert (c.sets, c.idx_bits, c.off_bits, c.tag_bits) == (64, 6, 6, 36)
    print("cache_sim self-test: PASS")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    selftest() if args.selftest else demo()
