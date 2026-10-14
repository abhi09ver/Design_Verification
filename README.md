# Design_Verification

Interview preparation notes for Senior Design Verification (DV) Engineer roles.
Each file takes one DV interview topic (often from a LinkedIn post), checks what the post got right and wrong, explains the topic from first principles, and ends with likely interviewer follow-ups and a 60-second answer pitch.

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
| 11 | [Functional vs. Code Coverage](11-functional-vs-code-coverage.md) | Code coverage types, what each metric misses, coverage ≠ checking, exclusions & sign-off, 4-stage pipeline and ALU coverage plans |
| 12 | [Emulation and FPGA Prototyping](12-emulation-and-fpga-prototyping.md) | Platform spectrum & realistic speeds, what each finds/misses, 2-state & no timing, transaction-based acceleration, emulator debug |
| 13 | [SVA Beyond the Happy Path](13-sva-beyond-happy-path.md) | What `disable iff` hides, reset properties, error responses, illegal states, correct AXI W-channel rules, assertion coverage, testing the checkers |
| 14 | [Formal Verification](14-formal-verification.md) | FPV vs. equivalence checking, proven/CEX/bounded, assumptions & over-constraint, convergence techniques, symbolic FIFO data integrity, formal coverage & sign-off |
| 15 | [UVM Register Model (RAL)](15-uvm-register-model-ral.md) | Block/map/reg/field, register generation, adapter, explicit vs. implicit prediction, desired/mirrored, front- vs. back-door, volatile fields, built-in sequences, SoC submaps |
| 16 | [UVM TLM: Ports, Exports, FIFOs](16-uvm-tlm-ports-exports-fifos.md) | Port/export/imp & connection rules, analysis broadcast, pass-by-handle bug, multi-stream scoreboards, `uvm_tlm_fifo` vs. analysis FIFO, driver–sequencer pull |
| 17 | [Bus Protocols: AXI, AHB-Lite, PCIe](17-bus-protocols-axi-ahb-pcie.md) | AXI per-ID ordering & interleaving, per-ID scoreboard, AHB-Lite pipelining & two-cycle error, HMASTLOCK, PCIe credit types, infinite credits, credit deadlock |
| 18 | [Coverage Architecture](18-coverage-architecture.md) | Cycle / transaction / scenario coverage levels, covergroup placement, controlling cross explosion, merging & ranking, static vs. dynamic closure, AXI-Lite slave plan |
| 19 | [Building a UVM Testbench From Scratch](19-building-uvm-testbench-from-scratch.md) | Bring-up order, file/package structure, working skeleton (interface, driver, monitor, agent, scoreboard, tests), independent reference model, proving the scoreboard can fail |
| 20 | [Leading Verification: Metrics & Sign-off Decisions](20-leading-verification-metrics-and-signoff-decisions.md) | Milestone-based timeline, effort estimation, metrics dashboard, bug-curve reading, when to stop, low-power/performance/security, escape analysis, asking for resources, behavioural questions |
| 21 | [Protocol Bridge Verification (AXI ↔ PCIe)](21-protocol-bridge-verification-axi-to-pcie.md) | No AXI read-after-write guarantee, AXI4-Lite limits, translation & splitting, byte enables, tags & split completions, error mapping, LCRC vs. TLP errors, end-to-end scoreboard, clock ratios |
| 22 | [PCIe Link Training & Recovery (LTSSM)](22-pcie-ltssm-link-recovery.md) | LTSSM states, Recovery triggers, speed/width changes, PIPE, no TLP loss across retrain, scaled timeouts, Recovery monitor, coverage; AXI 4KB & unaligned bursts, AHB ERROR rules |
| 23 | [SystemVerilog OOP for Verification](23-systemverilog-oop.md) | Handles vs. objects, shallow vs. deep copy, virtual vs. non-virtual dispatch, `$cast`, abstract & interface classes, `kind` field vs. subclasses, constraint inheritance, how UVM uses OOP |
| 24 | [Early-Career Expectations & Portfolio Project](24-early-career-dv-expectations-and-portfolio.md) | Realistic expectations, simulator vendors, free tools, writing a bug report, IEEE 1685 = IP-XACT, step-by-step portfolio project that produces real interview stories |
| 25 | [Debugging Persistent & Intermittent Failures](25-debugging-intermittent-and-persistent-failures.md) | Reproducibility, non-determinism sources, failure signatures, first divergence, record-and-replay, git bisect, discriminating experiments, deadlock wait-for chains, "passes interactively, fails in batch" |

## Recurring Myths (seen across many posts — don't repeat these in an interview)

| Myth | Reality | See |
|---|---|---|
| Quoting another company's internal flow or "% improvement" numbers | Only tell your own stories and numbers you measured | 02, 03 |
| VIP, coverage or testbenches depend on the **process node** | They model protocols and run in simulation; node matters for physical design, STA, power | 03, 18 |
| `create()` runs the child's `build_phase` | `create()` = factory lookup + `new()`; phasing runs build top-down later | 01, 07 |
| UVM has "8 phases" | 9 common phases + 12 run-time sub-phases | 07 |
| Seeds "prune" stimulus / good seeds stay good | Constraints define the space; seeds change meaning when code changes | 02, 09 |
| `#` is the SVA delay; `@(*)` clocks an assertion | `##` is the cycle delay; concurrent assertions need a real clock event | 08, 10 |
| `disable iff (stall)` handles stalls | It cancels the check; use goto repetition `[->n]` | 08 |
| `valid` without `ready` is an error; valid may wait for ready | A stall is legal; valid must never wait for ready (deadlock) | 10, 13 |
| VCS / Formality are formal property checkers | VCS is a simulator; Formality is an equivalence checker | 08, 14 |
| Formal proves full PCIe compliance | Formal targets blocks and rules; compliance needs VIP + compliance suites | 14 |
| Emulators run faster than real time; FPGAs prototype at GHz and check ASIC timing | Emulation ~MHz, FPGA ~10–100 MHz; ASIC timing is signed off with STA | 12 |
| Simulations run on TPUs | RTL simulators run on CPUs; licences are the usual bottleneck | 06 |
| Functional coverage "matters more" than code coverage | They catch different gaps; sign-off needs both plus checkers | 11 |
| Equivalence checking closes coverage | Formal helps coverage via unreachability and cover witness traces | 09 |
| RAL computes offsets itself; the predictor detects mismatches | Offsets are specified/generated; mismatches are found on checked reads | 15 |
| TLM has cycle latency; analysis FIFOs give back-pressure | TLM is untimed; analysis FIFOs are unbounded | 16 |
| PCIe: "no TLP when credits = 0" | Credits are per type; an advertised 0 means infinite | 17 |

## How each file is structured

1. The post (summary)
2. What's wrong with the post
3. Background concepts (fresher level)
4. Deep dive with code and worked examples
5. Likely interviewer follow-ups with model answers
6. Common mistakes
7. 60-second interview pitch
8. Self-check list
