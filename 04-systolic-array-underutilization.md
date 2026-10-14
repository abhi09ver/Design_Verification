# Challenge 04: "The Systolic Array Is Underutilized — Is It Compute, SRAM, or Data Movement?"

> **Level:** Fresher → Senior DV interview
> **Topics:** AI accelerator basics, systolic arrays, tiling, fill/drain, bandwidth, partial sums, performance counters, boundary-tile verification, turning a perf question into a verification plan

---

## 1. The Post (summary)

A LinkedIn post suggests a stronger RTL interview question than "define a systolic array":

> *A systolic array is underutilized. Is the bottleneck compute, SRAM, or data movement?*

It lists: the design promise (data reuse + bandwidth must keep the array fed), the trade-offs (PE count vs. SRAM, NoC, latency, power), the cycles that break it (tile edges, partial sums, padding, quantization, DMA backpressure), and the evidence to trust (utilization counters, bandwidth traces, golden-model comparison on boundary tiles).

**Verdict:** this one is technically sound. Two notes:
- The title promises **2026 salary benchmarks** but the post contains none. Ignore that part; don't quote salary "benchmarks" from posts like this.
- The post is a checklist of keywords. In an interview you must be able to **explain each one with numbers and a signal path**. That's what this file teaches.

---

## 2. Background a Fresher Must Know

### 2.1 What a systolic array does

Matrix multiply `C[M×N] = A[M×K] × B[K×N]` is the core of neural networks. A systolic array is a 2D grid of **PEs (processing elements)**, each doing one **MAC** (multiply-accumulate) per cycle. Data moves PE-to-PE like a heartbeat ("systolic"), so each value fetched from memory is **reused many times** inside the array instead of re-read from SRAM.

```
            B / weights (loaded into PEs)
             |     |     |     |
A rows -->  PE -> PE -> PE -> PE -->
             |     |     |     |
A rows -->  PE -> PE -> PE -> PE -->
             |     |     |     |
           partial sums flow down
             v     v     v     v
           outputs (C)
```

### 2.2 Dataflow styles (know the names)

| Dataflow | What stays inside the PE | Example |
|---|---|---|
| **Weight-stationary** | Weights loaded once, inputs stream through | Google TPU v1 (publicly described) |
| **Output-stationary** | Each PE accumulates its own output | Many edge accelerators |
| **Input-stationary** | Inputs held, weights stream | Less common |

The examples below assume **weight-stationary** on an `R × C` array.

### 2.3 Key terms

| Term | Meaning |
|---|---|
| **Utilization** | useful MACs ÷ (number of PEs × cycles). 100% = every PE does a useful MAC every cycle |
| **Tiling** | Big matrices are cut into array-sized tiles (`R × C` weight tiles) |
| **Edge / boundary tile** | Last tile when a dimension isn't a multiple of R or C; partly empty |
| **Padding** | Filling unused PE positions with zeros so the math still works |
| **Fill / drain** | Cycles for data to enter and exit the array diagonally (skewed wavefront) |
| **Partial sum (psum)** | Running sum when K is split across tiles; must be accumulated correctly |
| **Double buffering** | Load the next tile into buffer B while computing from buffer A |
| **Arithmetic intensity** | MACs per byte moved from memory. Low → memory-bound |
| **Backpressure** | Downstream says "not ready", so upstream must stall |

---

## 3. Reasoning Through the Question (with numbers)

**Utilization loss has four buckets.** A senior answer names them, puts numbers on them, and says which counter proves each.

### Bucket 1: Shape mismatch (compute side — the array is fed, but not full)

Example: array `R × C = 128 × 128`, layer with `K = 200`.
- K is split into `ceil(200/128) = 2` tiles: one uses 128 rows, the next only **72 rows**.
- Average row usage = 200 / 256 = **78%**, even with perfect memory.

Likewise, depthwise convolutions or small channel counts leave most of the array idle. **This is not a bug**; it's mapping efficiency. But it must be measured and expected.

### Bucket 2: Fill / drain overhead (small batch problem)

For one weight tile, streaming `M` input rows takes about `M + R + C − 2` cycles, but only `M` of them are fully productive.

| M (rows streamed) | Approx. utilization `M / (M + 254)` |
|---|---|
| 16 (batch 1, small layer) | ~6% |
| 256 | ~50% |
| 1024 | ~80% |

