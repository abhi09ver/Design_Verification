# Lesson 18 · Multiprocessing

4 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Why multicore](#l18-01-why-multicore)
2. [Shared memory vs message passing](#l18-02-shared-memory-vs-message-passing)
3. [Hardware multithreading](#l18-03-hardware-multithreading)
4. [Parallel speedup limits](#l18-04-parallel-speedup-limits)

---

## L18-01 Why multicore

*Flynn’s taxonomy · why multiprocessors*

> Single-core gains hit the power wall and diminishing ILP; more cores turn transistors into throughput.

**Concepts**

- Wider and deeper cores give diminishing returns (ILP limits, Amdahl).
- Power grows faster than frequency (V and f together).
- Two cores at lower V and f can beat one fast core in perf/W, if the software is parallel.

| Flynn class | Meaning | Example |
| --- | --- | --- |
| SISD | one instruction, one data stream | classic uniprocessor |
| SIMD | one instruction, many data | vector units, GPU warps |
| MISD | many instructions, one data | rare |
| MIMD | many instructions, many data | multicores |

**Verification lens**

- Multicore turns verification into a concurrency problem: the same core RTL now meets coherence, ordering, atomics and interconnect races. System-level random tests with many agents are mandatory.

**Interview**

<details><summary>Two cores at 0.8 V and 0.8f vs one core at 1.0 V and f: power?</summary>

Each core ≈ 0.8² × 0.8 = 0.51 of the original; two ≈ 1.02×. About the same power for up to 1.6× throughput if work parallelises.

</details>

---

## L18-02 Shared memory vs message passing

*Centralised vs distributed shared memory · message passing*

> Cores either share one address space (UMA or NUMA) or exchange explicit messages.

**Concepts**

- Shared memory is easier to program; communication is just loads and stores, but needs coherence.
- Message passing makes communication explicit; no coherence needed between nodes.
- Most chips: shared memory with coherence, often NUMA across sockets.

| Organisation | Memory | Scales | Notes |
| --- | --- | --- | --- |
| Centralised (UMA) | one shared memory | few cores | equal latency |
| Distributed (NUMA) | memory per node | many cores | local fast, remote slow |
| Message passing | private memories | clusters | explicit send/receive |

**Verification lens**

- NUMA adds variable remote latency and home-node logic. Randomise latency per node and cover requests whose home is local, remote and the requester itself.

**Interview**

<details><summary>Why is shared memory hard to scale?</summary>

Every shared write may need to invalidate copies everywhere (coherence traffic), and one shared memory becomes a bandwidth bottleneck. Distributing memory and using directories helps.

</details>

---

## L18-03 Hardware multithreading

*Multithreading: fine-grain, coarse-grain, SMT*

> Several threads share one core to fill idle slots: switch every cycle, switch on long stalls, or issue from several threads in the same cycle (SMT).

**Concepts**

- Each thread needs its own architectural state: PC, registers (via rename maps), CSRs.
- SMT on an OoO core: shared ROB/RS/caches, per-thread RAT and PC.
- Throughput rises; single-thread speed may drop slightly.

| Kind | Switches | Hides | Cost |
| --- | --- | --- | --- |
| Coarse-grain | on long stalls (L2 miss) | long latencies | small |
| Fine-grain | every cycle | all stalls | more state, slower single thread |
| SMT | no switch: mix in one cycle | stalls + unused width | most sharing logic |

**Verification lens**

- SMT invariants: no cross-thread register, forwarding or exception effects. Flush of thread 0 must not touch thread 1. Cross every flush cause with the other thread’s activity.

**Bugs that ship**

- Store-to-load forwarding across threads
- Thread 1 starved by thread 0 filling a shared queue
- Thread ID compared too narrowly on a shared table

**Interview**

<details><summary>Name three SMT-specific bugs.</summary>

Cross-thread forwarding, a per-thread flush that kills the other thread’s entries, and starvation or deadlock from shared resources. Also cross-thread predictor leakage if the spec forbids it.

</details>

---

## L18-04 Parallel speedup limits

*Multiprocessor performance*

> Speedup with N cores = 1 / ((1 − p) + p / N), minus communication and synchronisation overheads.

**Concepts**

- Serial fraction caps speedup (Amdahl).
- Overheads: coherence misses, lock contention, load imbalance, barriers.
- Weak scaling (bigger problem with more cores, Gustafson) often looks better than strong scaling.

**Numbers & formulas:** `S(N) = 1/((1−p)+p/N)`

**Worked**

| Problem | Answer |
| --- | --- |
| p = 0.9, N = 16 | 1/(0.1 + 0.9/16) = 6.4× |
| p = 0.9, N = ∞ | 10× |

**Verification lens**

- Multicore perf tests should include contention cases (all cores on one lock or line) to measure worst-case behaviour, not only parallel-friendly kernels.

**Interview**

<details><summary>90% parallel code on 16 cores: speedup?</summary>

1 / (0.1 + 0.05625) ≈ 6.4×.

</details>
