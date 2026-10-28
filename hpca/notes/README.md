# My HPCA lecture notes

My own notes on the Georgia Tech / Udacity **High Performance Computer Architecture** course: typed explanations plus hand-drawn diagrams and worked quizzes. The [flash sheets](../sheets/INDEX.md) for lessons 1–12 were built from these notes.

| # | Notes | Pages | Course lessons | Flash sheets | Text copy |
|---|---|---|---|---|---|
| 1 | [Ch 1 · Introduction](pdf/01-ch1-introduction.pdf) | 2 | Vid 1–24: Moore's law, memory wall, power, yield & cost | [01](../sheets/01-introduction.md) | [text](text/01-ch1-introduction.md) |
| 2 | [Ch 2 · Metrics & evaluation](pdf/02-ch2-metrics-and-evaluation.pdf) | 5 | Vid 25–57: latency/throughput, benchmarks, geometric mean, iron law, Amdahl | [02](../sheets/02-metrics-and-evaluation.md) | [text](text/02-ch2-metrics-and-evaluation.md) |
| 3 | [Ch 3 · Pipelining](pdf/03-ch3-pipelining.pdf) | 6 | Vid 59–82: CPI, flushes, dependences vs hazards, forwarding, depth | [03](../sheets/03-pipelining.md) | [text](text/03-ch3-pipelining.md) |
| 4 | [Part 1 · Branch prediction & predication](pdf/04-part1-branch-prediction-and-predication.pdf) | 26 | BTB, BHT, 1-bit, 2BC, history, PShare, GShare, tournament, RAS, if-conversion | [04](../sheets/04-branch-prediction.md), [05](../sheets/05-predication.md) | [text](text/04-part1-branch-prediction-and-predication.md) |
| 5 | [Part 2 · ILP & Tomasulo](pdf/05-part2-ilp-and-tomasulo.pdf) | 24 | renaming, RAT, ILP vs IPC, issue/dispatch/broadcast, timing tables | [06](../sheets/06-ilp.md), [07](../sheets/07-tomasulo.md) | [text](text/05-part2-ilp-and-tomasulo.md) |
| 6 | [Part 3 · ROB, memory ordering, compiler ILP, VLIW, caches](pdf/06-part3-rob-memory-ordering-compiler-ilp-vliw-caches.pdf) | 65 | ROB & recovery, LSQ, scheduling, unrolling, VLIW, cache review | [08](../sheets/08-reorder-buffer.md)–[12](../sheets/12-cache-review.md) | [text](text/06-part3-rob-memory-ordering-compiler-ilp-vliw-caches.md) |

Not yet written: lessons 13–22 (virtual memory onwards). Their flash sheets follow the course content for now.

**Corrections** found while building the sheets are listed in the [HPCA README](../README.md#corrections-to-my-lecture-notes) and flagged on each affected sheet.

**About the files:** the PDFs were recompressed (slide screenshots re-encoded as JPEG; handwriting and text unchanged) to bring the six files from 114 MB to 22 MB. GitHub's PDF viewer may not open the larger ones in the browser; use Download. The text copies are for searching on GitHub and are not reviewed for layout.
