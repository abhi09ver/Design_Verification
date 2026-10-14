# Challenge 20: Leading Verification — Estimation, Metrics, "Are We Done?", and Communicating Risk

> **Level:** Senior DV interview (the non-coding round)
> **Topics:** realistic project timeline, effort estimation, the metrics dashboard, bug-trend analysis, when to stop, power/performance/security as verification dimensions, escape analysis, asking for resources with data, behavioural questions
> **Related:** [06 – Verification Plan](06-verification-plan.md), [09 – Coverage Plateau](09-coverage-plateau-closure.md), [11 – Functional vs. Code Coverage](11-functional-vs-code-coverage.md)

---

## 1. The Post (summary)

A LinkedIn post says senior interviews are "a forensic drill into how you architect a test strategy" and recommends:

1. A **3-phase plan**: **30%** of the timeline on stimulus definition, **40%** on coverage closure, **30%** on sign-off; "Google's silicon-validation playbook forces candidates to articulate this cadence".
2. Blend UVM with "**formal equivalence checking** ... when the design hits a tight **power-budget or packaging constraint**"; NVIDIA demands a "**5-point coverage rubric**" including "**power-leakage**" collected in a **VCS** flow.
3. Present a slide tying a 2-year cycle to "**a projected 15% reduction in post-silicon bugs**".
4. "Review interview experiences on forums to **spot recurring phrasing** and adjust your answers."

The message is right: senior rounds test **judgment, metrics and communication**, not just UVM syntax. The specifics are invented or wrong.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| Fixed 30/40/30 sequential phases | Verification activities **overlap** and follow **RTL maturity**, not fixed percentages. Coverage closure isn't a phase after stimulus; it runs **alongside** stimulus development from the first regressions |
| Equivalence checking for **power-budget / packaging** constraints | Equivalence checking compares two designs (RTL vs. netlist). It has nothing to do with power budgets or packaging (Challenge 14) |
| "**Power-leakage** coverage" in a VCS flow | **Leakage power** is a physical/electrical quantity, estimated by **power analysis tools** on the implementation. What DV verifies is **low-power functionality**: power-aware (UPF) simulation of power states, isolation, retention, and power-up/down sequences, with coverage of those |
| Company "playbooks" and "rubrics" | Unverifiable. Don't quote them |
| "**Projected 15% fewer post-silicon bugs**" | You can't credibly forecast that. What you **can** show: bug-discovery trend, coverage per feature, open risks, and the cost of escaping each (Sections 5–7) |
| Memorize "recurring phrasing" from forums | Interviewers spot rehearsed phrases fast. Prepare **your own stories with real numbers** |

---

## 3. A Realistic Project Timeline (overlapping, milestone-driven)

```
Spec/arch ──► RTL 0.5 (compiles) ──► RTL 0.8 (features in) ──► RTL 1.0 (feature freeze) ──► Tape-out
   │               │                        │                           │
 vplan v1      TB bring-up,            CRV + coverage              closure, waivers,
 risk matrix   smoke tests,            ramp; bug rate peaks        regression stability,
 TB arch       first assertions        formal on control blocks    sign-off reviews, GLS
               ◄────────── coverage tracked from first regression ──────────►
```

Typical gates:
- **RTL 0.5:** TB bring-up done, smoke tests pass, vplan reviewed.
- **RTL 0.8:** all features have tests; random regression running nightly.
- **RTL 1.0 (feature freeze):** only bug fixes; coverage closure and waivers.
- **Tape-out:** sign-off criteria met (Challenge 06, Section 6).

**Interview point:** verification **starts before RTL** (plan, TB architecture, reference models) and ends after tape-out (post-silicon support, escape analysis).

---

## 4. Estimating Effort (how a senior answers "how long will this take?")

