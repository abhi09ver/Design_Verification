# Lesson 03 · Pipelining

8 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Pipelining basics](#l03-01-pipelining-basics)
2. [Pipeline CPI and stalls](#l03-02-pipeline-cpi-and-stalls)
3. [Pipeline flushes](#l03-03-pipeline-flushes)
4. [Control dependences](#l03-04-control-dependences)
5. [Data dependences: RAW, WAR, WAW](#l03-05-data-dependences-raw-war-waw)
6. [Dependences vs hazards](#l03-06-dependences-vs-hazards)
7. [Handling hazards: flush, stall, forward](#l03-07-handling-hazards-flush-stall-forward)
8. [How many stages?](#l03-08-how-many-stages)

---

## L03-01 Pipelining basics

*Vid 59–65*

> Overlap instructions in stages: latency stays the same, throughput approaches one per cycle.

**Concepts**

- Laundry analogy: wash, dry, fold overlap for different loads.
- 5-stage MIPS-style pipe: **IF ID EX MEM WB**.
- Unpipelined: one instruction per 20 ns. Pipelined (4 ns stages): still 20 ns latency, but one result every 4 ns.
- Quiz: 10 instructions on a 5-stage pipe: **50** cycles unpipelined, **5 + 9 = 14** pipelined.

**Numbers & formulas:** `cycles = k + (n − 1)` · `ideal speedup → k`

**Worked**

| Problem | Answer |
| --- | --- |
| 10 instr, 5 stages | 50 vs 14 cycles |

**Verification lens**

- Each stage boundary is a valid/stall/flush handshake; that handshake is the first thing to assert in any pipeline (valid held while stalled, data stable while stalled, flush clears valid).

**Interview**

<details><summary>Why isn’t speedup exactly k?</summary>

Pipeline fill and drain, latch overhead per stage, unequal stage delays (slowest sets the clock), and stalls or flushes from hazards.

</details>

---

## L03-02 Pipeline CPI and stalls

*Vid 66–67*

> Ideal pipelined CPI is 1; stalls push it above 1.

**Concepts**

- A stall holds earlier stages and inserts a bubble (no-op) downstream.
- Classic case: **load then use**. Without forwarding, with write-first-half / read-second-half register file: **2-cycle stall**.
- Every stall and flush adds to CPI: CPI = 1 + stall cycles per instruction.

**Numbers & formulas:** `CPI = 1 + stalls/instr`

**Check your notes**

- Vid 66: pipeline CPI is ≥ 1, and usually **greater** than 1 because of stalls (the notes say “less than”).

**Verification lens**

- Stalls are where data must stay stable: assert that a stalled stage’s payload does not change and that its valid does not drop unless flushed.

**Bugs that ship**

- Stalled stage’s data overwritten by upstream when the stall and the write enable disagree
- Bubble carries stale register-write enable

**Interview**

<details><summary>Write the basic stall assertion.</summary>

`assert property (@(posedge clk) disable iff(rst) v_q && stall && !flush |=> v_q && $stable(data_q));`

</details>

---

## L03-03 Pipeline flushes

*Vid 68*

> When the next PC was guessed wrong, the wrongly fetched instructions become bubbles.

**Concepts**

- Branch target known at the end of EX (stage 3): instructions fetched in IF and ID are wrong-path.
- They are invalidated (flushed) and the bubbles flow through the pipe.
- Penalty = number of stages before the branch resolves (2 here).

**Numbers & formulas:** `penalty = resolve stage − 1`

**Verification lens**

- Flush must kill exactly the younger instructions: none older, all younger, including ones being written into a stage in the same cycle. Cover flush in the same cycle as a stall, an exception, and a second branch.

**Bugs that ship**

- Wrong-path instruction in the cycle of the flush still writes the register file
- Two flushes in consecutive cycles: second uses the first’s redirect PC

**Interview**

<details><summary>How do you check that a flush is exact?</summary>

Tag every instruction with a sequence number. On flush with id F, assert no surviving valid instruction has id > F and every instruction with id ≤ F is untouched. Co-sim confirms the architectural result.

</details>

---

## L03-04 Control dependences

*Vid 69–71*

> Instructions after a branch depend on its outcome; until it resolves, fetch is a guess.

**Concepts**

- Both paths after `BEQ` are control-dependent on it.
- 20% branches, slightly over half taken, 2-cycle penalty on taken: CPI ≈ 1 + 0.1 × 2 = **1.2**.
- Quiz: 25% taken branch/jump, 10 stages, target in stage 6: CPI = 1 + 0.25 × 5 = **2.25**.
- Deep pipelines resolve late, so they need good prediction.

**Numbers & formulas:** `CPI = 1 + f_taken × penalty`

**Worked**

| Problem | Answer |
| --- | --- |
| 20% br, ~half taken, 2-cycle penalty | 1.2 |
| 25% taken, resolve in stage 6 | 2.25 |

**Verification lens**

- Control hazards are handled by flushing, so the checker that matters is flush exactness plus co-sim. Random code generators must place branches densely and make branch targets other branches.

**Interview**

<details><summary>How does pipeline depth change the branch penalty?</summary>

Penalty grows with the number of stages before resolution. Modern cores resolve 10–20 stages in, so even 95% accuracy costs a lot.

</details>

---

## L03-05 Data dependences: RAW, WAR, WAW

*Vid 72–73*

> RAW is a true dependence; WAR and WAW are name conflicts. RAR is no dependence.

**Concepts**

- Dependences are a property of the **program**.
- WAR and WAW disappear with renaming (later lesson); RAW never does.

| Type | Pattern | Also called | Real? |
| --- | --- | --- | --- |
| RAW | write R1 → read R1 | true / flow | yes, data must flow |
| WAR | read R1 → write R1 | anti | name only |
| WAW | write R1 → write R1 | output | name only |
| RAR | read → read | — | not a dependence |

**Verification lens**

- Random generators need a dependency-distance knob: distance 1, 2, 3 and far, for each producer/consumer class. Coverage should cross RAW/WAR/WAW with that distance.

**Interview**

<details><summary>Which dependence types can renaming remove and why?</summary>

WAR and WAW: they only exist because two values share one register name. Giving each write a new physical register removes the conflict. RAW carries a value and must be respected.

</details>

---

## L03-06 Dependences vs hazards

*Vid 75–76*

> A hazard is a dependence that the pipeline can actually break. Program plus pipeline decide it.

**Concepts**

- In the in-order 5-stage pipe, WAW and WAR are **never** hazards: writes happen in order in WB and reads happen early in ID.
- RAW is a hazard only when the consumer reads before the producer writes.
- With a split-cycle register file, RAW at distance **≥ 3** is safe; distances 1 and 2 are hazards.
- Not every true dependence is a hazard.

**Numbers & formulas:** `hazard ⇔ distance < 3 (5-stage, split RF)`

**Verification lens**

- Hazards are microarchitectural, so derive coverage from the pipeline: list for each stage pair which distances create a hazard, and make each a bin. When the pipeline changes, the hazard bins change.

**Interview**

<details><summary>Can WAR be a hazard?</summary>

Not in the in-order 5-stage pipe. It can in out-of-order or multi-cycle pipelines where a younger write can complete before an older read, which is why those designs rename.

</details>

---

## L03-07 Handling hazards: flush, stall, forward

*Vid 78–80*

> Control hazards: flush. Data hazards: forward if the value exists, otherwise stall.

**Concepts**

- **Control** hazard: flush the wrong-path instructions; stalling or forwarding cannot help.
- **Data** hazard: forward the value from where it is in the pipe to where it is needed.
- Forwarding fails when the value is not produced yet (load-use): stall until it exists, then forward.
- Quiz: instead of stalling 2 cycles, stall 1 and forward.

**Numbers & formulas:** `ALU→ALU: 0 stall` · `load→use: 1 stall + forward`

**Verification lens**

- Forwarding priority must pick the **youngest older** producer. Assert it and cover two in-flight writers to the same register, plus x0/zero-register which must never be forwarded as non-zero.

**Bugs that ship**

- Forward from the older of two writers
- Forward from a bubble whose destination field is stale
- Stall and flush in the same cycle leave a wrong-path instruction alive

**Interview**

<details><summary>Write the forwarding-priority assertion.</summary>

`assert property (ex_v && mem_v && ex_rd==rs1 && mem_rd==rs1 && rs1!=0 |-> op1==ex_result);`

</details>

---

## L03-08 How many stages?

*Vid 81–82*

> More stages shorten the cycle but raise CPI and power. Performance alone peaks near 30–40; real chips use 10–15.

**Concepts**

- More stages → shorter clock period, but more hazard stalls and bigger flush penalties.
- Considering performance only, the optimum is about **30–40** stages.
- Adding power (more latches, more speculation wasted): about **10–15** stages in practice.
- Every later lesson builds on this pipeline.

**Numbers & formulas:** `perf-optimal ≈ 30–40` · `perf+power ≈ 10–15`

**Verification lens**

- Deeper pipelines mean more in-flight state, more forwarding paths and longer flush windows. Scale stress tests (flush density, hazard density) with depth.

**Interview**

<details><summary>Why did Pentium 4 style very deep pipelines fall out of favour?</summary>

Branch mispredict penalties and power grew faster than frequency gains; per-cycle work dropped and power hit limits.

</details>