**This is why batch-1 inference on a big array looks "underutilized"**, with no memory problem at all. Also, if weight loading is **not double-buffered**, add the weight-load time per tile on top.

### Bucket 3: SRAM / memory bandwidth (memory-bound)

The array needs, per cycle, `R` input values on one edge (and weights during load). If the SRAM can't deliver that:
- **Bank conflicts**: two requests to the same bank in one cycle; one must wait.
- **Low arithmetic intensity** layers (e.g., fully-connected with batch 1) need lots of bytes per MAC, so even a perfect array starves.
- **No double buffering**: compute waits for the next tile to land.

Quick check (roofline idea): if `required bytes/cycle > available bytes/cycle`, the layer is memory-bound and utilization ≤ available/required.

### Bucket 4: Data movement / control (DMA, NoC, handshakes)

- **DMA backpressure**: off-chip (DRAM) or NoC can't keep up; input buffer runs empty.
- **Output backpressure**: results can't be written back, so the array stalls with full output FIFOs.
- **Scheduler bubbles**: control waits for a "tile done" handshake before issuing the next tile instead of overlapping.

### How to tell which bucket it is (the evidence)

| Counter / trace | Points to |
|---|---|
| `active_mac_cycles` vs. `total_cycles` | Overall utilization number |
| Per-row / per-column active counts | Bucket 1 (edge tiles, shape mismatch) |
| `fill_drain_cycles` per tile vs. `M` | Bucket 2 |
| `stall_input_starve` (input FIFO empty while array ready) | Bucket 3 or 4 (upstream) |
| `sram_bank_conflict` count | Bucket 3 |
| `stall_output_backpressure` (output FIFO full) | Bucket 4 (downstream) |
| `weight_load_stall` (compute waits for weights) | Missing/broken double buffering |
| DMA bytes/cycle trace vs. theoretical | Bucket 4 (DRAM/NoC) |

**Senior insight:** a stall counter must be **mutually exclusive and attributed by priority** (e.g., if both input starve and output full, count only one, by a defined rule). Otherwise percentages add up to more than 100% and the analysis is wrong. That's itself a verification item.

---

## 4. From Performance to Verification: Where Functional Bugs Hide

The post's "cycles that break it" are where **correctness** bugs live, not just performance loss. A DV engineer must check both.

| Risky cycle | What must stay true | How to check |
|---|---|---|
| **Edge tile** | Unused PEs contribute exactly 0; valid outputs not overwritten by garbage lanes | Golden model on K, N not multiples of R, C (e.g., K = R+1, N = 1) |
| **Padding** | Pad value is 0 (or zero-point for quantized) | Assertion on pad lanes; test with non-zero zero-point |
| **Partial sums across K tiles** | psum from tile *k* is added to tile *k+1*, cleared only at the start of a new output | Golden compare with K = 2R, 3R; check first-tile clear |
| **Quantization** | Correct rounding mode, saturation (not wrap-around), accumulator width enough | Max-magnitude inputs; compare to bit-accurate model |
| **Double buffer swap** | Never read the buffer being written | SVA: `!(rd_buf_sel == wr_buf_sel && rd_en && wr_en)` (adapt to design) |
| **DMA backpressure** | Data held stable while `valid && !ready`; nothing lost or duplicated | Standard handshake SVA; random `ready` throttling |
| **Output backpressure** | Array stalls cleanly; no psum lost mid-stall | Random output stall injection + golden compare |

Example handshake assertion (valid/ready):

```systemverilog
property p_hold_until_ready;
  @(posedge clk) disable iff (!rst_n)
  (in_valid && !in_ready) |=> (in_valid && $stable(in_data));
endproperty
assert property (p_hold_until_ready);
```

### Golden model strategy
- A **bit-accurate** C/C++ or Python reference (same integer widths, rounding, saturation), connected via DPI-C or file compare.
- Compare **every output element**, not checksums only. Checksums hide offsetting errors.
- Directed boundary shapes + randomized shapes: `M, K, N ∈ {1, R−1, R, R+1, 2R, 2R+1, random}`.
- Randomize **stall injection** (DMA ready, output ready) so the same math runs under different timing.

