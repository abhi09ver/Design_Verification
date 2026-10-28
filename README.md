# Design_Verification

Interview preparation notes for Senior Design Verification (DV) Engineer roles.
Each file takes one DV interview topic (often from a LinkedIn post), checks what the post got right and wrong, explains the topic from first principles, and ends with likely interviewer follow-ups and a 60-second answer pitch.

> **Before an interview:** start at **[`axi-interview-prep/`](axi-interview-prep/)**. It has 15 one-page AXI and DV cheat sheets (PDF, PNG, HTML), runnable AXI slave code with a self-checking testbench, an SVA checker, and the bug-and-fix story for the AXI4-Lite UVM project. The all-in-one PDF is [`AXI_DV_Interview_Cheatsheets_ALL.pdf`](axi-interview-prep/AXI_DV_Interview_Cheatsheets_ALL.pdf).

> **CPU verification track:** **[`riscv-soc-design/`](riscv-soc-design/README.md)**: chapter-by-chapter notes on *RISC-V System-on-Chip Design* (Ch 1–13, 20) with a book map and a CPU DV interview playbook, plus `cpu-from-scratch`, a Wally-style RV32 core with lock-step verification and 11 bug-hunt labs.

## SV Course Sessions — solved exercises with runnable code

**[sv-course-sessions/](sv-course-sessions/)**: worked solutions to the exercise slides from five SystemVerilog / UVM course sessions, each compiled and simulated. **Quick revision: [CHEATSHEET.md](sv-course-sessions/CHEATSHEET.md).**

| Session | Topic | Notes |
|---|---|---|
| 1 | SV data structures: arrays, queues, assoc arrays, strings (23 Qs) | [notes](sv-course-sessions/01-session1-sv-data-structures.md) |
| 2 | Layered UVM agent for AXI and AHB | [notes](sv-course-sessions/02-session2-layered-axi-ahb-agent.md) |
| 3 | Dual-port APB driver / monitor / scoreboard (no UVM) | [notes](sv-course-sessions/03-session3-apb-dual-port-testbench.md) |
| 4 | 12 constraint questions (4KB, alignment, primes, patterns…) | [notes](sv-course-sessions/04-session4-constraints.md) |
| 5 | APB functional coverage model | [notes](sv-course-sessions/05-session5-apb-functional-coverage.md) |

## Aligner UVM course: one-stop interview folder

