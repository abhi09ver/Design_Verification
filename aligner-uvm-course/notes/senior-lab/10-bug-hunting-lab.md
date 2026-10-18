# Bug-hunting lab

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 10 · the job

## Bug-hunting lab

Debugging is what senior interviews actually test. It starts with a real DUT bug I found in your RTL, which your `rx_err` test is set up to expose. Then eight bugs to inject and catch, each tied to the checker that should fire.

first-error triageTB vs DUTspec as refereeescapes

### 10.1Debug method

1. **Reproduce**Same seed, same test, same build. Rerun with `+UVM_VERBOSITY=UVM_HIGH` and waves on. No seed means no debug.
2. **First error only**`+UVM_MAX_QUIT_COUNT=1` (you already use it). Later errors are usually echoes of the first.
3. **Classify the ID**`DUT_ERROR` (scoreboard/predictor), `PROTOCOL_ERROR`/SVA (bus rule), `ALGORITHM_ISSUE` (TB self-check). That splits suspects in two.
4. **Spec decides**Model and RTL disagree, so read the datasheet. Whoever deviates from the spec is wrong. If the spec is silent, it's a spec bug and goes to the designer.
5. **Walk back in time**From the failing compare to the input that caused it: the monitor item, then the model's decision, then the waveform at that time.
6. **Shrink**Smallest test and fewest items that still fail. Becomes the regression test for the fix.

### 10.2Real bug: MAX\_DROP never reaches the irq pin

cfs\_regs.v · lines 164–168

The datasheet (§4.4, Fig. 11) ORs **five** enabled events into `irq`. The RTL ORs four. `edge_max_drop` is computed on line 162 and sets `IRQ.MAX_DROP` correctly, but never drives the pin:

```systemverilog
assign irq =
  (edge_rx_fifo_empty & irqen_rx_fifo_empty) |
  (edge_rx_fifo_full  & irqen_rx_fifo_full)  |
  (edge_tx_fifo_empty & irqen_tx_fifo_empty) |
  (edge_tx_fifo_full  & irqen_tx_fifo_full);
  // missing: | (edge_max_drop & irqen_max_drop)
```

**Why your rx\_err test finds it:** 300 illegal transfers push CNT\_DROP past 255 (it saturates). `cfs_algn_virtual_sequence_reg_config` randomizes IRQEN, so in roughly half the seeds `IRQEN.MAX_DROP = 1`. Then the model's `set_max_drop()` predicts an irq pulse and the scoreboard should report:

```systemverilog
UVM_ERROR … [DUT_ERROR] The IRQ expected from time …, was not received after 10 clock cycles
```

In the other half, IRQEN.MAX\_DROP=0 and the test passes, which is why one seed is never enough. Fix: add the fifth term. Also add an IRQ covergroup (Module 8) so "MAX\_DROP × enabled" is a bin that must be hit.

I found this by reading the RTL against the datasheet. I can't run Xcelium here, so confirm it on EDA Playground: run `cfs_algn_test_random_rx_err` over several seeds and paste me the log.

**Q: STAR Use it as your "hardest bug" interview story**

**Situation:** stream aligner with five interrupt sources; random regression was green. **Task:** close IRQ verification. **Action:** wrote a test that saturates the drop counter. It failed only on some seeds; I bucketed the failing seeds by IRQEN value, traced the scoreboard's expected IRQ to the model's MAX\_DROP prediction, checked IRQ.MAX\_DROP in the register (set correctly), then found the missing OR term on the pin. **Result:** RTL fix, a new covergroup on event × enable, and a rule to run IRQ tests across ≥20 seeds. Point out *why* random tests missed it: the event needed 255 errors *and* a 50% enable bit.

### 10.3Second real issue: CDC that the testbench can't see

cfs\_aligner\_core.v · cfs\_synch.v · cfs\_rx\_ctrl.v

The core has three clock domains (`md_rx_clk`, `pclk`, `md_tx_clk`) with async FIFOs between them, but `cfs_aligner.v` ties all three to one `clk`. CNT\_DROP (8 bits) crosses domains through `cfs_synch`, which is a *single* flop on a multi-bit bus. With real asynchronous clocks that can capture a mix of old and new bits. It's also cleared by `clr_cnt_dop` used as an asynchronous reset from another domain.

Your testbench drives one clock, so none of this can fail in simulation. Interview answer: "I'd parameterize the TB with independent clocks and random ratios, run a structural CDC tool, and either Gray-code the counter or hand it across with a handshake."

### 10.4Inject-and-catch: predict the checker before you reveal

**Q: INJ 1 cfs\_rx\_ctrl.v : change the legality test from != 0 to == 0 .**

**Fires:** scoreboard `Mismatch detected for the RX response` on the very first item. Then the model pushes legal items the DUT dropped, so TX watchdogs fire too. Fix the first error only.

**Q: INJ 2 cfs\_rx\_ctrl.v : remove the saturation check so CNT\_DROP wraps at 256.**

**Fires:** only in `rx_err` (≥256 errors), and only when STATUS is read afterwards: RAL check-on-read mismatch (mirror 255, DUT 44). `test_random` never catches it, which is a coverage lesson.

**Q: INJ 3 cfs\_rx\_ctrl.v : md\_rx\_ready = push\_valid & push\_ready (drop | md\_rx\_err ).**

**Fires:** an illegal transfer is never accepted. RX response watchdog ("not received after 10 clock cycles"), and if the test runs long enough the monitor's stuck threshold (1000 cycles) as `PROTOCOL_ERROR`.

**Q: INJ 4 cfs\_regs.v : change RESET\_VAL of the RX-empty edge detector from 1 to 0.**

**Fires:** a fake "became empty" edge right after reset. With IRQEN.RX\_FIFO\_EMPTY=1 you get `Unexpected IRQ detected`, and IRQ.RX\_FIFO\_EMPTY reads 1 unexpectedly (RAL mismatch). The RAL catches it even with IRQEN=0.

**Q: INJ 5 cfs\_regs.v : a write to STATUS returns pslverr = 0 .**

**Fires:** the custom predictor: `Mismatch detected for the bus operation status - expected: UVM_NOT_OK, received: UVM_IS_OK … Write access to a full read-only register`. Only in `test_reg_access`.

**Q: INJ 6 cfs\_ctrl.v : swap the byte order when packing a TX word.**

**Fires:** `Mismatch detected for the TX data`, but only when CTRL.SIZE > 1. With SIZE=1 the bug is invisible. Check whether your seed ever configured SIZE 2 or 4.

**Q: INJ 7 Build the DUT with FIFO\_DEPTH = 16 .**

**Fires:** a TB bug, not a DUT bug. The model (hard-coded depth 8) predicts FIFO-full IRQs and caps RX\_LVL at 8. Under back-pressure you get unexpected/missing IRQ errors and STATUS mismatches. Lesson: an error ID says `DUT_ERROR`, the root cause is in the TB.

**Q: INJ 8 cfs\_regs.v : stop ignoring paddr[1:0] (decode the full address).**

**Fires:** nothing. Register tests use aligned addresses, and the unmapped test excludes 0x01–0x03 etc. (Module 9). A complete escape. Fix: add a sequence that accesses each register at +1, +2, +3 and expects the same result as +0.

### 10.5Lab

- Run `cfs_algn_test_random_rx_err` on 5+ seeds. For each, note IRQEN.MAX\_DROP (from the REG\_PREDICT log) and pass/fail. You should see the correlation.
- Apply the one-line irq fix and rerun the failing seeds.
- Pick two injections, predict the first error, run, and compare. Write down the time from first error to root cause.
