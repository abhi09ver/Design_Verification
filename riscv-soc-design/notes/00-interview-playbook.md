# CPU DV Interview Playbook

This playbook prepares you for Senior CPU Verification interviews at NVIDIA, AMD, Google, ARM and Intel. Its goal is to turn the book chapters and the eleven labs into answers that sound like a senior engineer's.

Every answer in a senior CPU DV loop is really the same question asked at a different zoom level:

> **What could go wrong, how would you make it happen, how would you know it happened, and how would you know you're done?**

That maps to **stimulus, checker, coverage and closure**, the four columns of the book's DV plan (Ch 5.2). Answer every design question in those four columns.

## 1. Your story arc (say this in the first five minutes)

You are a RISC-V *subsystem* DV engineer moving to *CPU* DV. Don't hide that change; frame it:

- **What you already do at subsystem level:** register and pin-level verification (GPIO pinmux), interrupt and peripheral integration, APB/AHB-style interfaces, UVM environments with RAL (your ALIGNER\_UVM project), and CDC around peripherals.
- **What you added for the CPU core**, on your own initiative: you rebuilt the book's Wally microarchitecture piece by piece in cpu-from-scratch (single-cycle core → pipeline → traps → bus → cache → MMU → LSU → branch predictor → peripherals). You verified each piece with an ISS, lock-step compare, random generators, transaction models and functional coverage. Then you injected more than 50 bugs to measure which kind of check catches which kind of bug.
- **Thesis:** "I don't just run tests; I design the checking so that each class of bug has something that sees it. My labs showed that self-checking tests, lock-step and transaction models each miss bugs the others catch."

### The 60-second introduction

"I'm a DV engineer on a RISC-V subsystem today. I verify peripherals, pin muxing and interrupt paths around the core, mostly in UVM. To move into core verification, I rebuilt a five-stage RV32 pipeline the way the CORE-V Wally core is built: hazards, M-mode traps, an AHB bus, a write-back D-cache, an Sv32 MMU with a page-table walker, a synchronous-read LSU, gshare with a BTB and RAS, and the CLINT/PLIC/UART peripherals. I verified it against my own ISS in lock-step, with constrained-random generators and functional coverage. I then injected bugs on purpose to see which checks catch which bugs. The headline result: no single method caught everything. Lock-step missed performance-only bugs such as a stuck LRU and a broken RAS repair. Self-checks missed an off-by-four mepc. Loopback tests missed every protocol bug that the transmitter and receiver shared. That is how I'd approach a core here: layered checkers, with coverage saying which layer reached which scenario."

## 2. Company angles

These angles are drawn from public information and the book. Confirm the specifics against the job description and your recruiter before the loop.

| Company | What they are likely to probe | Chapters to refresh | Lab stories to lead with |
| --- | --- | --- | --- |
| **NVIDIA** | GPU-embedded RISC-V control cores (the book: more than a billion RISC-V cores shipped in NVIDIA GPUs); memory-subsystem corners; lock-step and coverage closure at scale; CDC and reset | 5, 7, 8, 10, 11, 20 | Lab 5 (traps), Lab 7 (cache transaction model), Lab 11 (set-vs-clear race, CDC synchronizer) |
| **AMD** | High-performance out-of-order cores (x86 and others); hazards, memory ordering, branch prediction, performance verification | 7, 10, 12, 13; plus OoO theory (ROB, rename, LSQ) | Lab 10 (exact predictor model, performance bugs), Lab 9 (store→load hazards) |
| **Google** | Custom silicon (TPU and SoC teams) and open-source RISC-V (riscv-dv originated at Google; OpenTitan uses Ibex); constrained-random ISA generation; coding rounds | 3, 5, 8, 11 | Lab 2 (generator + ISS), Lab 8 (random page tables), Ch 3 RISCOF/WARL |
| **ARM** | AMBA (AHB/AXI/CHI) as the native language, formal verification, architecture compliance (exceptions, MMU, memory model) | 5.10, 8, 9, 11 | Lab 6 (AHB bench, HSELD bug), Ch 9 AXI rules and assertions |
| **Intel** | Core and SoC validation at scale, coverage-driven closure, emulation/FPGA, post-silicon debug mindset; Intel is a RISC-V International premier member with a $1B fund (book Ch 2.9) | 5, 6, 8, 9, 10 | Lab 3 (debugging the first divergence), Lab 4 (STA by hand), chicken-bits answer (Ch 5 coverage check) |

