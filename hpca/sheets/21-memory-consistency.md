# Lesson 21 · Memory consistency

4 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Why ordering across addresses matters](#l21-01-why-ordering-across-addresses-matters)
2. [Sequential consistency (SC)](#l21-02-sequential-consistency-sc)
3. [Relaxed models and fences](#l21-03-relaxed-models-and-fences)
4. [Data-race-free programs](#l21-04-data-race-free-programs)

---

## L21-01 Why ordering across addresses matters

*Why memory ordering matters*

> Coherence orders one address; programs communicate through several, so the order of different addresses matters too.

**Concepts**

- Producer: data = 42; flag = 1. Consumer: while(!flag); read data.
- If the hardware lets flag become visible before data, the consumer reads stale data.
- Store buffers, OoO loads, and non-FIFO interconnects can all reorder.
- The **memory consistency model** is the ISA rule saying which reorderings are allowed.

**Verification lens**

- Consistency bugs pass every single-core test. You need multi-core litmus tests and an axiomatic checker.

**Interview**

<details><summary>Name three microarchitectural features that can reorder memory operations.</summary>

Store buffers (store → load), out-of-order load execution (load → load), write-combining or non-FIFO interconnect (store → store).

</details>

---

## L21-02 Sequential consistency (SC)

*Sequential consistency*

> Result is as if all operations ran in some single order that respects each core’s program order.

**Concepts**

- Lamport’s definition: one global interleaving, program order kept per core.
- Easy to reason about, hard to make fast: forbids store buffers bypassing loads.
- Fast SC: execute speculatively, check, and replay if an observed value could violate SC (load queue snoops).

| Litmus (SB) | Core 0 | Core 1 | r1=r2=0? |
| --- | --- | --- | --- |
|  | x=1; r1=y | y=1; r2=x | SC: forbidden |

**Verification lens**

- Under SC, any execution must match one interleaving; an axiomatic checker builds the happens-before graph and searches for a cycle.

**Interview**

<details><summary>Can an OoO core implement SC?</summary>

Yes: loads execute early but are replayed if their line is invalidated before commit, and stores drain in order. The core speculates and checks.

</details>

---

## L21-03 Relaxed models and fences

*Relaxed consistency · fences*

> Models relax some orders for speed (TSO relaxes store→load; Arm/RISC-V relax most); fences restore order when needed.

**Concepts**

- **TSO**: each core has a FIFO store buffer; loads may pass older stores.
- **Weak**: loads and stores to different addresses reorder unless fenced or using acquire/release.
- Fences: MFENCE (x86), DMB (Arm), FENCE (RISC-V).

| Litmus | Outcome | SC | TSO (x86) | Weak (Arm, RVWMO) |
| --- | --- | --- | --- | --- |
| SB | r1=r2=0 | ✗ | ✓ | ✓ |
| MP | flag=1, data=0 | ✗ | ✗ | ✓ w/o fence |
| LB | r1=r2=1 | ✗ | ✗ | ✓ (allowed) |

**Numbers & formulas:** `TSO relaxes only W→R`

**Verification lens**

- Run herd/diy-generated litmus suites millions of times with random delays; compare observed outcomes with the model’s allowed set. Any forbidden outcome is a bug.

**Bugs that ship**

- Fence doesn’t wait for the post-commit store buffer
- Loads reorder under TSO because invalidations don’t replay them

**Interview**

<details><summary>Why is store buffering (SB) allowed on x86?</summary>

Each core’s store waits in its store buffer while its younger load reads the old value from the cache. A full fence between them drains the buffer and forbids it.

</details>

---

## L21-04 Data-race-free programs

*Data races · synchronisation and consistency*

> If all conflicting accesses are ordered by synchronisation, the program behaves as if SC on any relaxed model (SC for DRF).

**Concepts**

- Data race: two accesses to the same location, at least one write, not ordered by synchronisation.
- Locks, barriers and atomics with acquire/release semantics provide the ordering.
- Hardware must make synchronisation operations act as the right fences.

**Verification lens**

- Verify that every atomic and lock-related instruction has the ordering semantics the ISA specifies (acquire, release, full fence). These are small, crisp litmus tests.

**Interview**

<details><summary>What does acquire/release guarantee?</summary>

Release: all earlier accesses become visible before the release store. Acquire: no later access is performed before the acquire load. Together they order a lock handoff.

</details>
