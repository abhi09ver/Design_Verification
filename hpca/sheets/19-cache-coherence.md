# Lesson 19 · Cache coherence

8 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [The coherence problem](#l19-01-the-coherence-problem)
2. [Protocol choices](#l19-02-protocol-choices)
3. [MSI](#l19-03-msi)
4. [MESI: the Exclusive state](#l19-04-mesi-the-exclusive-state)
5. [Owned state (MOSI / MOESI)](#l19-05-owned-state-mosi--moesi)
6. [Directory protocols](#l19-06-directory-protocols)
7. [Coherence misses and false sharing](#l19-07-coherence-misses-and-false-sharing)
8. [Transient states and races](#l19-08-transient-states-and-races)

---

## L19-01 The coherence problem

*The coherence problem · definition*

> Private caches can hold different values for one address; coherence makes them behave like one memory per location.

**Concepts**

- Core 0 writes A in its write-back cache; core 1 still reads the old A from its cache or memory.
- Coherence rules (per address): a read returns the latest write; writes are seen by all in the same order (write serialisation).
- Invariant form: **SWMR** (single writer or multiple readers per epoch) + **data-value** (each epoch starts with the last write’s value).
- Coherence is about one address; ordering across addresses is consistency (Lesson 21).

**Numbers & formulas:** `SWMR + data-value invariant`

**Verification lens**

- A global SWMR checker that sees every cache’s state each cycle catches most protocol bugs early, before data mismatches appear.

**Interview**

<details><summary>Coherence vs consistency?</summary>

Coherence: all cores agree on the order of writes to one address. Consistency: the allowed orders of accesses to different addresses.

</details>

---

## L19-02 Protocol choices

*Write-update vs write-invalidate · snooping vs directory*

> On a write, update other copies or invalidate them; find the copies by broadcasting (snooping) or by asking a directory.

**Concepts**

- Almost all real designs use **invalidate**: repeated writes by one core cost nothing extra.
- Snooping needs an ordered broadcast medium (bus or ordered ring).
- Directory: home node records the sharers per line.

| Choice | Option | Trade-off |
| --- | --- | --- |
| On write | invalidate | one message; next reader misses |
|  | update | every write broadcasts data |
| Finding copies | snooping (bus) | simple, broadcast-limited (~8–16 cores) |
|  | directory | point-to-point, scales, more latency and state |

**Verification lens**

- Snooping relies on a global order point; directories rely on the home node serialising requests. Your checker must know where the serialisation point is to judge races.

**Interview**

<details><summary>Why does write-invalidate win in practice?</summary>

A core that writes the same line many times invalidates once and then hits locally; update would send data on every write even if nobody reads it.

</details>

---

## L19-03 MSI

*MSI protocol*

> Modified (only dirty copy), Shared (clean, maybe others), Invalid. Writes need M, which invalidates every other copy.

**Concepts**

- Read miss: GetS (BusRd). Write miss: GetM (BusRdX). Write hit in S: Upgrade.
- A dirty owner supplies the data and writes back (or forwards).

| State | Read | Write | Snoop read | Snoop write/RdX |
| --- | --- | --- | --- | --- |
| M | hit | hit | supply data → S | supply data → I |
| S | hit | upgrade → M | stay S | → I |
| I | GetS → S | GetM → M | — | — |

**Verification lens**

- Cover every cell of the (state × event) table, including illegal ones as assertions. Each cell is one coverage bin; transient states add many more.

**Interview**

<details><summary>Core in S writes. What happens?</summary>

Sends an upgrade/invalidate; all other S copies go to I; when acknowledged, the line becomes M and the write completes.

</details>

---

## L19-04 MESI: the Exclusive state

*MESI · exclusive state*

> E = clean and the only copy. A later write upgrades silently, saving the bus transaction MSI would need.

**Concepts**

- Read miss with no other sharers → **E** instead of S.
- Write in E → M with no message (silent upgrade).
- Common pattern: read then modify private data (stack, heap).
- Snoop read in E → S (no data needed from E in some designs, since memory is clean).

**Numbers & formulas:** `E → M silent`

**Verification lens**

- Silent transitions are invisible to the interconnect, so the directory may think the line is clean. Verify the directory treats an E owner as a possible M (must forward or ask).

**Bugs that ship**

- Directory supplies stale memory data for a line silently upgraded E→M

**Interview**

<details><summary>Why does a directory have to forward requests to an E owner?</summary>

The owner may have silently written the line (E→M). Memory’s copy might be stale, so the owner must supply or confirm.

</details>

---

## L19-05 Owned state (MOSI / MOESI)

*MOSI · MOESI · owned state*

> O = dirty but shared: one cache owns the dirty data and supplies it, so memory need not be updated on every read share.

**Concepts**

- M with a snoop read → **O** (keeps dirty data, supplies readers) instead of writing back to memory.
- Owner must write back on eviction.
- Saves memory bandwidth for producer–consumer sharing.
- MESIF (Intel) adds F: one clean sharer designated to forward.

**Numbers & formulas:** `O: dirty + shared, owner responds`

**Verification lens**

- Ownership transfer is a race hotspot: owner evicting (writeback in flight) while another request arrives. The home must get data from exactly one place.

**Bugs that ship**

- Owner’s writeback and a forwarded request both supply data; one is stale

**Interview**

<details><summary>What does O save over MESI?</summary>

On M + remote read, MESI writes the dirty line back to memory; MOESI keeps it in O and supplies readers from cache, avoiding the memory write.

</details>

---

## L19-06 Directory protocols

*Directory-based coherence*

> Each line has a home node with a directory entry (state + sharers); requests go to home, which forwards and invalidates point-to-point.

**Concepts**

- Entry: state and sharer bit-vector (or limited pointers / coarse vectors).
- Read miss: requester → home → data from memory or forwarded from the owner.
- Write miss: home sends invalidations to sharers; requester collects acks.
- 3-hop (via owner) vs 4-hop transactions; acks may go to home or requester.
- Storage: N bits per line for full vectors; snoop filters / sparse directories cut this.

**Numbers & formulas:** `full vector: N bits / line`

**Verification lens**

- No ordered bus means messages race. Use separate virtual channels for requests, forwards and responses to avoid protocol deadlock; check with model checking before RTL.

**Bugs that ship**

- Directory entry evicted without invalidating sharers
- Ack counting off by one when a sharer is also the requester

**Interview**

<details><summary>Why are directory protocols harder to verify than snooping?</summary>

No global order: requests, forwards, acks and data travel independently and can arrive in any order, creating many transient states.

</details>

---

## L19-07 Coherence misses and false sharing

*Coherence misses · false sharing*

> A fourth C: misses caused by other cores’ writes. False sharing is when they wrote different words of the same line.

**Concepts**

- **True sharing**: cores really communicate through the same data.
- **False sharing**: different variables share a line, so writes ping-pong it.
- Bigger lines → more false sharing.
- Fix in software: pad or align hot per-core data to line boundaries.

**Verification lens**

- False-sharing patterns (two cores writing different bytes of one line) are the best stress for byte-merge and coherence correctness. Check every byte with a shadow memory.

**Interview**

<details><summary>Two threads each increment their own counter, adjacent in memory. Why slow?</summary>

Both counters share a cache line; each increment needs M, invalidating the other core’s copy, so the line ping-pongs.

</details>

---

## L19-08 Transient states and races

*Transient states · races (verification focus)*

> Real controllers have many intermediate states between I, S and M; crossing messages are where protocol bugs live.

**Concepts**

- Examples: IS^D (got S, waiting data), IM^AD (waiting acks and data), SM^A (upgrade waiting acks).
- Classic race: core in S sends Upgrade, but a remote GetM invalidates it first → must become a full GetM.
- Writeback races with a forward to the same line.
- Eviction while a request to the same line is outstanding.

| Race | Expected handling |
| --- | --- |
| Upgrade loses to remote GetM | convert to GetM, wait for data |
| Writeback + forward | home takes data from exactly one, acks the other |
| Inv arrives in IS^D | complete the read, then invalidate (one use) |

**Verification lens**

- Model-check the protocol tables (Murphi, TLA+, JasperGold). In sim: few lines, many agents, random delays per channel. Coverage: every (transient state × message) pair.

**Interview**

<details><summary>How do you get coverage of transient-state races in simulation?</summary>

Shrink the address set to a few lines, add random per-link delays, use many agents, and target bins for each (transient state × incoming message). Fill remaining holes with directed tests or formal.

</details>
