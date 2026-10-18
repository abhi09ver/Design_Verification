# Lesson 12 · Cache review

10 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Locality](#l12-01-locality)
2. [Cache performance: AMAT](#l12-02-cache-performance-amat)
3. [Block (line) size](#l12-03-block-line-size)
4. [Offset, index, tag and valid](#l12-04-offset-index-tag-and-valid)
5. [Direct-mapped caches](#l12-05-direct-mapped-caches)
6. [Set-associative and fully associative](#l12-06-set-associative-and-fully-associative)
7. [Replacement: LRU and approximations](#l12-07-replacement-lru-and-approximations)
8. [Write policies](#l12-08-write-policies)
9. [Write-back and the dirty bit](#l12-09-write-back-and-the-dirty-bit)
10. [Putting a cache access together](#l12-10-putting-a-cache-access-together)

---

## L12-01 Locality

*Locality principle · temporal & spatial quizzes*

> What happens soon is likely close to what just happened: the same address again (temporal) or nearby addresses (spatial).

**Concepts**

- **Temporal**: accessed X → likely to access X again soon.
- **Spatial**: accessed X → likely to access addresses near X soon.
- Quiz loop `sum += arr[j]`: **j** and **sum** have temporal locality; **arr** elements have spatial but not temporal.
- j and sum are usually next to each other on the stack, so they may give some spatial locality too.
- Not everything has locality (“it was New Year’s Eve yesterday”).

| Variable | Temporal | Spatial |
| --- | --- | --- |
| j | yes | weak (stack neighbour) |
| sum | yes | weak (stack neighbour) |
| arr[j] | no | yes |

**Verification lens**

- Random tests have poor locality and miss bugs that need lines to stay resident (hit-under-miss, replacement corners). Mix in loop-like address streams and a small hot set.

**Interview**

<details><summary>Which access pattern kills a cache?</summary>

A stream with no reuse over a footprint larger than the cache (or conflicting into one set). Every access misses, and with write-back each eviction may also write.

</details>

---

## L12-02 Cache performance: AMAT

*Cache quiz · lookups · AMAT · hit/miss quizzes*

> AMAT = hit time + miss rate × miss penalty. Design is a balance of small-and-fast against big-and-smart.

**Concepts**

- Cache = small fast memory near the core; a miss copies the block from slower memory.
- Low hit time → small, simple. Low miss rate → large, smarter (slightly slower).
- Miss time = hit time + miss penalty.
- Well-designed: hit time ≪ miss time; hit rate ≫ miss rate, close to 1.
- L1 sizes in real cores: **16–64 KB**, about **90%** hit rate, **1–3 cycles** (4–5 in today’s high-frequency cores).

**Numbers & formulas:** `AMAT = HT + MR × MP` · `= (1−MR)·HT + MR·(HT+MP)`

**Worked**

| Problem | Answer |
| --- | --- |
| HT 2, MR 5%, MP 100 | AMAT = 7 cycles |

**Verification lens**

- Latency counters (hit, miss, fill) let a perf test check AMAT against the model. A cache that is functionally correct but always misses on one path passes co-sim.

**Interview**

<details><summary>HT 1 ns, MR 10%, MP 50 ns. Halve MR or halve MP?</summary>

AMAT = 1 + 0.1 × 50 = 6 ns. Halving either gives 3.5 ns. Then compare cost: a bigger cache usually raises HT too.

</details>

---

## L12-03 Block (line) size

*Cache organisation · block size · block size quiz*

> Lines must cover the largest single access and capture spatial locality, but not waste the small cache: 32–128 B, power of two.

**Concepts**

- 1-byte blocks: a 4-byte word would need 4 lookups. Too small.
- Bigger blocks bring neighbours on a miss (spatial locality).
- 1 KB blocks in a 32 KB cache: only 32 lines, mostly unused data. Too big.
- Typical: **32–128 B**; must be a **power of 2** so the offset is just low bits (48 B would need a divide).
- Quiz: 32 KB cache, 64 B lines, scalars with no spatial locality: up to **512** variables fit, one per line.

**Numbers & formulas:** `line = 2ᵇ bytes` · `offset bits = b`

**Worked**

| Problem | Answer |
| --- | --- |
| 32 KB / 64 B | 512 lines |
| 2 KB cache: 1, 32, 48, 64, 1K B lines | only 32 and 64 are good |

**Verification lens**

- Line size is a key parameter for reuse: parameterise the testbench and run at least two sizes so offset/index slicing bugs show up.

**Interview**

<details><summary>Why must the block size be a power of two?</summary>

Then block number and offset are simple bit fields of the address; any other size needs a divider on every access.

</details>

---

## L12-04 Offset, index, tag and valid

*Block start address · offset & number · tags · valid bit*

> Blocks are aligned; low bits are the offset, middle bits pick the set, high bits are the tag; a valid bit marks real data.

**Concepts**

- Blocks start at aligned addresses, so each byte lives in exactly one block.
- Offset = low log₂(line) bits. Block number = the rest.
- Tag contains block-number bits only (never offset bits); fewer than the whole block number when index bits pick the set.
- **Valid bit**: at reset all 0, so garbage tags can’t produce false hits. Set on fill.
- Quiz: 0x3F1F with 32 B lines → offset 5 bits; with 8 lines, index = bits [7:5].

**Numbers & formulas:** `offset = log₂(line)` · `index = log₂(sets)` · `tag = addr − index − offset`

**Verification lens**

- Off-by-one in bit slicing is common when parameters change. Assert the reconstructed address {tag, index, offset} equals the request address on every fill and writeback.

**Bugs that ship**

- Writeback address rebuilt from the wrong tag slice
- Valid not cleared on invalidate, giving a false hit

**Interview**

<details><summary>48-bit PA, 32 KB, 8-way, 64 B lines. Bit fields?</summary>

Sets = 32K/(8×64) = 64 → index 6 bits [11:6]; offset 6 bits [5:0]; tag 36 bits [47:12].

</details>

---

## L12-05 Direct-mapped caches

*Types of caches · direct mapped · quizzes*

> Each block has exactly one possible line: fast, cheap, low energy, but conflicts raise the miss rate.

**Concepts**

- Upsides: one tag compare, fast hit, cheap, energy-efficient.
- Downside: **conflicts**. A and B mapping to the same line, accessed alternately, miss every time.
- Quiz: 16 KB, 256 B blocks → 64 lines, index = bits [13:8]. Conflicts with 0x12345678: **0x11115678** and **0x12341666**; 0x12345677 is the same block.
- Quiz: 8 lines × 32 B: 3F1F → line 0, 3F2F → line 1, 3F2E hits line 1, 3E1F evicts line 0.

**Worked**

| Problem | Answer |
| --- | --- |
| Conflicts with 0x12345678 | 0x11115678, 0x12341666 |
| 3F1F, 3F2F, 3F2E, 3E1F | miss, miss, hit, miss (evict) |

**Verification lens**

- Conflict misses are the easiest way to force evictions: generate addresses that differ only in tag bits.

**Interview**

<details><summary>Why does 0x12345677 not conflict with 0x12345678?</summary>

With 256 B blocks they are in the same block (only the offset differs), so it is a hit, not a conflict.

</details>

---

## L12-06 Set-associative and fully associative

*Set-associative · fully associative · quiz*

> N-way: a block can sit in any of N lines of its set. Direct-mapped is 1-way; fully associative is one set.

**Concepts**

- Cache split into **sets**; index bits pick the set; all N tags in the set are compared.
- Fully associative: no index bits, compare every tag.
- Find offset bits first, then the next bits are the index.
- Quiz (2-way, 4 sets, 32 B): f303 → set 0, f503 → set 0 (other way), f563 → set 3, ef63 → set 3 (other way).

| Type | Ways | Index bits | Compares |
| --- | --- | --- | --- |
| Direct mapped | 1 | log₂(lines) | 1 |
| N-way | N | log₂(lines/N) | N |
| Fully assoc. | lines | 0 | all |

**Numbers & formulas:** `sets = lines / ways` · `index bits = log₂(sets)`

**Verification lens**

- Multi-hit is illegal: assert at most one way matches per lookup. A double hit means a duplicate fill (two MSHRs for one line).

**Bugs that ship**

- Same line filled into two ways after racing misses → multi-hit

**Interview**

<details><summary>What causes a multi-hit and how do you catch it?</summary>

Two misses to the same line both allocate (missing MSHR merge), or a fill doesn’t check an in-flight eviction. Catch with an assertion on one-hot (or zero) way match.

</details>

---

## L12-07 Replacement: LRU and approximations

*Cache replacement · implementing LRU · LRU quiz*

> Evict the least recently used line. Exact LRU needs counters per line; approximations save area and energy.

**Concepts**

- Exact LRU with counters: N counters of log₂N bits per set, all distinct.
- On access to a line with counter c: lines above c decrement, the accessed line becomes N−1.
- Victim = the line with counter 0.
- Example (4-way): place A,B,C,D → 0123; place E replaces A → 3012; access B → 2301; access D → 1203; access B → 1302.
- Costly for 32-way (32 × 5-bit counters per set) and updates on every hit.
- **NMRU**: remember only the most recent; evict a random other line. Also PLRU (tree bits).

**Numbers & formulas:** `LRU bits/set = N·log₂N` · `NMRU = log₂N bits/set`

**Verification lens**

- Invariant: counters in a set are always a permutation of 0..N−1. One assertion catches nearly every update bug. For PLRU, compare with a reference model.

**Bugs that ship**

- Two hits in one cycle (two ports) update counters inconsistently
- Fill doesn’t update LRU, so the new line is evicted next

**Interview**

<details><summary>8-way with exact LRU: bits per set?</summary>

8 × 3 = 24 bits (counter scheme). The minimum possible is ceil(log₂ 8!) = 16 bits; tree PLRU uses 7.

</details>

---

## L12-08 Write policies

*Write policy*

> Allocate on write miss or not; write through to memory or write back on eviction. Write-back goes with write-allocate.

**Concepts**

- Most caches are write-allocate: reads and writes to a block are correlated.
- Write-through floods memory with writes; write-back is the usual choice.
- Write-back + write-allocate: after a write miss, later writes hit the cache.

| Choice | Option A | Option B |
| --- | --- | --- |
| Write miss | allocate (bring block in) | no-allocate |
| Write hit | write-through (memory too) | write-back (on eviction) |

**Verification lens**

- Write-allocate on a partial write needs a merge: bring the line, then apply byte enables. Cover every byte-enable pattern on a missing line.

**Bugs that ship**

- Partial write on a miss: fill data overwrites the bytes just written

**Interview**

<details><summary>Why pair write-back with write-allocate?</summary>

Write-back saves memory traffic only if later writes hit the cache; without allocation, every write to that block would miss and go to memory anyway.

</details>

---

## L12-09 Write-back and the dirty bit

*Write-back caches · example · quiz*

> A dirty bit marks lines modified since fill; only dirty lines are written back when evicted.

**Concepts**

- Without a dirty bit, every eviction would write back, wasting bandwidth on read-only data.
- Write hit: update the cache, set dirty (just set it, faster than checking).
- Miss to a set whose victim is dirty: write the victim back, then fill.
- Example: wr A, rd A, rd B, rd C, wr C, rd E (E maps to A’s line) → A written back before E fills.
- Quiz, one DM entry, start V=0 D=1 tag A: rd A, rd B, wr B, rd C, rd D, wr D → **4 misses, 1 writeback**, ends V=1 D=1 tag D.

**Numbers & formulas:** `evict dirty → writeback`

**Worked**

| Problem | Answer |
| --- | --- |
| rd A, rd B, wr B, rd C, rd D, wr D | 4 misses · 1 writeback |

**Verification lens**

- Ordering: the writeback of a victim and the fill of the new line to the same set must not race with a new request to the victim’s address. Cover a hit to the victim while its writeback is in flight.

**Bugs that ship**

- Victim writeback issued after a newer read of the same address went to memory, returning stale data
- Dirty bit not set on a write that merges into an in-flight fill

**Interview**

<details><summary>Initial state had D = 1 but V = 0. Is a writeback needed on the first miss?</summary>

No. An invalid line is never written back, whatever its dirty bit. Assert writeback only when V && D.

</details>

---

## L12-10 Putting a cache access together

*Cache summary · summary quiz · outro*

> Every access: index → compare tags in the set → hit: read/write with offset; miss: pick LRU victim, write back if dirty, fill, update LRU.

**Concepts**

- Per line metadata: valid, dirty, tag, replacement bits. That overhead is extra storage beyond the data.
- Example: 32 KB, 8-way, 64 B, 48-bit PA: tag 36 + V + D + 3 LRU = 41 bits per 512-bit line (~8%).
- Summary quiz split (32-bit address): tag [31:7], index [6:5], offset [4:0].
- All steps happen together on each access; misses also set LRU and supply data to the core.

**Numbers & formulas:** `overhead/line = tag + V + D + repl`

**Verification lens**

- The full flow is the checker’s model: a cache scoreboard tracks per-line state (V, D, tag, LRU) and a shadow memory for data. Compare on every response and every writeback.

**Interview**

<details><summary>Name the cache verification checks you would write first.</summary>

Data integrity (shadow memory), one-hot way match, writeback only if valid and dirty, LRU permutation invariant, and no lost requests (every request gets exactly one response).

</details>
