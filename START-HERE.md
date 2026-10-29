# Start here: Senior DV interview preparation map

Everything in this repo, arranged by **what the interviewer will ask** rather than by when it was written. Each row points to the fastest file first and the deep one second.

> **GitHub shows `.html` as source.** Download the repo (Code → Download ZIP) and open the pages locally; they work offline except for web fonts.

## The night before (90 minutes)

| Minutes | Read | Why |
|---|---|---|
| 20 | [39 – RISC-V Core & DV Atlas](cpu-lab/pages/riscv_dv_atlas.html) | 27 one-page plates: ISA → pipeline → OOO → verification → bug stories |
| 15 | [AXI & DV cheat sheets (PDF)](axi-interview-prep/AXI_DV_Interview_Cheatsheets_ALL.pdf) | 15 one-pagers on the most-asked protocol |
| 15 | [31 – CPU question bank](31-cpu-interview-question-bank.md) | Model answers with measured numbers |
| 15 | [40 – 5-stage pipeline: six questions](40-five-stage-pipeline-interview-answers.md) | The "you designed a pipeline?" checklist |
| 15 | [SV course cheat sheet](sv-course-sessions/CHEATSHEET.md) + [Aligner UVM Q&A](aligner-uvm-course/INTERVIEW-QA.md) | SystemVerilog and UVM recall |
| 10 | [README → Recurring Myths](README.md#recurring-myths-seen-across-many-posts--dont-repeat-these-in-an-interview) | Things not to say |

## By interview topic

| Topic | Quick | Deep | Hands-on code |
|---|---|---|---|
| **SystemVerilog language & OOP** | [SV cheat sheet](sv-course-sessions/CHEATSHEET.md) | [23 – SV OOP](23-systemverilog-oop.md), [sessions 1–5](sv-course-sessions/README.md) | `sv-course-sessions/code/` |
| **Constrained random** | [02](02-constrained-random-verification-storytelling.md) | [Session 4: 12 constraint puzzles](sv-course-sessions/04-session4-constraints.md), atlas plate 20 | YARP `yarp_tr_cmp` (`cpu-lab/yarp/qs/course_fixed/yarp_tests.sv`) |
| **UVM** | [07 – Pillars](07-uvm-pillars-phasing-factory-config-db.md) | [01](01-uvm-config-db-phasing-trap.md), [05](05-virtual-sequences.md), [15 RAL](15-uvm-register-model-ral.md), [16 TLM](16-uvm-tlm-ports-exports-fifos.md), [19 TB from scratch](19-building-uvm-testbench-from-scratch.md) | [`aligner-uvm-course/project/`](aligner-uvm-course/README.md) |
| **Class-based TB (non-UVM)** | atlas plate 19 | [38 – YARP TB review](38-yarp-class-based-testbench-review.md), [course notes](cpu-lab/yarp/qs/course_notes/README.md) | `cpu-lab/yarp/qs/course_fixed/` |
| **Assertions / formal** | [08 – SVA](08-sva-assertions.md) | [10 ready/valid](10-ready-valid-handshake-assertions.md), [13 beyond happy path](13-sva-beyond-happy-path.md), [14 formal](14-formal-verification.md) | `cpu-lab/tb/core_sva.sv`, YARP interface SVA |
| **Coverage & closure** | [11](11-functional-vs-code-coverage.md) | [09 plateau](09-coverage-plateau-closure.md), [18 architecture](18-coverage-architecture.md), atlas plate 23 | YARP compare-corner coverage (38 §1) |
| **Plans, metrics, sign-off** | [06 – Verification plan](06-verification-plan.md) | [20 – Metrics & sign-off](20-leading-verification-metrics-and-signoff-decisions.md) | — |
| **Debug stories** | atlas plates 25–26 | [25 – Intermittent failures](25-debugging-intermittent-and-persistent-failures.md), [27 – 15 OOO bugs](27-ooo-core-bug-hunt.md) | `cpu-lab/tests/b01..b19` |
| **TB qualification / mutation** | atlas plate 24 | [28 – CPU verification](28-cpu-verification-iss-random-sva-mutation.md), [38 §1](38-yarp-class-based-testbench-review.md) | `cpu-lab/yarp/qs/rtl_mut/` (`+MUT=n`) |
| **Emulation / FPGA** | [12](12-emulation-and-fpga-prototyping.md) | — | — |
| **VIP reuse** | [03](03-verification-ip-reuse.md) | — | — |

### CPU and computer architecture

| Topic | Quick | Deep | Hands-on code |
|---|---|---|---|
| **Fundamentals from zero** | [30 – RTL ladder](30-cpu-from-zero-rtl-ladder.md) | [`cpu_from_zero.html`](cpu-lab/pages/cpu_from_zero.html) | `cpu-lab/beginner/L01..L11` |
| **RV32I ISA, single-cycle** | atlas plates 1–9 | [37 – YARP core review](37-yarp-single-cycle-core-review.md) | `cpu-lab/yarp/` |
| **5-stage pipeline & hazards** | [40 – Six questions](40-five-stage-pipeline-interview-answers.md) | [29 – Pipelined CPU](29-pipelined-in-order-cpu-hazards.md), [`pequeno_study_guide.html`](cpu-lab/pages/pequeno_study_guide.html) | `cpu-lab/pq5/` |
| **Out-of-order / Tomasulo** | atlas plates 14–15 | [26 – Tomasulo core](26-ooo-cpu-tomasulo-core.md), [27 – Bug hunt](27-ooo-core-bug-hunt.md), [`tomasulo_core_lab.html`](cpu-lab/pages/tomasulo_core_lab.html) | `cpu-lab/rtl`, `solutions`, `tb` |
| **Whole HPCA course** | [HPCA flash sheets (127)](hpca/sheets/INDEX.md) | [`hpca/html/flash-sheets/index.html`](hpca/html/flash-sheets/index.html), [my lecture notes](hpca/notes/README.md) | — |
| **Caches, coherence, consistency** | [cache cheat sheet](cache-coherence/CHEATSHEET.md) | [32](32-cache-coherence-and-memory-consistency.md) | `cache-coherence/sv`, `python` |
| **MMU / SMMUv3** | [cheat sheet](33-mmu-smmu/05-cheat-sheet.md) | [33 kit](33-mmu-smmu/README.md) | `33-mmu-smmu/code` |
| **Interrupts (GIC)** | [35](35-gic-interrupt-controller.md), [beginner PDF](35-gic/printables/gic-from-zero.pdf) | [Field Guide PDF](35-gic/printables/gic-field-guide.pdf), [study kit](35-gic/README.md), [spec + page map](35-gic/docs/README.md) | `35-gic/code` |
| **Debug & trace (CoreSight)** | [CoreSight cheat sheet](coresight/CHEATSHEET.md) | [34](34-coresight-debug-and-trace.md) | `coresight/code` |
| **Accelerators** | [04 – Systolic arrays](04-systolic-array-underutilization.md) | — | — |

### Protocols

| Protocol | Quick | Deep | Hands-on code |
|---|---|---|---|
| **AXI / AHB / APB** | [AXI PDF](axi-interview-prep/AXI_DV_Interview_Cheatsheets_ALL.pdf) | [17 – Bus protocols](17-bus-protocols-axi-ahb-pcie.md), [sessions 2–3, 5](sv-course-sessions/README.md) | `axi-interview-prep/code` |
| **PCIe** | [22 – LTSSM](22-pcie-ltssm-link-recovery.md) | [21 – AXI↔PCIe bridge](21-protocol-bridge-verification-axi-to-pcie.md) | — |
| **UART** | [UART cheat sheet](uart-dv-pack/UART_CHEATSHEET.md) | [cards PDF](uart-dv-pack/uart-dv-cards.pdf) | `uart-dv-pack/code` |
| **Ready/valid (generic)** | [10](10-ready-valid-handshake-assertions.md) | atlas plate 8 | YARP `rtl_vr` + interface SVA |
| **GPIO / pinmux** (your own project area) | [GPIO field guide (HTML)](41-gpio-core-pinmux/gpio-dv-field-guide.html) | [41 – GPIO core & pinmux](41-gpio-core-and-pinmux-verification.md), [pinmux STAR story](41-gpio-core-pinmux/interview-story-pinmux.md) | `41-gpio-core-pinmux/tb`, `rtl` (`make smoke`, `make bugs`) |

## Career framing

- [24 – Early-career expectations & portfolio](24-early-career-dv-expectations-and-portfolio.md)
- [20 – Leading verification](20-leading-verification-metrics-and-signoff-decisions.md)
- **60-second pitches**: the last section of every numbered file, plus [31](31-cpu-interview-question-bank.md) and [40](40-five-stage-pipeline-interview-answers.md)

## Your numbers (say these)

| Project | Number |
|---|---|
| Tomasulo OOO core | 15 RTL bugs; random suite 0/720 → 720/720 after fixes; B12 failed 79/120 seeds before its fix |
| pq5 5-stage | 10/10 directed + 500/500 random; cycles = 4 + N + stalls + 2×flushes; no-prediction CPI 1.02 → 1.66 |
| YARP core | 4 RTL bugs (SLT, branch signedness, JALR phantom load, first-cycle double execute) |
| YARP course TB | 17 TB bugs fixed; mutation 4/9 → 9/9 caught, false failures 40% → 0 |
| GPIO kit (41) | 37/37 directed checks; 4/4 injected bugs caught; the W1C-vs-event race passed every directed check and only a white-box assertion caught it |
