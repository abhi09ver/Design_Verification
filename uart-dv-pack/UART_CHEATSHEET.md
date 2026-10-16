# UART for DV Interviews — One-Page-per-Topic Cheatsheet

Text version of the ten cards in [`cards/`](cards/index.html) / [`uart-dv-cards.pdf`](uart-dv-cards.pdf).
Code references point to [`code/`](code/).

---

## 01 · Fundamentals & frame format

```
idle(1) | START(0) | D0 D1 … D7 (LSB first) | [PARITY] | STOP(1) [STOP2] | idle(1)
```

- **Asynchronous** = no shared clock; each side has its own baud clock. Every frame re-syncs on its own falling start edge, so drift only accumulates over ~10 bits.
- **Idle = 1 (mark).** A falling edge is the only way a frame starts; a stuck-0 line is detectable (break).
- Data 5–8 bits (some 9), LSB first. Parity none / even / odd / mark / space. Stop 1, 1.5 or 2.
- Notation: **8N1**, 7E1, 8O2.
- **Numbers:** 115200 → 8.68 µs/bit · 9600 → 104.17 µs/bit · 8N1 = 10 bits/byte → 80 % efficiency → 11 520 B/s at 115200.
- **RX lock-on (16×):** sync RX (2-FF) → see 1→0 → wait 8 ticks → still 0? real start, else **false start** → sample every 16 ticks at mid-bit → stop must be 1.
- UART is the logic; RS-232/RS-485 are electrical layers (RS-232 is ±V and inverted).

| | UART | SPI | I2C |
|---|---|---|---|
| Clock | none | SCLK | SCL (open-drain) |
| Wires | 2 | 4 + CS/slave | 2 |
| Topology | point-to-point | 1 master, N slaves | multi-master, addressed |
| Duplex | full | full | half |
| Error check | parity, framing | none | ACK/NACK |

**Traps:** "async = no clock" (wrong) · MSB-first driver + MSB-first monitor still passes · throughput ≠ baud.

---

## 02 · UVM protocol checker architecture

```
DUT pins → uart_if (+SVA) → passive monitor → analysis_port.write()
                                         ├→ protocol checker  (frame rules)
                                         ├→ scoreboard        (data, FIFO model)
                                         └→ coverage
```

- **cfg** (`uvm_object`): baud, format, tolerance, per-check enables — set by test, fetched via `uvm_config_db`.
- **item** (`uvm_sequence_item`): data, parity, stop bits, timestamps, edge list, fe/pe flags.
- **Monitor never drives** (reuse as passive at SoC level). One monitor per direction.
- Phases: build (get cfg/vif, create) · connect (ap → subscribers) · run (forever sample) · check (leftovers) · report (summary).
- Where checks live: **timing → SVA**, **frame content → checker class**, **data correctness → scoreboard**.

**Bugs in tutorial-style code:** `uvm_analysis_port` has no `get()` (use `uvm_tlm_analysis_fifo`) · bit-per-transaction TLM loses timing · `new()` on a component in a module skips factory/hierarchy · no objections → sim ends at 0.

Code: [`uart_monitor.sv`](code/uart_monitor.sv), [`uart_agent.sv`](code/uart_agent.sv), [`uart_env.sv`](code/uart_env.sv).

---

## 03 · Baud rate check

```
T_bit   = 1 / baud
divisor = round(f_clk / (16 × baud))
actual  = f_clk / (16 × divisor)
error % = (actual − target) / target × 100
```

| 50 MHz, 16× | exact div | used | actual | error |
|---|---|---|---|---|
| 9600 | 325.52 | 326 | 9585.9 | −0.15 % |
| 115200 | 27.13 | 27 | 115740.7 | +0.47 % |
| 921600 | 3.39 | 3 | 1041666.7 | **+13.0 % ✕** |

**Where ±2 % comes from (8N1):** last sample (stop) is 9.5 T after the start edge → must drift < 0.5 bit → 5.26 % · minus 1/16-bit edge uncertainty → (0.5 − 0.0625)/9.5 ≈ **4.6 % total** · split TX/RX → ≈ ±2.3 % each → design to **±2 %**. Longer frames → tighter.

