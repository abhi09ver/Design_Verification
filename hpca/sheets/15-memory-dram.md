# Lesson 15 · Memory (DRAM)

3 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [SRAM vs DRAM](#l15-01-sram-vs-dram)
2. [DRAM access: rows and the row buffer](#l15-02-dram-access-rows-and-the-row-buffer)
3. [Memory controller scheduling](#l15-03-memory-controller-scheduling)

---

## L15-01 SRAM vs DRAM

*Memory technology: SRAM vs DRAM*

> SRAM (6 transistors) is fast and kept powered; DRAM (1 transistor + capacitor) is dense, slow and must be refreshed.

**Concepts**

- DRAM read drains the capacitor, so a row is sensed into the row buffer and written back.
- Charge leaks, so every row is refreshed periodically (typically all rows within 64 ms).

|  | SRAM | DRAM |
| --- | --- | --- |
| Cell | 6T | 1T + 1C |
| Density | low | high |
| Speed | fast | slower |
| Refresh | no | yes (~64 ms) |
| Read | non-destructive | destructive, rewrite |
| Use | caches, registers | main memory |

**Verification lens**

- Memory controller verification uses a DRAM model that checks timing and refresh: missing a refresh window loses data in silicon but not in a simple RTL memory model.

**Interview**

<details><summary>Why must DRAM be refreshed?</summary>

The capacitor leaks charge; without rewriting it periodically the bit fades within milliseconds.

</details>

---

## L15-02 DRAM access: rows and the row buffer

*DRAM organisation · row buffer · timing*

> Opening a row copies it into the row buffer; accesses to the open row are fast, others pay precharge and activate.

**Concepts**

- Address split: channel, rank, bank, row, column.
- Banks work in parallel; each has its own row buffer.
- Open-page policy favours locality; closed-page favours random access.

| Case | Commands | Latency |
| --- | --- | --- |
| Row hit | READ (CAS) | tCL |
| Row closed | ACT → READ | tRCD + tCL |
| Row conflict | PRE → ACT → READ | tRP + tRCD + tCL |

**Numbers & formulas:** `conflict = tRP + tRCD + tCL`

**Verification lens**

- Write a timing checker per JEDEC parameter (tRCD, tRP, tRAS, tRC, tFAW, tWTR…) as assertions on the command bus; a single violated parameter can work in sim and fail in silicon.

**Interview**

<details><summary>Why is row-buffer locality important?</summary>

A row hit skips precharge and activate, often halving latency and saving energy.

</details>

---

## L15-03 Memory controller scheduling

*Memory controller · scheduling*

> Reorder requests to hit open rows (FR-FCFS) while preventing starvation and honouring ordering rules.

**Concepts**

- **FR-FCFS**: first-ready (row hits) first, then oldest first.
- Starvation: a stream of row hits can block an old request; add age caps.
- Write queues drained in bursts to avoid read/write turnaround (tWTR).
- Address mapping (XOR bank hashing) spreads traffic across banks.

**Verification lens**

- Ordering: same-address read after write must see the write (forward from the write queue or order). Check with a memory scoreboard. Add a per-request age watchdog for starvation.

**Bugs that ship**

- Read bypasses an older write to the same address in the write queue
- Low-priority requester starved under constant row hits

**Interview**

<details><summary>How do you test for starvation in a memory controller?</summary>

Generate a hostile pattern (one master streaming row hits, another with a single request to a different row) and assert maximum wait below a bound.

</details>
