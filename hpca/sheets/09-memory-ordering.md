# Lesson 09 · Memory ordering

5 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Memory dependences and store timing](#l09-01-memory-dependences-and-store-timing)
2. [The load-store queue](#l09-02-the-load-store-queue)
3. [When may a load go to memory?](#l09-03-when-may-a-load-go-to-memory)
4. [Cost of in-order memory](#l09-04-cost-of-in-order-memory)
5. [Walking an LSQ](#l09-05-walking-an-lsq)

---

## L09-01 Memory dependences and store timing

*Memory ordering intro · when does the write happen*

> Stores write memory only at commit; loads want data early. The LSQ bridges the gap.

**Concepts**

- Renaming and the ROB order **register** dependences; loads and stores can depend through memory with no shared register.
- Same address → must respect order. Different addresses → can reorder freely.
- A store writes memory **at commit**: undoing a memory write is nearly impossible.
- Loads shouldn’t wait for commit, so they need values from earlier uncommitted stores: the **load-store queue**.

**Numbers & formulas:** `store → memory at commit`

**Verification lens**

- Assert no store reaches the cache before it commits (except designs with explicit speculative store buffers). Cover a store followed by an exception and a mispredict: memory must be unchanged.

**Interview**

<details><summary>Why not let stores write the cache early and undo on mispredict?</summary>

Other cores and devices could already have seen the value, and keeping undo state for every byte is costly. Holding stores until commit is far simpler.

</details>

---

## L09-02 The load-store queue

*LSQ · store-to-load forwarding*

> An in-order queue of loads and stores with address, value and done bit; a load searches older stores for its address.

**Concepts**

- Entry: L/S bit, address, value, done. Allocated in program order, removed at commit.
- Load: search **older** stores for the same address; take the **youngest** match (store-to-load forwarding). No match → go to memory.
- Store: once address and data are known, find younger loads that already ran with the same address.
- Non-memory instructions need RS + ROB entry; loads/stores need ROB + LSQ entry.

**Numbers & formulas:** `forward from youngest older match`

**Verification lens**

- Byte-level model: expected load data = shadow memory overlaid with older uncommitted stores in age order. Sweep size × alignment × overlap.

**Bugs that ship**

- Forwarding from a younger store
- Partial overlap merges bytes from two stores in the wrong order

**Interview**

<details><summary>Where can a load get its value?</summary>

From an older store in the LSQ (forwarding) or from the cache/memory. Not from the ROB or a result broadcast, because stores don’t produce register results.

</details>

---

## L09-03 When may a load go to memory?

*Options for load timing · go anyway*

> In order is slow; waiting for all older store addresses is safe; going anyway and replaying on a match is fastest.

**Concepts**

- **Go anyway**: if no known older store matches, read memory immediately.
- When an older store later resolves its address, it checks younger completed loads; on a match the load and everything after it is redone.
- Most modern cores do this, plus a **memory dependence predictor** that makes frequently conflicting loads wait.

| Policy | Correct | Speed | Needs |
| --- | --- | --- | --- |
| Fully in order | yes | slowest | nothing |
| Wait for older store addresses | yes | medium | address search |
| Go anyway | with replay | fastest | violation detect + flush |

**Numbers & formulas:** `violation → replay load + younger`

**Verification lens**

- Address-aliasing stress: few distinct addresses, slow store address generation, fast loads. Coverage: violation detected, violation with dependents already woken, violation on the oldest load.

**Bugs that ship**

- Violation detected but a dependent already committed
- Replay of a load whose dependents are also replaying twice

**Interview**

<details><summary>What does a store do when its address resolves late?</summary>

Searches younger loads that already executed. If any read the same bytes, those loads (and all younger instructions) are flushed and re-executed.

</details>

---

## L09-04 Cost of in-order memory

*In-order load/store execution · mem ordering quiz*

> Keeping loads and stores in order is correct but can triple runtime when loads miss.

**Concepts**

- In-order: a load can’t start until every older load/store is done (a store is done once its address and data are known).
- Quiz with 40-cycle misses: in order, loads issue at cycles 1, 43, 85 and return at 41, 83, 125; total **126** cycles.
- Out of order the three misses overlap: about **44** cycles. Nearly 3× faster.
- Reordering pays only if you can recover from a load that read too early.

**Numbers & formulas:** `in order ≈ 3× slower here`

**Worked**

| Problem | Answer |
| --- | --- |
| 3 dependent load-store pairs, 40-cycle miss, in order | 126 cycles |
| Same, loads overlapped | ~44 cycles |

**Verification lens**

- Memory-level parallelism is a perf feature: check the number of concurrent misses reached in a stress test equals the design’s MSHR count.

**Interview**

<details><summary>Why does in-order memory hurt so much more with cache misses?</summary>

Each miss blocks every younger memory operation, so misses serialise. OoO overlaps them, dividing total latency by the number in flight.

</details>

---

## L09-05 Walking an LSQ

*LSQ example · LSQ, ROB & RS · quiz*

> Loads take the youngest older matching store’s value; stores reach the cache only at commit; an exception flushes uncommitted stores.

**Concepts**

- Loads with no matching older store read the cache (42, 1234, 1…).
- A load matching the second store gets **−17**, not the older value.
- At commit, each store writes the cache in order.
- An exception at the commit pointer flushes every younger entry; the cache keeps only committed values.

**Check your notes**

- In the LSQ example the first store wrote 25, so the cache gets **25** (the notes say 28).

**Verification lens**

- This walk is exactly a scoreboard: replay it in your LSU model, then compare each load’s value and the final cache image with the DUT.

**Interview**

<details><summary>Three older stores to address A are in the LSQ; one has an unknown address. A load to A executes. What value does it get?</summary>

Under “go anyway”, the youngest older store with known matching address forwards. If the unknown one later resolves to A and is younger than that store, the load replays.

</details>
