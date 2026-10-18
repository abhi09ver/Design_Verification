# Lesson 22 · Many-cores

3 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Scaling to many cores](#l22-01-scaling-to-many-cores)
2. [Distributed shared LLC (NUCA)](#l22-02-distributed-shared-llc-nuca)
3. [Heterogeneous cores and GPUs](#l22-03-heterogeneous-cores-and-gpus)

---

## L22-01 Scaling to many cores

*Many-core challenges*

> More cores stress coherence traffic, the interconnect, off-chip bandwidth and power.

**Concepts**

- Bus and snooping stop scaling → directories and a **network-on-chip** (mesh, ring).
- Off-chip bandwidth grows slower than core count.
- Power: not all cores can run at full speed (dark silicon), so DVFS per core.
- Shared LLC split into slices across the chip.

**Verification lens**

- NoC verification: routing correctness, credit-based flow control (no credit leak), virtual channel deadlock freedom, fairness. Credit-conservation assertions at every link.

**Bugs that ship**

- Credit leaked on a dropped flit → link hangs after hours
- Routing cycle causes deadlock under heavy traffic

**Interview**

<details><summary>How do you prove a mesh NoC deadlock-free?</summary>

Use a deadlock-free routing (XY dimension-ordered) plus separate virtual channels per message class; check with formal on the router and with saturation tests in sim.

</details>

---

## L22-02 Distributed shared LLC (NUCA)

*Distributed shared cache · NUCA*

> The last-level cache is sliced across tiles; latency depends on which slice holds the line.

**Concepts**

- Address hash selects the home slice; each slice also holds the directory for its lines.
- Non-uniform cache access (NUCA): near slices are fast, far ones slower.
- Placement policies and page colouring can keep data near its user.

**Verification lens**

- Hash-function bugs send one address to two homes, breaking coherence. Assert every agent computes the same home for an address; test with addresses near hash-bit boundaries.

**Interview**

<details><summary>Why must every agent use the same slice hash?</summary>

The home slice serialises all requests for a line; two homes for one address means two serialisation points and broken coherence.

</details>

---

## L22-03 Heterogeneous cores and GPUs

*Heterogeneous cores · accelerators*

> Mix big and small cores, and offload data-parallel work to GPUs: same power budget, more work done.

**Concepts**

- big.LITTLE: same ISA, different microarchitectures; migrate threads by load.
- GPUs: thousands of threads, simple in-order cores, SIMT execution with divergence masks.
- CPU–GPU coherence over NVLink / CXL makes shared address spaces practical.

| Idea | CPU core | GPU SM (SIMT) |
| --- | --- | --- |
| Hide latency | OoO, caches, prefetch | switch warps every cycle |
| Parallelism | ILP + SMT 2-way | 32-thread warps, many warps |
| Memory | coherent L1/L2 | shared memory, coalescing, scoped coherence |
| Sync | locks, fences | barriers, scoped fences |

**Verification lens**

- For NVIDIA-style roles: SIMT divergence/reconvergence stack correctness, warp scheduler fairness, scoped memory model litmus tests (CTA, GPU, system scope), and coherence across CPU–GPU links.

**Interview**

<details><summary>How would you verify branch divergence in a SIMT core?</summary>

Reference model tracks the active mask stack per warp; generate nested and data-dependent branches; check per-thread results against a scalar model and that reconvergence happens at the right PC.

</details>