**Robust check:** timestamp every edge; each gap must be `n × T ± n × T × tol`, n = round(gap/T). `n == 0` → glitch. Use `realtime` and 1 ps precision.

**Weak approaches:** counting transitions in a window (data-dependent) · comparing loop-iteration counts (tautological) · only mid-bit sampling (hides drift until data breaks).

**Tests:** program every divisor (min/max) · drift sweep 0, ±1, ±2, ±3, ±4.5, ±6 % · change baud mid-traffic · autobaud with 0x55.

Code: [`uart_checker.sv`](code/uart_checker.sv) `check_timing()`, [`uart_tests.sv`](code/uart_tests.sv) `uart_drift_test`.

---

## 04 · Framing error

- **Definition:** stop bit sampled **0** at mid-bit. (Not "codes at both ends don't match".)
- **Causes:** baud mismatch · format mismatch (7E1 vs 8N1) · noise · break · TX reset mid-frame · lost sync after an earlier error.
- **DUT (16550-style):** LSR.FE (bit 3) for that char; char still stored; LSR bit 7 = error in FIFO; RLS interrupt.
- **Resync policy is spec-specific** (treat low stop as next start vs wait for idle) — checker must mirror the spec.
- 2 stop bits: RX usually checks only the first; TX must send both.
- **Edge cases:** FE vs false start (glitch → no FE) · all-zero + low stop = break candidate · FE on the char that fills the FIFO · cascades (count root causes) · reset mid-frame.
- **Negative tests:** carry intent (expected-error) or demote by ID with a report catcher — never globally.

Code: driver `INJ_FE`, checker `UART_FE` / `UART_FE2`, test `+UART_INJ=FE`.

---

## 05 · Parity error

| Mode | P | Passes if |
|---|---|---|
| Even | `^data` | `^{data,P} == 0` |
| Odd | `~^data` | `^{data,P} == 1` |
| Mark | 1 | P == 1 |
| Space | 0 | P == 0 |

- 0x53 (four 1s): even 0, odd 1 · 0x57 (five 1s): even 1, odd 0.
- **Detects odd numbers of flips; misses 2-bit flips;** can't locate or correct (Hamming distance 2).
- 16550: LCR bit 3 PEN, bit 4 EPS, bit 5 stick; LSR.PE bit 2.
- **Bugs:** parity over 8 bits when 7 configured · even/odd swapped on both sides · mark/space ignored · XOR-in-P then compare to P.
- Mark/space exist for 9-bit multi-drop addressing.

Code: [`uart_cfg.sv`](code/uart_cfg.sv) `exp_parity()` (configured width only), checker `UART_PE`.

---

## 06 · Break condition

- **Definition:** line low for **longer than one full character** (start + data + parity + stop); every sample is 0 and the line stays low.
- **DUT:** LSR.BI (bit 4), FE usually too; **one** 0x00 per break; wait for mark + new start before receiving. TX: LCR bit 6 forces TX low.
- **Uses:** attention/bootloader entry · LIN 13-bit sync break · resync · line-fault detection.
- **Break vs 0x00:** 0x00 has a high stop bit after 9 low bits.
- **Detector:** race "line went high" vs one-character timeout. Wrap in `fork begin … end join` before `disable fork` so only those threads die.
- **Tests:** 0.9 / 1.0 / 1.5 / 2 / 20+ char durations · break → immediate valid char · TX set-break idle and mid-char.

Code: monitor classifies `KIND_BREAK`, checker `UART_BRK`, test `+UART_INJ=BREAK`.

---

## 07 · Overrun error

- **Definition:** a new char completes in the shift register while the holding register / FIFO is full → one char lost, LSR.OE (bit 1). **Invisible on the wire.**
- FIFO off: new char overwrites unread RBR. FIFO on: shift-register char is dropped; FIFO contents stay valid. Exact count where OE rises is spec-specific.
- **Prevention:** trigger levels (1/4/8/14) · char timeout · auto-RTS/CTS · DMA.
- **Check it in the scoreboard** with two inputs: line monitor (chars in) + bus monitor (RBR/LSR reads out).
- **Pitfalls:** same-cycle read/arrive race · model push point vs RTL push point · oldest-vs-newest lost · LSR read clears several sticky bits.
- Underrun on TX is not an error — line idles, THRE fires.

