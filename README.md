# Design_Verification

Interview preparation notes for Senior Design Verification (DV) Engineer roles.
Each file takes one real-world DV challenge, explains it from first principles, corrects common misconceptions, and ends with likely interviewer follow-ups and a 60-second answer pitch.

## Challenges

| # | Topic | Key concepts |
|---|---|---|
| 01 | [The `uvm_config_db` "Phasing Trap"](01-uvm-config-db-phasing-trap.md) | `create()` vs `build_phase`, config_db lookup (scope/name/type), factory overrides, `super.build_phase`, objections, debug flow |
| 02 | [Constrained-Random Verification Storytelling](02-constrained-random-verification-storytelling.md) | Constraint layering, `dist`/`soft`/`solve-before`, seeds vs. constraints, regression budgeting, coverage ranking, STAR bug story |
| 03 | [Verification IP Reuse](03-verification-ip-reuse.md) | Vertical vs. horizontal reuse, active/passive agents, block→SoC migration, RAL submaps, parameterized interfaces, VIP versioning & CI |
| 04 | [Systolic Array Underutilization](04-systolic-array-underutilization.md) | Systolic dataflow, tiling, edge tiles, fill/drain math, bandwidth vs. compute, stall counters, psum/padding/quantization bugs, golden model |
| 05 | [Virtual Sequences and Virtual Sequencers](05-virtual-sequences.md) | Virtual sequencer as handle container, `p_sequencer` vs. `m_sequencer`, passive agents, factory overrides, fork/disable fork, lock/grab, layering vs. virtual |
| 06 | [The Verification Plan](06-verification-plan.md) | Feature → test point → method → checker → coverage, risk matrix, sim vs. formal vs. emulation, sign-off criteria, executable vplan, spec changes |
| 07 | [UVM Pillars: Phasing, Factory, config_db](07-uvm-pillars-phasing-factory-config-db.md) | 9 common + 12 run-time phases, objections & drain time, clocking blocks for races, factory overrides & pitfalls, config_db precedence & performance |
| 08 | [SystemVerilog Assertions (SVA)](08-sva-assertions.md) | Immediate vs. concurrent, sampling, implication operators, vacuity, goto `[->n]`, local variables, stalls, liveness, assume/cover in formal, debugging a failing property |
| 09 | [Coverage Plateau at 85%](09-coverage-plateau-closure.md) | Six causes of coverage holes, sampling bugs, targeted sequences, config sweeps, formal unreachability & witness traces, exclusions, worked arbiter example |
| 10 | [Ready/Valid Handshake Assertions](10-ready-valid-handshake-assertions.md) | Ready/valid rules, stall vs. error, reference-queue checker for dropped data, bounded deadlock check, ID-matched latency, simulator disagreements |
| 11 | [Functional vs. Code Coverage](11-functional-vs-code-coverage.md) | Code coverage types, what each metric misses, coverage ≠ checking, exclusions & sign-off, 4-stage pipeline coverage matrix |
| 12 | [Emulation and FPGA Prototyping](12-emulation-and-fpga-prototyping.md) | Platform spectrum & realistic speeds, what each finds/misses, 2-state & no timing, transaction-based acceleration, emulator debug |
| 13 | [SVA Beyond the Happy Path](13-sva-beyond-happy-path.md) | What `disable iff` hides, reset properties, error responses, illegal states, correct AXI W-channel rules, assertion coverage, testing the checkers |

## How each file is structured

1. Problem statement
2. Background concepts (fresher level)
3. Root-cause analysis
4. Debug steps used in real projects
5. Minimal fix vs. robust senior-level fix
6. Likely interviewer follow-ups with model answers
7. Common mistakes
8. 60-second interview pitch
9. Self-check list
