# Challenge 14: Formal Verification — What It Proves, Where It Fits, and How to Make It Converge

> **Level:** Fresher → Senior DV interview
> **Topics:** model checking vs. simulation, property checking vs. equivalence checking, formal apps, proof results (proven / CEX / bounded), assumptions and over-constraint, abstraction and convergence, symbolic data-integrity checking, formal coverage and sign-off, combining formal with simulation
> **Related:** [08 – SVA](08-sva-assertions.md), [09 – Coverage Plateau](09-coverage-plateau-closure.md), [13 – Beyond the Happy Path](13-sva-beyond-happy-path.md)

---

## 1. The Post (summary)

A LinkedIn post calls formal "the backbone of a zero-defect silicon strategy" and claims:

1. Run property checks on blocks as soon as they're locked; "at **Intel's 7nm** node" this "cut regression cycles by **30%**".
2. NVIDIA uses JasperGold to "**prove compliance with the PCIe and NVLink specifications across all clock domains**, **eliminating the need for separate compliance testbenches**", saving "2–3 weeks".
3. "**Synopsys' Formality** can generate proof obligations that **feed back into constrained-random seeds**, raising functional coverage by 10–15%."
4. "Map your **top-level interfaces** to formal properties and lock them before any RTL is handed to simulation."

The good idea: **start formal early on blocks, plan it as a milestone, and show its progress on the dashboard.** The rest is wrong.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| "Zero-defect silicon" | No method gives that. Formal proves **the properties you wrote, under the assumptions you wrote**. Missing properties or wrong assumptions mean bugs can still escape |
| Prove **full PCIe/NVLink compliance** with formal, **no compliance testbenches** | Full protocol stacks (link training, flow control, physical layer, analog) are far beyond what formal can prove end-to-end. Formal is used on **specific blocks and rules** (e.g., transaction-layer ordering, credit counters, interface handshakes). Compliance still needs **simulation VIP, compliance suites, and post-silicon** testing |
| "Across all clock domains" | Multi-clock formal is possible but costly; CDC correctness is normally checked with **structural CDC tools** plus targeted formal on synchronizer protocols |
| **Formality** generates proof obligations for **random seeds** | **Formality is an equivalence checker** (RTL vs. netlist). It doesn't do property checking, and nothing "feeds proof obligations into seeds". Seeds don't work that way (Challenge 09) |
| Formal on **top-level interfaces** before simulation | Formal works on **blocks** (thousands to low millions of state bits with abstraction), not full chips. Top-level checks are simulation/emulation |
| Intel 7nm 30%, 2–3 weeks, 10–15% | Unsourced numbers (and "Intel 7nm" isn't a node name Intel uses) |

---

## 3. Background a Fresher Must Know

### 3.1 Simulation vs. formal in one picture

```
Simulation:  you pick inputs → design runs → check results
             explores the paths YOUR TESTS chose

Formal:      tool considers ALL legal input sequences (from reset, within assumptions)
             and mathematically checks: can any of them violate the property?
```

| | Simulation | Formal (property checking) |
|---|---|---|
| Inputs | Testbench stimulus | All values allowed by **assumptions** |
| Result | Pass/fail on the tests run | **Proven** for all inputs, or a **counterexample** trace |
| Strength | Big designs, datapaths, end-to-end | Control logic, corner cases nobody thought of |
| Weakness | Only finds what stimulus reaches | **State-space explosion** on large/deep designs |
| Needs a testbench? | Yes | No: properties + assumptions only |

### 3.2 Types of formal (know the names)

| Type | Compares / proves | Tool examples |
|---|---|---|
| **Formal property verification (FPV)** | Design vs. SVA properties | Cadence Jasper, Synopsys VC Formal, Siemens Questa Formal |
| **Logic equivalence checking (LEC)** | RTL vs. synthesized netlist (same function) | Synopsys **Formality**, Cadence **Conformal** |
| **Sequential equivalence (SEC)** | Two RTL versions with different timing/structure (e.g., after clock gating or retiming) | Apps in the FPV tools |
| **Formal apps** | Pre-packaged checks: connectivity, X-propagation, register access, coverage unreachability, deadlock, security paths | Built into the FPV tools |

Interview tip: "Formality is property checking" is a red flag; know that **LEC is a different job**.

### 3.3 The three answers a formal tool gives

| Result | Meaning | Action |
|---|---|---|
| **Proven** | Holds for every reachable state under the assumptions | Check it's not vacuous or over-constrained (Section 5) |
| **CEX (counterexample)** | A trace from reset that breaks it | Debug like a sim failure: RTL bug, property bug, or missing assumption? |
| **Bounded / inconclusive** | No failure found up to depth *N*, but not proven | Is *N* deep enough? Compare to the design's **sequential depth** (cycles needed to reach all interesting states). Improve convergence (Section 6) |

---

## 4. Where Formal Fits Best

**Great fits:** arbiters (fairness, mutual exclusion, starvation), FIFOs and credit counters, FSMs and handshakes, interrupt controllers, cache-coherence protocol controllers (at block level), register blocks (connectivity/access), clock-gating equivalence, deadlock/livelock checks, security (no path from secret to output).

**Poor fits (use simulation):** large datapaths (multipliers, floating point: use specialized datapath formal or simulation), full SoC, deep pipelines with huge memories, analog/mixed-signal.

**When to start:** as soon as a block's RTL compiles. **Designer-level formal** (designer writes a few assertions and runs them in the first weeks) finds bugs before any testbench exists. That's the real version of the post's "formal early" point.

---

## 5. Assumptions: The Most Important (and Dangerous) Part

Formal explores **all** input values, including illegal ones. `assume` properties limit inputs to legal behaviour:

```systemverilog
// Environment rules for a block's input port (from the spec)
asm_valid_hold: assume property (@(posedge clk) disable iff (!rst_n)
                  in_valid && !in_ready |=> in_valid && $stable(in_data));
asm_no_x:       assume property (@(posedge clk) !$isunknown(in_valid));
```

**Under-constrained** → false counterexamples (illegal inputs) → add the missing assumption from the spec.
**Over-constrained** → the tool skips real scenarios → **false proofs**. This is the dangerous one.

How to catch over-constraint:
- **Covers** on interesting scenarios must be **reachable** (`cover property (in_valid && !in_ready ##1 in_ready);`). An unreachable cover = suspicious assumption.
- Review every assumption against the spec, with the designer.
- **Assume-guarantee**: an assumption on block A's input should be **asserted** on block B's output that drives it (in B's formal run or in integration simulation). Then the assumption is itself verified.

---

## 6. Convergence: Making Proofs Finish

Real blocks often give "bounded" instead of "proven". Techniques:

| Technique | Idea | Example |
|---|---|---|
| **Black-boxing** | Remove sub-blocks irrelevant to the property | Black-box a memory or a math unit for a control property |
| **Cut-points** | Make an internal signal a free input | Cut the output of a complex counter; formal treats it as any value |
| **Data-width reduction** | Shrink parameters | 64-bit data → 4-bit; 1024-deep FIFO → 4-deep (bugs usually still show) |
| **Abstraction of counters/timers** | Replace a 2^20-cycle timer with a free "expired" signal | Avoids needing 1M cycles of depth |
| **Helper assertions (invariants)** | Prove simple facts first, use them as lemmas | `count <= DEPTH`, `wr_ptr - rd_ptr == count` |
| **Case splitting** | Prove separately per mode/opcode | One run per arbitration policy |
| **Assume-guarantee decomposition** | Prove sub-blocks separately, compose | |

**Every abstraction must be safe**: it should allow *more* behaviours (over-approximation), not fewer. Cutting a signal is safe for proofs (may give false CEXs); constraining it is not.

---

## 7. Worked Example: Prove a FIFO Never Corrupts Data (symbolic tracking)

Problem: proving "every value comes out in order and unchanged" for **all** data values and **all** positions seems impossible. The standard trick: track **one arbitrary item**, chosen by the formal tool.

```systemverilog
module fifo_formal_chk #(parameter int W = 8, DEPTH = 4)
  (input logic clk, rst_n, push, pop,
   input logic [W-1:0] in_data, out_data,
   input logic [$clog2(DEPTH+1)-1:0] occupancy,   // from RTL
   input logic         sym_select,               // undriven: formal picks freely
   input logic [W-1:0] sym_data);                // undriven: formal picks freely

  default clocking @(posedge clk); endclocking
  default disable iff (!rst_n);

  asm_sym_stable: assume property ($stable(sym_data));   // fixed for the whole trace

  logic tracking;
  logic [$clog2(DEPTH+1)-1:0] ahead;   // entries in front of the tracked item

  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin tracking <= 0; ahead <= 0; end
    else if (!tracking && push && sym_select && in_data == sym_data) begin
      tracking <= 1;
      ahead    <= occupancy - (pop ? 1 : 0);       // items already queued ahead of it
    end
    else if (tracking && pop) begin
      if (ahead == 0) tracking <= 0;               // tracked item leaves this cycle
      else            ahead    <= ahead - 1;
    end

  // The core property: when the tracked item comes out, it is unchanged
  a_data_integrity: assert property (tracking && pop && ahead == 0 |-> out_data == sym_data);

  // Prove the tracking actually happens (not vacuous)
  c_track_full: cover property (tracking && occupancy == DEPTH);
  c_track_out:  cover property (tracking && pop && ahead == 0);
endmodule
```

Why this proves the whole FIFO: formal can choose **any** `sym_data` and **any** push to track (`sym_select`). If the property holds for an arbitrary choice, it holds for **every** item. Small `DEPTH` and `W` keep it converging. (Assumes no same-cycle bypass when empty; adapt `ahead` if your FIFO allows it.)

Add the simple invariants too: `occupancy <= DEPTH`, no push when full accepted, no pop when empty.

---

## 8. Formal Coverage and Sign-off

"Proven" isn't enough: you must show the proofs were **meaningful**.

| Metric | Question it answers |
|---|---|
| **Cover reachability** | Are the interesting scenarios reachable under my assumptions? (catches over-constraint) |
| **Cone-of-influence (COI) coverage** | Which RTL lines are even **in the logic** that my properties depend on? Logic outside every COI is unchecked |
| **Proof-core coverage** | Which logic was actually **needed** for the proofs? Stronger than COI |
| **Mutation / fault-injection coverage** | If I insert a bug here, does some property fail? Logic where mutations survive is unchecked |
| **Bounded depth vs. required depth** | For bounded results: is the reached depth ≥ the design's sequential depth for the scenarios that matter? |

Formal sign-off for a block typically = all properties proven (or bounded with justified depth), all covers reached, reviewed assumptions, and acceptable proof-core/mutation coverage, with simulation covering the rest.

---

## 9. Formal + Simulation Together (the realistic "formal-first" flow)

1. **Designer-level formal** early: basic assertions, FSM, FIFO, handshake properties.
2. **DV formal** on control-heavy blocks: full property sets, signed off with formal coverage.
3. **Simulation** for datapaths, integration, end-to-end flows; the **same assertions** run in simulation (assumes become asserts at integration).
4. **Coverage exchange**: formal **unreachability** results remove impossible items from simulation coverage (Challenge 09); formal **cover traces** give directed tests for hard corners.
5. **LEC** after synthesis and every netlist change, **SEC** after RTL optimisations like clock gating.

---

## 10. Likely Follow-ups (with model answers)

**Q. Formal says "proven". Are you done?**
Not yet. Check covers are reachable (no over-constraint), properties aren't vacuous, assumptions are reviewed, and formal coverage (COI/proof-core/mutation) shows the logic was actually checked.

**Q. You get a counterexample that can't happen in real use. What do you do?**
It's usually a missing assumption. Find the spec rule that forbids that input sequence, add it as an assume, and make sure the driving block asserts it.

**Q. The proof is bounded at depth 20 and won't converge.**
Check required sequential depth; reduce widths/depths, abstract counters, cut-points, black-box irrelevant logic, add helper invariants, or split cases.

**Q. Formal property checking vs. equivalence checking?**
Property checking: design vs. assertions. Equivalence: design vs. another design (RTL vs. netlist), e.g., Formality/Conformal after synthesis.

**Q. How do you prove data integrity through a FIFO with formal?**
Symbolic tracking: a free, stable symbolic value, a free select to choose which push to track, count entries ahead, assert it comes out unchanged.

**Q. What can't formal do well?**
Large datapaths, full-chip scale, very deep sequential behaviour without abstraction, analog. Use simulation or specialised tools there.

---

## 11. Common Fresher Mistakes
- Treating "proven" as "bug-free".
- Adding assumptions until counterexamples disappear without checking the spec.
- No covers → over-constraint goes unnoticed.
- Running formal on a huge block without abstraction and giving up.
- Confusing equivalence checking (Formality/Conformal) with property checking.
- Thinking formal replaces protocol compliance testing.

---

## 12. 60-Second Interview Pitch

> "Formal property checking considers every legal input sequence from reset, so it either proves a property or gives a counterexample, with no testbench. It's strongest on control logic like arbiters, FIFOs, credit counters, FSMs and handshakes, and I start it early, often designer-level, as soon as a block compiles. Equivalence checking is a different job: RTL against netlist with tools like Formality or Conformal.
>
> The key risk is assumptions. Missing ones give false counterexamples; too-strong ones give false proofs. So every assume comes from the spec, has reachable covers, and is asserted on the driving block. For convergence I use smaller widths and depths, cut-points, counter abstraction, black-boxing and helper invariants.
>
> For data integrity I use symbolic tracking of one arbitrary item through the FIFO. And 'proven' only counts once covers, proof-core or mutation coverage and the assumptions are reviewed. Simulation still owns datapaths and integration, and the two exchange results: unreachability prunes simulation coverage, and formal witness traces become directed tests."

---

## 13. Self-Check
- [ ] Can I explain proven vs. CEX vs. bounded, and what to do with each?
- [ ] Can I explain under- vs. over-constraint and how covers catch over-constraint?
- [ ] Can I list 5 convergence techniques?
- [ ] Can I explain the symbolic FIFO tracking trick?
- [ ] Can I explain why Formality isn't property checking and why formal doesn't replace PCIe compliance?

---

## 14. Addendum: State-Space Estimates, Induction, and How Equivalence Checking Really Works

A second formal post is closer to correct than most, but gets the numbers and the equivalence-checking flow wrong.

| Claim | Reality |
|---|---|
| Data abstraction gives "a **10× reduction**" | For a FIFO, removing or shrinking data reduces the state space by **many orders of magnitude** (see 14.1), not 10× |
| Equivalence: "partition into combinational blocks and run **directed** equivalence, then lift sequential logic into an **undirected** proof" | Not real terminology. LEC works by **mapping key points** and comparing **combinational cones** between them; **sequential** differences need **SEC** (14.3) |
| Run **Conformal** on an open-source core | Conformal and Formality are commercial. Open-source options: **Yosys** equivalence passes or a **miter** checked with **SymbiYosys** |
| "Scan interview debriefs for phrasing" | Same advice as Challenge 20: use your own words and real experience |

### 14.1 The FIFO state-space estimate (a classic interview exercise)

FIFO: depth 8, 32-bit data.

| Part | Bits | States |
|---|---|---|
| Storage: 8 × 32 | 256 | 2^256 |
| Read pointer, write pointer (3 bits each) | 6 | 2^6 |
| Full flag (or a 4-bit count) | 1 | 2^1 |
| **Total** (upper bound) | **263** | **~2^263** |

Abstractions:
- **Control-only** (cut the data: storage becomes free/irrelevant for control properties such as "no overflow"): ~2^7 = **128** states. Reduction ≈ 2^256.
- **Data-width reduction** (32 → 1 bit): storage 2^8, total ~2^15.
- **Symbolic tracking of one item** (Section 7): proves data integrity for **all** values while the solver reasons about one tracked entry + a counter.

Two nuances that impress interviewers:
1. These are **upper bounds**: what matters is the **reachable** state space (e.g., pointers and count are correlated, so fewer states are reachable).
2. Modern engines (SAT-based BMC, **IC3/PDR**, BDDs) **don't enumerate states**; they reason symbolically. The estimate explains *why* proofs get hard, not how tools work internally.

### 14.2 Bounded proofs vs. k-induction
- **BMC (bounded model checking):** "no failure within k cycles from reset". Finds bugs; proves nothing beyond k.
- **k-induction:**
  1. *Base case:* property holds for the first k cycles from reset (BMC).
  2. *Inductive step:* if the property holds for **any** k consecutive cycles, it holds in the next one.
  - The step often **fails on unreachable states** (e.g., `count != wr_ptr - rd_ptr`), giving a "counterexample" that can't happen from reset. Fix by adding **helper invariants** (strengthening), e.g., `assert property (count == wr_ptr - rd_ptr);`, then using them as lemmas.
- **IC3/PDR:** the engine that learns these invariants automatically; it's often the default for full proofs.
- **Symmetry reduction:** for identical components (e.g., 8 identical requesters of an arbiter), prove for one representative and argue by symmetry, or the tool exploits it directly.

### 14.3 Equivalence checking, correctly

**LEC (combinational equivalence)**: e.g., RTL vs. synthesized netlist.
1. **Setup:** read both designs; set constraints (e.g., scan/test mode off); black-box the same blocks on both sides (memories, analog).
2. **Mapping:** match **key points**: inputs, outputs, flops, black-box pins.
3. **Compare:** prove each mapped point's **combinational logic cone** is equivalent.
4. **Debug** non-equivalences: unmapped points, wrong constraints, real synthesis issues.

**SEC (sequential equivalence)**: when the state elements don't map one-to-one (retiming, pipelining, clock gating, FSM re-encoding). The tool proves the outputs match over time from reset.

**X and don't-cares** (a real interview trap):
- An RTL `default: out = 'x;` tells synthesis "anything is fine here". LEC treats X in the **reference** (golden) design as a **don't-care**, so the netlist can be anything there and still be "equivalent".
- That's legal, but it can hide **simulation/synthesis mismatch**: RTL simulation shows X (or some value), silicon does something else. Review X assignments and run **X-propagation** checks (Challenge 13).

**ALU vs. a behavioural model:**
- If the model is SystemVerilog RTL: **SEC** (or LEC if both are combinational with mapped I/O).
- If the model is **C/C++**: **C-to-RTL / datapath equivalence** tools (vendor datapath-formal apps).
- **Multipliers and dividers** are hard for SAT-based engines; datapath-specific engines or decomposition are used.

---

## 15. Addendum: Formal in CI, and Another Round of Myths

| Claim | Reality |
|---|---|
| Jasper, VC Formal and Questa Formal "**each excel at one layer**", so use a **mixed-tool strategy** | All three are full formal platforms. Teams usually **standardize on one** (licences, setup and expertise are expensive to duplicate); a second tool is sometimes used to cross-check critical proofs |
| A formal layer for "**end-to-end constraints spanning clock-domain crossings**" | CDC correctness is mainly checked with **structural CDC tools**, plus targeted formal on synchronizer handshakes (Section 2). End-to-end multi-clock proofs are hard to converge |
| Formal gives "a **12% increase in toggle coverage**" | Toggle coverage is a **simulation** metric. Formal contributes **unreachability** results (exclusions) and **cover witnesses** (Challenge 09, Section 6) |
| "Formal failures caught **before the first simulation run**" | Good when designer-level formal starts early (Section 4). But it complements simulation; it doesn't replace it |
| Intel 30%/2.5×, IBM 45%, NVIDIA/AMD 25%, "15% of budget" | Unsourced company statistics |

### 15.1 Running formal in CI (the realistic version)

Formal proofs don't have a fixed runtime, and results can change from **proven** to **bounded** when the RTL changes. So formal CI is set up differently from simulation CI:

| Run | What | Time limit | Gate |
|---|---|---|---|
| **Per commit** | Small set of fast properties on changed blocks (handshakes, FIFO invariants, one-hot) | Minutes | Any **new CEX** fails the commit |
| **Nightly** | Full property set per block, with saved engine settings | Hours | CEX → bug triage; **proven → bounded** or **depth dropped** → investigate |
| **Weekly / milestone** | Full proofs + formal coverage (cover reachability, proof core) | Long | Feeds sign-off (Section 8) |

Track per property: **status** (proven / bounded with depth / CEX / covers reached) and **runtime**. A property that used to be proven and is now bounded is a **regression**, even if nothing failed: something in the RTL made the proof harder, or an assumption changed.