**[aligner-uvm-course/](aligner-uvm-course/README.md)** covers Cristian Slav's UVM course on the Aligner DUT end to end: a [last-30-minutes cheatsheet](aligner-uvm-course/cheatsheets/LAST-30-MINUTES.md), [7 STAR stories](aligner-uvm-course/cheatsheets/STORIES.md), [244 interview Q&A](aligner-uvm-course/INTERVIEW-QA.md), chapter notes, the interactive study pages, and the full RTL + UVM project code.

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
| 26 | [Out-of-Order CPU: The 3-Wide Tomasulo Core](26-ooo-cpu-tomasulo-core.md) | Rename/RAT, ROB as physical register, RS wakeup/select, CDB + completion buffer, in-order commit, LSQ, circular-buffer age, branch-recovery capstone |
| 27 | [Bug Hunt: 15 Real Bugs in an OOO Core](27-ooo-core-bug-hunt.md) | Bug masking, sentinel bugs (tag 0, way 3), lost instructions, memory ordering & SQ deadlock, Booth −2M overflow, frontend back-pressure, STAR bug stories |
| 28 | [Verifying a CPU: ISS, Random, SVA, Mutation](28-cpu-verification-iss-random-sva-mutation.md) | Commit-trace scoreboard vs ISS, liveness watchdog, hazard-dense random, bind SVA, unit tests, mutation testing, random blind spots, perf checks |
| 29 | [Pipelined In-Order CPU (Pequeno-style 5-stage)](29-pipelined-in-order-cpu-hazards.md) | RV32I formats, valid/stall/flush, forwarding distances 1–3, load-use interlock, static prediction, cycles = 4 + N + stalls + 2×flushes |
| 30 | [CPU From Zero: 11-Level RTL Ladder](30-cpu-from-zero-rtl-ladder.md) | Adder → counter → ALU → regfile → FIFO → single-cycle CPU → scoreboard → rename → RS/CDB → ROB → tiny OOO; RTL rules of thumb |
| 31 | [CPU Interview Question Bank](31-cpu-interview-question-bank.md) | Every CPU question from 26–30 with model answers, pitches and measured numbers |
| 32 | [Cache Organization, Coherence & Memory Consistency](32-cache-coherence-and-memory-consistency.md) | Tag/index/offset, write policies, inclusion, SWMR & data-value invariants, MOESI, transient-state races, snoop vs directory, virtual networks, SC/TSO/weak litmus tests, GPU scoped acquire/release, coherence checkers & coverage. Kit with HTML guides, cheat sheet, Python models and SV checkers in [`cache-coherence/`](cache-coherence/) |
| 33 | [MMU & SMMUv3 One-Stop Kit](33-mmu-smmu/README.md) | VA/PA, pages, multi-level walks, TLB/ASID/VMID, stage 1/2 nesting, StreamID→STE→CD, command/event queues, CMD_SYNC, stall vs terminate, ATS/PRI/PASID, RME/GPC, invalidation-aware scoreboard; Python model, SVA, UVM code, fresher + senior HTML guides |
| 34 | [CoreSight Debug and Trace](34-coresight-debug-and-trace.md) | DAP (DP/AP), ID registers, ROM tables & discovery, topology detection, APB/ATB/event/channel/timestamp, authentication, trace formatter, CTI/CTM, power & reset, vplan, SVA, bug catalog. **Kit:** [`coresight/`](coresight/README.md) (beginner + senior HTML guides, Python golden models, SVA checkers, [cheat sheet](coresight/CHEATSHEET.md)) |
| 35 | [Arm GIC Interrupt Controller (GICv3/v4)](35-gic-interrupt-controller.md) · [study kit](35-gic/) | Distributor/Redistributor/CPU IF/ITS, INTID map, state machine, groups → IRQ/FIQ, PMR/BPR/preemption, EOImode, LPIs & ITS commands, list registers & GICv4, WAKER; beginner + senior HTML pages, Python ref model, SVA, UVM scoreboard |
| 36 | [HPCA: Computer Architecture Flash Sheets](hpca/README.md) | Georgia Tech HPCA course in 127 one-screen sheets across 22 lessons: iron law & Amdahl, pipelining & hazards, branch predictors (2BC, PShare, GShare, tournament, RAS), predication, ILP & renaming, Tomasulo, ROB & precise exceptions, LSQ & memory disambiguation, compiler ILP, VLIW, caches, VM/TLB, VIPT, MSHRs, DRAM, RAID & ECC, coherence (MSI/MESI/MOESI, directories, transient races), atomics & locks, SC/TSO/weak litmus tests, NoC & GPUs. Each sheet: worked numbers, verification lens, bugs that ship, interview Q&A. Flip-through HTML + Markdown per lesson in [`hpca/`](hpca/) |
| 37 | [YARP Single-Cycle Core Review](37-yarp-single-cycle-core-review.md) | 4 RTL bugs found vs ISS, valid/ready spec mismatch, reviewed interface with driver/monitor clocking blocks + protocol SVA |
| 38 | [YARP Class-Based Testbench Review](38-yarp-class-based-testbench-review.md) | Course TB fixed in place: 3 compile + 14 functional TB bugs, C++ DPI model, coverage closure, mutation table (9/9 bugs caught, 0 false alarms) |
| 39 | [RISC-V Core & DV Atlas](cpu-lab/pages/riscv_dv_atlas.html) | 27 one-page infographics: ISA → single-cycle → pipeline → OOO/LSQ/caches → DV strategy, golden model, TB anatomy, random, SV timing, SVA, coverage, mutation, bug catalog, debug, rapid-fire drills |

## CPU Lab (code for challenges 26–31 and 37–39)

[`cpu-lab/`](cpu-lab/README.md) holds the runnable code: the uploaded 3-wide OOO core with all fixes and per-file patches, a commit-scoreboard testbench with an ISS, 20 directed bug hunts, a random generator, bind-based SVA, a 5-stage pipelined RV32I CPU (pq5), an 11-level beginner RTL ladder, the YARP single-cycle core with its class-based testbench (C++ ISS over DPI, coverage, protocol SVA, runtime mutation campaign), and four HTML study pages in [`cpu-lab/pages/`](cpu-lab/pages/), including the 27-plate **[RISC-V Core & DV Atlas](cpu-lab/pages/riscv_dv_atlas.html)** for a last-minute skim. Runs on free Verilator.

## Protocol Packs

| Pack | Contents |
|---|---|
| [UART DV Interview Pack](uart-dv-pack/README.md) | 10 one-page cards (PDF / HTML / PNG), text cheatsheet, UVM reference environment: baud, framing, parity, break, overrun, idle-line checks |

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
| "The test passes, so the design works" | A hand-written checker on one program passed 33/33 while 15 bugs remained; an assertion fired on that same passing test | 27, 28 |
| Out-of-order means results can be written to registers as soon as they're ready | Execution is out of order; commit to architectural state stays in program order (precise state) | 26, 30 |

## How each file is structured

1. The post (summary)
2. What's wrong with the post
3. Background concepts (fresher level)
4. Deep dive with code and worked examples
5. Likely interviewer follow-ups with model answers
6. Common mistakes
7. 60-second interview pitch
8. Self-check list