1. **Feature list** from the vplan, each with complexity (low/med/high) and risk.
2. **Reuse factor:** existing VIP, agents, reference models, RAL generation reduce effort.
3. **Historical data:** similar blocks on past projects (person-weeks per feature, bugs found per feature).
4. **Method mix:** formal on control blocks, simulation for datapaths, emulation for software scenarios.
5. **Unknowns buffer:** spec instability, late features, new protocols; state the buffer explicitly.
6. **Output:** person-weeks per feature, critical path, and **what you need** (people, licences, emulator time).

Say the assumptions out loud. An estimate without assumptions is just a number.

---

## 5. The Metrics Dashboard

No single metric means "done". A senior tracks several, **per feature**:

| Metric | What it tells you | Warning sign |
|---|---|---|
| **Test-point completion** (vplan) | Planned work implemented | Features with no tests near freeze |
| **Functional coverage per feature** | Planned scenarios exercised | P0 feature stuck below plan |
| **Code coverage** | Unplanned / dead logic | Uncovered blocks with no review |
| **Assertion status** | Non-vacuous passes, covers hit | Assertions only vacuous |
| **Regression pass rate** (with fresh seeds) | Stability | Pass rate drops after RTL drops |
| **Bug discovery rate** (per week, per severity, per feature) | Maturity | Still rising near freeze |
| **Bug closure rate / open bugs** by severity | Risk remaining | Open P0/P1 near tape-out |
| **Waivers / exclusions** count and review status | Hidden risk | Many unreviewed waivers |
| **Regression throughput** (tests/day, turnaround) | Capacity | Nightly doesn't finish overnight |

### Reading the bug curve
```
bugs/week
   │        ▲▲
   │      ▲▲  ▲▲
   │    ▲▲      ▲▲
   │  ▲▲          ▲▲▲
   │▲▲               ▲▲▲▲▲▲▁▁▁▁   ← flattening = good sign (if stimulus is still changing)
   └──────────────────────────────── weeks
```
- A flat curve is meaningful **only if** stimulus and checks are still evolving. A flat curve because nobody added new tests just means you've stopped looking.
- Track **where** bugs are found (which feature, which method: sim/formal/emulation) to redirect effort.

---

## 6. "When Do We Stop?" (the real senior question)

You stop when the **agreed sign-off criteria** are met (Challenge 06):
- P0/P1 test points done; coverage closed or reviewed waivers.
- Bug rate flattened **while** new stimulus kept being added; no open P0/P1.
- Regression stable over N nightly runs with fresh seeds.
- Formal properties proven or bounded with justified depth.
- Static checks (lint, CDC, RDC, low-power) clean or waived.

And when the schedule forces a decision before criteria are met:
1. List **what's not done**, per feature, with risk (likelihood × impact).
2. For each item: can it be **fixed in software/firmware** later? Is there a **chicken bit** (a register that disables the feature)?
3. Present **options**, not just problems: add resources, reduce scope, accept risk with mitigation.
4. Get the **risk acceptance written down** by the people who own the decision.

---

## 7. The Other Dimensions (corrected version of the "5-point rubric")

| Dimension | What DV actually verifies | How |
|---|---|---|
| **Functional** | Features per spec | CRV, directed, formal, scoreboards |
| **Corner cases** | Boundaries, concurrency, errors, reset | Coverage crosses, targeted sequences, formal |
| **Performance** | Throughput/latency meet the architecture's targets | Perf counters, analytical model comparison (Challenge 04), emulation workloads |
| **Low-power (functional)** | Power states and transitions; isolation, retention, level shifting behave correctly; power-up/down sequences | **UPF power-aware simulation**, static low-power checks, coverage of power states/transitions |
| **Security** | No unauthorized access paths; secure/non-secure separation; debug locked | Access-control tests, formal information-flow/path checks, negative tests |

Power **numbers** (leakage, dynamic) are estimated by power-analysis tools, often using **activity from emulation** (Challenge 12), not by DV coverage.

---

## 8. Escape Analysis (what seniors do after a bug escapes)

When a bug is found late (or in silicon):
1. **Root cause** in RTL.
2. **Why did verification miss it?** Missing feature in the plan? Missing cross? Stimulus couldn't reach it? Checker didn't compare that field? Waived wrongly?
3. **Fix the process**, not just the test: update the vplan, coverage model, checkers, waiver review.
4. **Look for siblings**: same bug pattern in other blocks.

