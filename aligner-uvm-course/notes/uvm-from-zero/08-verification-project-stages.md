# Lecture companion: Verification project stages

> Card-by-card notes for Cristian Slav's course. Diagrams and toys are in `pages/uvm-from-zero.html`.

Chapter · the finish line (2 videos)

## The verification project end to end, and the end of the course

The course focused on one stage: building the environment. The real job has six stages, from the first read of the spec to a signed-off report, and interviewers often ask "walk me through a project" to see whether you know all of them.

*[Diagram: Stages of a verification project with the regression and coverage loop. Open the HTML page to see it.]*

Stages 4 and 5 loop until everything is clean. The course spent most of its time in stage 3, plus a manual version of stage 4 (re-running seeds by hand), because EDA Playground has no regression runner.

---

F1

## The six stages of a verification project

Stages of a verification project · lecture

| Stage | What you do | Lecturer's advice |
| --- | --- | --- |
| 1 · Understand the spec | Read every document describing the DUT's expected behaviour. | "Don't be afraid to ask questions." Ask the author, usually the concept engineer, **before writing any code**. Modeling a misunderstood feature is the most expensive mistake. |
| 2 · Verification documents | (a) **Environment architecture**: block diagram, UML class APIs, how objects communicate. (b) **Verification plan**: the coverage tree, plus the checks and tests. | Put in as much detail as you can. Write → review → fix action items → re-review. Review the architecture with the verification team, and the vplan with **verification + design + concept**, so missing features are caught in the review. |
| 3 · Develop the environment | Agents, RAL, model, scoreboard, coverage, sequences, tests. | Everything in this course. |
| 4 · Regressions | Run all tests with random seeds, many times. Goal 1: 100% passing. Goal 2: 100% coverage. | **Functional** coverage is verification's responsibility. **Code** coverage (lines, expressions, FSM transitions…) is design's. Coverage holes → new tests → new failures → loop. |
| 5 · Qualification | Tools inject bugs into the DUT (negate a signal, disconnect one…) and rerun your regressions. Every bug that isn't detected shows a gap in your checks. | Not required everywhere, but increasingly common. Iterate until it's clean. |
| 6 · Sign-off | Reports proving verification is complete. | The contents vary by company, but they always include coverage and the tests and seeds that achieved it. |

Background the lecture assumes

- **Code coverage types**: line/statement, branch, condition/expression, toggle, FSM state and transition. 100% code coverage with weak checkers still misses bugs, which is why functional coverage *and* qualification exist.
- **Qualification = mutation analysis**. Commercial tools (Synopsys Certitude is the best known) classify each injected fault as not activated (a stimulus gap), activated but not propagated (an observability gap), or propagated but not detected (a **checker gap**). The last is the most damning.
- In this course: three RTL bugs were found by re-running seeds by hand. The lecturer is explicit that without real regressions, nobody can claim there are no more.

**Q: "Walk me through how you'd verify a new block from day one."**

Spec study with an open-questions list to the architect. A testbench architecture document and a verification plan (features → checks, coverage, tests), reviewed with design and architecture. Reuse or build agents, then RAL, model, scoreboard and coverage, bringing them up with simple directed tests. Then random tests and regressions, triaging failures until everything passes. Close functional and code coverage, with waivers reviewed. Mutation qualification if required. Sign off with coverage reports, the test/seed list and the bug summary.

**Q: "When are you done verifying?"**

When the agreed criteria in the plan are met: all regression tests passing over a statistically meaningful number of seeds, functional coverage closed (with holes explained or waived in review), code coverage closed by design (exclusions reviewed), the bug-discovery rate flattened, and qualification clean if required. "Done" is a reviewed decision against evidence, not a feeling.

**Q: "100% code coverage but a bug escaped to silicon. How?"**

Code coverage only shows the lines executed. It doesn't show that the effect was **checked**, or that the right **combination** of conditions occurred. Typical causes: a missing or weak checker (exactly what mutation qualification exposes), functional coverage missing the corner (e.g. reconfiguring with data inside), or a spec gap where both RTL and model were wrong in the same way, like the SIZE + OFFSET bug in R8.

**Q: "Who reviews the verification plan, and why does that matter?"**

Verification, design and concept/architecture. Design knows the implementation risks (arbiters, clock crossings, corner states), and architecture knows the intended system use. Their sign-off means everyone agrees on what will and won't be verified, so a missing feature is caught at review time, not after tape-out.

---

F2

## Course complete: what you can now say you've built

Final video

agents

#### Reusable UVM agents

APB and reactive MD, both on a shared base library.

registers

#### RAL + hidden features

Custom predictor, field callbacks, and the W1C randomization trap.

checking

#### Model + scoreboard

Including three synchronization issues and their fixes.

tests & debug

#### Random tests that find bugs

Message control, transaction recording, source tracking, three RTL bugs.

Turn it into a portfolio piece

- The final project is over 5000 lines. Keep it in a public repository (with the course author's terms in mind), with a README showing the environment diagram and the bug table from T9.
- Practise the T9 project story and the C10 debug story out loud. They answer "tell me about your project" and "tell me about a hard bug".
- Extensions that would stand out: a real regression script with seed sweeps, completed split-cross exclusions, a reset-in-traffic test, and the "track the source" adapter from T4.
- The lecturer invites feedback and shares articles on LinkedIn (Cristian Slav).

Where to go from here on this page

Tick the "I watched…" boxes as you revise. The lecture map at the top tracks them. For interview prep, open every Q without reading the answer first, say your answer out loud, then compare. For senior roles, the bug-hunt boxes (the coral notes) are the best practice: each one is a real defect or trap found in your own project's code.

---

