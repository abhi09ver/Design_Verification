#!/usr/bin/env python3
"""
mesi_model.py - MESI snooping protocol model + a miniature verification environment.

What it shows (the verification mindset from Challenge 32):
  * Protocol:   N private caches, atomic snooping bus, MESI (optionally MSI with --msi)
  * Stimulus:   constrained-random loads/stores/evictions on a SMALL hot address pool
                (so cores collide and races happen)
  * Checkers:   1. SWMR monitor          - at most one M/E, and M/E excludes S
                2. Data-value scoreboard - every load returns the latest store (golden memory)
                3. Read-read coherence   - a core never sees an older value after a newer one
                4. End-of-test drain     - flush and compare memory to golden
  * Coverage:   (state, event) transition cells hit, printed as a table
  * Bug injection: --bug <name> breaks the protocol on purpose so you can watch
                   a checker catch it ("prove the scoreboard can fail")

Run:
    python3 mesi_model.py                       # clean run, prints coverage
    python3 mesi_model.py --bug upgrade_no_inv  # S->M without invalidating others
    python3 mesi_model.py --bug stale_e         # grants E even when others share
    python3 mesi_model.py --bug no_flush        # M owner doesn't supply data on snoop
    python3 mesi_model.py --bug silent_m_evict  # dirty eviction without writeback
    python3 mesi_model.py --trace 20            # print first 20 bus transactions

The bus is atomic (one transaction at a time), so there are no transient states.
Real designs add transient states (IS_D, IM_AD, SM_AD, MI_A ...) - see the
Challenge 32 notes for the races that appear once the bus is split-transaction.
"""
from __future__ import annotations

import argparse
import random
from collections import Counter

M, E, S, I = "M", "E", "S", "I"
BUGS = ("upgrade_no_inv", "stale_e", "no_flush", "silent_m_evict")


class CheckerError(AssertionError):
    pass


class System:
    def __init__(self, ncores: int, msi: bool = False, bug: str | None = None, trace: int = 0):
        self.n = ncores
        self.msi = msi
        self.bug = bug
        self.trace_left = trace
        self.state: list[dict[int, str]] = [dict() for _ in range(ncores)]
        self.data: list[dict[int, int]] = [dict() for _ in range(ncores)]
        self.mem: dict[int, int] = {}
        # --- verification side (never read by the design) ---
        self.golden: dict[int, int] = {}
        self.last_seen: list[dict[int, int]] = [dict() for _ in range(ncores)]  # per core, per addr: version
        self.version: dict[int, int] = {}       # addr -> monotonically increasing write count
        self.val_version: dict[tuple[int, int], int] = {}  # (addr, value) -> version that wrote it
        self.cov: Counter[tuple[str, str]] = Counter()
        self.bus_txns = 0

    # ------------------------------------------------------------ helpers
    def st(self, c: int, a: int) -> str:
        return self.state[c].get(a, I)

    def _set(self, c: int, a: int, s: str, event: str) -> None:
        self.cov[(self.st(c, a), event)] += 1
        if s == I:
            self.state[c].pop(a, None)
            self.data[c].pop(a, None)
        else:
            self.state[c][a] = s

    def _trace(self, msg: str) -> None:
        if self.trace_left > 0:
            self.trace_left -= 1
            print("   ", msg)

    # ------------------------------------------------------------ protocol (the "DUT")
    def bus_rd(self, req: int, a: int) -> None:
        """GetS: requester wants a readable copy."""
        self.bus_txns += 1
        shared = False
        supplier_val = None
        for c in range(self.n):
            if c == req:
                continue
            s = self.st(c, a)
            if s == I:
                continue
            shared = True
            if s == M:
                if self.bug != "no_flush":
                    supplier_val = self.data[c][a]
                    self.mem[a] = supplier_val          # flush to memory
                self._set(c, a, S, "snoop_BusRd")
            elif s == E:
                self._set(c, a, S, "snoop_BusRd")
            else:
                self._set(c, a, S, "snoop_BusRd")
        val = supplier_val if supplier_val is not None else self.mem.get(a, 0)
        grant = S if (shared or self.msi) else E
        if self.bug == "stale_e" and not self.msi:
            grant = E
        self._set(req, a, grant, "own_Load_miss")
        self.data[req][a] = val
        self._trace(f"C{req} BusRd  A{a}: shared={shared} -> {grant}, value {val}")

    def bus_rdx(self, req: int, a: int, upgrade: bool) -> None:
        """GetM / Upgrade: requester wants the only writable copy."""
        self.bus_txns += 1
        supplier_val = None
        for c in range(self.n):
            if c == req:
                continue
            s = self.st(c, a)
            if s == I:
                continue
            if upgrade and self.bug == "upgrade_no_inv":
                continue  # BUG: forgot to invalidate sharers on upgrade
            if s == M and self.bug != "no_flush":
                supplier_val = self.data[c][a]
                self.mem[a] = supplier_val
            self._set(c, a, I, "snoop_BusRdX")
        if not upgrade:
            self.data[req][a] = supplier_val if supplier_val is not None else self.mem.get(a, 0)
        self._trace(f"C{req} {'BusUpgr' if upgrade else 'BusRdX '} A{a}: others -> I")

    def load(self, c: int, a: int) -> int:
        if self.st(c, a) == I:
            self.bus_rd(c, a)
        else:
            self.cov[(self.st(c, a), "own_Load_hit")] += 1
        return self.data[c][a]

    def store(self, c: int, a: int, v: int) -> None:
        s = self.st(c, a)
        if s == M:
            self.cov[(M, "own_Store_hit")] += 1
        elif s == E:
            self._set(c, a, M, "own_Store_hit")  # silent E->M
        elif s == S:
            self.bus_rdx(c, a, upgrade=True)
            self._set(c, a, M, "own_Store_upgrade")
        else:
            self.bus_rdx(c, a, upgrade=False)
            self._set(c, a, M, "own_Store_miss")
        self.data[c][a] = v

    def evict(self, c: int, a: int) -> None:
        s = self.st(c, a)
        if s == I:
            return
        if s == M and self.bug != "silent_m_evict":
            self.mem[a] = self.data[c][a]  # PutM / writeback
        self._set(c, a, I, "own_Evict")

    # ------------------------------------------------------------ checkers (the "testbench")
    def check_swmr(self, a: int) -> None:
        states = [self.st(c, a) for c in range(self.n)]
        excl = sum(s in (M, E) for s in states)
        shr = sum(s == S for s in states)
        if excl > 1 or (excl == 1 and shr > 0):
            raise CheckerError(f"SWMR violated on A{a}: states {states}")

    def tb_load(self, c: int, a: int) -> None:
        got = self.load(c, a)
        exp = self.golden.get(a, 0)
        if got != exp:
            raise CheckerError(f"Scoreboard: C{c} load A{a} got {got}, expected {exp} "
                               f"(states {[self.st(x, a) for x in range(self.n)]})")
        ver = self.val_version.get((a, got), 0)
        if ver < self.last_seen[c].get(a, 0):
            raise CheckerError(f"CoRR: C{c} saw older value of A{a} after a newer one")
        self.last_seen[c][a] = ver

    def tb_store(self, c: int, a: int, v: int) -> None:
        self.store(c, a, v)
        self.version[a] = self.version.get(a, 0) + 1
        self.val_version[(a, v)] = self.version[a]
        self.golden[a] = v
        self.last_seen[c][a] = self.version[a]

    def drain_and_compare(self) -> None:
        for c in range(self.n):
            for a in list(self.state[c]):
                self.evict(c, a)
        for a, v in self.golden.items():
            if self.mem.get(a, 0) != v:
                raise CheckerError(f"End-of-test: memory A{a} = {self.mem.get(a, 0)}, expected {v}")


