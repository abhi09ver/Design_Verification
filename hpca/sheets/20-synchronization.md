# Lesson 20 · Synchronization

4 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Why we need atomic operations](#l20-01-why-we-need-atomic-operations)
2. [Atomic instructions](#l20-02-atomic-instructions)
3. [Efficient spin locks](#l20-03-efficient-spin-locks)
4. [Barriers](#l20-04-barriers)

---

## L20-01 Why we need atomic operations

*Why synchronisation · locks*

> Read-modify-write sequences from two threads interleave and lose updates; locks need hardware atomicity.

**Concepts**

- `count++` = load, add, store. Two threads can both load 5 and both store 6.
- A lock protects the critical section, but acquiring it is itself a read-modify-write.
- Ordinary loads and stores cannot build a lock efficiently; hardware provides atomic instructions.

**Verification lens**

- Lost-update tests: many cores increment one counter with atomics a known number of times; final value must equal the total. Simple, strong end-to-end check.

**Interview**

<details><summary>Why isn’t a lock built from plain loads and stores enough?</summary>

Between reading “free” and writing “taken”, another core can do the same. Algorithms like Peterson’s exist but need many accesses and strict memory ordering; atomics are simpler and faster.

</details>

---

## L20-02 Atomic instructions

*Atomic instructions · LL/SC*

> Test-and-set, swap, fetch-and-add, compare-and-swap, or load-linked / store-conditional.

**Concepts**

- Atomic RMW: the core holds the line in M and blocks snoops until done.
- LL sets a reservation (link) on the line; any invalidation or eviction clears it; SC fails if cleared.
- LL/SC suits RISC load/store pipelines (two separate instructions).

| Instruction | Does |
| --- | --- |
| Test-and-set | read old, write 1 |
| Swap (XCHG) | exchange register and memory |
| Fetch-and-add | read old, add |
| CAS | write new if memory == expected |
| LL / SC | SC succeeds only if no other write since LL |

**Numbers & formulas:** `LL/SC: reservation cleared on snoop`

**Verification lens**

- Cover LR/SC with: intervening snoop, eviction, interrupt, context switch, another store to the same line by the same core, and SC without LR. Check forward-progress guarantees from the ISA.

**Bugs that ship**

- SC succeeds after the reserved line was evicted
- Atomic split across two lines not atomic
- Snoop serviced in the middle of an RMW

**Interview**

<details><summary>How do you verify atomicity of fetch-and-add?</summary>

Many cores hammer one address with fetch-and-add; check the final sum and that the set of returned old values has no duplicates and no gaps.

</details>

---

## L20-03 Efficient spin locks

*Spin locks · test-and-test-and-set · backoff*

> Spin on a plain read (cached in S) and attempt the atomic only when the lock looks free.

**Concepts**

- Test-and-set in a loop: every attempt is a write, invalidating all other caches: huge traffic.
- **Test-and-test-and-set**: spin with loads (hits in S); on release, race with one atomic.
- **Backoff**: wait a random, growing time after failure.
- Queue locks (ticket, MCS) give fairness and spin on separate lines.

**Numbers & formulas:** `TTAS: traffic only on release`

**Verification lens**

- Lock-contention tests reveal livelock and starvation in coherence (a core never wins the line). Add a forward-progress watchdog per core.

**Interview**

<details><summary>Why is TTAS better than TAS on a coherent multicore?</summary>

Waiters spin on a shared copy of the line without bus traffic; only when the owner releases (one invalidation) do they try the atomic.

</details>

---

## L20-04 Barriers

*Barriers*

> All threads wait until everyone arrives; sense reversal makes the barrier reusable.

**Concepts**

- Centralised barrier: atomic increment of a counter; last arriver releases everyone.
- Problem: a fast thread re-entering the next barrier before others left the previous one.
- **Sense reversal**: each barrier instance flips a flag; threads wait for the flag to match their local sense.
- Tree barriers reduce contention for many cores.

**Verification lens**

- Barriers in real software rely on correct memory ordering (release on arrive, acquire on leave). Good system tests: barrier loops with data handed between phases, checked after each phase.

**Interview**

<details><summary>What bug does sense reversal fix?</summary>

A thread leaving barrier k could re-enter barrier k+1 and reset the counter while slow threads still spin on k, deadlocking them.

</details>
