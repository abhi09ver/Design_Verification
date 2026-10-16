# Cache & Coherence Cheat Sheet (read 10 minutes before the interview)

## Numbers and formulas
| | |
|---|---|
| Line | 64 B (CPU); GPU often 128 B line / 32 B sector |
| sets | size ÷ (ways × line) |
| offset / index / tag | log2(line) / log2(sets) / addr − index − offset |
| Example | 32 KiB, 8-way, 64 B, 48b PA → 64 sets, 6/6/36 bits |
| AMAT | hit + miss_rate × penalty → 4 + 0.05×300 = 19 cycles |
| Latency ballpark | L1 ~4, L2 ~12, LLC ~40, DRAM ~300 cycles |
| VIPT rule | index + offset bits ≤ page offset (else synonyms) |

## Organization one-liners
- 3 C's + coherence misses. Direct-mapped / N-way / fully associative.
- LRU, tree-PLRU, RRIP. Dirty victim → writeback.
- Write-back + allocate (CPU) vs write-through (GPU L1). Store buffer sits in front.
- Inclusive LLC = snoop filter, needs back-invalidate. Exclusive. NINE + separate filter.
- MSHR = outstanding miss = transient state. WB/fill buffers must answer snoops.

## Coherence invariants
1. **SWMR**: one writer XOR many readers, per line, at all times.
2. **Data-value**: each epoch starts with the last writer's value.
(Alt: write serialization = safety, write propagation = liveness.)

## States
| | Valid | Dirty | Excl | Owner | Write |
|---|---|---|---|---|---|
| M | ✓ | ✓ | ✓ | ✓ | ✓ |
| O | ✓ | ✓ | ✗ | ✓ | ✗ |
| E | ✓ | ✗ | ✓ | opt. | silent→M |
| S | ✓ | ✗ | ✗ | ✗ | ✗ |
| I | ✗ | | | | |

MESIF (Intel, F=forwarder) · MOESI (AMD) · CHI: UC/UD/SC/SD/I.
Requests: GetS, GetM, Upgrade, PutM/PutS/PutE. Snoops: Fwd-GetS, Fwd-GetM, Inv.

## Transient states and races
| State | Waiting for | Race |
|---|---|---|
| IS^D | data | Inv before data → use once, go I |
| IM^AD | data + acks | acks before data |
| SM^AD | acks (+data) | lose to other GetM → IM^AD |
| MI^A | Put-Ack | Fwd arrives → supply from WB buffer |
| II^A | Put-Ack | dir gets stale Put from non-owner |

## Snoop vs directory
Snoop: ordered broadcast, 2-hop, O(N) bandwidth, small N.
Directory: home serializes, 3-hop, point-to-point, scales. ≥3 virtual networks (req/fwd/resp) for deadlock freedom. Formats: bit-vector, coarse, limited pointer. Silent vs explicit S evictions. Blocking vs non-stalling home.

## Consistency
| Kept? | SC | TSO/x86 | Weak (Arm/RISC-V/Power) |
|---|---|---|---|
| L→L | ✓ | ✓ | fence/acq/dep |
| L→S | ✓ | ✓ | fence/dep |
| S→S | ✓ | ✓ | fence/rel |
| S→L | ✓ | ✗ | ✗ |
| Write atomic | ✓ | ✓ | Arm/RV ✓, Power ✗ |

| Litmus | Outcome | SC | TSO | Weak |
|---|---|---|---|---|
| SB `x=1;r1=y ‖ y=1;r2=x` | r1=r2=0 | ✗ | ✓ | ✓ |
| MP `d=1;f=1 ‖ r1=f;r2=d` | r1=1,r2=0 | ✗ | ✗ | ✓ |
| LB `r1=x;y=1 ‖ r2=y;x=1` | r1=r2=1 | ✗ | ✗ | ✓ |
| IRIW | readers disagree | ✗ | ✗ | Power |
| CoRR | new then old | ✗ | ✗ | ✗ |

Fences: x86 MFENCE / lock · Arm DMB, DSB, LDAR/STLR · RISC-V fence rw,rw · Power sync/lwsync.
OoO TSO: load queue snoops invalidations → squash+replay. FIFO SB, same-thread forwarding only.
RMW: get M, defer snoops between load and store; under TSO drains SB.
SC-for-DRF. Acquire = nothing moves above; release = nothing moves below.
Axiomatic: SC ⇔ acyclic(po ∪ rf ∪ co ∪ fr).

## GPU
Write-through L1, L2 = point of coherence. Acquire → self-invalidate; release → flush. Scopes CTA / GPU / system (PTX .cta/.gpu/.sys). Bug: scope mismatch across SMs. CPU–GPU over NVLink-C2C / CXL.cache / CHI.

## Verification
**Checkers**: SWMR monitor · scoreboard (golden mem, per-address coherence order, legal window, CoRR) · MCM graph checker · protocol assertions (single owner, dir ⊇ sharers, ack counts) · liveness watchdogs · end-of-test drain + compare.
**Stimulus**: 2–8 hot lines, set aliasing, tiny caches, false sharing, directed races, litmus with skew, NoC delay/credit randomization, lock/barrier torture.
**Coverage**: (stable+transient) × event, msg type × VN, VC full, race crosses, ack orderings, eviction × snoop, litmus outcome histograms.
**Formal**: Murphi/TLA+ protocol model check; SVA on tables, credits, bounded liveness; symbolic address.
**Liveness**: deadlock, livelock, starvation.

## Top bugs
PutM vs Fwd · upgrade loses race · Inv in IS^D · acks before data · unsquashed speculative load · SMT SB forwarding · snoop inside RMW · back-invalidate misses WB buffer · resp/req share queue · NACK unfairness · stale Put at dir · DMA/I-cache not invalidated.

## Debug template
Scoreboard history → supplier & its state → protocol log for the line → transient state that mishandled a message → directed test → coverage point.

## Primer pop quiz
False: 1 SC needs in-order coherence requests · 2 MCM orders coherence transactions · 3 RMW must talk to other cores · 4 TSO SMT threads may forward from any thread's SB · 6 MSI has only 3 states · 7 snooping needs a bus · 8 GPUs without HW coherence can't enforce a model.
True: 5 properly synchronized (data-race-free) HLL code need not reason about the ISA model; the compiler and hardware provide SC for DRF.
