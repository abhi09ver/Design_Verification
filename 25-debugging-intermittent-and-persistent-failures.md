# Challenge 25: Debugging Persistent and Intermittent Failures — A Systematic Method

> **Level:** Fresher → Senior DV interview
> **Topics:** reproducing failures, non-determinism sources, failure signatures and triage, finding the first divergence, shrinking the failing case, record-and-replay, bisecting commits, hypothesis-driven experiments, deadlock debugging, "passes interactively, fails in batch", closing the loop
> **Related:** [10 – Simulator disagreements](10-ready-valid-handshake-assertions.md), [16 – Pass-by-handle bug](16-uvm-tlm-ports-exports-fifos.md), [20 – Escape analysis](20-leading-verification-metrics-and-signoff-decisions.md)

---

## 1. The Post (summary)

A LinkedIn post describes a "failure-first" method for a bug that survived three regression cycles:

1. **Define the failure envelope**: "In **my recent AMD Zen 4-based SoC project** we narrowed a sporadic deadlock to a **0.8 ns timing window** across the L2-cache interface, cutting the search space by more than 30%."
2. **Layered isolation**: inserting "a single scoreboard checkpoint at the transaction boundary" per "**Google's Chip-Level Verification (CLV) framework**" reveals mismatches "in **under 2 μs of simulation**, versus **minutes** when scanning the full waveform".
3. **Hypothesis scoring**: rank causes by probability from historical data; "**NVIDIA's verification analytics tools** auto-rank hypotheses".
4. "Isolate the failure to a single clock domain and **log the exact timing margins**."

Two good ideas: **check closer to the source** (intermediate checkpoints), and **test hypotheses deliberately**. The rest is invented or confused.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| "**0.8 ns timing window**" / "log the exact **timing margins**" in RTL verification | RTL simulation is **zero-delay, cycle-based**: there are no timing margins. Sub-cycle "windows" only exist in **SDF-annotated gate-level simulation** or in testbench timing (e.g., clock phase between async domains). Real timing margins come from **STA** |
| First-person claim about an AMD project; "Google CLV framework"; "NVIDIA analytics tools" | Unverifiable. In an interview, tell **your** debug story |
| "Under **2 μs of simulation** vs. **minutes**" | Mixes **simulation time** (2 μs of modelled time) with **wall-clock time** (minutes of a person looking at waves). The real point: an **earlier check** points to the cause directly |
| Rank hypotheses by "probability from historical defect data" | Ranking helps choose order, but the key is designing an experiment that **distinguishes** hypotheses (Section 8) |
| "3-tier hierarchy (stimulus, DUT, scoreboard)" as the isolation method | Every testbench has those. Isolation means **moving checks closer to the bug** and **shrinking the failing case** (Sections 6–7) |

---

## 3. The Method at a Glance

```
1. Reproduce reliably  →  2. Classify (signature)  →  3. Find the FIRST divergence
        ↓                                                       ↓
8. Close the loop  ←  7. Fix & prove  ←  6. Test hypotheses  ←  4/5. Shrink the case
```

---

## 4. Step 1: Reproduce Reliably

Capture everything that defines the run:
- **Seed** (`+ntb_random_seed=` / `-sv_seed`), **test name**, all **plusargs**.
- **RTL and TB revision** (commit hashes).
- **Simulator version** and **compile options**.
- Any external inputs: files read by the TB, memory images, environment variables.

**Same seed, same build, still not reproducible?** Then the simulation is **non-deterministic**. Common causes:

| Source | Example | Fix |
|---|---|---|
| **TB race** | Driver uses blocking `=` at `@(posedge clk)`; DUT/monitor sees old or new value depending on scheduling | Clocking blocks / nonblocking drives (Challenge 07, Section 3.4) |
| **Time-0 ordering** | Two `initial` blocks depend on each other | Remove the dependency; explicit ordering via events |
| **Unseeded randomness** | `$urandom` in a module without a controlled seed; random from system time | Seed everything from the test seed |
| **External state** | Reading a file another job writes; wall-clock time; `$system` calls | Make inputs fixed and versioned |
| **Uninitialized variables** | 2-state vs. 4-state defaults differ by option/tool | Initialize; check X |
| **Compile-option differences** | Optimizations or debug-access flags change how a race resolves | Same options for batch and debug runs; fix the race |

