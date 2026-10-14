# Challenge 09: Coverage Stuck at 85% — Diagnosing the Plateau and Closing It

> **Level:** Fresher → Senior DV interview
> **Topics:** coverage hole classification, over-constraint, coverage model bugs, sampling bugs, test ranking, directed vs. random, reactive/coverage-driven stimulus, formal unreachability and cover traces, exclusions and sign-off
> **Related:** [02 – CRV](02-constrained-random-verification-storytelling.md), [06 – Verification Plan](06-verification-plan.md), [08 – SVA](08-sva-assertions.md)

---

## 1. The Post (summary)

A LinkedIn post says that when random stimulus stalls at 85% functional coverage, you need a "strategic pivot":

1. **Layered stimulus**: directed + constrained random. "**NVIDIA's Hopper** flow uses risk-based **seed-tuning**, weighting seed vectors by historical miss rates, shrinking uncovered space by **~30%**."
2. **Feature-oriented coverage**: map blocks to intent-driven items; "**Intel's 7nm CPU teams**" embed pipeline stalls and speculative windows into coverage; nightly dashboards.
3. **Formal-assisted closure**: "bring in **bounded model checking or equivalence checking**" for hard-to-reach states; "**JasperGold** can generate proof obligations for the top **uncovered assertions**", "**10–15% reduction**" in simulation effort; formal "constrained to the same RTL clock domain, **preserving timing intent**".

Directed + random, feature-oriented coverage, and formal-assisted closure are all **real, correct techniques**. The explanation of *how* they work is mostly wrong.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| NVIDIA Hopper seed weighting, ~30% | Unsourced, and not something to quote. Never present another company's internal flow as fact in an interview |
| "Weight seeds by historical miss rates" | A seed has no meaning by itself. When the testbench or RTL changes, the **same seed produces different stimulus** (random stability). Reusing "good seeds" is fragile. What lasts is changing **constraints, sequences, or tests**. Ranking seeds is useful only to **pick a regression subset** on a frozen snapshot |
| "Intel's 7nm CPU teams" | Name-drop; "Intel 7" is a 10nm-class node. The idea (micro-architectural coverage like stalls and speculation windows) is valid; describe it with your own design |
| **Equivalence checking** for hard-to-reach states | Equivalence checking compares **two designs** (RTL vs. netlist, RTL vs. RTL). It has nothing to do with coverage closure |
| "Proof obligations for the top **uncovered assertions**" | Mixes up coverage and assertions. Formal helps coverage closure in two specific ways: **(1) prove a bin is unreachable** so it can be excluded, **(2) produce a witness trace** showing how to reach it |
| "Constrained to the same clock domain, **preserving timing intent**" | Formal is **cycle-based**: it has no notion of delays/timing. This sentence means nothing technically |
| "10–15% reduction" | Unsourced number |

---

## 3. First Principle: A Plateau Is a Diagnosis Problem, Not a "More Seeds" Problem

When coverage stops growing, **more seeds of the same test give almost nothing**. Each remaining hole has a **cause**. Find the cause, then pick the fix.

### The six causes of a coverage hole

| # | Cause | How you recognise it | Fix |
|---|---|---|---|
| 1 | **Unreachable / illegal** | Spec says it can't happen; tied-off parameter; config not built | Prove (formal or review), **exclude with a written reason** |
| 2 | **Over-constrained stimulus** | A constraint forbids the needed values (e.g., `delay inside {[1:10]}` → never back-to-back) | Relax / move to `soft`, add scenario constraint |
| 3 | **Rare but legal** | Reachable, but needs a long or specific sequence (e.g., FIFO full + error + wrap at the same time) | Bias with `dist`, write a targeted sequence, or a directed test |
| 4 | **Configuration never run** | Bin depends on a mode/parameter no test enables | Add tests/configs to the regression matrix |
| 5 | **Coverage model bug** | Bins defined wrong: impossible cross, wrong range, wrong `iff` | Fix the covergroup; get it reviewed |
| 6 | **Sampling bug** | Event happens on the waveform but bin stays 0: sampled at the wrong time, wrong condition, or covergroup never constructed | Fix the sample point (e.g., sample on transaction complete, from the monitor) |

