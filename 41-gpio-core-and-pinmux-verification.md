# Challenge 41: GPIO Core and Pinmux Verification (Chipmunk Logic GPIO v1.0)

> **Level:** Fresher → Senior DV interview
> **Topics:** memory-mapped peripherals, tristate pads, 2-FF synchronizers and glitch filters, level vs. edge interrupts, enable vs. mask, W1C status, APB timing, RAL access types, reference model with an uncertainty window, white-box SVA for races, bug injection, pinmux bugs, STAR story
> **Related:** [06](06-verification-plan.md), [08](08-sva-assertions.md), [13](13-sva-beyond-happy-path.md), [15](15-uvm-register-model-ral.md), [18](18-coverage-architecture.md), [19](19-building-uvm-testbench-from-scratch.md), [25](25-debugging-intermittent-and-persistent-failures.md), APB course sessions [3](sv-course-sessions/03-session3-apb-dual-port-testbench.md) and [5](sv-course-sessions/05-session5-apb-functional-coverage.md)
> **Code and cheat sheet:** [`41-gpio-core-pinmux/`](41-gpio-core-pinmux/) · visual one-pager: [`gpio-dv-field-guide.html`](41-gpio-core-pinmux/gpio-dv-field-guide.html) · interview story: [`interview-story-pinmux.md`](41-gpio-core-pinmux/interview-story-pinmux.md)

---

## 1. The Source (summary)

