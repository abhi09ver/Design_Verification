# AXI + DV Interview Prep — one-stop folder

Everything to revise before a Design Verification interview (Google, NVIDIA, AMD and similar), in one place:

- **15 one-page cheat sheets** covering the AXI protocol, then a project deep-dive and interview strategy, each as PDF, PNG and HTML.
- **Runnable code**: an AXI4 slave RAM with a self-checking testbench. Free iverilog, 10-seed regression, planted bugs that must be caught.
- **AXI4-Lite SVA checker**, plus **UVM reference code** (RAL adapter, per-ID scoreboard, protocol coverage).
- **Findings and fixes** for the AXI4-Lite UVM project ([NitishVerifies/AXI4_UVM_Verification](https://github.com/NitishVerifies/AXI4_UVM_Verification)), with reproducible evidence.

> Fastest path: open **[`AXI_DV_Interview_Cheatsheets_ALL.pdf`](AXI_DV_Interview_Cheatsheets_ALL.pdf)**. It has all 15 sheets, one per page.

---

## Cheat sheets

| # | Sheet | Covers | PDF | PNG | HTML |
|---|---|---|---|---|---|
| 01 | AXI overview | AMBA family, why AXI is fast, AXI3 vs AXI4, 5 channels, handshake, dependencies, bursts, responses, IDs, DV checks, rapid-fire Q&A | [pdf](cheatsheets/pdf/01-axi-overview.pdf) | [png](cheatsheets/png/01-axi-overview.png) | [html](cheatsheets/html/01-axi-overview.html) |
| 02 | Signals by channel | Every AW/W/B/AR/R signal: width, driver, meaning; reset rules; SIZE/BURST/RESP/PROT/LOCK/CACHE encodings | [pdf](cheatsheets/pdf/02-axi-signals-by-channel.pdf) | [png](cheatsheets/png/02-axi-signals-by-channel.png) | [html](cheatsheets/html/02-axi-signals-by-channel.html) |
| 03 | Write & read transfers | Cycle-by-cycle bursts with stalls, single beat, W-before-AW, overlapping transfers, narrow/unaligned byte lanes | [pdf](cheatsheets/pdf/03-write-read-transfers.pdf) | [png](cheatsheets/png/03-write-read-transfers.png) | [html](cheatsheets/html/03-write-read-transfers.html) |
| 04 | VALID–READY handshake | 5 rules, 3 legal cases, 3 violations, channel dependencies, skid buffers, SVA | [pdf](cheatsheets/pdf/04-valid-ready-handshake.pdf) | [png](cheatsheets/png/04-valid-ready-handshake.png) | [html](cheatsheets/html/04-valid-ready-handshake.html) |
| 05 | Burst length, size, type | Formulas for every beat address and lane, 4 worked INCR examples, 4 KB rule, FIXED/WRAP, SV constraints | [pdf](cheatsheets/pdf/05-burst-length-size-type.pdf) | [png](cheatsheets/png/05-burst-length-size-type.png) | [html](cheatsheets/html/05-burst-length-size-type.html) |
| 06 | WRAP burst | Critical-word-first, 4-step algorithm, every start offset, worked examples, illegal WRAPs | [pdf](cheatsheets/pdf/06-wrap-burst.pdf) | [png](cheatsheets/png/06-wrap-burst.png) | [html](cheatsheets/html/06-wrap-burst.html) |
| 07 | Out-of-order & IDs | Ordering rules, timelines, interleaving, interconnect ID widening, per-ID scoreboard | [pdf](cheatsheets/pdf/07-out-of-order-and-ids.pdf) | [png](cheatsheets/png/07-out-of-order-and-ids.png) | [html](cheatsheets/html/07-out-of-order-and-ids.html) |
| 08 | Slave RAM in Verilog | Architecture, write/read FSMs, `next_addr()`, design choices, classic slave bugs | [pdf](cheatsheets/pdf/08-axi-slave-ram-verilog.pdf) | [png](cheatsheets/png/08-axi-slave-ram-verilog.png) | [html](cheatsheets/html/08-axi-slave-ram-verilog.html) |
| 09 | Write testbench | `axi_write` task, fork AW ∥ W, NBA drives, write tests, checking strategies | [pdf](cheatsheets/pdf/09-write-testbench.pdf) | [png](cheatsheets/png/09-write-testbench.png) | [html](cheatsheets/html/09-write-testbench.html) |
| 10 | Read testbench | `axi_read` task, per-beat RID/RRESP/RLAST checks, read-after-write table | [pdf](cheatsheets/pdf/10-read-testbench.pdf) | [png](cheatsheets/png/10-read-testbench.png) | [html](cheatsheets/html/10-read-testbench.html) |
| 11 | Verification environment | Layered TB, constraints, monitor, byte-level scoreboard, coverage, test plan, sign-off, UVM mapping | [pdf](cheatsheets/pdf/11-verification-environment.pdf) | [png](cheatsheets/png/11-verification-environment.png) | [html](cheatsheets/html/11-verification-environment.html) |
| 12 | **Your project, explained** | Both TB layers, UVM concept map, DUT FSMs, constraints, tests, 60-second pitch | [pdf](cheatsheets/pdf/12-project-axi4-lite-uvm-explained.pdf) | [png](cheatsheets/png/12-project-axi4-lite-uvm-explained.png) | [html](cheatsheets/html/12-project-axi4-lite-uvm-explained.html) |
| 13 | **Bugs found & fixed** | False-PASS regression, W-before-AW deadlock, no SLVERR, X-pessimism, tool bug, uncompiled UVM, STAR story | [pdf](cheatsheets/pdf/13-project-bugs-and-fixes.pdf) | [png](cheatsheets/png/13-project-bugs-and-fixes.png) | [html](cheatsheets/html/13-project-bugs-and-fixes.html) |
| 14 | **Top-tier roadmap** | Priority upgrades, SVA checker, driver knobs, protocol coverage, RAL, what big-company loops cover | [pdf](cheatsheets/pdf/14-top-tier-upgrade-roadmap.pdf) | [png](cheatsheets/png/14-top-tier-upgrade-roadmap.png) | [html](cheatsheets/html/14-top-tier-upgrade-roadmap.html) |
| 15 | **UVM core + project Q&A** | Phases, factory, config_db, objections, TLM, seq↔driver, clocking blocks, 14 questions about your repo | [pdf](cheatsheets/pdf/15-uvm-core-and-project-qa.pdf) | [png](cheatsheets/png/15-uvm-core-and-project-qa.png) | [html](cheatsheets/html/15-uvm-core-and-project-qa.html) |

The HTML pages have previous/next links and work offline, with fonts bundled. On GitHub, PNG previews inline; download the PDF for printing or your phone.

## Revision plan

| Time you have | Do this |
|---|---|
| **15 min before the call** | Sheet 01 (rapid-fire Q&A at the bottom) + sheet 12 (60-second pitch) |
| **The night before** | Sheets 01, 04, 05, 13, 15 — protocol rules, burst math, your bug story, UVM Q&A |
| **One week** | All 15 in order, then run the code below and explain every line out loud |
| **Two weeks** | Sheet 14's plan: apply the project fixes, add SVA + RAL, push, then mock-interview on sheets 12–15 |

## Code

```
code/
├── 01_axi4_slave_ram/          AXI4 burst slave RAM + self-checking TB   (runs on iverilog)
├── 02_axi_lite_sva/            AXI4-Lite SVA checker, bind-able           (needs concurrent-SVA tool)
├── 03_axi4_lite_repo_fixes/    patch + probes for the AXI4-Lite UVM repo   (runs on iverilog)
└── 04_uvm_reference/           UVM building blocks from the sheets        (reference, not compiled here)
```

### 01 — AXI4 slave RAM (sheets 08–11)

FIXED/INCR/WRAP bursts, WSTRB, narrow and unaligned transfers, SLVERR on out-of-range addresses or reserved burst type. The testbench has a byte-level reference model written independently of the RTL. It checks RID/RRESP/RLAST and data on every beat, and checks that payloads stay stable under back-pressure.

```bash
sudo apt install iverilog gtkwave
cd code/01_axi4_slave_ram
make                         # 11 directed tests + 300 random bursts
make sim SEED=7 NRAND=1000 BP=1
make regress                 # 10 seeds, half with random BREADY/RREADY back-pressure
make mutants                 # 3 planted bugs — every one must be caught
```

Verified results (iverilog 12):

```
make regress   PASS seed=1 … seed=10   (up to ~10,000 checks per seed)
make mutants   caught BUG_IGNORE_WSTRB   (RDATA mismatch vs model)
               caught BUG_WRAP_AS_INCR   (RDATA mismatch vs model)
               caught BUG_RLAST_EARLY    (RLAST on wrong beat)
```

`make mutants` is the interview story behind "how do you know your checker works?"

### 02 — AXI4-Lite SVA checker (sheets 04, 14)

`axi_lite_sva.sv` covers: VALID held and payload stable on all 5 channels, no X, reset values, B after AW+W, R after AR, bounded liveness, and cover properties for W-first, same-cycle and SLVERR cases. Attach it with `bind axi4_slave_ram axi_lite_sva u_sva (.*);`. It needs VCS, Questa, Xcelium or a formal tool. EDA Playground runs it for free.

### 03 — AXI4-Lite UVM project fixes (sheets 12, 13)

See [`code/03_axi4_lite_repo_fixes/README.md`](code/03_axi4_lite_repo_fixes/README.md). It covers how to reproduce each bug and apply the patch.

### 04 — UVM reference (sheets 05–07, 14, 15)

[`axi_uvm_reference.sv`](code/04_uvm_reference/axi_uvm_reference.sv) contains:

- an interface with clocking blocks and modports
- the AXI4 transaction with legal-by-construction constraints
- driver config knobs
- a per-ID read scoreboard using `uvm_analysis_imp_decl`
- a protocol covergroup
- an AXI-Lite RAL adapter
- a WRAP address model

It's written to IEEE 1800.2 but isn't compiled here, so paste it into a UVM-capable simulator to run it.

## Go deeper: matching challenge notes in this repo

| Cheat sheet | Read next |
|---|---|
| 01, 07 AXI overview, out-of-order & IDs | [17 Bus protocols](../17-bus-protocols-axi-ahb-pcie.md), [21 AXI ↔ PCIe bridge](../21-protocol-bridge-verification-axi-to-pcie.md) |
| 04 VALID–READY handshake | [10 Ready/valid assertions](../10-ready-valid-handshake-assertions.md), [13 SVA beyond the happy path](../13-sva-beyond-happy-path.md) |
| 11 Verification environment | [19 UVM testbench from scratch](../19-building-uvm-testbench-from-scratch.md), [18 Coverage architecture](../18-coverage-architecture.md) |
| 13 Bugs found & fixed | [25 Debugging failures](../25-debugging-intermittent-and-persistent-failures.md), [02 Bug storytelling](../02-constrained-random-verification-storytelling.md) |
| 14 Top-tier roadmap | [08 SVA](../08-sva-assertions.md), [14 Formal](../14-formal-verification.md), [15 RAL](../15-uvm-register-model-ral.md) |
| 15 UVM core | [07 UVM pillars](../07-uvm-pillars-phasing-factory-config-db.md), [16 TLM](../16-uvm-tlm-ports-exports-fifos.md), [05 Virtual sequences](../05-virtual-sequences.md) |

## Sources & notes

- Sheets 01–11 follow the AXI series by the YouTube channel **ALL ABOUT VLSI**:
  - [Intro / channels / ordering](https://youtu.be/XNzC6FJvloI)
  - [Signals](https://youtu.be/f7oLw5HSNYI)
  - [Write & read transfer](https://youtu.be/g_3HOUGftZk)
  - [Handshake](https://youtu.be/UJJ66wB25jI)
  - [Burst length/size/type](https://youtu.be/MOTS0gBIXoc)
  - [Wrapping burst](https://youtu.be/jagqQdpRPpQ)
  - [Out-of-order](https://youtu.be/VUlJxyVp704)
  - [RAM design](https://youtu.be/cl1SEaN3xy0)
  - [Write via testbench](https://youtu.be/TBl-q9R4TwE)
  - [Read operation](https://youtu.be/8EEjVfY08bA)
  - [Final testbench](https://youtu.be/fc26rZDfDTE)

  The sheets were written from each video's topic using the AMBA AXI specification's rules. They are not transcripts, so watch the videos for the presenter's own walkthrough.
- Sheets 12–15 and `code/03` analyse [NitishVerifies/AXI4_UVM_Verification](https://github.com/NitishVerifies/AXI4_UVM_Verification) at commit `7de78e6`.
- The "what big-company loops cover" panel on sheet 14 is based on widely shared candidate experiences. Formats vary by team, so confirm with your recruiter.
- Fonts: IBM Plex, SIL Open Font License 1.1 ([`cheatsheets/html/fonts/OFL.txt`](cheatsheets/html/fonts/OFL.txt)).
