# Lesson 02 · Metrics & evaluation

9 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Latency vs throughput](#l02-01-latency-vs-throughput)
2. [Speedup](#l02-02-speedup)
3. [Benchmarks and benchmark suites](#l02-03-benchmarks-and-benchmark-suites)
4. [Summarising performance: geometric mean](#l02-04-summarising-performance-geometric-mean)
5. [Iron law of performance](#l02-05-iron-law-of-performance)
6. [Iron law with different instruction types](#l02-06-iron-law-with-different-instruction-types)
7. [Amdahl’s law](#l02-07-amdahls-law)
8. [Lhadma’s law](#l02-08-lhadmas-law)
9. [Law of diminishing returns](#l02-09-law-of-diminishing-returns)

---

## L02-01 Latency vs throughput

*Vid 25–28*

> Latency = time for one job. Throughput = jobs finished per second. Once jobs overlap, throughput ≠ 1 / latency.

**Concepts**

- **Latency**: start-to-finish time of one operation.
- **Throughput**: operations completed per unit time.
- Pipelining and replication raise throughput without reducing latency (5-stage example: latency 20 ns, one result every 4 ns).
- **Little’s law** links them: items in flight N = throughput λ × latency L.

**Numbers & formulas:** `N = λ · L` · `pipelined: thr = 1 / stage time`

**Worked**

| Problem | Answer |
| --- | --- |
| 64 GB/s of 64 B lines at 100 ns latency: outstanding misses? | 10⁹/s × 100 ns = 100 |

**Verification lens**

- Perf checks cover both: per-op latency (load-to-use, branch redirect) and sustained bandwidth.
- Little’s law sizes stress tests: to reach peak bandwidth the test must keep N requests in flight; to find full-queue bugs push past it.

**Interview**

<details><summary>Your LSU has 16 MSHRs and memory latency is 160 ns. Max miss bandwidth with 64 B lines?</summary>

λ = N / L = 16 / 160 ns = 0.1 lines/ns = 6.4 GB/s per core. Adding bandwidth needs more MSHRs or lower latency.

</details>

---

## L02-02 Speedup

*Vid 29–34*

> Speedup of X over Y = time(Y) / time(X) = throughput(X) / throughput(Y).

**Concepts**

- Speedup **> 1**: X is faster. **< 1**: X is slower.
- Use old/new for times, new/old for throughputs. Mixing them inverts the answer.
- “33% faster” (speedup 1.33) means 25% less time, not 33% less.

**Numbers & formulas:** `S = T_old / T_new` · `S = Thr_new / Thr_old`

**Worked**

| Problem | Answer |
| --- | --- |
| Old 40 s, new 30 s | 1.33× faster, 25% less time |

**Check your notes**

- Your Vid 51 note writes speedup as new / old time; it should be old / new.

**Verification lens**

- Perf regressions are reported as speedups against a baseline build; agree on the direction in the dashboard or you will chase phantom regressions.

**Interview**

<details><summary>Test went from 40 s to 50 s. Speedup and slowdown?</summary>

Speedup = 40/50 = 0.8. It is 1.25× slower (25% more time).

</details>

---

## L02-03 Benchmarks and benchmark suites

*Vid 35–40*

> Performance needs a workload; benchmarks are agreed programs plus inputs, grouped into suites.

**Concepts**

- Real user workloads vary and are hard to collect, so we use **benchmarks**.
- A suite holds many programs, each representing a class of applications.
- **Standards bodies**: SPEC (CPU and engineering, processor-bound), TPC (databases, servers, transactions), EEMBC (embedded).

| Type | Code from | Use | Weakness |
| --- | --- | --- | --- |
| Real applications | full real apps | most representative | need OS, I/O, compiler |
| Kernels | hot loop of a real app | prototypes, early silicon | miss the rest of the app |
| Synthetic | written to resemble apps | design studies | not for reporting |
| Peak | none | marketing | says nothing about real code |

**Worked**

| Problem | Answer |
| --- | --- |
| Uses real application code but not all of it | application kernel |

**Verification lens**

- Pre-silicon perf runs kernels and sampled traces (SimPoints) on RTL and emulation; full apps are too long.
- Real code also finds functional bugs random tests miss: OS boot, context switches, page faults under load.

**Interview**

<details><summary>Random tests all pass. Why still boot Linux on emulation?</summary>

Real software builds long, realistic sequences: TLB shootdowns, interrupts during system calls, many context switches, long-lived cache state. Random generators rarely build that depth.

</details>

---

## L02-04 Summarising performance: geometric mean

*Vid 41–43*

> Never average ratios. Use the ratio of total or mean times, or the geometric mean of speedups.

**Concepts**

- Mean of times: 12 / 8 = **1.5×**. Mean of speedups (1.63) is **wrong**.
- Geometric mean of speedups = ratio of geometric means of times = **1.456×**.
- Only the geometric mean gives the same ranking whichever machine is the reference.
- Quiz: speedups 2 and 8 with unknown times → GM = **4×**.

| App | X (s) | Y (s) | Speedup |
| --- | --- | --- | --- |
| A | 9 | 18 | 2.0 |
| B | 10 | 7 | 0.7 |
| C | 5 | 11 | 2.2 |
| Mean | 8 | 12 | 1.5 |
| Geo mean | 7.66 | 11.15 | 1.456 |

**Numbers & formulas:** `GM = (Πxᵢ)^(1/n)` · `GM(Sᵢ) = GM(T_Y)/GM(T_X)`

**Verification lens**

- Perf dashboards summarise suites with GM, but GM hides a single large regression. Always show per-test outliers next to the summary.

**Interview**

<details><summary>Why geometric mean for speedups?</summary>

Ratios multiply. GM of ratios equals ratio of GMs, so the result does not depend on which machine you normalise to; arithmetic mean does.

</details>

---

## L02-05 Iron law of performance

*Vid 44–46*

> CPU time = instructions × cycles per instruction × time per cycle.

**Concepts**

- **Instruction count**: algorithm, compiler, ISA.
- **CPI**: ISA and processor design.
- **Clock period**: processor design, circuit design, transistor physics.
- Simple ISAs need more instructions but can have lower CPI and shorter cycles. A good processor balances CPI against cycle time; a good ISA balances instruction count against CPI.
- Quiz: 3 B instructions, CPI 2, 3 GHz → **2 s**.

**Numbers & formulas:** `T = IC × CPI × T_clk` · `IPC = 1 / CPI`

**Worked**

| Problem | Answer |
| --- | --- |
| 3 B instr × 2 CPI / 3 GHz | 2 s |

**Verification lens**

- Retired-instruction and cycle counters feed every CPI analysis, so verify PMU counters against the ISS retire count.
- CPI stacks (where cycles go) come from stall-reason counters; check they add up to total cycles.

**Bugs that ship**

- Counter off by one on faulting or interrupted instructions
- Fused µops counted once instead of twice
- Counter overflow interrupt lost or late

**Interview**

<details><summary>How do you verify the instructions-retired counter?</summary>

Compare with the ISS’s retire count every N instructions. Cover faults, interrupts, fused ops, string or repeat ops, debug single-step, privilege filtering and overflow interrupts.

</details>

---

## L02-06 Iron law with different instruction types

*Vid 47–49*

> CPU time = Σ (ICᵢ × CPIᵢ) × clock period.

**Concepts**

- Each instruction class has its own CPI; sum cycles per class, then multiply by the period.
- Quiz: 50 B instructions at 4 GHz.

| Class | Count | CPI | Cycles |
| --- | --- | --- | --- |
| Branch | 10 B | 4 | 40 B |
| Load | 15 B | 2 | 30 B |
| Store | 5 B | 3 | 15 B |
| Int | 20 B | 1 | 20 B |
| Total | 50 B | 2.1 avg | 105 B |

**Numbers & formulas:** `CPI_avg = Σ fᵢ·CPIᵢ`

**Worked**

| Problem | Answer |
| --- | --- |
| 105 B cycles / 4 GHz | 26.25 s |

**Verification lens**

- Coverage by instruction class mirrors this table: each class needs operand corners and hazard crosses. Weight regression time toward classes with most cycles and most complexity (loads, branches).

**Interview**

<details><summary>Average CPI here?</summary>

105 B cycles / 50 B instructions = 2.1.

</details>

---

## L02-07 Amdahl’s law

*Vid 50–54*

> Speedup = 1 / ((1 − f) + f / s). Make the common case fast.

**Concepts**

- **f** = fraction of original **time** the enhancement affects (not fraction of instructions). **s** = speedup of that part.
- Branch CPI 4 → 2 in the mix 40/20/30/10%: CPI 2.1 → 1.7 → **1.24×**.
- 20× on 10% of time → 1.105×. 1.6× on 80% → **1.43×**. Even infinite speedup on 10% caps at 1.11×.
- Quiz: branch CPI 4→3 (1.05×), clock 2→2.3 GHz (**1.15×**, affects 100%), store CPI 3→2 (1.03×). Pick the clock.

**Numbers & formulas:** `S = 1/((1−f)+f/s)` · `S_max = 1/(1−f)`

**Worked**

| Problem | Answer |
| --- | --- |
| Branch CPI 4→2 | 1.24× |
| 20× on 10% | 1.105× |
| 1.6× on 80% | 1.43× |
| Clock +15% | 1.15× |

**Check your notes**

- Vid 54 option 1 should read “reduce branch CPI from 4 to 3”.

**Verification lens**

- Amdahl applies to verification effort too: speeding up a simulator component that is 10% of wall time cannot give more than 1.11×. Profile the regression before optimising it.

**Interview**

<details><summary>Parallel part is 95% of runtime. Max speedup with infinite cores?</summary>

1 / 0.05 = 20×.

</details>

---

## L02-08 Lhadma’s law

*Vid 55*

> While making the common case fast, do not make the uncommon case much slower.

**Concepts**

- Amdahl spelled backwards.
- 2× on 90% of time but the other 10% gets 10× slower: 1 / (0.9/2 + 0.1×10) = **0.69×**, an overall slowdown.
- A small part made much worse can erase a large gain.

**Worked**

| Problem | Answer |
| --- | --- |
| 2× on 90%, 10× slower on 10% | 0.69× |

**Verification lens**

- Corner-case paths (replays, serialising instructions, uncacheable accesses, rare exceptions) get slow-path implementations. Track their performance too: a perf bug there can be a 10× slowdown in a real workload.

**Interview**

<details><summary>Example of Lhadma’s law in a CPU?</summary>

Aggressive memory speculation that wins on average but triggers a full pipeline flush on every violation: a workload with frequent store-load aliasing gets slower. Hence store-set predictors.

</details>

---

## L02-09 Law of diminishing returns

*Vid 56–57*

> Each repeat improvement of the same part buys less, because that part shrinks as a share of time.

**Concepts**

- Gen 1: halves A and B. Gen 2: 2× on B → **1.33×**.
- Gen 3: 2× on B again → only **1.20×**, because B is now 1/3 of time.
- Re-measure what dominates after each improvement and move effort there.

**Worked**

| Problem | Answer |
| --- | --- |
| 1/(0.5+0.5/2) | 1.33× |
| 1/(0.67+0.33/2) | 1.20× |

**Verification lens**

- Coverage closure behaves the same way: the last few percent of bins cost the most. Re-prioritise by where bugs are being found (bug rate per unit), not by the raw percentage.

**Interview**

<details><summary>Coverage is at 96% with 2 weeks left. How do you decide what to do?</summary>

Rank holes by risk (new logic, complex state, recent bug clusters), waive provably unreachable bins, use formal for small hard-to-hit control states, and spend remaining sim time on targeted stress rather than more random seeds.

</details>