def run(ncores: int, ops: int, addrs: int, seed: int, msi: bool, bug: str | None, trace: int) -> System:
    rng = random.Random(seed)
    sys_ = System(ncores, msi=msi, bug=bug, trace=trace)
    next_val = 1
    for step in range(ops):
        c = rng.randrange(ncores)
        a = rng.randrange(addrs)  # small pool -> lots of sharing and races
        r = rng.random()
        if r < 0.45:
            sys_.tb_load(c, a)
        elif r < 0.85:
            sys_.tb_store(c, a, next_val)
            next_val += 1
        else:
            sys_.evict(c, a)
        sys_.check_swmr(a)
    sys_.drain_and_compare()
    return sys_


def print_coverage(sys_: System, msi: bool) -> None:
    states = [M, S, I] if msi else [M, E, S, I]
    events = ["own_Load_hit", "own_Load_miss", "own_Store_hit", "own_Store_upgrade",
              "own_Store_miss", "own_Evict", "snoop_BusRd", "snoop_BusRdX"]
    legal = {
        (I, "own_Load_miss"), (I, "own_Store_miss"),
        (S, "own_Load_hit"), (S, "own_Store_upgrade"), (S, "own_Evict"), (S, "snoop_BusRd"), (S, "snoop_BusRdX"),
        (E, "own_Load_hit"), (E, "own_Store_hit"), (E, "own_Evict"), (E, "snoop_BusRd"), (E, "snoop_BusRdX"),
        (M, "own_Load_hit"), (M, "own_Store_hit"), (M, "own_Evict"), (M, "snoop_BusRd"), (M, "snoop_BusRdX"),
    }
    w = 18
    print("\nCoverage: (current state x event) hit counts   '.' = not a legal cell")
    print(" " * 6 + "".join(e[:w - 1].ljust(w) for e in events))
    hit = tot = 0
    for s in states:
        row = []
        for e in events:
            if (s, e) in legal:
                tot += 1
                n = sys_.cov.get((s, e), 0)
                hit += n > 0
                row.append((str(n) if n else "HOLE").ljust(w))
            else:
                row.append(".".ljust(w))
        print(f"  {s}   " + "".join(row))
    print(f"\n  {hit}/{tot} legal cells covered")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cores", type=int, default=4)
    ap.add_argument("--ops", type=int, default=20000)
    ap.add_argument("--addrs", type=int, default=4, help="hot address pool size (keep small!)")
    ap.add_argument("--seeds", type=int, default=20)
    ap.add_argument("--msi", action="store_true", help="MSI instead of MESI")
    ap.add_argument("--bug", choices=BUGS)
    ap.add_argument("--trace", type=int, default=0, help="print first N bus transactions of seed 0")
    args = ap.parse_args()

    print(f"MESI model: {args.cores} cores, {args.addrs} hot addresses, {args.ops} ops x {args.seeds} seeds"
          f"{' [MSI]' if args.msi else ''}{' [BUG: ' + args.bug + ']' if args.bug else ''}")
    total_cov: Counter = Counter()
    last = None
    for seed in range(args.seeds):
        try:
            last = run(args.cores, args.ops, args.addrs, seed, args.msi, args.bug, args.trace if seed == 0 else 0)
            total_cov.update(last.cov)
        except CheckerError as e:
            print(f"  seed {seed}: FAIL -> {e}")
            if args.bug:
                print("  The injected bug was caught. Re-run without --bug to see a clean pass.")
            raise SystemExit(1)
    assert last is not None
    last.cov = total_cov
    print(f"  all {args.seeds} seeds PASS (SWMR, scoreboard, CoRR, end-of-test drain)")
    print_coverage(last, args.msi)


if __name__ == "__main__":
    main()
