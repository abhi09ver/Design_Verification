# Challenge 24: What's Really Expected of an Early-Career DV Engineer — and a Portfolio Project That Proves It

> **Level:** Early-career → interviewing for senior
> **Topics:** realistic expectations, tools and how to get access, writing bug reports, what to put on GitHub/LinkedIn, a step-by-step portfolio project that produces real interview stories
> **Related:** [19 – Building a TB From Scratch](19-building-uvm-testbench-from-scratch.md), [20 – Leading Verification](20-leading-verification-metrics-and-signoff-decisions.md)

---

## 1. The Post (summary)

A LinkedIn post says your first DV role is about "turning a spec into silicon-ready confidence" and claims:

1. Deliver a self-checking testbench hitting **~80% functional coverage on an IP block within a two-week sprint**; "**NVIDIA and Intel list this as a baseline**"; US starting salary "**$85k–$110k**".
2. Be fluent in "Cadence's Xcelium and **Synopsys' VCS/Questa**"; run a nightly regression of 150–200 jobs.
3. Freshers producing "**1–2 defect reports per day are flagged for fast-track promotion**" at AMD and Broadcom.
4. Install a **free trial of Xcelium or VCS**; write bug reports "**using the IEEE 1685 standard**"; clone "**an OpenRISC-V core**" and write a UVM testbench.

The spirit is right: early-career DV is about **self-checking testbenches, debugging regressions, and clear communication**. The details are invented or wrong.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| "NVIDIA and Intel list 80% coverage in two weeks as a baseline" | No public source. Coverage targets depend on the block and the plan (Challenge 09); time depends on block complexity and existing VIP |
| Salary figures | Unsourced and region-specific. Check current data for **your** location and level (e.g., company postings, salary-survey sites) rather than numbers in a post |
| "Synopsys' VCS/**Questa**" | **Questa is Siemens EDA**, not Synopsys. The three big simulators: **VCS** (Synopsys), **Xcelium** (Cadence), **Questa** (Siemens) |
| "1–2 defect reports per day → fast-track promotion" | Invented. Bug **count** is a poor metric (it rewards splitting bugs and filing noise). What's valued: **quality** of root-cause analysis and **important** bugs found |
| "Install a free trial of Xcelium or VCS" | Commercial simulators are licensed to **companies and universities**, not generally to individuals. See Section 4 for real options |
| Bug reports "using **IEEE 1685**" | IEEE 1685 is **IP-XACT**: an XML standard for describing IP blocks and **registers** (used to generate RAL models, Challenge 15). It has nothing to do with bug reports |
| "An **OpenRISC-V** core" | **OpenRISC** and **RISC-V** are two **different** open instruction-set architectures. Also, a CPU core is a heavy first UVM project; start smaller (Section 6) |

---

## 3. What Is Actually Expected (early-career)

| Area | Expectation in the first year |
|---|---|
| **SystemVerilog** | Classes, constraints, covergroups, interfaces, clocking blocks, basic SVA (Challenges 08, 23) |
| **UVM** | Read and extend an existing env: write sequences and tests, add a scoreboard check, add coverage, fix a monitor (Challenges 07, 16, 19) |
| **Debug** | Reproduce a failing seed, read logs and waveforms, decide **TB bug vs. RTL bug vs. spec ambiguity** |
| **Regression** | Run, triage failures (group by signature), re-run with seeds, track pass rate |
| **Communication** | Clear bug reports, short status updates, ask precise questions |
| **Ownership** | Take a feature or sub-block from test plan to coverage closure, with guidance |

**For a *senior* interview** (your target), add: architecture decisions, verification planning, metrics and sign-off judgment, mentoring, and **stories of your own decisions** (Challenge 20). Being honest about your level while showing senior-style reasoning is better than overstating experience.

---

## 4. Getting Tool Access as an Individual

| Option | What you get | Notes |
|---|---|---|
| **EDA Playground** (web) | Run small SV/UVM examples in a browser with commercial and open-source simulators | Simulator availability changes over time; good for snippets and small TBs |
| **Verilator** (open source) | Very fast simulator; recent versions have growing SystemVerilog and **UVM support** | Check current UVM support level for your features |
| **Icarus Verilog** (open source) | Verilog simulation | Limited SystemVerilog, **no UVM** |
| **cocotb** (open source, Python) | Python testbenches with open-source simulators | Different from UVM, but shows verification thinking |
| **SymbiYosys** (open source) | Formal property checking | Practice SVA and formal (Challenge 14) |
| **University or employer licences** | Full commercial tools | If you're at a company or university, use them |

---

## 5. Writing a Good Bug Report

