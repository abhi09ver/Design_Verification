# Challenge 26: Cache Organization, Coherence and Memory Consistency — From Zero to Senior DV

> One-stop page for caches and coherence interviews (CPU and GPU verification roles).
> Companion material lives in [`cache-coherence/`](cache-coherence/): two interactive HTML guides, a one-page cheat sheet, runnable Python models and SystemVerilog checkers.
> Main reference: Nagarajan, Sorin, Hill, Wood, *A Primer on Memory Consistency and Cache Coherence*, 2nd ed., 2020 ([free PDF](https://pages.cs.wisc.edu/~markhill/papers/primer2020_2nd_edition.pdf)).

---

## 1. The Source (summary)

Unlike the other challenges, this one is not based on a LinkedIn post. It condenses the Primer (Ch. 2–11) and the way interview loops at GPU/CPU companies probe the topic:

- **Organization**: derive sets/index/tag on the whiteboard, explain write-back vs write-through, inclusion, MSHRs.
- **Coherence**: state the invariants, draw MESI, explain transient states and the races they cause.
- **Consistency**: explain why a coherent machine can still reorder (store buffer), know the SB/MP/IRIW litmus tests.
- **Verification**: name the checkers, the stimulus tricks and the coverage model, and walk through a debug.

## 2. Common Misconceptions (don't say these)

| Myth | Reality |
|---|---|
| "Coherence and consistency are the same thing" | Coherence = one address. Consistency = ordering across **all** addresses. A perfectly coherent x86 still allows the SB outcome `r1=r2=0`. |
| "SC requires cores to issue coherence requests in program order" | False (Primer quiz Q1). Loads/stores must *perform* in order; GetS/GetM and prefetches can go in any order. |
| "The memory model defines legal orderings of coherence transactions" | False (quiz Q2). It constrains loads/stores, not the protocol's messages. |
| "An atomic RMW must lock the bus / talk to other cores" | False (quiz Q3). Get the line in M, then hold off snoops until the store half completes. |
| "MSI means a line can only be in 3 states" | False (quiz Q6). Real controllers have many transient states (IS<sup>D</sup>, IM<sup>AD</sup>, SM<sup>AD</sup>, MI<sup>A</sup> …). |
| "Snooping needs a physical bus" | False (quiz Q7). It needs a totally ordered broadcast; rings and logical buses qualify. |
| "GPUs have no coherence, so they can't enforce a memory model" | False (quiz Q8). They use consistency-directed coherence: self-invalidate on acquire, flush on release. |
| "Random tests passing on 10k seeds means coherence is clean" | With a wide address range, cores almost never collide, so races never happen. |

## 3. Background Concepts (fresher level)

**Why caches.** DRAM is ~300 cycles away; L1 is ~4. Programs show *temporal* locality (reuse) and *spatial* locality (neighbours), so a small fast memory near the core catches most accesses.

**Line.** Caches move and track fixed 64 B chunks. Everything (fill, eviction, coherence) is per line.

**Address split.**
```
sets        = cache_size / (ways * line_size)
offset bits = log2(line_size)
index bits  = log2(sets)
tag bits    = address_bits - index - offset
```
Example: 32 KiB, 8-way, 64 B, 48-bit PA → 64 sets → offset 6, index 6, tag 36.

**Associativity.** 1 way = direct-mapped (conflict misses), N-way set-associative (the norm), fully associative (TLBs). Misses: compulsory, capacity, conflict, plus *coherence* misses in multicore.

**Replacement.** LRU / tree-PLRU / RRIP. Evicting a dirty line means a writeback.

**Write policy.** Write-back + write-allocate (CPUs, needs a dirty bit), write-through (many GPU L1s). In front of the cache sits the **store buffer**, which is where most consistency surprises come from.

**AMAT** = hit time + miss rate × miss penalty → `4 + 0.05 × 300 = 19` cycles.

**Hierarchy.** Inclusive LLC (LLC ⊇ inner caches, acts as snoop filter, eviction needs back-invalidation), exclusive, or NINE (needs a separate snoop filter/directory).

Run `python3 cache-coherence/python/cache_sim.py` to see all of this with numbers.

## 4. Coherence

### 4.1 The two invariants (Primer Ch. 2)

1. **SWMR** — for every line at every instant: exactly one core may write (and read), *or* any number may only read.
2. **Data-value** — the value at the start of an epoch equals the value at the end of the last read-write epoch.

Alternative textbook definition: *write serialization* (all cores see writes to one address in the same order, a safety property) + *write propagation* (every write eventually becomes visible, a liveness property).

### 4.2 MOESI

| State | Valid | Dirty | Exclusive | Owner (supplies data) | Read | Write |
|---|---|---|---|---|---|---|
| M | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| O | ✓ | ✓ | ✗ | ✓ | ✓ | ✗ |
| E | ✓ | ✗ | ✓ | design choice | ✓ | silent → M |
| S | ✓ | ✗ | ✗ | ✗ | ✓ | ✗ |
| I | ✗ | – | – | ✗ | ✗ | ✗ |

- **E** saves the upgrade for private data (read then write with no second transaction).
- **O** shares dirty data without writing memory first.
- Variants: MESIF (Intel, F = designated forwarder), AMBA CHI naming UC/UD/SC/SD/I.

Requests: **GetS** (read), **GetM** (write), **Upgrade** (S→M, no data needed if still valid), **PutM/PutS/PutE** (evictions).

### 4.3 Transient states — where the bugs are

Naming `XY^Z`: going from X to Y, waiting for Z (D = data, A = acks).

| Transient | Meaning | Classic race |
|---|---|---|
| IS<sup>D</sup> | GetS sent, waiting for data | Inv arrives before data → use the data once, then go to I |
| IM<sup>AD</sup> | GetM sent, need data + N acks | Acks arrive before data; counter can go negative |
| SM<sup>AD</sup> | Upgrade from S | Another GetM ordered first → own copy invalidated → becomes IM<sup>AD</sup> and now needs data |
| MI<sup>A</sup> | Dirty eviction, PutM sent | Fwd-GetS/GetM arrives → supply data from the writeback buffer |
| SI<sup>A</sup>/II<sup>A</sup> | Put in flight, already invalidated | Directory must accept and ack a stale Put from a non-owner |

The protocol spec is a table of (state × event) → (action, next state). Every cell is either *handled*, *stall* or *impossible*; hitting an "impossible" cell in simulation is a bug.

### 4.4 Snooping vs directory

| | Snooping | Directory |
|---|---|---|
| Ordering point | Totally ordered broadcast (bus/ring) | Home node, per address |
| Miss latency | 2 hops | 3 hops (requester → home → owner → requester) |
| Bandwidth | O(N) per miss | Point-to-point |
| Scales to | Few cores | Many cores / sockets |
| Extra cost | Snoop bandwidth/power | Directory storage, many more races |

Directory details interviewers ask about:
- **Virtual networks**: separate request / forward / response classes so a response never waits behind a request (deadlock avoidance). At least 3 for a typical MOESI directory.
- **Directory formats**: full bit-vector, coarse vector, limited pointers.
- **Directory organization**: DRAM-backed directory cache, inclusive sparse directory (eviction forces back-invalidation), null directory with broadcast.
- **Silent vs explicit S evictions**: silent = fewer messages but stale sharer bits; explicit PutS = exact but new PutS-vs-Inv race.
- **Blocking vs non-stalling home**: blocking NACKs/queues new requests until Unblock; non-stalling adds transient states at the directory.
- Real systems: SGI Origin, AMD HyperTransport + HT Assist, Intel QPI/UPI (MESIF), Arm CHI (home node, snoop filter, direct data transfer), NVLink-C2C / CXL.cache for CPU–accelerator coherence.

### 4.5 Liveness

- **Deadlock**: cyclic wait on buffers or virtual channels.
- **Livelock**: requests keep bouncing (NACK/retry loops).
- **Starvation**: one core never wins the line (lock contention).

Safety checkers do not catch these; you need watchdogs and progress counters.

## 5. Memory Consistency

### 5.1 What is kept in order

| Earlier → later | SC | TSO / x86 | Weak (Arm, RISC-V WMO, Power) |
|---|---|---|---|
| Load → Load | ✓ | ✓ | ✗ unless fence / acquire / dependency |
| Load → Store | ✓ | ✓ | ✗ unless fence / dependency |
| Store → Store | ✓ | ✓ (FIFO store buffer) | ✗ unless fence / release |
| Store → Load | ✓ | ✗ (store buffer) | ✗ |
| Write atomicity | ✓ | ✓ | Arm v8 / RISC-V ✓, Power ✗ |

### 5.2 Litmus tests (run `python3 cache-coherence/python/litmus.py`)

Output of the included explorer (exhaustive interleavings, x86-TSO operational model):

```
test       interesting outcome       SC        TSO (x86)
SB         r1=0 r2=0                 forbidden allowed
SB+fences  r1=0 r2=0                 forbidden forbidden
MP         r1=1 r2=0                 forbidden forbidden
LB         r1=1 r2=1                 forbidden forbidden
IRIW       r1=1 r2=0 r3=1 r4=0       forbidden forbidden
CoRR       r1=1 r2=0                 forbidden forbidden
SB+fwd     r1=1 r2=0 r3=1 r4=0       forbidden allowed
```

On weak models MP, LB and (on Power) IRIW are also allowed without fences. CoRR is forbidden everywhere: a core must never see an older value after a newer one for the same address.

### 5.3 How an out-of-order core keeps SC/TSO

Loads execute speculatively out of order. The load queue watches incoming invalidations and evictions; if a performed-but-uncommitted load's line is lost, squash and replay (MIPS R10000 style). Stores retire into the store buffer and drain in order; a thread may forward only from **its own** buffered stores (quiz Q4: SMT threads must not forward from each other under TSO).

### 5.4 Atomics, fences, SC-for-DRF

- **RMW**: obtain M, perform load+store locally, defer snoops in between. Under TSO it also drains the store buffer.
- **Fences**: x86 `MFENCE`/locked op; Arm `DMB`/`DSB`, `LDAR`/`STLR`; RISC-V `fence rw,rw`; Power `sync`/`lwsync`.
- **Release consistency**: acquire = later ops can't move above; release = earlier ops can't move below.
- **SC for DRF**: if all conflicting accesses are ordered by synchronization, weak hardware looks SC. C++/Java models are built on this.
- **Axiomatic view**: relations `po`, `rf`, `co`, `fr`. SC ⇔ acyclic(po ∪ rf ∪ co ∪ fr). Weak models keep only a subset of `po` (preserved program order) plus fences.

## 6. GPU and Heterogeneous Coherence (Primer Ch. 10)

- GPU L1s are often write-through and not kept coherent by invalidations; L2 is the point of coherence.
- **Consistency-directed coherence**: acquire → self-invalidate L1; release → flush pending writes to L2. Temporal coherence uses leases instead of invalidations.
- **Scopes**: CTA/block, GPU/device, system (PTX `.cta/.gpu/.sys` with `.acquire/.release/.relaxed`). A block-scope release need not leave the SM.
- Classic bug: producer releases at CTA scope, consumer on another SM acquires → stale data.
- CPU + GPU: each device has its own model; the combined system must define cross-device ordering. Coherent links (NVLink-C2C, CXL.cache, CHI) bridge protocols, which is a rich source of bugs.

## 7. Verification

### 7.1 The environment

```
 stimulus ──► [ L1s · interconnect/VCs · home+directory · LLC/mem ] ──► monitors
                                                                         │
     ┌───────────────────────────┬────────────────────────┬──────────────┴──────────┐
  SWMR/state monitor     data-value scoreboard     consistency checker     liveness watchdogs
  (every cycle)          (golden mem, per-addr     (po/rf/co/fr graph,     (txn timeout, MSHR age,
                          coherence order)          cycle = violation)      VC credits, progress)
```

Why all four: SWMR catches permission bugs; the scoreboard catches stale data even when permissions look right; the graph checker catches pipeline ordering bugs that coherence monitors cannot see; watchdogs catch hangs.

Code in this repo:
- [`cache-coherence/python/mesi_model.py`](cache-coherence/python/mesi_model.py): MESI protocol + SWMR monitor + scoreboard + CoRR check + drain compare + coverage table + **bug injection** (`--bug upgrade_no_inv | stale_e | no_flush | silent_m_evict`) so you can watch each checker catch a broken design.
- [`cache-coherence/sv/coherence_pkg.sv`](cache-coherence/sv/coherence_pkg.sv): SystemVerilog scoreboard (legal-value window, CoRR) and covergroup (state × event, races, sharer counts).
- [`cache-coherence/sv/coherence_assertions.sv`](cache-coherence/sv/coherence_assertions.sv): SVA for SWMR, single owner, legal L1 transitions, miss completion, ack accounting, with cover properties.

### 7.2 Stimulus

- **Shrink the address space** to 2–8 hot lines, some aliasing to the same set.
- **Shrink the caches** (config knob) so evictions race with snoops constantly.
- False-sharing patterns: different bytes, same line, many writers.
- Directed races: GetM vs PutM, upgrade vs invalidate, two upgrades from S, Fwd-GetS vs eviction.
- Litmus suites (diy/litmus7-generated) with randomized start skew.
- Randomize NoC latency, credits, arbitration, NACK/retry, error injection.
- Software torture: locks, barriers, atomics, fence-heavy kernels.

### 7.3 Coverage — how you know you are done

- Every (stable + transient state) × (incoming event) cell, including stall cells.
- Every message type on every virtual network; VC-full / zero-credit conditions.
- Race crosses: own request type × concurrent forward/invalidate type.
- Ack orderings: acks before data, data before acks, zero acks.
- Replacement × in-flight snoop for every dirty state.
- Litmus: every allowed outcome observed at least once, no forbidden outcome ever.

### 7.4 Formal

- Protocol-level model checking (Murphi, TLA+) with 2–3 caches, 1–2 addresses: exhaustive interleavings, finds deadlocks and SWMR violations early.
- RTL formal: SVA on controller tables, FIFO/credit correctness, bounded liveness, symbolic address for SWMR.
- Axiomatic MCM specs (herd/cat) as reference; PipeCheck/CCICheck-style checks of pipeline + coherence together.

### 7.5 Bug catalog

| # | Scenario | Symptom | Caught by |
|---|---|---|---|
| 1 | PutM crosses an incoming Fwd-GetS/GetM | Stale memory data or hang | Scoreboard, MI<sup>A</sup> × Fwd coverage |
| 2 | Upgrade from S loses race to another GetM | Write merged into stale data | Scoreboard, SM<sup>AD</sup>→IM<sup>AD</sup> coverage |
| 3 | Inv arrives in IS<sup>D</sup>, line kept valid after fill | SWMR violation, later stale read | SWMR monitor |
| 4 | Acks counted before data, counter wraps | Premature M, two writers | SWMR, ack assertion |
| 5 | Speculative load not squashed on snoop | MP / CoRR violation while coherence looks fine | MCM checker, litmus |
| 6 | SMT thread forwards from sibling's store buffer | TSO violation | Litmus with SMT |
| 7 | Snoop serviced between RMW load and store | Lost increment, broken lock | Atomic counter self-check |
| 8 | Inclusive LLC back-invalidate misses WB buffer | Stale data resurrected | Scoreboard, inclusion assertion |
| 9 | Responses share a queue with requests | Deadlock under load | Watchdog, formal deadlock proof |
| 10 | NACK/retry without fairness | Livelock / starvation | Progress counters, latency histograms |
| 11 | Stale Put from non-owner corrupts directory | Wrong owner/sharers | Directory-vs-actual assertion |
| 12 | DMA write doesn't invalidate caches / I-cache | Device or self-modifying code reads stale | IO coherence tests |

### 7.6 Debugging a stale load (answer template)

1. Pull the scoreboard's history for the line: write order, which version the load returned.
2. Find the cache that supplied the data and its state at that time.
3. Walk the protocol log for that line around the window: requests, forwards, invalidates, acks, evictions.
4. Identify the transient state that mishandled a message (usually an upgrade race, eviction crossing a forward, or a missed squash).
5. Reduce to a directed test, fix, and add a coverage point for that cell so it never regresses.

## 8. Likely Interviewer Follow-ups (with model answers)

**Q: Coherence vs consistency in one minute?**
Coherence: per address, SWMR plus the data-value invariant; caches become invisible. Consistency: the ISA's rule for ordering loads/stores across all addresses. The pipeline plus coherence together implement it. x86 is coherent yet allows SB `r1=r2=0` because of the store buffer.

**Q: 1 MiB, 16-way, 64 B lines, 48-bit PA: sets, index, tag?**
16384 lines / 16 = 1024 sets → index 10 bits [15:6], offset 6 bits, tag 32 bits.

**Q: Why E? Why O?**
E: silent E→M for private data, saving the upgrade. Needs "no sharers" knowledge. O: share dirty data without a memory writeback; the O holder supplies data and owns the eventual writeback.

**Q: Walk me through an upgrade losing a race.**
C0 in S sends Upgrade (SM<sup>AD</sup>). C1's GetM is ordered first; C0 gets Inv, acks, drops to IM<sup>AD</sup> because its data is gone. When serviced, C0 needs data, not just acks. A bug here writes into stale data; the scoreboard catches the lost update.

**Q: Dirty eviction racing a forward?**
C0 evicts M, sends PutM, enters MI<sup>A</sup> with data in the WB buffer. The directory forwards C1's request to C0 as owner; C0 must supply data from the WB buffer and move to II<sup>A</sup>. The directory later receives a PutM from a non-owner and must ack it without writing stale data to memory.

**Q: Why multiple virtual networks?**
Requests generate forwards, which generate responses. If they share a queue, a full queue of requests can block the responses needed to drain it. Separate VNs with always-sinkable responses guarantee progress.

**Q: How does an OoO core guarantee TSO?**
Speculative loads tracked in the load queue; any invalidation/eviction of a matching performed-but-uncommitted load squashes and replays. FIFO store buffer, same-thread forwarding only.

**Q: Design the checkers for a coherence bench.**
SWMR monitor, data-value scoreboard with coherence order and a legal-value window, axiomatic consistency checker, protocol assertions (directory ⊇ actual sharers, single owner, ack counts), liveness watchdogs, end-of-test drain and compare.

**Q: 10k random seeds pass. Is coverage good?**
Probably not: random addresses rarely collide. Use hot address pools, set aliasing, small caches, biased same-line multi-writer traffic, randomized NoC delay, and drive transient × event and race-cross coverage.

**Q: How does GPU coherence differ?**
Write-through L1s, no invalidation traffic; acquire self-invalidates, release flushes to L2, at the requested scope. Gives SC for DRF. Verify scope semantics, fence lowering, L2 atomics and the CPU–GPU link.

**Q: Where does formal beat simulation here?**
Protocol-level model checking explores every message interleaving for small configs, finding deadlocks and invariant violations simulation may never hit. RTL formal proves local tables, credits and bounded liveness. Simulation is still needed at full scale and for pipeline + memory interactions.

**Q: What goes in the coherence verification plan?**
Specs (ISA memory model, protocol tables, interconnect spec); features (requests, responses, stable and transient states, replacement, inclusion, atomics, fences, DMA/IO, ECC/poison, power-down flush); checkers; stimulus plan; coverage model and closure criteria; formal scope; unit → cluster → SoC reuse; emulation/silicon plan.

## 9. Common Mistakes

- Drawing only stable-state MESI and stopping there; seniors are expected to discuss transient states.
- Claiming "SWMR holds, therefore the system is correct": the data-value invariant and the pipeline both matter.
- Forgetting liveness. A protocol can be safe and still deadlock.
- Random stimulus over a wide address range, then claiming closure.
- Mixing up x86 (TSO) and Arm/RISC-V (weak) litmus results.
- Saying GPUs are "incoherent" without explaining scoped acquire/release.

## 10. 60-Second Interview Pitch

"Coherence makes private caches invisible by enforcing single-writer/multiple-reader plus a data-value invariant per line; consistency is the ISA's ordering contract across addresses, implemented by the pipeline and coherence together. In a real protocol, the hard part is the transient states: upgrades losing races, evictions crossing forwards, acks arriving before data. To verify it I run four independent checkers—an SWMR monitor, a scoreboard with per-address coherence order, a memory-model graph checker for litmus and random tests, and liveness watchdogs. I drive stimulus with tiny hot address pools and shrunken caches so races happen constantly, and I close on (state × event) and race-cross coverage, backed by protocol-level model checking for deadlock and invariant proofs. On GPUs I shift focus to scoped acquire/release, self-invalidation and the CPU–GPU coherent link."

## 11. Self-Check

- [ ] I can derive sets/index/tag for any cache configuration in under a minute.
- [ ] I can draw MESI stable states and name four transient states with their races.
- [ ] I can explain why E and O exist and what each costs.
- [ ] I can compare snooping and directory, and explain virtual networks.
- [ ] I can state SB, MP, IRIW, CoRR and their SC / TSO / weak results.
- [ ] I can explain how an OoO core preserves TSO.
- [ ] I can describe GPU acquire/release with scopes.
- [ ] I can list the four checker types and why each is necessary.
- [ ] I ran `mesi_model.py --bug ...` and watched each checker fire.
- [ ] I can walk through debugging a stale-load failure step by step.
