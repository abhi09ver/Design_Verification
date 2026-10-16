#!/usr/bin/env python3
"""
litmus.py - exhaustive litmus-test explorer for SC and TSO.

Enumerates EVERY interleaving of a small multi-threaded program under two
operational models and prints which final outcomes each model allows:

  SC  : one shared memory, each thread executes in program order, one op at a time.
  TSO : like SC, but each thread has a FIFO store buffer.
        - a store goes into the thread's own store buffer
        - the buffer drains to memory in FIFO order at any time
        - a load first checks the thread's OWN buffer (forwarding), else reads memory
        - FENCE (MFENCE / locked RMW) waits until the thread's buffer is empty

This is exactly the x86-TSO model from the Primer (Ch. 4). Weak models (Arm, RISC-V,
Power) allow even more outcomes; use herd7 / the official model tools for those.

Run:
    python3 litmus.py            # all built-in tests
    python3 litmus.py SB MP      # selected tests
"""
from __future__ import annotations

import sys
from functools import lru_cache

# Instruction encoding: ("st", var, value) | ("ld", reg, var) | ("fence",)
TESTS: dict[str, dict] = {
    "SB": {
        "desc": "Store buffering (Dekker). Can both loads miss the other core's store?",
        "threads": [[("st", "x", 1), ("ld", "r1", "y")],
                    [("st", "y", 1), ("ld", "r2", "x")]],
        "interesting": {"r1": 0, "r2": 0},
    },
    "SB+fences": {
        "desc": "SB with MFENCE between store and load.",
        "threads": [[("st", "x", 1), ("fence",), ("ld", "r1", "y")],
                    [("st", "y", 1), ("fence",), ("ld", "r2", "x")]],
        "interesting": {"r1": 0, "r2": 0},
    },
    "MP": {
        "desc": "Message passing. Flag seen but data not?",
        "threads": [[("st", "data", 1), ("st", "flag", 1)],
                    [("ld", "r1", "flag"), ("ld", "r2", "data")]],
        "interesting": {"r1": 1, "r2": 0},
    },
    "LB": {
        "desc": "Load buffering. Can each load see the other thread's later store?",
        "threads": [[("ld", "r1", "x"), ("st", "y", 1)],
                    [("ld", "r2", "y"), ("st", "x", 1)]],
        "interesting": {"r1": 1, "r2": 1},
    },
    "IRIW": {
        "desc": "Independent reads of independent writes. Do readers disagree on order?",
        "threads": [[("st", "x", 1)],
                    [("st", "y", 1)],
                    [("ld", "r1", "x"), ("ld", "r2", "y")],
                    [("ld", "r3", "y"), ("ld", "r4", "x")]],
        "interesting": {"r1": 1, "r2": 0, "r3": 1, "r4": 0},
    },
    "CoRR": {
        "desc": "Read-read coherence. New value then old value on the same address?",
        "threads": [[("st", "x", 1)],
                    [("ld", "r1", "x"), ("ld", "r2", "x")]],
        "interesting": {"r1": 1, "r2": 0},
    },
    "SB+fwd": {
        "desc": "Own-store forwarding: thread reads its own buffered store, then the other variable.",
        "threads": [[("st", "x", 1), ("ld", "r1", "x"), ("ld", "r2", "y")],
                    [("st", "y", 1), ("ld", "r3", "y"), ("ld", "r4", "x")]],
        "interesting": {"r1": 1, "r2": 0, "r3": 1, "r4": 0},
    },
}


def explore(threads: list[list[tuple]], tso: bool) -> set[tuple]:
    """Return the set of final register assignments reachable under SC or TSO."""
    nthr = len(threads)
    vars_ = sorted({ins[1] for t in threads for ins in t if ins[0] == "st"} |
                   {ins[2] for t in threads for ins in t if ins[0] == "ld"})
    results: set[tuple] = set()

    # state: (pcs, mem(tuple), sbufs(tuple of tuples), regs(tuple of (name,val)))
    @lru_cache(maxsize=None)
    def step(pcs: tuple, mem: tuple, sbufs: tuple, regs: tuple) -> None:
        memd = dict(zip(vars_, mem))
        done = all(pcs[t] == len(threads[t]) for t in range(nthr)) and all(len(b) == 0 for b in sbufs)
        if done:
            results.add(tuple(sorted(regs)))
            return
        for t in range(nthr):
            # option A: drain oldest store-buffer entry (TSO only)
            if tso and sbufs[t]:
                (var, val), rest = sbufs[t][0], sbufs[t][1:]
                m2 = dict(memd); m2[var] = val
                sb2 = sbufs[:t] + (rest,) + sbufs[t + 1:]
                step(pcs, tuple(m2[v] for v in vars_), sb2, regs)
            # option B: execute next instruction
            if pcs[t] == len(threads[t]):
                continue
            ins = threads[t][pcs[t]]
            pcs2 = pcs[:t] + (pcs[t] + 1,) + pcs[t + 1:]
            if ins[0] == "st":
                _, var, val = ins
                if tso:
                    sb2 = sbufs[:t] + (sbufs[t] + ((var, val),),) + sbufs[t + 1:]
                    step(pcs2, mem, sb2, regs)
                else:
                    m2 = dict(memd); m2[var] = val
                    step(pcs2, tuple(m2[v] for v in vars_), sbufs, regs)
            elif ins[0] == "ld":
                _, reg, var = ins
                val = memd[var]
                if tso:
                    for (bv, bval) in reversed(sbufs[t]):  # youngest matching store wins
                        if bv == var:
                            val = bval
                            break
                step(pcs2, mem, sbufs, regs + ((reg, val),))
            elif ins[0] == "fence":
                if not tso or not sbufs[t]:
                    step(pcs2, mem, sbufs, regs)
                # else: blocked until buffer drains (option A above)

    step(tuple(0 for _ in threads), tuple(0 for _ in vars_), tuple(() for _ in threads), ())
    return results


def fmt(outcome: tuple) -> str:
    return " ".join(f"{r}={v}" for r, v in outcome)


def main(names: list[str]) -> None:
    names = names or list(TESTS)
    print(f"{'test':<11}{'interesting outcome':<26}{'SC':<10}{'TSO (x86)':<10}")
    print("-" * 57)
    for name in names:
        t = TESTS[name]
        sc = explore(t["threads"], tso=False)
        tso = explore(t["threads"], tso=True)
        want = tuple(sorted(t["interesting"].items()))
        allowed = lambda s: "allowed" if want in s else "forbidden"  # noqa: E731
        print(f"{name:<11}{fmt(want):<26}{allowed(sc):<10}{allowed(tso):<10}")
        assert sc <= tso, "every SC outcome must also be a TSO outcome"
    print("\nDetails (all reachable outcomes):")
    for name in names:
        t = TESTS[name]
        print(f"\n{name}: {t['desc']}")
        sc = explore(t["threads"], tso=False)
        tso = explore(t["threads"], tso=True)
        for o in sorted(tso):
            print(f"   {fmt(o):<28} SC:{'yes' if o in sc else 'NO ':<4} TSO:yes")


if __name__ == "__main__":
    main(sys.argv[1:])