```
Title:     [FIFO] Write accepted when full: data overwritten (seed 48213)
Severity:  High (data corruption, no software workaround)
Build:     RTL rev a1b2c3d, TB rev 9f8e7d6
Test:      fifo_stress_test  +ntb_random_seed=48213  (command line attached)
Expected:  When full=1, in_ready=0 and writes are not accepted (spec §3.2)
Observed:  At 1,245 ns, full=1 but in_ready=1; write accepted; entry 0 overwritten.
           Scoreboard: expected 0x1234 at pop #17, got 0x9ABC.
Evidence:  waveform snapshot (cycles 1,230–1,260), assertion a_no_overflow failed at 1,245 ns
Root cause (suspected): full flag registered one cycle late (fifo_ctrl.sv:88)
Repro rate: 100% with this seed; 3 other seeds in nightly show same signature
```
What makes it good: **reproducible** (seed, build, command), **expected vs. observed tied to the spec**, **evidence** (assertion, scoreboard, waveform window), and a **suspected root cause** without overclaiming.

---

## 6. A Portfolio Project That Gives You Real Interview Stories

The best answer to "tell me about a bug you found" is **your own**. This project is sized for a few weekends and produces code for this repo **and** honest STAR stories.

**DUT:** an open-source **APB or AXI-Lite UART**, or a **synchronous FIFO + APB register block** (small, well-specified, enough corners).

| Step | Deliverable | Interview story it gives you |
|---|---|---|
| 1 | Short **verification plan** (features → test points → checks → coverage) | "How I planned verification" (Challenge 06) |
| 2 | UVM env: agent, scoreboard with **spec-based model**, prove it fails on an injected bug | "How I know my scoreboard works" (Challenge 19) |
| 3 | **SVA** on the bus interface + FIFO full/empty, with covers | "An assertion that caught X" (Challenges 10, 13) |
| 4 | **Coverage** model + constrained-random tests; record coverage vs. seeds | "How I closed coverage / what plateaued and why" (Challenge 09) |
| 5 | **RAL** model generated from a register description; run built-in reset/bit-bash sequences | "RAL bring-up" (Challenge 15) |
| 6 | **Bug hunt**: inject 3–5 realistic bugs (late full flag, wrong reset value, byte-enable error), see which checker catches each | "Mutation testing my own TB": a strong senior-level story |
| 7 | **Formal** on the FIFO with SymbiYosys (overflow, data integrity) | "Sim vs. formal: what each found" (Challenge 14) |
| 8 | **Regression script** + README with results and a coverage chart | "How I automated regression" |

**On GitHub:** a `projects/` folder in this repo with the code, the vplan, results, and a short write-up of each bug found.
**On LinkedIn:** list what you **built and measured** ("UVM TB for APB UART: scoreboard, 12 assertions, RAL, 96% functional coverage; caught 5/5 injected bugs, formal proved FIFO data integrity"), not just tool names.

---

## 7. Likely Interview Questions for Early-Career Candidates (with model answers)

**Q. A test fails in nightly regression. What do you do first?**
Reproduce with the same seed and command line; check whether the failure is new (which commit); read the first error, not the last; decide TB vs. RTL vs. spec using the waveform and the spec; file a report with evidence.

**Q. How do you know your testbench is checking anything?**
Inject bugs and confirm checkers fail; scoreboard reports the number of comparisons; assertions have non-vacuous passes and covers.

**Q. What's your biggest gap, and what are you doing about it?**
Answer honestly with a concrete plan, for example: "Formal verification. I've practised SVA properties and ran SymbiYosys on a FIFO, including a symbolic data-integrity proof."

---

## 8. Common Early-Career Mistakes
- Listing tools without saying what you built with them.
- Claiming coverage numbers without saying what was covered.
- Telling a bug story that isn't yours (Challenge 02).
- Starting with a CPU core as a first UVM project.
- Bug reports without a seed, build or expected-vs-observed.

---

## 9. 60-Second Pitch (for "tell me about yourself", early-career → senior)

> "I verify by turning the spec into a plan, then into a self-checking environment I can trust. For example, in my APB UART project I wrote a verification plan, a UVM environment with a spec-based scoreboard, interface assertions, a generated register model, and coverage-driven random tests. Then I proved the checkers worked by injecting five realistic bugs; all five were caught, and I documented which checker caught each. I also ran formal on the FIFO and proved data integrity with symbolic tracking.
>
> At work, I triage regressions, file reports with seed, evidence and suspected root cause, and own features from test plan to coverage closure. I'm working towards senior scope by leading verification planning and reviewing coverage and waivers."

(Replace with your own real details: only claim what you did.)

---

## 10. Self-Check
- [ ] Can I name the three major simulators and their vendors?
- [ ] Do I know free tools to practise with?
- [ ] Can I write a bug report with seed, expected/observed and evidence?
- [ ] Have I picked a portfolio DUT and written its vplan?
- [ ] Do I have at least one real bug story of my own?
