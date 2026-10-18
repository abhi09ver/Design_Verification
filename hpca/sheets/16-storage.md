# Lesson 16 · Storage

2 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Magnetic disks](#l16-01-magnetic-disks)
2. [Flash and connecting I/O](#l16-02-flash-and-connecting-io)

---

## L16-01 Magnetic disks

*Storage · magnetic disks*

> Access time = seek + rotational latency + transfer + controller overhead; mechanics dominate.

**Concepts**

- Platters, tracks, sectors; arm moves heads (seek).
- Average rotational latency = half a revolution.
- 7200 RPM: 8.33 ms per revolution → **4.17 ms** average rotation.
- Typical access: several ms, millions of CPU cycles.

**Numbers & formulas:** `T = seek + ½ rev + xfer + ctrl`

**Worked**

| Problem | Answer |
| --- | --- |
| 7200 RPM half rotation | 4.17 ms |
| seek 5 + rot 4.17 + xfer 0.1 + ctrl 0.2 | ≈ 9.5 ms |

**Verification lens**

- Storage latency is why the OS switches tasks on page faults; for CPU DV the relevant pieces are DMA, interrupts and coherence of I/O writes with caches.

**Interview**

<details><summary>How many 3 GHz cycles is a 10 ms disk access?</summary>

3 × 10⁹ × 0.01 = 3 × 10⁷ cycles.

</details>

---

## L16-02 Flash and connecting I/O

*Flash · SSD · connecting I/O*

> Flash has no moving parts but erases in blocks and wears out; devices reach memory through buses and DMA.

**Concepts**

- Flash: read/write pages, erase whole blocks; limited erase cycles → wear levelling in the controller.
- SSD latency ~tens of µs vs ms for disks.
- I/O connects over buses (PCIe); the CPU uses memory-mapped I/O registers.
- **DMA**: the device moves data to memory itself and interrupts when done. **Polling** vs **interrupts** trade CPU time for latency.

**Numbers & formulas:** `SSD ~10–100 µs` · `HDD ~5–10 ms`

**Verification lens**

- CPU-side concerns: uncached/device memory types (no speculation, no merging, strict order), DMA coherence (snooped or explicit cache flushes), interrupt delivery and ordering with DMA data.

**Bugs that ship**

- Speculative load to a device register (side-effecting read)
- Interrupt observed before DMA data is visible

**Interview**

<details><summary>Why must loads to device memory not be speculative?</summary>

Reading a device register can change device state (pop a FIFO). A speculative read on a wrong path would lose data.

</details>