**Senior insight:** causes 5 and 6 are **testbench bugs**, and they're common. Always check that the scenario really didn't happen (look at the log/waveform) before writing new stimulus.

---

## 4. Step-by-Step Closure Workflow

1. **Merge coverage** from the whole regression (not one test).
2. **Hole report** per covergroup / cross. Sort by **priority from the vplan** (P0 features first), not by bin count.
3. **Classify each hole** into the six causes above. Talk to the designer for anything that might be unreachable.
4. **Check sampling**: pick one hole, find in a log whether the event ever happened. If yes → cause 5/6.
5. **Read the constraints** that drive the related fields. If they forbid it → cause 2.
6. **Pick the fix** (table above).
7. **Rank tests** (coverage grading, e.g. `urg -grade` / ranking in vManager / `vcover ranktest`) to keep the regression efficient once new tests are added.
8. **Re-run and track** the coverage curve per feature on a nightly dashboard.
9. **Review exclusions** with design and get them signed off.

---

## 5. Stimulus Techniques for Rare Holes

### 5.1 Bias, don't just randomize more
```systemverilog
// before: uniform, back-to-back almost never happens
constraint c_delay { delay inside {[0:20]}; }
// after: scenario-biased
constraint c_delay { delay dist {0 := 60, [1:3] :/ 30, [4:20] :/ 10}; }
```

### 5.2 Targeted sequence for a multi-condition corner
Hole: `fifo_full × error_resp × addr_wrap`.
```systemverilog
class full_err_wrap_seq extends base_seq;
  task body();
    repeat (FIFO_DEPTH) `uvm_do_with(req, {delay == 0;})       // fill the FIFO
    `uvm_do_with(req, {inject_err == 1; burst == WRAP;})       // error + wrap while full
  endtask
endclass
```
Still constrained-random in its fields, but **steered** into the corner.

### 5.3 Reactive (coverage-aware) stimulus
A sequence can query coverage at runtime (`cg.get_inst_coverage()` or a bin hit flag set by the monitor) and switch to a different scenario once a goal is met. Useful for long tests; keep it simple and deterministic.

### 5.4 Configuration sweep
Add the missing modes/parameters to the regression matrix (e.g., every `DATA_W`, every power mode, every arbitration policy).

### 5.5 ML-assisted regression tools
Vendors now offer ML-based tools that tune constraints/regressions toward coverage goals. Fine to mention you know they exist; don't claim results you haven't seen.

---

## 6. Formal for Coverage Closure (the correct version)

| Use | What it does | Result |
|---|---|---|
| **Unreachability analysis** (e.g., Jasper COV / Coverage Unreachability app, VC Formal FCA, Questa CoverCheck) | Tries to prove each uncovered **code coverage** item (line, branch, FSM transition) can never be reached | Auto-generated **exclusion list**, often removing a big chunk of the "remaining 15%" in one run. Each still needs review |
| **Cover property witness** | `cover property (fifo_full && err && wrap);` → formal finds a **trace** that reaches it | Shows **how** to reach it: the input sequence becomes a directed test or a hint for constraints |
| **Formal instead of sim for a block** | For control-heavy blocks (arbiters, FIFOs), prove the properties directly | Coverage of that block no longer depends on random luck |

**Caveats to state in an interview:**
- Unreachability is proven **under the formal setup's assumptions**. Wrong or over-strong `assume`s can make reachable code look unreachable, so exclusions must be reviewed.
- Bounded proofs only cover up to a **depth**; "not reached within 30 cycles" is not "unreachable".
- Formal works on **blocks**, not whole SoCs.

---

## 7. Worked Example

**Situation:** Arbiter block, functional coverage at 85% for a week.

