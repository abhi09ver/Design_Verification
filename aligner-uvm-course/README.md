# Aligner UVM course: interview one-stop folder

Everything from studying Cristian Slav's course *Design Verification with SystemVerilog and UVM Library* (Aligner DUT), in one place: cheatsheets, every interview question with a model answer, chapter notes, the two interactive study pages, your complete project code and the exercise solution.

## Before the interview: read in this order

| When | Open | What it gives you |
|---|---|---|
| 30 minutes before | [cheatsheets/LAST-30-MINUTES.md](cheatsheets/LAST-30-MINUTES.md) | Project pitch, the DUT in 6 lines, a table of 20 facts interviewers probe, the bugs you can claim, questions to ask them |
| Evening before | [cheatsheets/STORIES.md](cheatsheets/STORIES.md) | 7 STAR stories ("a bug you found", "a hard debug", …). Say each one out loud in 60–90 s. |
| Practice drills | [INTERVIEW-QA.md](INTERVIEW-QA.md) | All 244 questions from both pages, with collapsible model answers. Answer first, then open. |
| Deep revision | [notes/](notes/) | Chapter notes as Markdown: readable on GitHub and on your phone |
| Visual / interactive | [pages/](pages/) | The two HTML study pages (diagrams, 7 toys). Download and open in a browser. |
| Code questions | [project/](project/) | The full RTL and UVM environment (46 files) to point at while answering |

## What's inside

```
aligner-uvm-course/
├── cheatsheets/
│   ├── LAST-30-MINUTES.md      one-page final revision
│   └── STORIES.md              7 interview stories in STAR format
├── INTERVIEW-QA.md             244 Q&A, grouped by topic, linked to notes
├── notes/
│   ├── uvm-from-zero/          beginner course + lecture companion (112 videos)
│   │   ├── 00-levels-beginner.md
│   │   ├── 01-course-intro.md
│   │   ├── 02-apb-agent.md
│   │   ├── 03-md-agent-reactive.md
│   │   ├── 04-uvm-extension-library.md
│   │   ├── 05-register-model-ral.md
│   │   ├── 06-model-scoreboard-coverage-virtual-sequencer.md
│   │   ├── 07-debug-and-tests.md
│   │   └── 08-verification-project-stages.md
│   └── senior-lab/             senior "Aligner UVM Lab" modules 0–11 + findings
├── pages/
│   ├── uvm-from-zero.html      beginner course + companion (interactive)
│   └── aligner-uvm-lab.html    senior lab (architecture, hidden concepts, bug hunting)
├── project/                    complete EDA Playground project (RTL + UVM env) + README
├── exercises/rx_err/           illegal RX traffic test (the exercise solution)
└── docs/aligner_datasheet_v_1_0_2.pdf
```

## The study pages

The HTML files in `pages/` are self-contained. Download them (GitHub shows HTML as source) and double-click to open. Online versions you can open from claude.ai:

- UVM from Zero: https://claude.ai/artifact/CUYjoKZUXfLb9LGVtrPpmE
- Aligner UVM Lab (senior): https://claude.ai/artifact/C94be1q7dS2cCNSV9MvQpX

Both links are private to your claude.ai account until you share them.

## Bugs you can point to in this code

| # | Bug | Where | Status in `project/` |
|---|---|---|---|
| 1 | SIZE + OFFSET > bus width accepted (also a spec gap) | `cfs_regs.v` CTRL write checks | fixed |
| 2 | IRQEN reset value 0x1F instead of 0 | `cfs_regs.v` reset branch | fixed |
| 3 | MAX_DROP missing from the `irq` OR | `cfs_regs.v` `assign irq` (~line 164) | **still present**: run `exercises/rx_err` to see it fail on seeds with IRQEN.MAX_DROP = 1 |
| 4 | Scoreboard pops an empty expected queue on an unexpected TX/RX item (crashes instead of a clean error) | `cfs_algn_scoreboard.sv` `write_in_agent_*` | testbench issue, fix described in the notes (C9) |
| 5 | `reg2bus()` direction constraint only works because of operator precedence plus the enum encoding | `cfs_apb_pkg.sv` adapter | latent, fix described in the notes (R7) |

## Running the code

See [project/README.md](project/README.md) for the Xcelium command line (as used on EDA Playground) and how to add the rx_err exercise.
