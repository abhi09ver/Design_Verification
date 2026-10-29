# Interview Story: GPIO and Pinmux Verification

Fill in every `[bracket]` with your own facts before the interview. Only tell bugs and numbers you actually saw. If a pattern below didn't happen on your project, describe it as "a case I made sure to cover", not as your bug.

The bridge from the Chipmunk GPIO IP to your work: its user guide says that for an ASIC you remove the tristate buffer and bring out **OE and data**. Those are exactly the signals a pinmux takes. Your pinmux work is the system-level version of this GPIO block.

```
GPIO core ──(o_data, oe, i_data, irq)──┐
UART tx/rx ────────────────────────────┤
SPI / I2C (open-drain) ────────────────┼──▶ PINMUX (per-pad select CSR) ──▶ pad cell ──▶ PIN[k]
PWM / timer ───────────────────────────┘                                   A, OE, Y, IE,
                 ◀──────────── Y fans back to every function + GPIO sync ── PU/PD, drive
```

---

## STAR outline

**Situation**
- SoC with `[N]` multiplexed pads. Each pad selects GPIO or one of `[k]` alternate functions (UART, SPI, I²C, PWM, …) through pinmux CSRs.
- Pad attributes: pull-up/down, drive strength, input enable, `[schmitt / slew]`.
- The GPIO block was APB-mapped with per-pin direction and level/edge interrupts (like Chipmunk GPIO v1.0).

**Task**
- I owned verification of the pinmux and GPIO pad path: every pad × function route, direction, reset defaults, pad attributes, and GPIO interrupt routing through the mux.
- Goal: `[100% pad × function cross]` with `[zero open bugs]` before `[tape-out / milestone]`.

**Action**
- Wrote the testplan from the **pin spreadsheet**: every (pad, function) pair became a coverage bin; illegal pairs became `ignore_bins` and assertions.
- Built a **pad agent**: drives or releases each pin, models pulls, so a floating pin shows as Z instead of a quiet 0.
- Built a **reference table / model**: (pad, mux_sel) → expected output source, OE source, and which function's input sees the pad.
- **Random mux configurations** through the register model, including **re-muxing while traffic runs**.
- **Assertions**: only the selected function's OE reaches the pad; unselected inputs are gated; open-drain pads never drive high.
- `[Formal connectivity / connectivity checks generated from the spreadsheet]`.
- Coverage: pad × function × direction × pull, plus mux-switch transitions.

**Result**
- `[X]` bugs found, best one: `[your bug]`.
- Functional coverage closed at `[Y%]`, waivers reviewed with `[designer / lead]`.
- `[The spreadsheet-driven checks were reused on the next project / caught a late ECO pad swap]`.
- What I'd do differently: `[e.g., run formal connectivity on day one; simulation is slow at N×k static routes]`.

---

## 90-second spoken version

"On my last project I owned pinmux and GPIO verification for a `[N]`-pad SoC. Each pad could be GPIO or one of `[k]` peripheral functions, chosen by mux-select registers. The GPIO itself was an APB block with per-pin direction and level or edge interrupts.

I wrote the testplan from the pin spreadsheet, so every pad and function pair became a coverage bin. I built a pad agent that can drive or release each pin and models pulls, so a floating pin shows up instead of reading as a quiet zero. A reference model predicted which function owned each pad, and I ran random mux configurations through the register model, including re-muxing while traffic was running.

The bug I'm proudest of was `[your bug]`. *(If it is true for you:* when a pad switched from UART to GPIO input, the line went from idle-high to the pad's pull-down and the GPIO edge detector logged a falling edge, which was a spurious interrupt. We fixed it by `[gating IE during reconfiguration / documenting a firmware sequence]`.*)*

We closed at `[Y%]` functional coverage with `[X]` bugs filed. If I did it again, I'd generate the connectivity checks straight from the spreadsheet and run formal connectivity on day one."

---

## Pinmux bug patterns (to draw on, only claim what's yours)

| Pattern | How it shows up | How to catch it |
|---|---|---|
| Spurious GPIO edge on re-mux or pull change | Interrupt with no real event | Re-mux during traffic with GPIO IE on; check status stays 0 |
| OE leak from an unselected function | X on the pad (contention) | Assertion: pad OE == OE of the selected function only |
| Wrong reset-default function | Pad drives at power-up | Reset test reading every mux CSR + pad state during reset |
| Input not gated for unselected functions | UART receives garbage while pad is GPIO | Assertion on each function's input when not selected |
| Open-drain pad driven push-pull | I²C line driven high | Assertion: OD pads only drive 0 or release |
| Spreadsheet vs RTL mismatch | Wrong pin for a function | Generate checks from the spreadsheet; formal connectivity |
| Interrupt left enabled on a re-assigned pad | Interrupts from another function's traffic | Cover "IE on while function ≠ GPIO" |

Safe firmware sequence to change a pad's function: disable the pin's IE → switch the mux → clear status → re-enable.

---

## Follow-ups they'll ask about the story

| Question | Answer outline |
|---|---|
| How did you scale to N×k combinations? | Coverage cross with illegal pairs ignored; formal connectivity for static routes; sim for dynamic behaviour |
| How did you model the pad? | `wire` with drive/release, pullup/pulldown, Z and X detection; strengths if needed |
| Who owned the pin spreadsheet? How did you catch drift from RTL? | Generated checks from it on every regression; any ECO changes the spreadsheet first |
| Did you use the real pad library? | `[behavioural pad models / library models at gate level]`; analog behaviour out of scope |
| What did you not verify, and why? | Slew, ESD, analog levels: covered by the pad vendor and physical sign-off |
| How do you know your checker works? | Injected a known bug (e.g., swap two select indices) and saw it fail |
| What's the link to the GPIO IP you studied? | Its ASIC note exposes OE + data, exactly what the pinmux takes; same interrupt and synchronizer concerns one level up |

---

## Lines to use

- "Enable decides whether an event is recorded. Mask decides whether a recorded event is reported."
- "Passing tests doesn't mean a behaviour was checked. All 37 directed checks passed with a lost-interrupt race in the design. Only an assertion on the cycle itself caught it."
- "I build the model from the spec, not the RTL, so the model doesn't inherit the RTL's bugs."
- "Most GPIO and pinmux bugs are at boundaries: a direction change, a function switch, a pulse near the filter threshold."
