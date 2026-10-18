# HPCA: Computer Architecture for CPU Verification Interviews

Study kit for the Georgia Tech / Udacity **High Performance Computer Architecture** (CS6290) course, framed for **Senior CPU Design Verification** interviews (NVIDIA-style roles). Every concept is paired with how you would verify it, the bugs that reach silicon, and interview questions with model answers.

## What's here

| Item | What it is | Best for |
|---|---|---|
| [`sheets/`](sheets/INDEX.md) | **127 flash sheets** as Markdown, one file per lesson (22 lessons) | Reading on GitHub or phone |
| [`html/flash-sheets/index.html`](html/flash-sheets/index.html) | Same 127 sheets as a flip-through page with a diagram on each sheet, ← / → keys, lesson strip, show/hide answers | Last-minute glancing before an interview |
| [`html/cpu-verification-codex.html`](html/cpu-verification-codex.html) | 14 longer module pages: mechanism diagram, numbers, spec / design / verify lenses, bugs, interview drill | Deeper revision of one topic |
| [`tools/export_markdown.js`](tools/export_markdown.js) | Regenerates `sheets/*.md` from the flash-sheet data | After editing a sheet |

**Opening the HTML pages:** GitHub shows HTML as source. Clone the repo and open the file in a browser (works offline except web fonts), or enable GitHub Pages for the repo.

## Each sheet has

1. One-line summary (the thing to say first)
2. Concepts, with a table where useful
3. Numbers and formulas to quote, and worked problems from the lecture quizzes
4. **Verification lens**: checkers, assertions, coverage and stimulus for this mechanism
5. **Bugs that ship**: realistic failure modes
6. **Interview** questions with answers

## Lessons

| # | Lesson | Sheets | Source |
|---|---|---|---|
| 01 | [Introduction](sheets/01-introduction.md) | 7 | lecture notes Ch 1 |
| 02 | [Metrics & evaluation](sheets/02-metrics-and-evaluation.md) | 9 | lecture notes Ch 2 |
| 03 | [Pipelining](sheets/03-pipelining.md) | 8 | lecture notes Ch 3 |
| 04 | [Branch prediction](sheets/04-branch-prediction.md) | 12 | annotated notes, Part 1 |
| 05 | [Predication](sheets/05-predication.md) | 3 | annotated notes, Part 1 |
| 06 | [ILP](sheets/06-ilp.md) | 5 | annotated notes, Part 2 |
| 07 | [Tomasulo](sheets/07-tomasulo.md) | 7 | annotated notes, Part 2 |
| 08 | [Reorder buffer](sheets/08-reorder-buffer.md) | 8 | annotated notes, Part 3 |
| 09 | [Memory ordering](sheets/09-memory-ordering.md) | 5 | annotated notes, Part 3 |
| 10 | [Compiler ILP](sheets/10-compiler-ilp.md) | 6 | annotated notes, Part 3 |
| 11 | [VLIW](sheets/11-vliw.md) | 3 | annotated notes, Part 3 |
| 12 | [Cache review](sheets/12-cache-review.md) | 10 | annotated notes, Part 3 |
| 13 | [Virtual memory](sheets/13-virtual-memory.md) | 6 | course content |
| 14 | [Advanced caches](sheets/14-advanced-caches.md) | 6 | course content |
| 15 | [Memory (DRAM)](sheets/15-memory-dram.md) | 3 | course content |
| 16 | [Storage](sheets/16-storage.md) | 2 | course content |
| 17 | [Fault tolerance](sheets/17-fault-tolerance.md) | 4 | course content |
| 18 | [Multiprocessing](sheets/18-multiprocessing.md) | 4 | course content |
| 19 | [Cache coherence](sheets/19-cache-coherence.md) | 8 | course content |
| 20 | [Synchronization](sheets/20-synchronization.md) | 4 | course content |
| 21 | [Memory consistency](sheets/21-memory-consistency.md) | 4 | course content |
| 22 | [Many-cores](sheets/22-many-cores.md) | 3 | course content |

Lessons 1–12 follow my own lecture notes, so each sheet names the videos it covers. Lessons 13–22 follow the course's standard content and are organised by concept; they will be redone against my notes when those are written.

## Corrections to my lecture notes

Flagged on the matching sheets as **Check your notes**:

- Speedup is `T_old / T_new` (Vid 51 note had it inverted).
- Vid 54 option 1 should read "**reduce** branch CPI from 4 to 3".
- Vid 66: pipeline CPI is ≥ 1 and usually **greater** than 1 because of stalls.
- Vid 21 large die cost is $5000 / 10 = **$500**, not $454.5.
- LSQ example: the first store wrote 25, so the cache gets **25**, not 28.

## Related material in this repo

- [26 OOO Tomasulo core](../26-ooo-cpu-tomasulo-core.md) · [27 OOO bug hunt](../27-ooo-core-bug-hunt.md) · [28 CPU verification](../28-cpu-verification-iss-random-sva-mutation.md) · [29 in-order pipeline](../29-pipelined-in-order-cpu-hazards.md) · [31 CPU question bank](../31-cpu-interview-question-bank.md)
- [32 Coherence and consistency](../32-cache-coherence-and-memory-consistency.md) and its kit [`cache-coherence/`](../cache-coherence/)
- [33 MMU & SMMUv3](../33-mmu-smmu/README.md)

## Source playlists

[Part 1](https://www.youtube.com/playlist?list=PLAwxTw4SYaPmqpjgrmf4-DGlaeV0om4iP) · [Part 2](https://www.youtube.com/playlist?list=PLAwxTw4SYaPkNw98-MFodLzKgi6bYGjZs) · [Part 3](https://www.youtube.com/playlist?list=PLAwxTw4SYaPnhRXZ6wuHnnclMLfg_yjHs) · [Part 4](https://www.youtube.com/playlist?list=PLAwxTw4SYaPn79fsplIuZG34KwbkYSedj) · [Part 5](https://www.youtube.com/playlist?list=PLAwxTw4SYaPkr-vo9gKBTid_BWpWEfuXe)
