# Challenge 06: The Verification Plan — What Goes In, How It's Tracked, and When You Can Sign Off

> **Level:** Fresher → Senior DV interview
> **Topics:** feature extraction, test points, risk-based prioritization, choosing sim vs. formal vs. emulation, coverage model, executable vplan, sign-off criteria, handling spec changes, regression/CI

---

## 1. The Post (summary)

A LinkedIn post says the verification plan "can make or break a tape-out" and recommends:

1. Define coverage targets in a **risk-based matrix** and **lock them before any RTL is written**; "a **30% boost** in functional coverage early on cuts debug cycles dramatically"; use the **IEEE 1800-2017 coverage model** as a baseline.
2. Anchor the plan to the architecture, e.g., "for a design destined for **NVIDIA's H100**", separate blocks for Tensor Core scheduler, HBM interface, power-gating.
3. Run CI/CD on cloud, using **Google Cloud TPU v5p instances** to run a full regression in under 12 hours.

The headline is true and the risk-based idea is right. Several details are **technically wrong** and would hurt you in an interview.

---

## 2. What's Wrong With the Post

### ❌ 2.1 "Run regressions on TPU v5p instances"
TPUs are accelerators for **machine-learning math**. RTL simulators (VCS, Xcelium, Questa, Verilator) run on **general-purpose CPUs**. You can't run a simulation regression on a TPU. Cloud regressions use **CPU VMs**, and the real bottleneck is usually **simulator licences**, not machines.

### ❌ 2.2 "IEEE 1800-2017 coverage model as a baseline"
IEEE 1800 is the **SystemVerilog language standard**. It defines the *syntax* of `covergroup`, `coverpoint`, `cross`, `cover property`. It does **not** tell you *what* to cover for your design. Your coverage model comes from **your spec and your risks**. (Also, the current revision is IEEE 1800-2023.)

### ❌ 2.3 "Lock coverage targets before any RTL is written"
Write the first version early, yes. **Locking** it is wrong: specs change, micro-architecture decisions add new corner cases (FIFO depths, arbitration, pipelines) that don't exist until RTL is designed. A vplan is a **living, versioned, reviewed document**. What you lock is the **sign-off criteria**, and changes go through review.

### ❌ 2.4 "A 30% boost in functional coverage cuts debug cycles"
Coverage percentage is a **measure of what you've exercised**, not a lever. A 30% jump can come from adding easy bins. Quality comes from **what the bins represent**.

### ⚠️ 2.5 "Design destined for NVIDIA's H100"
Irrelevant name-dropping. The principle (partition the plan by architectural units and risk) is correct; describe it with **your** design.

---

## 3. Background a Fresher Must Know

### 3.1 Testplan vs. verification plan
| Term | Scope |
|---|---|
| **Verification plan (vplan)** | The whole strategy: what to verify, how, with what methods, coverage, checkers, owners, schedule, sign-off criteria |
| **Testplan** | Often the list of tests/scenarios. Part of the vplan |

In many companies people use the words interchangeably. Clarify in interviews: *"By verification plan I mean features → test points → methods → coverage → checkers → sign-off."*

### 3.2 The chain every vplan must have

```
Spec feature  →  Test point  →  Method  →  Stimulus  →  Checker  →  Coverage  →  Status
"FIFO full     "Write when    Sim (CRV)   back-to-back  scoreboard   cp_full ×    80% /
 backpressure"  full is        + SVA       writes,       + SVA        wr_attempt  owner: A
                rejected"                  zero delay    !wr_accept
```

**Key idea:** every feature needs **both** a way to *exercise* it (stimulus + coverage) **and** a way to *check* it (scoreboard / assertion). Coverage without a checker means you saw it but didn't verify it.

