# Lesson 14 · Advanced caches

6 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Three ways to cut AMAT](#l14-01-three-ways-to-cut-amat)
2. [Fast hits: pipelining and way prediction](#l14-02-fast-hits-pipelining-and-way-prediction)
3. [Virtually indexed, physically tagged](#l14-03-virtually-indexed-physically-tagged)
4. [Reducing miss rate](#l14-04-reducing-miss-rate)
5. [Non-blocking caches and MSHRs](#l14-05-non-blocking-caches-and-mshrs)
6. [Multi-level caches](#l14-06-multi-level-caches)

---

## L14-01 Three ways to cut AMAT

*Improving cache performance overview*

> Lower hit time, lower miss rate, or lower miss penalty. Every advanced cache trick attacks one of them.

**Concepts**

- Many changes trade one term for another (more associativity → lower miss rate, higher hit time).
- Evaluate with AMAT, then with real IPC (overlap matters).

| Target | Techniques |
| --- | --- |
| Hit time | small/simple L1, way prediction, pipelined caches, VIPT |
| Miss rate | bigger, more assoc., better replacement, prefetching, compiler layout |
| Miss penalty | multi-level caches, non-blocking caches, critical word first, write buffers |

**Verification lens**

- Each technique adds a mechanism with its own corner cases (prediction miss, prefetch race, MSHR merge). Track coverage per mechanism, not just per cache.

**Interview**

<details><summary>Which technique attacks miss penalty but adds the most verification risk?</summary>

Non-blocking caches: many outstanding misses, merges, out-of-order fills and hits under misses multiply the races.

</details>

---

## L14-02 Fast hits: pipelining and way prediction

*Pipelined caches · way prediction*

> Pipeline the lookup to keep throughput at one access per cycle; predict the way to read only one line.

**Concepts**

- **Pipelined cache**: index/read, tag compare, data select over 2–4 stages; latency stays, throughput rises.
- **Way prediction**: guess which way hits (e.g. MRU); read only that way, like a direct-mapped hit. Wrong guess → check others next cycle.
- Saves energy and hit time when prediction is good.

**Numbers & formulas:** `way-pred miss → +1 cycle`

**Verification lens**

- A wrong way prediction must never deliver data. Assert data is used only after the full tag check confirms the predicted way, or the load is replayed.

**Bugs that ship**

- Load wakes dependents on predicted-way data that later fails the tag check, without replay

**Interview**

<details><summary>What makes a pipelined cache harder to verify?</summary>

Back-to-back accesses to the same set: a write in stage 3 and a read in stage 1 to the same line need forwarding or a stall.

</details>

---

## L14-03 Virtually indexed, physically tagged

*VIPT caches · aliasing*

> Index the cache with page-offset bits while the TLB translates in parallel, then compare physical tags.

**Concepts**

- PIPT: translate, then look up: slow. VIVT: fast, but aliasing and flushes on context switch.
- **VIPT**: index from untranslated bits, tag from the PA: fast and no aliasing **if index + offset bits ≤ page offset bits**.
- Condition: **cache size / ways ≤ page size**. 32 KB / 8 ways = 4 KB ✓.
- Bigger L1 needs more ways, page colouring, or alias detection.

**Numbers & formulas:** `size/ways ≤ page size`

**Worked**

| Problem | Answer |
| --- | --- |
| 32 KB, 8-way, 4 KB page | 4 KB ≤ 4 KB, no aliasing |
| 64 KB, 8-way, 4 KB page | 8 KB > 4 KB, aliasing possible |

**Verification lens**

- If a design allows aliasing, test synonyms: two VAs to one PA with different index bits, writes through one and reads through the other.

**Interview**

<details><summary>Why does Apple’s 128 KB L1 with 16 KB pages work as VIPT?</summary>

128 KB / 8 ways = 16 KB = page size, so index bits stay within the page offset.

</details>

---

## L14-04 Reducing miss rate

*Reducing miss rate · 3Cs · larger blocks · prefetching*

> Misses are compulsory, capacity or conflict (plus coherence). Different fixes hit different Cs.

**Concepts**

- Larger blocks cut compulsory misses but can raise conflicts and pollution.
- **Prefetching**: stride and stream detectors fetch ahead. Risks: useless prefetches pollute and waste bandwidth; late ones don’t help.
- Compiler: loop interchange and blocking (tiling) improve locality.

| Miss type | Cause | Fix |
| --- | --- | --- |
| Compulsory | first touch | larger blocks, prefetch |
| Capacity | working set > cache | bigger cache |
| Conflict | too many blocks per set | more ways, better replacement |
| Coherence | another core invalidated | less sharing |

**Verification lens**

- Prefetches are requests nobody waits for: verify they can be dropped safely, never fault architecturally, respect page boundaries and memory types, and race correctly with demand misses to the same line.

**Bugs that ship**

- Prefetch crosses into an unmapped or device page
- Demand miss and prefetch to the same line allocate twice

**Interview**

<details><summary>How would you classify a miss as capacity vs conflict in a simulator?</summary>

Run the same trace on a fully associative cache of the same size: misses there are capacity (or compulsory); extra misses in the real cache are conflict.

</details>

---

## L14-05 Non-blocking caches and MSHRs

*Non-blocking caches · MLP · MSHRs*

> Keep serving hits and new misses while earlier misses are outstanding; MSHRs track each pending line.

**Concepts**

- **Hit under miss**, then **miss under miss**: memory-level parallelism (MLP).
- **MSHR** per outstanding line: address, waiting requests (which bytes, which destination).
- A second miss to the same line **merges** into the existing MSHR (secondary miss).
- MSHRs full → stall new misses.

**Numbers & formulas:** `MLP ≤ #MSHRs`

**Verification lens**

- Cover: secondary miss merge (load and store), MSHR full, fill returning while a new miss to the same line arrives, eviction of a line with a pending MSHR to it, out-of-order fills.

**Bugs that ship**

- Secondary store merges into a read MSHR and its bytes are lost on fill
- MSHR freed before all waiting requests are served

**Interview**

<details><summary>How many MSHRs to sustain 10 GB/s at 100 ns with 64 B lines?</summary>

λ = 10e9/64 ≈ 156 M lines/s; N = λ × 100 ns ≈ 16 MSHRs.

</details>

---

## L14-06 Multi-level caches

*Multi-level caches · inclusion*

> A larger L2/L3 behind L1 turns most L1 misses into short trips instead of DRAM.

**Concepts**

- AMAT = HT₁ + MR₁ × (HT₂ + MR₂ × MP).
- **Local** miss rate = misses / accesses reaching that level. **Global** = misses / all CPU accesses = product of local rates.
- L2 local miss rates look high (L1 already took the easy hits); global rate is what matters.
- Inclusion policies: **inclusive** (L2 holds all of L1), **exclusive** (no overlap), **NINE** (neither). Inclusive LLC can act as a snoop filter.

**Numbers & formulas:** `global MR = Π local MR`

**Worked**

| Problem | Answer |
| --- | --- |
| HT₁ 2, MR₁ 10%, HT₂ 10, MR₂ 20%, MP 100 | AMAT = 2 + 0.1 × (10 + 20) = 5 |
| Global L2 miss rate | 0.1 × 0.2 = 2% |

**Verification lens**

- Inclusive caches need back-invalidation: evicting from L2 must invalidate L1 copies. Cover L2 eviction of a line that is dirty in L1 or has an L1 miss outstanding.

**Bugs that ship**

- L2 evicts a line without back-invalidating L1 (inclusion broken)
- Exclusive hierarchy loses a line when both levels evict at once

**Interview**

<details><summary>Why might an L2 with 50% local miss rate still be good?</summary>

If L1 misses only 5%, global L2 miss rate is 2.5%. L2 serves half of L1’s misses at a fraction of DRAM latency.

</details>
