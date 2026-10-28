# RISC-V SoC Design: book notes + CPU-from-scratch labs

Interview prep for **Senior CPU Verification** roles, built chapter by chapter from
*RISC-V System-on-Chip Design* (Harris, Stine, Thompson & Harris) and the CORE-V Wally core
([openhwgroup/cvw](https://github.com/openhwgroup/cvw)).

**Start here:** [`notes/00-book-map.md`](notes/00-book-map.md) (where every book section is covered) and
[`notes/00-interview-playbook.md`](notes/00-interview-playbook.md) (story arc, company angles, question bank).

## Notes (Markdown export of the interview-notes doc)

Each chapter ends with a recap, an interview drill and a **Book coverage check** from a section-by-section audit
against the full book text. Chapters 14–19 and 21–23 are intentionally not covered. Diagrams and interactive
widgets from the original doc appear as text placeholders.

| Chapter | Notes | Lab |
|---|---|---|
| 1 History of Computer Design | [ch01](notes/ch01-history-of-computer-design.md) | — |
| 2 Introduction to RISC-V | [ch02](notes/ch02-introduction-to-risc-v.md) | 1, 3 |
| 3 Software Tool Flow | [ch03](notes/ch03-risc-v-software-tool-flow.md) | 2 |
| 4 HDL Design Practices | [ch04](notes/ch04-hdl-design-practices.md) | — |
| 5 Design Verification | [ch05](notes/ch05-design-verification.md) | 2, 3 |
| 6 Logic Synthesis | [ch06](notes/ch06-logic-synthesis.md) | 4 |
| 7 Pipelined Core | [ch07](notes/ch07-pipelined-core.md) | 3 |
| 8 Privileged Operations | [ch08](notes/ch08-privileged-operations.md) | 5 |
| 9 Bus Interface | [ch09](notes/ch09-bus-interface.md) | 6 |
| 10 Caches | [ch10](notes/ch10-caches.md) | 7 |
| 11 Virtual Memory | [ch11](notes/ch11-virtual-memory.md) | 8 |
| 12 Load/Store Unit | [ch12](notes/ch12-load-store-unit.md) | 9 |
| 13 Instruction Fetch Unit | [ch13](notes/ch13-instruction-fetch-unit.md) | 10 |
| 20 Peripherals | [ch20](notes/ch20-peripherals.md) | 11 |
| Labs 1–3 walkthrough | [labs](notes/labs-build-a-cpu.md) | 1–3 |

## Code: [`cpu-from-scratch/`](cpu-from-scratch/)

An RV32I core built the way Wally is built (single-cycle → 5-stage pipeline → traps → AHB bus → D-cache → Sv32 MMU →
sync-read LSU → branch predictor → GPIO/CLINT/PLIC/UART/SPI), verified with a Python ISS in lock-step,
constrained-random generators, transaction models and functional coverage, plus 50+ injected-bug hunts.
See [`cpu-from-scratch/README.md`](cpu-from-scratch/README.md) for `make` targets and results.
Generated synthesis netlists, build outputs and the downloaded SKY130 `.lib` are not committed;
`synth/run_all.sh` regenerates them.