**Your interviews at Google and NVIDIA are first.** Lead with Labs 2, 5, 7 and 11, and with CDC (the Ch 20 synchronizer and the set-vs-clear race). Have riscv-dv versus a hand-written generator ready for Google.

## 3. The question bank, cross-referenced

Each question has a **30-second answer** (the core idea), a **60-second answer** (core idea plus mechanism plus one number) and a **90-second answer** (plus how you'd verify it and a lab result). The model answers live in the chapter drills; this table tells you where.

### Pipeline and ISA

| Question | Model answer in | Lab proof |
| --- | --- | --- |
| Walk me through forwarding, the load-use stall and the branch flush | Ch 7 drill; Ch 2 Q5 | Lab 3 bug hunt |
| What happens when a stall and a flush arrive in the same cycle? | Ch 4 Q6; Ch 7 coverage check (hazard.sv) | Lab 3 |
| Why must forwarding never come from x0? | Ch 2 Q8 | Lab 3: the book's test missed it, random lock-step caught it 20/20 |
| Why are RISC-V immediates scrambled? | Ch 2 Q1 | — |
| Why does Wally commit in Writeback? | Ch 7 coverage check; Ch 8 precise traps | Lab 5 (faulting jalr must not write ra) |
| A divide is busy and a branch mispredicts: what happens? | Ch 7 coverage check (`BPWrongE & ~DivBusyE`) | Next lab (M extension) |

### Traps and privilege

| Question | Model answer in | Lab proof |
| --- | --- | --- |
| What does hardware do on an exception and on an interrupt? | Ch 8 drill 1 | Lab 5 cycle-by-cycle trace |
| Why isn't mepc PC+4 for ecall? | Ch 8 drill 2 | Lab 5 BUG\_MEPC\_PLUS4 passed a self-check |
| Can a U-mode program block an M timer interrupt? | Ch 8 drill 3 | — |
| How do you verify interrupt priority and delegation? | Ch 8 drill 4 | — |
| What is WARL and how do you test it? | Ch 8 drill 6; Ch 3 coverage check (riscv-config) | — |
| Why flush after a CSR write? | Ch 8 drill 7 | Lab 5: the missing flush was invisible, a lesson about test reach |
| Lock-step fails right after an interrupt: how do you debug it? | Ch 8 drill 8; Ch 5 lock-step | Lab 5 ISS follows the DUT's interrupt timing |
| How does FS gate FP state, and what do you cover? | Ch 8 coverage check | — |

### Methodology

| Question | Model answer in | Lab proof |
| --- | --- | --- |
| How would you verify a RISC-V core? | Ch 5 "Say it in the interview" | Labs 2–11 as the layered plan |
| Lock-step versus signatures? | Ch 5; Ch 3 signature strengths and weaknesses | Lab 5 |
| Code coverage versus functional coverage? | Ch 5.8–5.9 | Lab 3: 100% instruction coverage, bug escaped |
| When is verification done? | Ch 5 Q&A ladder | — |
| Walk me through debugging a failing regression | Ch 5 coverage check (the three-bug walkthrough) | Lab 3 first-divergence output |
| Where does formal pay off in a core? | Ch 5.10 | — |
| A performance bug lock-step can't see? | Ch 7 lab; Ch 13 | Labs 7, 8, 10 (stuck LRU, victim-0 TLB, RAS no-repair) |
| Your change improved the predictor and an old bug test stopped failing. Why? | Ch 13 Q8 | Lab 10 BUG\_INT\_BUBBLE |

### Memory system

| Question | Model answer in | Lab proof |
| --- | --- | --- |
| Explain the cache FSM: miss, dirty victim, flush | Ch 10 | Lab 7 |
| How do you verify pLRU, which never changes results? | Ch 10 drill | Lab 7 transaction model |
| VIPT: why is it legal for Wally's L1? | Ch 10 coverage check; Ch 11 | Lab 9 elaboration check |
| Walk a TLB miss through the HPTW | Ch 11; Ch 12 | Lab 8 GIF |
| PMP TOR/NAPOT edge cases | Ch 11 coverage check (Example 11.9) | Lab 8 BUG\_WALK\_NO\_PMP |
| Why can't an interrupt be taken during a bus transfer to a UART? | Ch 9 drill 7 | Lab 6 BUG\_NO\_COMMIT lost a byte |
| The Linux-boot hang from the shared EBU | Ch 12 drill 5 | — |

### Interconnect and SoC

| Question | Model answer in | Lab proof |
| --- | --- | --- |
| AHB pipeline, HREADY versus HREADYOUT, HSELD | Ch 9 drills 1–3 | Lab 6 HSELD bug found only at block level |
| State the AXI handshake rules and write an assertion | Ch 9 drill 5; coverage check | — |
| PLIC claim/complete and threshold | Ch 20 | Lab 11 PLIC\_THRESH\_GE |
| Why does loopback testing miss bugs? | Ch 20 | Lab 11: 4/14 bugs missed |
| CDC: a 2-flop synchronizer, and the set-versus-clear race | Ch 20 (and your own CDC study) | Lab 11 GPIO\_NO\_SYNC; overrun race fixed |
| Writing a RAL model for these peripherals | Ch 20 RAL notes | ALIGNER\_UVM RAL plan |

### Implementation

| Question | Model answer in | Lab proof |
| --- | --- | --- |
| Setup versus hold; what does clock skew do to each? | Ch 6.1.1 | Lab 4 sta.py |
| Verifying a clock-gating change | Ch 6 Q5 | — |
| Synthesis removed a register: should you care? | Ch 6 Q8 | Lab 4 (maxopt removed whole cores) |

## 4. Answer patterns that sound senior

- **Start from the bug, not the tool.** "The bug I'd worry about is X, because Y. To make it happen I'd do Z, and I'd see it with checker W."
- **Name what your checker can't see.** For example: "Lock-step won't see a stuck LRU, so I'd add a transaction model or performance bounds." Every lab gives you one of these lines.
- **Quantify.** Use your own numbers: a bus load costs exactly 2 cycles plus wait states; a TLB miss costs 3 cycles (5 over the bus); CPI 1.238 → 1.020 with gshare plus forwarding; 14/14 versus 10/14 bugs caught by the two Lab 11 benches.
- **Cross the hazards.** Senior answers always mention the cross: trap × stall, interrupt × committed bus transfer, mispredict × divide busy, sfence × stale TLB entry, write × read to the same SRAM.
- **Close with closure.** "I'd know I'm done when the functional coverage tied to the DV plan is 100%, the bug-find rate has flattened, every exclusion is reviewed, and the regression runs on two simulators."

## 5. The week-before checklist

1. Say the 60-second introduction out loud three times.
2. Re-derive these on paper: the hazard.sv equations (Ch 7 coverage check), the trap entry sequence (Ch 8), the AHB HSELD timing (Ch 9 Example 9.2), the pLRU update (Example 10.8), an Sv32 walk (Ch 11), the GHR forwarding (Example 13.3), and a PLIC claim (Ch 20).
3. Rehearse one lab story per company angle (table above).
4. Prepare two questions to ask them, for example: "Which checking layer finds most of your late bugs?" and "How do you verify performance features that don't change architectural state?"
5. Re-read the *Book coverage check* in Ch 5, 7 and 8 the night before.