### 3.3 Sections of a good vplan
1. **Scope and references**: spec versions, what's in/out of scope.
2. **Feature list**: extracted from spec + micro-architecture spec, each with an ID.
3. **Test points per feature**: normal, boundary, error, concurrency, reset, low-power.
4. **Verification method per feature**: simulation, formal, emulation/FPGA, gate-level, static (lint/CDC/RDC).
5. **Testbench architecture**: agents, scoreboards, reference model, RAL.
6. **Checkers**: scoreboard, SVA, reference model compare.
7. **Coverage model**: functional covergroups, assertion coverage, code coverage targets.
8. **Risk / priority** per feature (P0/P1/P2).
9. **Owners and schedule**, tied to project milestones.
10. **Sign-off criteria** (Section 6).
11. **Assumptions, dependencies, exclusions** (with reasons).

---

## 4. Risk-Based Prioritization (the right version of the post's "matrix")

**Risk = Likelihood of a bug × Impact if it escapes.**

| Raises likelihood | Raises impact |
|---|---|
| New or heavily changed logic | No software workaround (silicon respin) |
| Complex control (arbiters, coherency, ordering) | Data corruption / security |
| Concurrency, multiple clock domains, CDC | Affects every customer use case |
| Low-power: power gating, retention, isolation | Safety-critical behaviour |
| Unclear spec / late spec changes | Boot / reset path (chip doesn't start) |
| Configurable parameters (many combinations) | |

Example matrix:

| Feature | Likelihood | Impact | Priority | Method |
|---|---|---|---|---|
| Arbiter fairness & starvation | High | High | **P0** | CRV + formal (liveness) |
| Async FIFO across clock domains | Med | High | **P0** | CDC tool + formal + sim |
| Power-gate isolation/retention | High | High | **P0** | UPF-aware sim + static power checks |
| Register reset values | Low | Med | P1 | RAL built-in sequences |
| Debug counters | Low | Low | P2 | Directed |

**Senior point:** risk decides *how much* effort and *which method*, not just priority order. A P0 arbiter gets formal proofs on top of simulation.

---

## 5. Choosing the Method per Feature

| Method | Best for | Weak at |
|---|---|---|
| **Constrained-random sim** | Data paths, protocols, end-to-end behaviour | Proving absence of bugs; very deep states |
| **Directed sim** | Bring-up, specific sequences, reproducing bugs | Unknown corners |
| **Formal (property checking)** | Control logic, arbiters, FIFOs, handshakes, deadlock/liveness | Large datapaths (state explosion) |
| **Emulation / FPGA** | Long software runs, boot, OS, performance workloads | Debug visibility, early availability |
| **Gate-level sim** | Reset/init X-issues, timing-annotated paths, DFT | Speed |
| **Static: lint, CDC, RDC, power (UPF) checks** | Structural issues across the whole design | Functional intent |

---

## 6. Sign-Off Criteria (what "done" means)

Write these in the vplan up front and **get them agreed with design and management**:

- [ ] **100% of P0 and P1 test points** implemented and passing
- [ ] **Functional coverage**: 100% of planned bins, or each hole reviewed and waived with a reason
- [ ] **Code coverage** (line, branch/condition, FSM, toggle): 100% or reviewed exclusions (unreachable, debug-only, tied-off)
- [ ] **Assertion coverage**: every assertion fired at least once (covers its antecedent); no assertion vacuous-only
- [ ] **Formal**: all P0 properties proven, or bounded proofs with an agreed depth
- [ ] **Regression health**: e.g., ≥ 99% pass rate over N consecutive nightly runs with fresh seeds
- [ ] **Bug trend**: discovery rate flattened; **no open P0/P1 bugs**
- [ ] **Static checks** clean or waived: lint, CDC, RDC, low-power
- [ ] **Gate-level sims** pass (reset, smoke, DFT patterns)
- [ ] **Reviews**: vplan, coverage model, and waivers reviewed by design + verification leads

**Why both code and functional coverage:** code coverage finds RTL you never exercised (missing stimulus); functional coverage finds **features you never exercised**, even if every line ran. 100% code coverage with missing functional coverage is a classic escape.

---

## 7. Making the Plan Executable and Tracked

- Write the vplan in a **planner format** (e.g., spreadsheet/XML in Verdi Planner, Cadence vManager, Questa testplan tracking) where each test point links to **covergroups, assertions, and tests**.
- Merged coverage from each regression is **back-annotated** into the plan, so status updates automatically instead of by hand.
- Weekly review: coverage per feature, holes, new bugs per feature, waivers.

### Regression / CI (realistic version of the post's cloud point)
- **Per commit**: lint + compile + short smoke tests with **fixed seeds** (deterministic gate).
- **Nightly**: full random regression with **fresh seeds**, coverage merge, results dashboard.
- **Weekly**: long tests, gate-level, formal re-runs.
- Compute: on-prem farm (LSF/SGE/Slurm) or cloud **CPU** VMs; plan for **licence** count, not just machines.

---

## 8. Handling Spec Changes Mid-Project
1. Impact analysis: which features/test points change.
2. Update vplan (versioned), coverage model, checkers, and reference model.
3. Re-prioritize: a late change in a P0 area raises its risk.
4. Re-run affected regressions; check old waivers still apply.
5. Communicate schedule impact early.

---

## 9. Likely Follow-ups (with model answers)

**Q. Coverage is 100% but a bug escaped. What does that say about the plan?**
The plan missed a scenario (feature not extracted, cross not defined, temporal sequence not covered) or a checker wasn't checking. Fix the plan first, then the test.

**Q. How do you extract features from a vague spec?**
Read spec + micro-architecture spec, list every requirement with an ID, review with designers, and write explicit questions for every ambiguity. Treat unanswered ambiguity as risk.

**Q. How do you decide formal vs. simulation?**
Control-heavy, small-state, concurrency-sensitive blocks (arbiters, FIFOs, handshakes) go to formal; datapaths and end-to-end flows to simulation. Often both: formal for the control, sim for integration.

**Q. How do you justify a coverage waiver?**
State why the bin is unreachable or irrelevant (tied-off parameter, debug-only logic, illegal by spec), get designer agreement, record it, and re-review if the RTL changes.

**Q. Who owns the vplan?**
DV lead owns it; designers and architects review it; every test point has an individual owner.

**Q. When do you start the vplan?**
As soon as the architecture/spec draft exists, in parallel with RTL design. Early test points also find spec bugs before RTL exists.

---

## 10. Common Fresher Mistakes
- Treating the vplan as a list of test names.
- Coverage with no matching checker.
- Only code coverage, or only functional coverage.
- No sign-off criteria agreed up front.
- Unreviewed exclusions/waivers.
- Never updating the plan after spec changes.
- Same effort on every feature instead of risk-based.

---

## 11. 60-Second Interview Pitch

> "My verification plan maps every spec feature, by ID, to test points, a method, stimulus, a checker and coverage, with an owner and a priority. Priority comes from risk, likelihood times impact, so new or complex control logic, CDC, low-power and anything without a software workaround get the most effort, and often formal on top of simulation.
>
> Every feature must be both exercised and checked: coverage without a checker isn't verification.
>
> I agree sign-off criteria up front: P0/P1 test points passing, functional and code coverage closed or reviewed waivers, assertion coverage, formal proofs, a stable pass rate with fresh seeds, a flattened bug curve with no open P0s, and clean lint, CDC and power checks.
>
> The plan is executable: covergroups and tests are linked so regression coverage back-annotates it automatically. It's versioned, not frozen: when the spec changes I do an impact analysis and update the plan, the coverage model and the checkers."

---

## 12. Self-Check
- [ ] Can I list the sections of a vplan?
- [ ] Can I fill the chain feature → test point → method → checker → coverage for one feature?
- [ ] Can I build a small risk matrix and justify priorities?
- [ ] Can I list 8 sign-off criteria?
- [ ] Can I explain why TPUs, "IEEE 1800 coverage model" and "lock before RTL" are wrong?
