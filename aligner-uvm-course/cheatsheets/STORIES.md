# Interview stories (STAR format)

Seven stories from this project. Each one answers a common behavioural or technical prompt. Say them out loud until each one takes about 60–90 seconds.

---

## 1. "Tell me about a bug you found" → the SIZE-5 spec + RTL bug

- **Situation:** I was integrating the register model for the aligner and randomizing the CTRL register under the datasheet's alignment formula `(bytes + OFFSET) % SIZE == 0`.
- **Task:** Make register randomization always produce legal configurations.
- **Action:** One seed produced SIZE 5, OFFSET 1 on a 32-bit (4-byte) bus. The formula allowed it and the RTL accepted it with OKAY. I sent traffic, and an assertion I'd put on the MD interface fired: size + offset exceeded the bus width. Looking at the waves, the RTL tried to emit a 5-byte transfer.
- **Result:** The spec was missing a rule (`OFFSET + SIZE <= bytes`). We added it to the datasheet (v1.1), the RTL now returns SLVERR, I added the rule to the predictor's expected-response logic and to the register constraints. **Lesson:** constrained-random found a case nobody had written down, and an assertion based on physical limits caught what spec-derived checks couldn't.

## 2. "Tell me about a hard debug" → 7 IRQs expected, 6 received

- **S:** Once the IRQ scoreboard check was on, a random test failed: an IRQ was expected but never received.
- **T:** Decide whether the RTL or the testbench was wrong.
- **A:** I pinned the seed. I counted 7 expected IRQs against 6 actual pulses. Matching them by time didn't work, because the model and RTL fire a few cycles apart. So I grouped them by cause: the model had 4 RX-empty + 3 TX-empty, the RTL's internal `edge_*` signals showed 4 + 2. Zooming in on TX_LVL showed a push and a pop in the same cycle: the RTL's level stayed at 1 (no 1→0 edge), while my model went 0→1→0.
- **R:** The concept engineer confirmed the flag means the *level* goes 1→0, so this was a testbench bug. The fix exposed two more synchronization issues (story 3).

## 3. "How do you handle model/RTL timing differences?" → three sync fixes

1. **Same-time push/pop:** flag setters are deferred by 2 NBA regions in a killable process, and the opposite FIFO operation kills them 1 NBA region later. This works regardless of thread order.
2. **The model was faster than the RTL FIFOs** (4 pushes and 1 pop in the same time step): before each push or pop, wait for the RTL's internal valid&ready probe, with a 10-cycle timeout that only counts cycles where the operation was possible. The probe is a timing *hint*, never the expected value.
3. **Overlapping IRQ sources:** all setters set one `exp_irq` bit, and a single sampler at the negedge sends at most one expectation per cycle. That's the spec's OR gate.

I rejected adding delays (a synchronization nightmare) and copying the RTL (that stops being verification).

## 4. "Describe a test that found something" → illegal-RX test and MAX_DROP

- Extended the RX virtual sequence with an "illegal transfer" constraint, extended the random test with 300 transfers (more than 255), and added a factory override. About 30 additive lines.
- Some seeds failed: an IRQ was expected but not received. I switched on the CNT_DROP/IRQ message IDs in `messages.f`: the drop counter reached 255 with IRQEN.MAX_DROP = 1, and the RTL's flag was set, but `irq` stayed low.
- Root cause: `cfs_regs.v` ORed 4 of the 5 sources. It only fails when random IRQEN enables MAX_DROP. **Lesson:** coverage must include the IRQ source × enable cross.

## 5. "A refactor you did" → base-class library

After two agents (APB and MD), I moved the common config, reset handling, run loops, port wiring and coverage helpers into a parameterized `uvm_ext_pkg`. APB went from 940 to 617 lines (−34%) and MD from 1278 to 953 (−25%). One regression it caused: PSEL was X at time 0, because the agent's reset loop `$cast` to the old reset-handler type and silently skipped the new driver. I fixed it by unifying on one interface class. Next step would be templates plus a generator script.

## 6. "Register model experience" → custom predictor

The default `uvm_reg_predictor` updated the mirror even on SLVERR writes. I extended it so it checks the bus status against the datasheet's six error rules (unmapped, write RO, read WO, SIZE=0, misaligned, overflow), returns a status *plus a reason string* for debug, and calls `super.write()` only for OK accesses. I also modeled the CLR → CNT_DROP side effect with a `uvm_reg_cbs::post_predict` callback.

## 7. "Something non-obvious in UVM" → the W1C randomize trap

`randomize()` + `update()` never wrote the IRQ register. Root cause: `uvm_reg_field::configure()` forces `is_rand = 0` and `value.rand_mode(0)` for W1C-type accesses, ignoring the argument you pass. The desired value never changed, so `needs_update()` was 0. Fix: `FIELD.value.rand_mode(1)` after configure.
