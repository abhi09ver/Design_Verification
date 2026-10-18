# Lesson 10 · Compiler ILP

6 sheets. Generated from the [flash sheets](../html/flash-sheets/index.html); edit the data files there, then re-run `node hpca/tools/export_markdown.js`.

1. [Tree height reduction](#l10-01-tree-height-reduction)
2. [Instruction scheduling](#l10-02-instruction-scheduling)
3. [Scheduling across branches](#l10-03-scheduling-across-branches)
4. [Loop unrolling](#l10-04-loop-unrolling)
5. [Function inlining](#l10-05-function-inlining)
6. [Software pipelining and trace scheduling](#l10-06-software-pipelining-and-trace-scheduling)

---

## L10-01 Tree height reduction

*Compiler ILP intro · tree height reduction*

> The compiler can shorten dependence chains by regrouping associative operations.

**Concepts**

- Two ways the compiler helps: break long dependence chains; bring independent instructions within reach of the hardware window.
- `r1+r2−r3+r4−r5+r6−r7`: chain of 6 dependent ops.
- Regroup: (r1+r2) + (r4+r6) − ((r3+r5)+r7): **3 levels**, ILP = 6/3 = **2**.
- Only valid when the math is associative (integer, or floating point with relaxed rules).

**Worked**

| Problem | Answer |
| --- | --- |
| 6 ops in 3 levels | ILP = 2 |

**Verification lens**

- Floating-point regrouping changes rounding. If the compiler does it, the hardware still must produce IEEE results for whatever order it is given; FP verification checks the order the binary specifies, not the source.

**Interview**

<details><summary>Why can’t compilers freely reassociate floating-point sums?</summary>

FP addition isn’t associative under rounding; reordering changes results. It needs a relaxed math flag.

</details>

---

## L10-02 Instruction scheduling

*Instruction scheduling · quiz*

> Reorder independent instructions into stall slots, so a simple in-order core stalls less.

**Concepts**

- Array loop on an in-order core that sees only the next instruction: **10 cycles** per iteration with stalls.
- Move `ADDI R1` up into the load’s stall and use offset −4 in the store: 3 stalls removed.
- Quiz (LW 2 cycles, ADD/SW 1): **8 cycles → 6 cycles** by hoisting the second load.
- Hardware OoO does the same thing at run time; here the compiler does it once.

**Worked**

| Problem | Answer |
| --- | --- |
| Quiz, unscheduled | 8 cycles |
| Scheduled | 6 cycles |

**Verification lens**

- Scheduled code changes register and memory ordering patterns (store with negative offset after an increment). Random generators should emit compiler-like schedules, not only naive code.

**Interview**

<details><summary>Why must the store use offset −4 after moving ADDI R1 above it?</summary>

R1 was already incremented by 4, so the same address is now R1 − 4.

</details>

---

## L10-03 Scheduling across branches

*Scheduling and if-conversion · if-convert a loop?*

> Branches fence scheduling; if-conversion removes them and opens more slots. Loops can’t be if-converted, so we unroll.

**Concepts**

- Without if-conversion, instructions can only move within a basic block.
- If-conversion makes one larger block: more choices to fill stalls, fewer branches to predict.
- If-converting a loop would need a new predicate per iteration and predicate away most of a long loop: impractical.
- The loop equivalent is **loop unrolling**.

**Verification lens**

- Basic-block size in generated tests matters: long branch-free runs stress wide issue; short blocks stress fetch and prediction.

**Interview**

<details><summary>Why does a basic block limit scheduling?</summary>

Moving an instruction across a branch changes which paths execute it; it may be wrong or harmful on the other path.

</details>

---

## L10-04 Loop unrolling

*Loop unrolling · benefits · quiz · downsides*

> Copy the loop body, adjust offsets, update the counter once: fewer instructions and more independent work per iteration.

**Concepts**

- Unroll once: two copies of the body, second uses offset +4, counter steps by 8.
- **Instruction count drops**: 1000 iterations × 5 = 5000 → 500 × 8 = 4000 (loop overhead ADDI + BNE removed half the time).
- **CPI drops** too on a wide in-order core: more independent loads and adds can issue together.
- Quiz: 7000 → 5000 cycles with scheduling → about **3000** unrolled and scheduled.
- Downsides: code size grows; unknown trip counts need a remainder loop.

**Numbers & formulas:** `overhead = counter update + branch`

**Worked**

| Problem | Answer |
| --- | --- |
| Instructions, 1000 iterations | 5000 → 4000 |
| Cycles: base / scheduled / unrolled | 7000 / 5000 / ~3000 |

**Verification lens**

- Unrolled code produces many loads and stores to adjacent addresses in one window: good stress for store-to-load forwarding and bank conflicts.

**Interview**

<details><summary>Two benefits and two costs of unrolling?</summary>

Benefits: fewer overhead instructions; more independent work to schedule. Costs: larger code (I-cache pressure); handling trip counts not divisible by the unroll factor.

</details>

---

## L10-05 Function inlining

*Function call inlining · quiz*

> Replace the call with the function body: no call/return, no argument shuffling, better scheduling.

**Concepts**

- Saves two jumps, calling-convention moves, stack pushes and pops, copying the result.
- Opens scheduling across the old call boundary.
- Small functions benefit most.
- Downside: code bloat. Your example: 10 instructions + return, called twice (13 total) becomes 20.
- Quiz: inlining alone cut 10 → 7 cycles even with no scheduling gain.

**Worked**

| Problem | Answer |
| --- | --- |
| Code size: 13 → 20 instructions | bloat |
| Quiz runtime | 10 → 7 cycles |

**Verification lens**

- Inlined code removes calls, so RAS behaviour in tests changes. Keep a mix of deep call chains in generated code to test the RAS.

**Interview**

<details><summary>When does inlining hurt performance?</summary>

When the bloat overflows the I-cache or micro-op cache, or when a large function is inlined at many sites.

</details>

---

## L10-06 Software pipelining and trace scheduling

*Other IPC-enhancing compiler techniques*

> Software pipelining overlaps iterations like pipeline stages; trace scheduling optimises the common path and fixes up the rare one.

**Concepts**

- **Software pipelining**: each instruction of the loop body is treated as a stage; one iteration’s load overlaps another’s add and another’s store.
- **Trace scheduling**: “if-conversion on steroids”. Pick the common path, schedule it aggressively, insert checks; if the rare path happens, run compensation code.
- Pays only if the common path really is common.

**Verification lens**

- These are compiler techniques, but they matter for CPU DV: they generate unusual instruction patterns (rotating registers, speculative loads with checks) that the hardware must handle.

**Interview**

<details><summary>What hardware features helped Itanium do software pipelining?</summary>

Rotating registers, predication and loop-count registers, so each overlapped iteration used fresh register names without unrolling.

</details>
