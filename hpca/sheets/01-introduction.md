# Lesson 01 · Introduction

7 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [What computer architecture is](#l01-01-what-computer-architecture-is)
2. [Moore’s law: design for the future](#l01-02-moores-law-design-for-the-future)
3. [The memory wall](#l01-03-the-memory-wall)
4. [Speed, cost and power trade-offs](#l01-04-speed-cost-and-power-trade-offs)
5. [Dynamic (active) power](#l01-05-dynamic-active-power)
6. [Static power and the best voltage](#l01-06-static-power-and-the-best-voltage)
7. [Fabrication yield and cost](#l01-07-fabrication-yield-and-cost)

---

## L01-01 What computer architecture is

*Vid 1–5*

> Designing a computer that fits its purpose — and keeps fitting it as technology moves.

**Concepts**

- **Purpose decides “better”**: speed, battery life, size, weight, cost, energy efficiency, security.
- **Two goals**: improve performance (faster, smaller, cheaper, more efficient) and add abilities (3D graphics, debug support, security features).
- **Two levers** it exploits: advances in fabrication technology and in circuit design.
- **ISA** = the contract the programmer sees. **Microarchitecture** = how one chip implements it (pipeline, caches, predictors).
- Same binary, same results on every implementation of an ISA; speed and power may differ.

**Numbers & formulas:** `ISA = architectural state + behaviour` · `µarch = invisible except via time, power, PMU`

**Verification lens**

- Verification has two targets: **architectural equivalence** (matches the ISA) and **microarchitectural intent** (latency, throughput, power).
- Every new “ability” (debug, security, virtualisation) adds spec surface: more CSRs, more modes, more crosses.
- Keep a list of implementation-defined choices; each one needs a decision and a test.

**Interview**

<details><summary>Architecture vs microarchitecture?</summary>

ISA = programmer-visible state and rules (registers, instructions, memory model, exceptions). Microarchitecture = the implementation (pipeline depth, ROB size, cache sizes). Two microarchitectures of one ISA must produce identical architectural results.

</details>

<details><summary>Name something architecturally invisible that DV must still check.</summary>

Branch predictor and prefetcher behaviour, cache replacement, performance counters for non-architectural events, power state. Wrong results there do not break co-sim but break performance or security.

</details>

---

## L01-02 Moore’s law: design for the future

*Vid 6–9*

> Design for the technology you will ship on, not the one you started on.

**Concepts**

- **Moore’s law**: feature size shrinks so transistors per area double every **18–24 months**.
- Architects plan for speed, memory capacity and energy/op to double on the same cadence.
- A design takes years, so a design built only for today’s technology is obsolete at launch.
- Rule of thumb: if the project ships after *T* years, target about **2^T/2×** today’s performance.
- Held from 1971 to the lecture (2007). Since ~2005 **Dennard scaling** ended: frequency flattened, core counts and specialisation took over.

**Numbers & formulas:** `2× transistors / 18–24 mo` · `ship in 4 yr → aim ~4×`

**Verification lens**

- Verification is usually on the critical path of that multi-year schedule.
- Next generation arrives in ~2 years: build parameterised, reusable testbenches (cache sizes, widths, core counts as knobs).
- Scaling widths and counts each generation is where off-by-one and overflow bugs come from.

**Interview**

<details><summary>Why did single-thread frequency stop scaling?</summary>

Dennard scaling ended: voltage could not keep dropping because leakage rises as threshold voltage falls, so power density climbed. Designers moved to multicore, wider cores and accelerators.

</details>

<details><summary>How do you make a testbench survive the next generation?</summary>

Parameterise everything that scales (queue depths, ways, sets, widths, core count), derive coverage bins from parameters, and keep the checker at the architectural boundary so microarchitecture changes need few edits.

</details>

---

## L01-03 The memory wall

*Vid 10*

> Processors got ~2× faster every 2 years; memory latency only ~1.1×. Caches are the stairs over the wall.

**Concepts**

- Instructions per second and memory **capacity** double every 18–24 months.
- Memory **latency** improves only about **1.1× every two years**.
- The gap compounds: after 10 years, ~32× vs ~1.6× (see chart).
- **Caches** are the stairs: small, fast memories that serve most accesses.
- Every later lesson on memory (caches, VM, prefetch, DRAM) is a response to this gap.

**Numbers & formulas:** `CPU ×2 / 2 yr` · `DRAM latency ×1.1 / 2 yr` · `DRAM ≈ 200–300+ core cycles today`

**Verification lens**

- Hiding latency needs many outstanding requests, out-of-order completion and shared state: exactly where races live.
- That is why the memory subsystem (LSU, caches, MSHRs, coherence) usually has the most bugs and the most DV engineers.
- Throttle and randomise memory latency in the testbench; fixed latency hides ordering bugs.

**Interview**

<details><summary>Why are most CPU silicon bugs in the memory system?</summary>

To hide latency the design keeps many requests in flight, completes them out of order, merges and forwards data, and shares lines between cores. Each mechanism adds concurrency and transient states that random tests rarely line up.

</details>

<details><summary>One testbench knob that finds memory-ordering bugs fast?</summary>

Randomised, bursty memory latency per request (including very long and back-to-back short), so responses return in many different orders.

</details>

---

## L01-04 Speed, cost and power trade-offs

*Vid 11–13*

> Each technology step can buy 2× speed at the same cost and power, or the same speed at about half the cost and power.

**Concepts**

- Processor quality = **speed** (instructions/s), **cost** (fabrication), **power** (battery, form factor).
- Per generation choose roughly: **2× / 1× / 1×** (speed / cost / power) or **1.1× / 0.5× / 0.5×**.
- The market decides: phones, laptops and servers pick different points.
- Lecture quiz: the worst laptop chip is **Burnium** (4× speed, 2-minute battery, 2 kg, $5000). Crawlium is extreme but rational for some uses.

| Model | Perf | Battery | Weight | Cost |
| --- | --- | --- | --- | --- |
| Crawlium | 0.1 | 30 h | 12 g | $10 |
| Slowium | 0.5 | 15 h | 50 g | $30 |
| Laptium | 1 | 5 h | 100 g | $100 |
| Fastium | 1.5 | 1 h | 500 g | $200 |
| Hotium | 2 | 15 min | 1.5 kg | $500 |
| Burnium | 4 | 2 min | 2 kg | $5000 |

**Numbers & formulas:** `perf / W` · `perf / $`

**Verification lens**

- Performance and power targets are part of the spec; DV signs off against a perf model and power budgets, not only correctness.
- Features that save power (gating, DVFS) create new modes and transitions that must be verified.

**Interview**

<details><summary>Design A is 1.5× faster but draws 5× power. When is it right?</summary>

Only where power and cooling are not the constraint (some desktops, accelerated servers with headroom). For battery or dense-rack designs perf/W dominates, so A loses. State the metric before choosing.

</details>

---

## L01-05 Dynamic (active) power

*Vid 14–15*

> P = ½ · C · V² · f · α. Voltage is the big lever because it is squared.

**Concepts**

- Two kinds of power: **dynamic** (switching) and **static** (leakage).
- **C** ∝ switched capacitance (roughly chip area). **α** = activity factor (fraction switching per cycle).
- Higher **f** needs higher **V** for transistors to switch in time, so power grows roughly with f³.
- Worked (your notes): shrink lets 2 cores fit in the old area (same C). V × 0.9, f × 1.1 → power 0.81 × 1.1 = **0.89×** for ~2.2× compute.

**Numbers & formulas:** `P_dyn = ½CV²fα` · `V ×0.5 → P ×0.25` · `f ∝ V ⇒ P ∝ f³`

**Worked**

| Problem | Answer |
| --- | --- |
| 2 cores in same area, V×0.9, f×1.1 | 0.89× power, ~2.2× work |

**Verification lens**

- **Clock gating** lowers α. Verify enables never gate a stage holding a valid transaction or an outstanding response.
- Power estimation tools read switching activity from your simulations (SAIF/FSDB), so realistic stimulus matters.
- DVFS adds clock-ratio changes: verify CDC paths and handshakes at every ratio.

**Interview**

<details><summary>Halve V or halve f: which saves more dynamic power?</summary>

Halving V cuts it to a quarter (V²); halving f only halves it. But lower V forces lower f, so in practice both drop together.

</details>

<details><summary>What bug class does clock gating introduce?</summary>

A gated block that still owes a response (lost wake-up), a gate enable computed one cycle late, glitches on gated clocks. Check with assertions: gate only when idle and no pending requests.

</details>

---

## L01-06 Static power and the best voltage

*Vid 16–18*

> Lowering V cuts dynamic power but raises leakage; the best voltage minimises the sum.

**Concepts**

- **Static (leakage)** power flows even when nothing switches.
- Lower V → lower threshold voltage → **more leakage**. So total power is U-shaped in V.
- Quiz (30 W at 1.0 V, 2 GHz): most efficient 0.9 V, 1.8 GHz = **21.9 W**; fastest 1.5 V, 3 GHz = **101.3 W**.
- ~1.67× the speed for ~4.6× the power. This is why chips use several slower cores instead of one very fast core.

**Numbers & formulas:** `0.9²×0.9×30 = 21.9 W` · `1.5²×1.5×30 = 101.3 W`

**Worked**

| Problem | Answer |
| --- | --- |
| P at 0.9 V, 1.8 GHz | 21.9 W |
| P at 1.5 V, 3.0 GHz | 101.3 W |

**Verification lens**

- **Power gating** removes leakage of idle blocks. Verify with power-aware simulation (UPF): isolation clamps, retention save/restore, power-up sequencing.
- Cover traffic arriving during each step of the power-down handshake.

**Bugs that ship**

- Output of a powered-off domain floats into a live one (missing isolation)
- Retained state restored from a stale snapshot
- Interrupt lost while the core was entering sleep

**Interview**

<details><summary>What goes wrong if isolation is missing on a power-gated block?</summary>

Its outputs float to X during power-off; the live logic samples garbage. Power-aware sim shows X propagation; a normal RTL sim shows nothing, which is why UPF simulation is required.

</details>

---

## L01-07 Fabrication yield and cost

*Vid 19–23*

> Defects kill big dies, so cost per good die rises much faster than area.

**Concepts**

- **Yield** = working dies / total dies on a wafer.
- Example: $5000 wafer, 10 defects, each defect kills one die.
- Per generation choose: same chip in less area (cheaper) or twice the chip in the same area (same cost, more capable).
- Quiz: a 100 mm² laptop chip costs **more than 100×** a 1 mm² watch chip, because yield falls with area.

| Die | Per wafer | Good | Cost / good die |
| --- | --- | --- | --- |
| Small (1×) | 400 | 390 | $12.8 |
| Medium (4×) | 96 | 86 | $58.1 |
| Large (16×) | 20 | 10 | $500 |

**Check your notes**

- Large die: $5000 / 10 = **$500** (the notes show $454.5, which is $5000 / 11).

**Verification lens**

- A silicon bug means a respin: millions of dollars and months. That cost is the business case for pre-silicon verification.
- **Chicken bits** (disable bits for features) are the post-silicon escape hatch; each “feature off” mode is a real configuration to verify.
- Yield harvesting (fusing off a bad core or cache way) needs verified reduced configurations.

**Interview**

<details><summary>What are chicken bits and how do you verify them?</summary>

Configuration bits that disable or slow a feature to work around a silicon bug. Run regressions with each bit set; the design must stay correct and make progress in every combination you ship.

</details>