**Random stability caveat:** in SystemVerilog, each thread/object has its own random generator. Changing the **testbench** (even adding a `randomize()` call earlier) can change later random values, so the **same seed may not reproduce after a TB change**. That's why **record-and-replay** (Section 6) is valuable.

---

## 5. Step 2: Classify Failures by Signature

When many seeds fail, don't debug them one by one:
- Extract the **first error message** (not the last), strip variable parts (times, addresses, IDs) → **signature**.
- Group failing runs by signature; count per signature; note when each first appeared (which commit).
- Debug **one representative per signature**, starting with the **shortest** failing run.

A failure that "survived three regression cycles" is often several different bugs sharing one symptom (e.g., "timeout"). Signatures separate them.

---

## 6. Step 3: Find the First Divergence

The **error message** is where the bug was **noticed**, often thousands of cycles after it **happened**. Move the detection point earlier:

| Technique | What it gives |
|---|---|
| **Assertions on internal interfaces** (`bind`) | Catch the protocol/control violation at the exact cycle |
| **Intermediate scoreboards / checkpoints** on internal buses (white-box monitors) | Show **which stage** first produced wrong data (the real version of the post's "checkpoint") |
| **Transaction-level logs** from every monitor | Diff expected vs. actual **transaction streams** instead of scanning waveforms |
| **Watchdogs** that print state on timeout | For hangs: dump every FSM state, FIFO level, outstanding transaction (Section 9) |
| **Waveform dump around the failure** | Start dumping shortly before the failure time; full dumps of long tests are slow and huge |

Work **backwards** from the first wrong value: which input to that block was wrong, or was the block itself wrong given correct inputs?

---

## 7. Steps 4–5: Shrink the Failing Case

A smaller case is faster to simulate and easier to understand.

- **Stop at the first error** (`+UVM_MAX_QUIT_COUNT=1`).
- **Fewer transactions**: reduce sequence counts while it still fails.
- **Disable unrelated agents/traffic** one at a time; keep only what's needed to fail.
- **Record and replay**: log the exact transactions the failing test drove (with timing), then replay them in a **directed** test. Now you can delete transactions (bisect the stimulus) until a **minimal** failing sequence remains. Replay is also immune to random-stability changes.
- **Save/restore (checkpoint)** if the simulator supports it: restart just before the failure.
- **Bisect the commit history** (`git bisect`) with the replayed stimulus: find the first RTL/TB commit where it fails. This is often the fastest path to the root cause for regressions that "used to pass".

---

## 8. Step 6: Test Hypotheses Deliberately

For each plausible cause, design an experiment whose result **differs** depending on whether the hypothesis is true:

| Hypothesis | Discriminating experiment |
|---|---|
| "Arbiter starves port B under back-pressure" | Force back-pressure only on B's path; check grant counts; add a fairness assertion |
| "FIFO full flag is one cycle late" | Directed sequence filling to exactly DEPTH with zero-delay writes; assertion `full \|-> !in_ready` |
| "Testbench race, not RTL" | Rerun with clocking-block drive or different compile option; if the result changes, it's a TB race |
| "Clock-ratio dependent (CDC)" | Same stimulus at several clock ratios and phase offsets; fails only at some? |
| "Reset during activity" | Replay with reset moved earlier/later |

Ranking hypotheses by likelihood decides **order**; the experiment design decides **speed**. One good experiment can rule out half the list.

**Then decide: TB bug, RTL bug, or spec ambiguity?** Check against the spec, not against what the RTL does. If the spec is unclear, get the architect to clarify in writing.

---

## 9. Special Case: Deadlocks and Hangs

Symptom: test times out, nothing moves.
1. At timeout, a **watchdog** prints: each FSM's state, each FIFO's occupancy, each valid/ready pair's values, all outstanding transactions (with age).
2. Build a **wait-for chain**: A waits for B's ready, B waits for C's credit, C waits for A's response → **cycle = deadlock**.
3. Check **who should have made progress**, and add a **bounded-progress assertion** there (Challenge 10, Section 4) so the next occurrence fails at the cause, not at the global timeout.
4. Common causes: credit leak, missing response for an error case, arbitration starvation, ordering rule violation (posted stuck behind non-posted, Challenge 17), testbench sequence waiting for a response the driver never sends (`item_done` missing).

---

## 10. Classic Interview Scenario: "Passes Interactively, Fails in Batch"

Differences between the two runs to check:
- **Seed** (interactive may use a default seed).
- **Plusargs / test name / verbosity settings** (verbosity shouldn't change randomization, but custom code sometimes does).
- **Compile options**: debug access and optimization levels can change how **races** resolve.
- **Waveform dumping** on vs. off (shouldn't change behaviour, but can expose races through different optimization).
- **Environment**: working directory, file paths, environment variables, input files, licences, time-outs.
- **Timeouts**: batch machines may be slower, so wall-clock timeouts kill runs that pass interactively.

If behaviour changes with compile options or dumping, suspect a **race** first.

---

## 11. Step 8: Close the Loop
- **Fix** (RTL or TB) and verify with the minimal case **and** the original failing seed.
- **Lock it down**: add the replayed/directed test to regression.
- **Detect earlier next time**: add the assertion or intermediate check that would have pointed at it immediately.
- **Coverage**: add a coverpoint for the triggering scenario so you know regressions keep reaching it.
- **Look for siblings**: same pattern elsewhere (other FIFOs, other arbiters)?
- **Escape analysis**: why did it take three cycles? Missing check? Signature hidden under a generic timeout? (Challenge 20, Section 8)

---

## 12. Likely Follow-ups (with model answers)

**Q. A failure happens in 1 of 1,000 seeds. How do you start?**
Get a failing seed and reproduce it with the same build and options; classify by signature across all failing seeds; take the shortest failing run; find the first divergence with internal assertions and transaction logs; shrink it with record-and-replay; then test hypotheses with discriminating experiments.

**Q. Same seed doesn't reproduce. Why?**
Non-determinism: testbench races, time-0 ordering, unseeded randomness, external files, uninitialized variables, or compile-option differences. Or the TB changed and random stability shifted the stimulus; use recorded stimulus.

**Q. How do you debug a hang?**
A watchdog dumps FSM states, FIFO levels, handshakes and outstanding transactions at timeout; I build the wait-for chain to find the cycle; then add a bounded-progress assertion at the stuck point.

**Q. How do you know whether it's a TB or RTL bug?**
Compare against the spec, not the RTL's behaviour; check the TB model and stimulus legality (protocol assertions on inputs); use a discriminating experiment (e.g., change the TB drive style).

**Q. What do you do after fixing it?**
Add a regression test, an earlier-detecting assertion and coverage for the scenario, look for the same bug pattern elsewhere, and do a short escape analysis.

---

## 13. Common Mistakes
- Debugging the **last** error instead of the first.
- Debugging each failing seed separately instead of by signature.
- Scanning full waveforms instead of moving checks closer to the bug.
- Assuming same seed = same stimulus after TB changes.
- Fixing the symptom (e.g., longer timeout) instead of the cause.
- Not adding an earlier check after the fix.

---

## 14. 60-Second Interview Pitch

> "First I make the failure reproducible: seed, test, plusargs, RTL and TB revision, simulator version and compile options. If the same seed doesn't reproduce, I look for non-determinism, usually testbench races, unseeded randomness or external inputs. I group failing runs by the signature of the first error and debug the shortest one per signature.
>
> The error is where the bug was noticed, not where it happened, so I move detection earlier with internal assertions, white-box checkpoints on internal interfaces and transaction-level logs. I shrink the case with record-and-replay, delete stimulus until it's minimal, and git-bisect the history with the replayed stimulus. Then I test hypotheses with experiments that distinguish them, and decide TB versus RTL versus spec against the spec.
>
> For hangs, a watchdog dumps states and outstanding transactions so I can find the wait-for cycle. Afterwards I add the regression test, an assertion that catches it at the source, coverage for the scenario, and look for the same pattern elsewhere."

---

## 15. Self-Check
- [ ] Can I list what must be captured to reproduce a run?
- [ ] Can I list 5 sources of non-determinism?
- [ ] Can I explain signatures, first divergence, and record-and-replay?
- [ ] Can I describe how to debug a deadlock?
- [ ] Can I answer "passes interactively, fails in batch"?