The Chipmunk Logic blog post ["Design of GPIO core in RTL"](https://chipmunklogic.com/ip-cores/design-of-gpio-core-in-rtl/) (Aug 2025) and its open-source **GPIO v1.0** IP:

- GPIO is a **memory-mapped peripheral**. The CPU writes CSRs to set **direction**, **output state** and **interrupt behaviour** of each pin.
- Pads are driven by **tristate buffers**: OE = 1 drives the pin, OE = 0 releases it to **Hi-Z**.
- Input pins can be **interrupt sources** (level or edge, either polarity), with enable, mask, status and a single **level-type** core interrupt.
- CSRs are accessed over **APB**. The core is FPGA-friendly (tristate inside the core maps to IOBs). For ASIC, remove the tristate and bring out **OE + data**.
- Tested on a Basys-3 (Artix-7) at **100 MHz**: 8-bit tristate + interrupts + sync + filter = **89 LUTs, 132 FFs**.

The package (`gpio_v1_0.rar`) contains: `gpio_top.sv`, `gpio_cfg_macros.svh`, `intr_gateway.sv`, `intr_gen.sv`, `irq_sync.sv`, `areset_sync.sv`, `tristate_buff.sv`, `apb_transactor.sv`, `tb_gpio.sv`, `Makefile`, `scripts/run.do`, user guide and overview PDFs. **The sources are password-protected** (subscriber password). Everything here comes from the public user guide, so the testbench ships with a **clean-room reference DUT** written from the user guide ([`rtl/gpio_ref_dut.sv`](41-gpio-core-pinmux/rtl/gpio_ref_dut.sv)) and a switch to run on the real `gpio_top` once unlocked.

---

## 2. What the Documentation Leaves Open (spec gaps)

Reading the spec critically is a DV skill. Each line below is a clarification ticket and a test.

| Gap | Why it matters | Decision taken in this TB |
|---|---|---|
| `gpio_intr_sts_reg` listed **RO**, text says **write 1 to clear** | RAL access type; bit-bash fails if wrong | Model as **W1C** + volatile |
| **GME** (global mask enable) vs per-pin mask not defined | Changes `o_intr` and the 0x20 read | `cfg.gme_enables_mask = 1`: mask applies only when GME = 1 |
| Raw status has **no clear of its own** | Can a masked raw bit be cleared? | Cleared through the 0x20 W1C |
| **Set vs. clear in the same cycle** not specified | A lost interrupt | **Set wins** (checked white-box) |
| "32-bit address space", 8-bit `paddr`, map ends at 0x28 | Aliasing, unmapped behaviour | Unmapped / unaligned reads return 0, writes ignored |
| **No PSLVERR** | Bad accesses can't be reported | Must complete with no side effects |
| No **synchronizer latency**, **glitch-filter length**, **min pulse width** | Checker timing, firmware spec | `GLF_LEN = 4` placeholder; checker uses a latency **window** |
| No atomic **SET/CLR** for `o_data` | Firmware read-modify-write race (ISR vs main loop) | Design critique point |
| Register named `gpio_intr_set_rg` | Breaks generated headers/RAL names | Typo ticket |
| "Synchronize reset release externally" yet `areset_sync.sv` ships | Who owns reset sync? | Check in the RTL |

---

## 3. Background a Fresher Must Know

### 3.1 What a GPIO core is
Per pin: a **direction** bit (drives OE), an **output data** bit, and a path back from the pad (**input data**). Optionally, input pins raise interrupts. The CPU sees it all as registers on a bus.

### 3.2 Tristate buffer
| OE | Pad |
|---|---|
| 1 | driven with `o_data` |
| 0 | Hi-Z (someone else drives it) |
If both the chip and the board drive a pin, the net resolves to **X**: **contention**. In this IP `io_dir` bit = **1 means input** (OE = 0). Default-input at reset is the safe state: nothing drives at power-up.

### 3.3 Why a 2-flop synchronizer
A pin from a button or sensor is **asynchronous** to `clk`. The first flop can go **metastable**; the second gives it a clock period to settle. Without it, the edge detector can see a **double or missed edge**. RTL simulation never shows metastability (Section 4.5).

### 3.4 Glitch filter
A new level is accepted only after it has been **stable for N clocks**. Pulses shorter than N are ignored. It's a filter for short spikes, not a debouncer for millisecond-long button bounce (that needs a much longer counter).

### 3.5 Level vs. edge interrupts
| | Edge | Level |
|---|---|---|
| Sets status on | a transition (rising/falling) | the pin being at the active level |
| After W1C, if the pin is still active | stays clear | **sets again next cycle** |
| Risk | lost/merged edges | **interrupt storm** if the ISR doesn't remove the source |

### 3.6 Enable vs. mask vs. global enable
- **IE = 0**: events are dropped **and** existing status is cleared. The event is gone.
- **ME = 1**: status still latches, but is hidden from `o_intr`. The event **waits**.
- **GIE = 0**: `o_intr` held low; status still latches underneath.

### 3.7 W1C (write-1-to-clear)
Write 1 to a status bit to clear it; writing 0 does nothing. Lets software clear exactly the bits it serviced without a read-modify-write race.

### 3.8 APB in two lines
SETUP (PSEL = 1, PENABLE = 0), then ACCESS (PENABLE = 1) until PREADY = 1. This core: **write = 2 clocks**, **read = 3 clocks** (one wait state).

---

## 4. Deep Dive

### 4.1 Architecture

```
            APB                               OE = ~dir
 CPU  ───────────────▶ CSR file ── o_data, dir ──▶ tristate_buff ──▶ io_gpio[i] pad
  ▲                       ▲  │                                         │
  │                i_data │  │ IE, type, evnt                          │ async pin
  │                       │  ▼                                         ▼
  │                    irq_sync (2-FF + glitch filter) ◀───────────────┘
  │                       │
  │                       ▼
  │                intr_gateway: level/edge detect, & IE, sticky raw status
  │                       │        ▲ W1C @0x20, set @0x28, IE→0 clears
  │                       ▼
  └──── o_intr ◀── intr_gen: & ~mask (GME), OR all pins, & GIE
```

### 4.2 Build-time modes (each needs its own compile)
| Mode | Macros | Ports | Interrupts |
|---|---|---|---|
| Tristate | `EN_TRISTATE_BUFF` | `io_gpio` | with `EN_INTR_IF` |
| Input | `EN_IPORTS` | `i_gpio` | with `EN_INTR_IF` |
| Output | `EN_OPORTS` | `o_gpio` | no |
| Dual | `EN_IPORTS` + `EN_OPORTS` | `i_gpio`, `o_gpio` | with `EN_INTR_IF` |

Parameters: `GPIO_WIDTH` 1–32 (default 6), `DEF_O_VAL`, `DEF_IO_DIR`, `EN_SYNC`, `EN_GLF` (per-pin masks; a filter only exists where a sync does).

### 4.3 Register map (UG Table 6.1) and how to model each one in RAL
| Off | Register | Access | Reset | RAL / DV note |
|---|---|---|---|---|
| 0x00 | `gpio_i_data_reg` | RO | — | volatile, no HW-reset test (follows pins) |
| 0x04 | `gpio_o_data_reg` | RW | `DEF_O_VAL` | pad follows on output pins |
| 0x08 | `gpio_io_dir` | RW | `DEF_IO_DIR` | 0 = out, 1 = in; **excluded from bit-bash** (would cause contention) |
| 0x0C | `gpio_glb_intr_ctrl_reg` | RW | 0 | [0] GIE, [1] GME |
| 0x10 | `gpio_intr_en_reg` | RW | 0 | IE → 0 clears status |
| 0x14 | `gpio_intr_mask_reg` | RW | 0 | 1 = masked |
| 0x18 | `gpio_intr_type_reg` | RW | 0 | 0 = level, 1 = edge |
| 0x1C | `gpio_intr_evnt_reg` | RW | 0 | 0 = low/falling, 1 = high/rising |
| 0x20 | `gpio_intr_sts_reg` | **W1C** | 0 | volatile, compare off, model predicts |
| 0x24 | `gpio_intr_sts_raw_reg` | RO | 0 | volatile, compare off |
| 0x28 | `gpio_intr_set_rg` | WO | 0 | reads 0; gated by IE |

Firmware trap: the reset value of type/evnt is **level, active-low**. If a pin idles low and firmware sets IE before writing type, it gets an interrupt immediately. Configure type/evnt first, clear status, then enable.

Code: [`tb/gpio_ral.svh`](41-gpio-core-pinmux/tb/gpio_ral.svh).

### 4.4 The interrupt pipeline, one pin
`pin → 2-FF (~2 clk) → GLF (N clk) → detect (type × evnt) → & IE → raw sts (sticky) → & ~ME (if GME) → OR → & GIE → o_intr`

Each stage is a place where an event can be **lost, duplicated or delayed**. Total pin-to-`o_intr` latency ≈ 2 + N + 1–2 clocks, and it changes with `EN_SYNC`/`EN_GLF`. Check it with a window, not a fixed count.

### 4.5 CDC: what simulation can and can't show
- RTL sim samples a clean 0 or 1: **no metastability**. Use a **CDC tool** (structural check that every async input goes through a recognised synchronizer).
- Add **metastability injection** in sim (randomly delay the synchronizer output by 0 or 1 clock) and make sure the checkers tolerate it.
- Test **pulse widths** 1, 2, N−1, N, N+1 clocks at **random phase** relative to `clk`. Widths near the threshold are where filter bugs live.
- Per-bit 2-FF is fine here because pins are **independent**. A multi-bit bus through per-bit syncs is a classic CDC bug (bits arrive in different cycles).

### 4.6 Testbench architecture (what's in [`41-gpio-core-pinmux/tb/`](41-gpio-core-pinmux/tb/))

```
gpio_base_test ── gpio_env
                   ├── apb_agent (driver, monitor, sequencer) ──┐
                   ├── pin_agent (async-phase driver, monitor) ─┤ analysis
                   ├── gpio_reg_block (RAL) + apb_reg_adapter   │
                   ├── gpio_scoreboard (reference model) ◀──────┘
                   ├── gpio_coverage (sampled by the scoreboard)
                   └── gpio_vsequencer (handles: apb, pins, RAL, cfg)
tb_top: DUT (gpio_ref_dut or gpio_top) + gpio_sva (ports) + gpio_ref_wb_sva (bind, internals)
```

| File | What it shows in an interview |
|---|---|
| `gpio_if.sv` | Bidirectional pin: `assign io = tb_en ? tb_val : 'z` on a **wire**, clocking blocks |
| `apb_agent.svh` | APB driver (SETUP → ACCESS → wait PREADY), monitor, RAL adapter with `provides_responses = 0` |
| `pin_agent.svh` | Driving pins **asynchronously** (random ns into the period) so the synchronizer is really exercised |
| `gpio_ral.svh` | RO / RW / W1C / WO, volatile fields, compare off, excluding fields from built-in sequences |
| `gpio_scoreboard.svh` | Independent model from the spec, **uncertainty window**, taint + re-sync, "prove the scoreboard checked something" |
| `gpio_coverage.svh` | Covering **outcomes** (set / masked / dropped), pulse widths around the threshold, race corners |
| `gpio_seqs.svh` | One virtual sequence per testplan item, safe direction changes, firmware-style ISR |
| `gpio_sva.sv` | Port-only assertions: APB rules, 2/3-cycle timing, reserved bits, Hi-Z/contention, GIE gate |
| `gpio_ref_wb_sva.sv` | White-box race check: **set beats W1C in the same cycle** |
| `directed/tb_smoke.sv` | 37-check directed test that runs on **free tools** |

### 4.7 The scoreboard: why an uncertainty window
A cycle-exact model would need the exact sync, filter and status latency. The user guide doesn't give it, and it changes per build. So the model is **behavioural** (from the spec) and a bit is **not compared** for `lat_max` clocks after its pin or the interrupt config changes.

```systemverilog
// Bits whose value can't be predicted exactly at cycle c.
function bit [GPIO_W-1:0] uncertain(longint c);
  bit [GPIO_W-1:0] u = taint;
  for (int i = 0; i < GPIO_W; i++)
    if (c - last_pin_chg[i] <= LAT) u[i] = 1;
  if (c - last_cfg <= LAT) u = '1;
  return u;
endfunction
```

Pulses whose width is within one clock of the filter length **taint** the pin (the model can't know whether the DUT accepted them). A later read of the raw status, taken while the pin is quiet, re-syncs the model. The ISR in the sequences always waits for quiet first, so most reads are fully checked. The scoreboard reports bits checked vs. skipped, and `check_phase` fails the test if it compared nothing.

**The trade-off to say out loud:** a race *inside* the window (W1C in the same cycle as an event) is **covered but not checked** by the scoreboard. That's why there is a white-box assertion for it (4.8).

### 4.8 Assertions: port-level vs. white-box
Port-level (`gpio_sva.sv`, works on any implementation):
```systemverilog
`define CK @(posedge clk) disable iff (!resetn)
a_wr_no_wait : assert property (`CK access && i_pwrite |-> o_pready);          // 2-cycle write
a_rd_wait    : assert property (`CK rd_start |-> !o_pready);                    // 3-cycle read
a_rsvd_zero  : assert property (`CK rd_done |-> o_prdata[31:W] == '0);
a_release    : assert property (`CK dir_sh[i] && $stable(dir_sh[i]) && !tb_en[i]
                                    |-> io_gpio[i] === 1'bz);                    // input = Hi-Z
a_gie_gate   : assert property (`CK !gie_sh && $past(!gie_sh) |-> !o_intr);
```
White-box (`gpio_ref_wb_sva.sv`, bound into the DUT):
```systemverilog
a_set_beats_w1c: assert property (`CK (evt[i] || swset[i]) && w1c[i] && ie[i] |=> raw[i]);
c_race         : cover  property (`CK evt[i] && w1c[i] && ie[i]);   // proof it happened
```
Portability note: properties avoid `default disable iff` and `##` inside sequences so the same file runs on Verilator 5.020 as well as VCS/Xcelium/Questa. Pad checks need 4-state values, so they're skipped under Verilator (`ifndef VERILATOR`).

### 4.9 Proving the checkers can fail (bug injection)
`gpio_ref_dut.sv` has four switchable bugs. `make bugs` runs the smoke test on each:

| Bug | What it breaks | Caught by |
|---|---|---|
| `BUG_W1C_WINS` | W1C beats a same-cycle set → lost event | **white-box SVA only** (all 37 directed checks pass) |
| `BUG_NO_RD_WAIT` | read in 2 clocks instead of 3 | `a_rd_wait` (port SVA) |
| `BUG_IE_NO_CLEAR` | IE → 0 leaves status set | directed checks |
| `BUG_MASK_DROPS` | masked event dropped instead of pending | directed checks |

The interesting result: **All 37 directed checks pass with `BUG_W1C_WINS` in the design** (run with assertions off to see it). The race happens in one cycle, and every read happens later, after the level source has set the bit again. Only the white-box assertion saw it. It actually fired during the *level* test: clearing a level bit while its source is active is the same race.

### 4.10 Testplan
| # | Test (virtual sequence) | Checks |
|---|---|---|
| T1 | `gpio_reset_vseq` (uvm_reg_hw_reset_seq) | reset values per parameter |
| T2 | `gpio_reg_access_vseq` (bit-bash) | RW/RO/WO/W1C, no aliasing |
| T3 | `gpio_out_drive_vseq` | pad follows `o_data`, live direction flips, no contention |
| T4 | `gpio_in_sample_vseq` | `i_data` after sync, random phase |
| T5 | `gpio_intr_rand_vseq` | random config × random pins × ISR |
| T6 | `gpio_level_storm_vseq` | level status re-sets while source active |
| T7 | `gpio_w1c_race_vseq` | offset sweep so W1C and edge coincide |
| T8 | `gpio_mask_pending_vseq` | unmask raises `o_intr` with no new event |
| T9/10 | `gpio_ie_swset_vseq` | IE clears; software set gated by IE; WO reads 0 |
| T11 | `gpio_glitch_vseq` | pulse widths 1 … N+3 at random phase |
| T12 | `gpio_multi_pin_vseq` | all pins fire in one cycle |
| T13 | `gpio_reconfig_live_vseq` | type/polarity change while IE = 1 |
| T14 | `gpio_apb_robust_vseq` | unmapped, unaligned, RO write, WO read, back-to-back |
| T15 | build matrix | `WIDTH=1/8/32`, `NOGLF=1`, real RTL modes |

### 4.11 Coverage model (in `gpio_coverage.svh`)
- `cg_pin_cfg`: dir × IE × ME × type × evnt × GIE × GME, crosses **trigger (4)** and **gating (16)**, pin × trigger.
- `cg_event`: event kind × **outcome** (set / masked / dropped / no-match).
- `cg_pulse`: width bins `short`, `thr-1`, `thr`, `thr+1`, `long` × filter present.
- `cg_race`: W1C with event, W1C while level active, unmask with pending, IE-off with pending.
- `cg_apb`: every register × R/W, unmapped, unaligned, back-to-back.

### 4.12 Where pinmux fits (your story)
In an SoC the ASIC version of this core exposes `oe`, `o_data`, `i_data`. They go into the **pinmux**, together with UART, SPI, I²C, PWM, and from there to the **pad cell** (A, OE, Y, IE, pull-up/down, drive strength). Bugs live at the boundaries:
- A **spurious GPIO edge** when a pad switches function or pull (e.g., UART idle-high → GPIO with pull-down = falling edge).
- **OE leaking** from a function that isn't selected → contention.
- Wrong **reset-default function** → a pad drives at power-up.
- **Inputs not gated** for unselected functions (UART sees GPIO toggling).
- **Open-drain** (I²C) pads driven push-pull high.
- Spreadsheet ↔ RTL **pad swaps** or select-index off-by-one.
- Interrupt still enabled on a pad now owned by another function.

Safe firmware sequence to change a pad's function: disable that pin's IE → switch the mux → clear status → re-enable.

Full STAR outline and spoken version: [`interview-story-pinmux.md`](41-gpio-core-pinmux/interview-story-pinmux.md).

---

## 5. Likely Follow-ups (with model answers)

**Q: Walk me through a GPIO core.**
APB CSRs drive data and direction into tristate pads. The input path goes pad → 2-FF sync and glitch filter → `i_data` and a per-pin level/edge detector → sticky W1C status → mask → OR → GIE → one level `o_intr`.
*Follow-up: why a level interrupt output?* An interrupt controller in another domain can miss a pulse; a level holds until software acknowledges it.

**Q: How do you verify a W1C register that hardware also sets?**
RAL access `W1C`, volatile, compare off; a reference model predicts it. Tests: write 0 no-op, write 1 clears, and **set and clear in the same cycle** (priority agreed with the designer). For level type, expect the bit to come back next cycle while the source is active.

**Q: Enable vs. mask?**
IE = 0 drops and clears; ME = 1 keeps the event pending and hides it. Test: event while masked → raw = 1, masked = 0 → unmask → `o_intr` rises with no new event.

**Q: Can simulation verify CDC?**
No metastability in RTL sim. Use a CDC tool for structure, metastability injection for robustness, and pulse-width sweeps at random phase for the filter.

**Q: How do you model a bidirectional pin in UVM?**
A `wire` in the interface, driven with `assign io = en ? val : 'z`. Drive only pins configured as inputs; check X for contention and Z for release. A `logic` can't resolve two drivers.

**Q: Your checker can't predict the exact latency. How do you still check o_intr?**
Behavioural model plus an uncertainty window (Section 4.7): compare only when nothing changed for `lat_max` clocks. Covers every build; the race inside the window gets a white-box assertion.

**Q: All your directed checks passed. Why did you still find a bug?**
The W1C-vs-set race lasts one cycle and later reads can't see it. Coverage told me the race happened; only an assertion on the cycle itself could judge it. Passing tests ≠ checked behaviour.

**Q: The level interrupt keeps firing after the ISR clears it. Bug?**
Expected if the source is still active. To tell it from an RTL bug, look at the synchronized pin at the cycle the bit re-sets: inactive pin = RTL bug.

**Q: How do you verify all parameter combinations?**
A build matrix (widths 1/8/32, modes, `EN_GLF` masks), a config object that tests read, and tests that skip features a build doesn't have. Pairwise selection, not the full product.

**Q: What would you change in this design?**
Add atomic SET/CLR registers for `o_data`, PSLVERR for bad accesses, a defined GIE/GME relationship, the filter length in a CSR, and pull/drive controls (usually in the pad/pinmux block).

**Q: The vendor's FPGA test passed. Why isn't that enough?**
Directed, one configuration, and LEDs only show slow behaviour. A one-cycle spurious interrupt or a lost event is invisible. Board tests are good for real I/O timing and true asynchronous inputs.

**Q (pinmux): How did you verify N pads × k functions?**
Generate the expected connectivity from the pin spreadsheet; formal connectivity for the static routes; simulation for dynamic behaviour (re-muxing during traffic, interrupts, pulls). Coverage cross pad × function with illegal combinations ignored.

---

## 6. Common Mistakes

| Mistake | Better |
|---|---|
| Treating `io_dir` = 1 as output (MCU habit) | In this IP, **1 = input** |
| Modelling `intr_sts` as RO because the table says so | It's **W1C**; raise the spec ticket |
| Bit-bashing `io_dir` while the TB drives the pins | Exclude it; test direction separately with release-first |
| Leaving input pins floating in the TB | X enters the synchronizer and spreads into status and `o_intr` |
| Hard-coding the pin-to-interrupt latency | Use a window derived from the build config |
| Mirror-checking volatile fields | Compare off; the reference model checks them |
| Expecting a level status bit to stay clear after W1C | It re-sets while the source is active |
| Calling a pass "verified" when the race was never checked | Cover the race and check it on the cycle (white-box SVA) |
| Claiming a bug story that isn't yours | Say "a case I made sure to cover" |

---

## 7. 60-Second Interview Pitch

"GPIO looks trivial, but most of its bugs are timing corners. It's an APB peripheral: direction drives each pad's output enable, data drives its value, and inputs come back through a 2-flop synchronizer and glitch filter into a per-pin level/edge detector, sticky W1C status, a mask and one level interrupt.

When I verify it, I build the reference model from the spec, not the RTL. Since sync and filter latency vary by build, the model compares a bit only once its pin has been quiet for a latency window, and it re-syncs after pulses near the filter threshold. That leaves one-cycle races unchecked, so I add a white-box assertion that a set beats a W1C in the same cycle. In my bug-injection run, all 37 directed checks passed with that bug in the design, and only the assertion caught it.

The same thinking carried into my pinmux work: [your pads × functions], where the bugs were at the boundaries, like a spurious GPIO edge when a pad changes function."

---

## 8. Self-Check

- [ ] Draw the input path from pad to `o_intr` and name the latency of each stage.
- [ ] Explain IE vs. ME vs. GIE in one sentence each, and the test that separates them.
- [ ] Say what happens when an ISR clears a level interrupt whose source is still active.
- [ ] Give the RAL access type and volatility of each of the 11 registers.
- [ ] Explain why RTL simulation can't show metastability and what you do instead.
- [ ] Write the `assign io = en ? val : 'z` interface and say why it must be a wire.
- [ ] Explain the uncertainty window and its blind spot.
- [ ] List three spec gaps in the user guide and the decision you'd ask for.
- [ ] List five pinmux bug patterns and the firmware sequence for changing a pad's function.
- [ ] Tell your pinmux story in 90 seconds with your real numbers.
