# UART DV Interview Pack

One stop for UART design-verification interview prep: ten one-page cards, a text cheatsheet, and a UVM environment that implements every check on the cards.

Built from the **UART PROTOCOL** playlist by ALL ABOUT VLSI (9 parts), its companion write-ups on allaboutvlsi.com, and the Chipmunk Logic UART controller page.

## Start here

| If you have… | Open |
|---|---|
| 2 minutes | [`UART_CHEATSHEET.md`](UART_CHEATSHEET.md) → the "10-line revision" in section 09 |
| 20 minutes | [`uart-dv-cards.pdf`](uart-dv-cards.pdf) — all 10 cards, one per page |
| A browser | [`cards/index.html`](cards/index.html) — same cards as HTML with prev/next |
| A whiteboard question | [`code/`](code/) — the UVM code the cards describe |

## Contents

```
uart-dv-pack/
├── UART_CHEATSHEET.md      text version of all cards (searchable on GitHub)
├── uart-dv-cards.pdf       10 pages, print-ready
├── cards/                  standalone HTML cards + index
├── images/                 PNG of each card (1860 × 2700)
└── code/                   UVM reference environment
```

| # | Card | Key code |
|---|---|---|
| 01 | UART fundamentals & frame format | `uart_cfg.sv`, `uart_item.sv` |
| 02 | UVM protocol checker architecture | `uart_monitor.sv`, `uart_agent.sv`, `uart_env.sv` |
| 03 | Baud rate check | `uart_checker.sv` `check_timing()`, `uart_drift_test` |
| 04 | Framing error | driver `INJ_FE`, checker `UART_FE` |
| 05 | Parity error | `uart_cfg::exp_parity()`, checker `UART_PE` |
| 06 | Break condition | monitor `KIND_BREAK`, checker `UART_BRK` |
| 07 | Overrun error | `uart_scoreboard.sv` |
| 08 | Data validity & idle line | `uart_if.sv` SVA, monitor false-start handling |
| 09 | Error reporting & integration | `uart_report_catcher.sv`, `uart_tests.sv` |
| Bonus | Chipmunk Logic UART IP map | — |

## The code

`code/uart_pkg.sv` includes everything; `code/uart_if.sv` and `code/tb_top.sv` sit outside the package.

```
tb_top
 └─ uvm_test_top (uart_base_test / uart_error_test / uart_drift_test)
     └─ env
         ├─ tb_agt   (active)  sqr → drv → DUT rx pin      mon → rx_chk, sb.line_export, cov
         ├─ dut_agt  (passive) DUT tx pin                  mon → tx_chk, cov
         ├─ sb       FIFO / OE / LSR model — connect your bus monitor to sb.bus_export
         └─ cov      format × error crosses
```

`tb_top.sv` ships with a wire loopback (DUT TX = DUT RX), so the environment runs with no DUT. Swap in your UART where marked.

Example run (Questa; adjust for VCS / Xcelium):

```sh
vlog -sv +incdir+code code/uart_if.sv code/uart_pkg.sv code/tb_top.sv
vsim -c tb_top +UVM_TESTNAME=uart_error_test +UART_INJ=FE -do "run -all; quit"
```

| Test | Plusargs | Proves |
|---|---|---|
| `uart_base_test` | — | clean traffic, zero errors |
| `uart_error_test` | `+UART_INJ=FE` / `PE` / `BREAK` | every injected error is reported exactly once |
| `uart_error_test` | `+UART_INJ=GLITCH` | every false start is rejected |
| `uart_drift_test` | `+UART_DRIFT=40` (permille) | out-of-tolerance clock is flagged; in-tolerance is not |

**Status:** written as interview reference code and checked by reading, **not compiled or simulated** (no simulator was available). Spec-dependent behaviour (overrun boundary, break flags, resync policy) is marked `SPEC:` — set it from the datasheet of the UART you are verifying.

## Notes on sources

- The YouTube playlist exposed only its title and count, so the 9-part split follows the series roadmap on allaboutvlsi.com (basics → checker → baud → framing → parity → break → overrun → data/idle → reporting).
- Cards point out real bugs in the tutorial-style companion code (`get()` on an analysis port, a tautological baud check, a parity XOR mix-up) — good interview material.
- Numbers (divisors, error %, tolerance budgets) are computed, not quoted.
- The Chipmunk card uses the public product page only; the downloadable RTL archives are password-protected.

Sources: [UART PROTOCOL playlist](https://www.youtube.com/playlist?list=PLqPfWwayuBvPNEejEgA82Xq_n4gk8f0Kk) · [allaboutvlsi UART basics](https://www.allaboutvlsi.com/uart-basics) · [UART protocol checker](https://www.allaboutvlsi.com/uart-protocol-checker) · [Baud rate](https://www.allaboutvlsi.com/protocol-checker-2) · [Frame check](https://www.allaboutvlsi.com/protocol-checker-frame-check) · [Parity error](https://www.allaboutvlsi.com/uart-protocol-checker-parity-error) · [Chipmunk Logic UART controller](https://chipmunklogic.com/ip-cores/design-of-uart-controller/)