### Performance verification (separate from functional)
- Build a simple **analytical model** (the formulas in Section 3) that predicts cycles per layer.
- Run the same layers on RTL and compare cycles; flag anything outside a tolerance (e.g., ±5%).
- Check counters themselves: sum of attributed stall cycles + active cycles == total cycles.

---

## 5. Worked Example: One Failing Scenario (what the post asks you to do)

**Scenario:** On layers where `K` is not a multiple of 128, the output mismatches the golden model in a few elements, and only when output backpressure happens.

**Signal path in words:**
1. K = 200 → tile 0 (128 rows) then tile 1 (72 rows, 56 padded).
2. Tile 0 psums go to the accumulator buffer.
3. Output FIFO goes full; the array stalls.
4. During the stall, the controller advances the tile counter anyway; tile 1 starts with the **first-tile flag set**, so the accumulator is **cleared** instead of adding.
5. Outputs for that column equal only tile 1's contribution → mismatch.

**Evidence that proves it:**
- Golden compare: mismatching elements = exactly tile 1's partial result.
- Waveform: `acc_clear` asserted on tile 1 while `out_ready == 0`.
- Assertion that would have caught it early:
  ```systemverilog
  assert property (@(posedge clk) disable iff (!rst_n)
    acc_clear |-> (k_tile_idx == 0));
  ```
- Counter: `stall_output_backpressure > 0` only in failing runs.

**Fix and closure:** gate the tile counter with the stall; add a covergroup cross `k_tile_idx × output_stall`; add a directed test (K = R+1, forced output stall at tile boundary) to the regression.

---

## 6. Likely Follow-ups (with model answers)

**Q. Utilization is 30%. Is that a bug?**
Not necessarily. First compute the *expected* utilization for that layer shape and batch from the analytical model. If expected is 32%, it's fine. If expected is 75%, investigate the stall counters.

**Q. How do you know a stall counter is correct?**
Check the invariant `active + Σ(stall reasons) + idle == total cycles`, write SVA that each cycle is attributed to exactly one category, and cross-check against a hand-calculated small case.

**Q. Why test K = R+1 specifically?**
It creates a second tile with a single valid row: the most extreme edge case for padding and psum accumulation.

**Q. Quantized int8: what corners matter?**
Max positive × max positive accumulated over K (accumulator overflow), min negative values (−128 × −128), non-zero zero-points, and the requantization step (rounding mode and saturation).

**Q. How do you stress data movement?**
Random backpressure on every valid/ready interface, random DMA latencies, bank-conflicting address patterns, and back-to-back layers to check overlap.

---

## 7. Common Fresher Mistakes
- Treating "underutilized" as automatically a bug, without computing the expected value.
- Only testing nicely aligned shapes (multiples of the array size).
- Comparing checksums instead of every element.
- Ignoring that stalls can change results (psum/clear bugs under backpressure).
- Using a floating-point golden model for an integer datapath.
- Giving a keyword list instead of numbers and a signal path.

---

## 8. 60-Second Interview Pitch

> "I'd split the loss into four buckets and put a number on each. First, shape mismatch: a K of 200 on a 128-row array uses only 78% of the rows. Second, fill and drain: with batch 1 and only 16 rows streamed, a 128×128 array is around 6% utilized even with perfect memory. Third, SRAM bandwidth: bank conflicts, low arithmetic intensity, or missing double buffering. Fourth, data movement: DMA or output backpressure and scheduler bubbles.
>
> To tell them apart I'd compare the measured cycles to an analytical model, then read the attributed stall counters: input-starve, output-backpressure, weight-load and bank-conflict. I'd also verify the counters, by checking they sum to total cycles.
>
> For correctness, the risky cycles are edge tiles, padding, partial-sum accumulation across K tiles, quantization saturation, and buffer swaps under stalls. I'd use a bit-accurate golden model with shapes like K = R+1 and random backpressure, plus assertions such as 'the accumulator clears only on the first K tile'."

---

## 9. Self-Check
- [ ] Can I define utilization as a formula?
- [ ] Can I compute edge-tile and fill/drain utilization for a given shape?
- [ ] Can I name the counter that separates SRAM-bound from DMA-bound?
- [ ] Can I list 5 boundary shapes to test, and why?
- [ ] Can I describe one failing scenario as a signal path, with the assertion that catches it?
