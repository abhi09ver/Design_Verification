# Start here · Book map

This tab shows where each section of *RISC-V System-on-Chip Design* (Harris, Stine, Thompson & Harris) is covered in these notes.

I audited Chapters 1–13 and 20 section by section against the full book text. Each chapter tab now ends with a **Book coverage check** that adds whatever the main notes had missed: worked examples, tables, Wally RTL details, and slips in the book itself. Read a chapter tab top to bottom and you have the chapter. You only need the book itself for the figures.

Chapters 14–19 and 21–23 are not covered, at your request; there is a pointer list for them at the end.

## How to use this doc in the last week before an interview

1. Read the **Interview Playbook** tab first. It tells you which chapters each company will probe.
2. For each chapter, read the *recap and interview drill* at the bottom of its tab, then its *Book coverage check*. Go back into the body only for the questions you can't answer out loud.
3. Rehearse the lab stories. Every lab is something you built, broke on purpose and measured, and those are the answers that separate a senior candidate from someone who has only read about it.

## Chapter-by-chapter map

| Book chapter | Sections | Where in these notes | Lab | Coverage status |
| --- | --- | --- | --- | --- |
| 1 · History of Computer Design | 1.1–1.9 | Ch 1 tab; coverage check adds the open-source history, why Dennard scaling ended, pipeline-depth ranges | — | Complete |
| 2 · Introduction to RISC-V | 2.1–2.10 (all 38 sub-sections) | Ch 2 tab; coverage check adds Code Examples 2.1–2.13, the toy-core SV internals (lazy Sub decode, SLT via overflow), testbench critique, Tables 2.10–2.13 cores | Lab 1 (single-cycle core), Lab 3 (pipeline) | Complete |
| 3 · Software Tool Flow | 3.1–3.8 | Ch 3 tab; coverage check adds the arch-test pool, canary, riscv-config WARL YAML, RISCOF work layout, how to add a wally-riscv-arch-test | Lab 2 (ISS + lock-step) | Complete |
| 4 · HDL Design Practices | 4.1–4.5, 44 guidelines, 46 code examples | Ch 4 tab; coverage check adds $clog2, or\_rows, reset synchronizer, DesignWare branch, and (beyond the book) unique/priority case | all labs (RTL style) | Complete |
| 5 · Design Verification | 5.1–5.12 | Ch 5 tab (the deepest tab); coverage check adds the exact three-bug debug walkthrough, riscvISACOV coverage levels, chicken bits | Lab 2, Lab 3 bug hunt | Complete |
| 6 · Logic Synthesis | 6.1–6.6, Tables 6.1–6.12 | Ch 6 tab; coverage check adds activity-factor defaults, the hazard netlist, latch register files, the area breakdown | Lab 4 (Yosys + own STA) | Complete |
| 7 · Pipelined Core | 7.1–7.5, Tables 7.1–7.10 | Ch 7 tab; coverage check adds commit-in-W, the prefix comparator and Example 7.2, Table 7.8, **the full hazard.sv with interview talking points** | Lab 3 | Complete |
| 8 · Privileged Operations | 8.1–8.5, Tables 8.1–8.12 | Ch 8 tab; coverage check adds the FS/VS/XS protocol, UXL/SXL, TW/TVM/TSR, the counter CSRs, envcfg bits, mip writability, AIA, exact interrupt-test recipes | Lab 5 (privileged unit) | Complete |
| 9 · Bus Interface | 9.1–9.6, Tables 9.1–9.9 | Ch 9 tab; coverage check adds the full AHB signal/encoding table (HSIZE, HBURST, HRESP note), AXI4 encodings, skid-buffer reasoning | Lab 6 (AHB + uncore) | Complete |
| 10 · Caches | 10.1–10.5, Examples 10.1–10.8 | Ch 10 tab; coverage check adds port structure, Examples 10.6/10.7 cycle by cycle (with the book's address slip), hierarchy sizing rules | Lab 7 (D-cache) | Complete |
| 11 · Virtual Memory | 11.1–11.5, Examples 11.1–11.9 | Ch 11 tab; coverage check adds physical reach, Svpbmt, PMA/PMP rules, TLB CAM, **Example 11.9 with the book's TOR slip corrected** | Lab 8 (MMU) | Complete |
| 12 · Load/Store Unit | 12.1–12.7 | Ch 12 tab; coverage check adds the EBU burst fixes and fault timing | Lab 9 (sync-read D-cache) | Complete |
| 13 · Instruction Fetch Unit | 13.1–13.4 | Ch 13 tab; coverage check adds GHR update rules, misprediction-rate formulas, RAS repair cases, INSTR\_CLASS\_PRED | Lab 10 (branch predictor) | Complete |
| 20 · Peripherals | 20.1–20.6 | Ch 20 tab, written from the full online chapter, including the book's code errata | Lab 11 (GPIO/CLINT/PLIC/UART/SPI, 14-bug hunt) | Complete |

## Section index for the chapters most asked in CPU DV loops

| Topic an interviewer names | Book section | Tab → heading |
| --- | --- | --- |
| Instruction formats, immediates | 2.1–2.2 | Ch 2 → 2.2 Machine language |
| Traps, mepc/mcause/mtval | 2.3.5, 8.2.5 | Ch 2 → 2.3; Ch 8 → 8.2.5 and coverage check |
| Reference models, lock-step, RVVI | 5.1.2, 5.6, 5.11.9 | Ch 5 → 5.6 |
| Code vs functional coverage | 5.8, 5.9 | Ch 5 → 5.8, 5.9 and coverage check |
| Constrained random (riscv-dv) | 5.9.3 | Ch 5 → 5.9.3 |
| Formal | 5.10 | Ch 5 → 5.10 |
| Debugging a failing regression | 5.11.7 | Ch 5 → coverage check (three-bug walkthrough) |
| Setup/hold, STA, power | 6.1 | Ch 6 → 6.1.1–6.1.3 |
| Forwarding, stalls, flushes | 7.2.2 | Ch 7 → 7.2.2 and the hazard.sv in its coverage check |
| Precise exceptions | 8.1.2, 8.4.5.1 | Ch 8 → precise vs imprecise; Ch 7 → commit in W |
| Interrupt priority, delegation | 8.2.5.3–8.2.5.5 | Ch 8 → Interrupts, Delegation |
| WARL, CSR permissions | 8.2.3 | Ch 8 → 8.2.3; Ch 3 → riscv-config WARL |
| AHB/APB/AXI protocol | 9.2 | Ch 9 → 9.2 and coverage check |
| Cache FSM, pLRU, write-back | 10.1, 10.4 | Ch 10 → 10.4 |
| TLB, page walk, Sv39, PMP | 11.1–11.4 | Ch 11 |
| Load/store hazards with a cache | 12.4 | Ch 12 → 12.4 |
| Gshare, BTB, RAS | 13.1, 13.3.3 | Ch 13 |
| CLINT, PLIC, UART, CDC sync | 20.1–20.4 | Ch 20 |

## Labs index (all in cpu-from-scratch)

| Lab | Book | You built | What the bug hunt taught | Where it is written up |
| --- | --- | --- | --- | --- |
| 1 | 2.7.1, 7.1 | Single-cycle RV32I core, module names as in Wally | — | Labs tab |
| 2 | 5.1, 5.6, 5.9 | Python ISS, random generator, lock-step compare, functional coverage | Lock-step finds what self-checks miss | Labs tab |
| 3 | 2.7.2, 7.2 | 5-stage pipeline: forwarding, load-use stall, branch flush | x0-forward bug missed by the book's test; load-use bug missed by a 100%-instruction-coverage directed test | Labs tab |
| 4 | 6 | Yosys/ABC on SKY130, your own NLDM STA and power estimator | A half-cycle negedge path sets the real limit; 82% of power is clocking | Ch 6 tab |
| 5 | 8 | M-mode CSRs, traps, interrupts | mepc+4 passes a self-check but fails lock-step; a missing CSR flush can be invisible | Ch 8 tab |
| 6 | 9 | AHB port, uncore, APB bridge, block-level AHB bench | A polite CPU hides interconnect bugs; layered benches | Ch 9 tab |
| 7 | 10 | Write-back D-cache, pLRU, flush, bursts | A stuck LRU is invisible to everything except a transaction model | Ch 10 tab |
| 8 | 11 | Sv32 DTLB, HPTW, PMP, U-mode | TLB victim bug is performance-only; walker PMP bug needs randomized table placement | Ch 11 tab |
| 9 | 12 | Synchronous-read D-cache, VIPT, store-to-load re-read | The generator's addressing style decides which hazards you reach | Ch 12 tab |
| 10 | 13 | BTB + class, bimodal/gshare + GHR forwarding, RAS | An exact predictor model turns performance bugs into failures; a predictor removed coverage of an old bug | Ch 13 tab |
| 11 | 20 | GPIO, CLINT, PLIC, 16550 UART, SPI + cycle-exact bench | Loopback misses every self-consistent protocol bug (4/14); set-vs-clear race found | Ch 20 tab |

## Not covered (by your choice), with a one-line pointer each

| Chapter | What it adds | One interview fact worth knowing anyway |
| --- | --- | --- |
| 14 · C extension | 16-bit instructions, decompressor in Decode | Instructions can straddle a cache line or page ("spills"), a classic IFU corner |
| 15 · M extension | Multiplier and radix-2/4 divider | The divider stalls E with DivBusyE; see the hazard.sv in the Ch 7 coverage check |
| 16 · F/D/Q/Zfh | FMA, divide/sqrt, conversions, TestFloat | Rounding modes × exceptions × NaN boxing are the coverage space |
| 17 · A extension | LR/SC, AMOs, fences | Reservation-set loss on traps and interrupts is the classic bug class |
| 18 · Zb\*/Zk\* | Bit manipulation, scalar crypto | Data-independent latency (Zkt) is a security requirement you can verify |
| 19 · Other extensions | Zicbo\*, Zicond, Zicclsm, Zfa and others | Cache-block ops interact with PMA and coherence |
| 21 · Benchmarking | CoreMark, Embench, performance counters | Use counters (Ch 8 coverage check) to tie CPI to causes |
| 22 · Linux boot | OpenSBI, device tree, boot in lock-step | 550M instructions; the ultimate system test, the worst debug signal |
| 23 · FPGA | Vivado flow, Arty A7 / VCU108/118 | Emulation is the 5.1.4 story |