Interviewers love: *"Tell me about a bug that escaped your verification and what you changed."* Have one ready, honestly told.

---

## 9. Asking for Resources With Data

Bad: *"We need two more people."*
Good:
> "Three P0 features are behind plan: coverage at 60%, 55% and 40%, with bug discovery still rising in the arbiter. At current capacity, closure lands four weeks after freeze. Options: add two engineers for six weeks to close on time; move the arbiter's power-down mode to firmware-disabled with a chicken bit; or accept the risk on the low-priority debug feature. I recommend option one plus the chicken bit."

Data, options, recommendation, and what each option risks.

---

## 10. Behavioural Questions (be ready with real stories)

| Question | What they test | Structure |
|---|---|---|
| Disagreement with a designer on whether something is a bug | Technical judgment, communication | Spec reference → evidence (waveform, assertion) → resolution (spec clarification) |
| Late spec change two weeks before freeze | Prioritization | Impact analysis → re-plan → communicate risk |
| A bug you missed | Ownership | Escape analysis (Section 8) |
| Mentoring a junior | Leadership | What they struggled with, what you did, result |
| Regression broken by someone's commit | Process | Gating, bisecting, fixing the CI rather than blaming |

Use **STAR** (Situation, Task, Action, Result) and real numbers from **your** work.

---

## 11. Likely Follow-ups (with model answers)

**Q. How do you know verification is complete?**
Agreed sign-off criteria across plan completion, coverage, assertions, formal, regression stability, bug trend and static checks, all per feature. Not one percentage.

**Q. The bug rate is flat. Are we done?**
Only if stimulus and checkers kept evolving during that time. Otherwise the flat curve means we stopped looking.

**Q. Tape-out is fixed and coverage isn't closed. What do you do?**
Classify the gaps by risk, check for software workarounds and chicken bits, present options, and get risk acceptance documented by the decision owners.

**Q. How do you verify low-power design?**
UPF power-aware simulation of power states and transitions, checking isolation, retention and sequencing, plus static low-power checks and coverage of power states. Power numbers come from power-analysis tools.

**Q. How do you estimate verification effort for a new block?**
Feature list with complexity and risk, reuse factor, historical data, method mix and an explicit unknowns buffer, with assumptions stated.

---

## 12. Common Mistakes at Senior Level
- Giving a single coverage number as "done".
- Fixed-percentage timelines with no link to RTL maturity.
- Promising forecasts you can't derive.
- Raising problems without options.
- Only technical answers; no stories about people and decisions.
- Rehearsed phrases instead of real experience.

---

## 13. 60-Second Interview Pitch

> "I plan verification against RTL milestones, not fixed percentages: the plan and testbench architecture before RTL, bring-up at 0.5, all features under random regression by 0.8, and closure and waivers after feature freeze, with coverage tracked from the first regression.
>
> I estimate from the feature list, complexity, reuse and historical data, with assumptions and an unknowns buffer stated. I track a per-feature dashboard: test-point completion, functional and code coverage, assertion status, pass rate with fresh seeds, and bug discovery and closure by severity. A flat bug curve only counts if stimulus kept evolving.
>
> Beyond functionality I cover performance against an analytical model, low-power through UPF-aware simulation, and security with negative and formal checks. When the schedule forces a call, I present the open risks with options, such as more people, a chicken bit or reduced scope, and get the decision documented. After any escape, I fix the process: plan, coverage and checkers."

---

## 14. Self-Check
- [ ] Can I sketch a milestone-based timeline?
- [ ] Can I explain how I'd estimate effort, with assumptions?
- [ ] Can I list 6 dashboard metrics and their warning signs?
- [ ] Can I answer "when do we stop?" and "tape-out is fixed, what now?"
- [ ] Do I have 3 real STAR stories: a bug found, a bug missed, a disagreement?
