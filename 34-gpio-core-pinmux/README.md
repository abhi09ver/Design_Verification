# 34 · GPIO Core and Pinmux: one-stop interview kit

Everything for a DV interview on GPIO / pinmux in one folder: the study notes, a visual one-pager, your interview story, and a complete testbench you can point to.

## Read before the interview (in this order)

| # | File | Time | What it gives you |
|---|---|---|---|
| 1 | [`gpio-dv-field-guide.html`](gpio-dv-field-guide.html) | 10 min | Visual cheat sheet: block diagram, register map, interrupt pipeline, APB waveform, UVM plan, spec gaps, 18 Q&A with quiz mode. Download and open in a browser. |
| 2 | [`../34-gpio-core-and-pinmux-verification.md`](../34-gpio-core-and-pinmux-verification.md) | 20 min | Full notes in the same format as challenges 01–33: background, deep dive, follow-ups, mistakes, 60-second pitch, self-check |
| 3 | [`interview-story-pinmux.md`](interview-story-pinmux.md) | 15 min | STAR outline + 90-second spoken story for your pinmux work. **Fill in the `[brackets]` with your real facts.** |
| 4 | `tb/` and `rtl/` | as needed | Code to show or talk through (map below) |

## Code map

```
34-gpio-core-pinmux/
├── rtl/gpio_ref_dut.sv        clean-room GPIO written from the user guide (+4 injectable bugs)
├── tb/
│   ├── gpio_tb_pkg.sv         package: build constants + includes
│   ├── gpio_if.sv             APB interface, bidirectional pin interface
│   ├── gpio_cfg.svh           register offsets, build config, spec-gap decisions
│   ├── apb_agent.svh          APB item, driver, monitor, agent, RAL adapter
│   ├── pin_agent.svh          async-phase pin driver, per-clock pin monitor
│   ├── gpio_ral.svh           register model (RO / RW / W1C / WO, volatile fields)
│   ├── gpio_scoreboard.svh    reference model with uncertainty window
│   ├── gpio_coverage.svh      config, outcome, pulse-width, race and APB coverage
│   ├── gpio_env.svh           env + virtual sequencer
│   ├── gpio_seqs.svh          virtual sequences T1..T14 + full regression
│   ├── gpio_tests.svh         base test + one test per sequence
│   ├── gpio_sva.sv            port-level assertions (any implementation)
│   ├── gpio_ref_wb_sva.sv     white-box race assertions, bound into the DUT
│   ├── tb_top.sv              UVM top
│   └── directed/tb_smoke.sv   37-check directed test, runs on free tools
├── scripts/slang_elab.py      elaborates the UVM TB with slang (free)
├── ip/                        the original Chipmunk package (sources encrypted)
└── Makefile
```

## Run it

Free tools, no licence:

```bash
make smoke     # Verilator 5.x : 37 directed checks + port and white-box SVA
make smoke4    # Icarus 12     : same test in 4-state, incl. Hi-Z pad check
make bugs      # each of 4 injected bugs must be caught
make lint      # Verilator -Wall on the reference DUT, widths 8 / 32 / 1
make elab      # full UVM TB + UVM library elaborated by slang
               # needs: pip install pyslang
               #        git clone https://github.com/accellera-official/uvm-core
```

UVM regression (commercial simulator):

```bash
make vcs    TEST=gpio_full_test SEED=7
make xrun   TEST=gpio_w1c_race_test
make questa TEST=gpio_glitch_test WIDTH=32
# any sequence without writing a test:
make vcs TEST=gpio_base_test PLUSARGS=+GPIO_VSEQ=gpio_mask_pending_vseq
# on the real Chipmunk RTL once unlocked:
make vcs RTL=chipmunk RTL_DIR=ip/gpio_v1_0/src
```

## What has actually been run (Oct 2026)

| Check | Tool | Result |
|---|---|---|
| Directed smoke test, 37 checks + SVA | Verilator 5.020 | pass, no assertion fired |
| Same test, 4-state (Hi-Z pad check) | Icarus 12.0 | pass |
| Bug injection, 4 bugs | Verilator 5.020 | 4/4 caught; `BUG_W1C_WINS` only by white-box SVA |
| Lint, widths 8 / 32 / 1 | Verilator `-Wall` | clean |
| Full UVM TB elaboration, widths 8 / 32 / 1 | slang (pyslang 12) + Accellera UVM | 0 errors |
| UVM simulation | needs VCS / Xcelium / Questa | **not run yet** |

Run `make smoke` and `make bugs` yourself before the interview, so the results are yours to quote.

## Not verified yet / placeholders

- The Chipmunk RTL itself (sources are password-protected). The reference DUT follows the user guide; where the guide is silent it makes the choices listed in `gpio_cfg.svh` and the notes, Section 2.
- `GLF_LEN = 4` is a placeholder; read the real filter length from `irq_sync.sv`.
- Internal-signal assertions for the real RTL: templates at the bottom of `gpio_sva.sv`; copy `gpio_ref_wb_sva.sv` and rename the bound signals.
- The UVM scoreboard and sequences elaborate cleanly but haven't been simulated; expect a first-run debug pass on a commercial simulator.