Code: [`uart_scoreboard.sv`](code/uart_scoreboard.sv).

---

## 08 · Data validity & idle line

- **Data:** LSB first · exact width · unused upper RBR bits 0 · no X/Z · end-to-end in order.
- **Symmetric-bug trap:** MSB-first DUT + MSB-first TB (or loopback) passes. Break symmetry with one raw-waveform check of 0x01, asymmetric patterns, independently written driver/monitor.
- **Glitches (16× sampler):** 1/16 and 7/16 bit → rejected · 9/16 bit → accepted as start, decodes 0xFF. Boundary is a coverage bin.
- **Idle rules:** TX = 1 in and right after reset · no X/Z · gap ≥ stop bits · reset/disable mid-frame → TX high at once, RX drops partial · char timeout ≈ 4 char times.

```systemverilog
a_idle_rst : assert property (@(posedge clk) !rst_n |-> tx === 1'b1);
a_no_x     : assert property (@(posedge clk) disable iff (!rst_n) !$isunknown(tx));
a_min_low  : assert property (@(posedge clk) disable iff (!rst_n)
                              $fell(tx) |-> (!tx)[*(BIT_CLKS-1)]);
```

Code: [`uart_if.sv`](code/uart_if.sv).

---

## 09 · Error reporting & integration

| Error | On wire? | Caught by | LSR | Inject with |
|---|---|---|---|---|
| Baud / timing | yes | checker edge gaps | — (shows as FE) | drift % |
| Framing | yes | checker stop sample | FE · 3 | stop = 0 |
| Parity | yes | checker XOR | PE · 2 | flip P / 1 data bit |
| Break | yes | low-time | BI · 4 | low > 1 char |
| Overrun | **no** | scoreboard | OE · 1 | stop reading |
| False start | yes | pulse width | — | short glitch |
| Data / order | partly | scoreboard + waveform | — | asymmetric bytes |
| Idle / X | yes | SVA | — | reset mid-frame |

Other LSR bits: DR 0 · THRE 5 · TEMT 6 · bit 7 FIFO error. Error bits are sticky, clear on LSR read.

**Reporting:** one ID per check · DUT violation = `uvm_error` · message has time, direction, data, measured vs expected · suppress cascades until idle · `report_phase` summary · enables in cfg, never disabled to pass.

**Expected errors:** report catcher demotes one ID and **counts** — `check_phase` compares with injected count.

**10-line revision:**
1. Idle 1, start 0, 5–8 data LSB-first, optional parity, 1–2 stop.
2. RX: 16× oversample, confirm start mid-bit, sample every 16 ticks.
3. Tolerance: last sample at 9.5 T → ~4.6 % total → ±2 % per side.
4. Check baud by timing every edge gap as n × T.
5. Framing = stop sampled 0; resync policy from spec.
6. Parity catches odd-count flips; compute over configured width.
7. Break = low > one char; one 0x00 + BI per break, then wait for mark.
8. Overrun is invisible on the wire — model FIFO with line + bus monitors.
9. Symmetric bugs pass loopback; check one raw waveform against the spec.
10. Unique IDs, expected-error catchers that count, cascade suppression, summary.

---

## Bonus · Chipmunk Logic UART IP

From the [product page](https://chipmunklogic.com/ip-cores/design-of-uart-controller/) (RTL archives are password-protected, not reviewed):

- One clock / one reset · baud **enable pulses** (1× TX, **8×** RX), no divided clocks · multi-flop sync on RX · 8-bit data, parity none/odd/even, 1–2 stop · valid/ready data ports, **no FIFO** · parity + framing flags.
- **±5 % claim vs 8× reality:** edge uncertainty 1/8 bit → (0.5 − 0.125)/9.5 ≈ **3.9 %** (8N1), 0.375/10.5 ≈ **3.6 %** with parity — combined TX+RX budget.
- Card changes: overrun → **backpressure** (byte completes with ready low) · break → 0x00 + FE · RX sync flops must **reset to 1** · status flags instead of LSR.
- Open questions for the RTL: backpressure behaviour · flag pulse vs sticky · sync stages + reset value · mid-bit start recheck · both stop bits checked · config change mid-frame · baud counter width · what the synthesisable TB checks.