| Hole | Investigation | Cause | Action |
|---|---|---|---|
| `grant × requester[7]` = 0 | Config only builds 6 requesters | 1 | Exclude with reason; add 8-requester config to weekly regression |
| `starvation_counter == MAX` = 0 | Request `dist` makes all requesters equally active → never starve | 3 | Scenario: 1 requester constantly active at high priority, others idle; target the low-priority one |
| `back_to_back_grant_same_id` = 0 | Waveform shows it **does** happen | 6 | Covergroup sampled on `req`, not `grant`. Fixed sampling → bin hit immediately |
| FSM `ARB_HOLD → IDLE` (code cov) = 0 | Formal unreachability: unreachable because HOLD exits only via GRANT | 1 | Excluded after designer review; designer later removed dead logic |

Result: four real problems found (one dead-code cleanup, one testbench sampling bug, one missing config, one stimulus gap). **"Add more seeds" would have fixed none of them.**

---

## 8. Is 85% Even a Problem?

Maybe not. The question is **which** 15%:
- 15% of reviewed, unreachable or low-priority bins → could be acceptable at sign-off.
- 1% of a P0 feature uncovered → not acceptable.
**Coverage percentage is meaningful only against the vplan priorities.**

---

## 9. Likely Follow-ups (with model answers)

**Q. Why not just run 10× more seeds?**
At a plateau, the remaining holes have causes that randomness doesn't fix (over-constraint, wrong model, unreachable, missing config). More seeds cost compute and add nothing.

**Q. A bin is 0 but you see the event on the waveform. What's wrong?**
Sampling: wrong event, wrong condition (`iff`), sampled before the field is updated, or the covergroup instance was never created/sampled.

**Q. How do you justify an exclusion?**
Reason (spec / parameter / formal proof), designer agreement, recorded in the exclusion file with owner and date, re-reviewed if RTL changes.

**Q. How does formal help coverage?**
Proves unreachability (exclusions) and gives witness traces for reachable but hard covers. Not equivalence checking.

**Q. Code coverage is 100%, functional 85%. Meaning?**
All RTL lines ran, but some feature-level scenarios (crosses, sequences) never happened. Stimulus or configuration gap, or the functional model has impossible bins.

**Q. How do you prevent plateaus next project?**
Coverage model reviewed against the vplan early; legal vs. bias constraints separated; configuration matrix planned; coverage sampled from monitors on completed transactions; weekly hole reviews from the start.

---

## 10. Common Fresher Mistakes
- Treating a plateau as "need more seeds".
- Writing directed tests before checking for sampling bugs.
- Excluding bins without review.
- Counting coverage percentage without priority.
- Keeping "good seeds" as if they stay good after code changes.
- Calling equivalence checking a coverage-closure tool.

---

## 11. 60-Second Interview Pitch

> "At a plateau, more seeds don't help, so I diagnose. I merge coverage, sort holes by vplan priority, and classify each one: unreachable, over-constrained, rare but legal, configuration never run, a coverage-model bug, or a sampling bug. The last two are testbench bugs, so I first check the log or waveform to see whether the scenario really never happened.
>
> Then the fix follows from the cause. Over-constraint means relaxing or moving to soft. Rare means biasing with dist or writing a targeted sequence. A missing config goes into the regression matrix. Unreachable means a reviewed exclusion.
>
> Formal helps in two ways: unreachability analysis to prove code coverage items can't be hit, and cover-property witness traces that show how to reach hard corners, which I turn into directed tests. I treat formal exclusions carefully, since they're only as good as the assumptions. And I judge the remaining percentage against priorities: 15% of low-priority bins can be fine, 1% of a P0 feature isn't."

---

## 12. Self-Check
- [ ] Can I list the six causes of a coverage hole and the fix for each?
- [ ] Can I explain why "good seeds" don't stay good?
- [ ] Can I explain the two ways formal helps coverage, and its caveats?
- [ ] Can I spot a sampling bug from the symptom?
- [ ] Can I explain why 85% may or may not be a problem?
