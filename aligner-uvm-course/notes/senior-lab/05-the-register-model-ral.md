# The register model (RAL)

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 5 · registers as a model

## The register model (RAL)

Your RAL does three jobs: a register API for sequences, a mirror the reference model uses as its state store, and (with the custom predictor) a checker for every APB response. Interviewers probe mirror/desired, prediction modes and side effects.

desired · mirrored · actualexplicit predictionadapter both waysfield callbacksW1C / WO / RO

### 5.1Two paths through the RAL

*[Diagram: RAL frontdoor and prediction paths. Open the HTML page to see it.]*

| Register @ offset | Fields (access) | What the TB must model |
| --- | --- | --- |
| CTRL @ 0x00 | SIZE[2:0] RW (reset 1) · OFFSET[9:8] RW · CLR[16] WO | Legal combos only (constraint); illegal write → pslverr and no update; CLR=1 clears CNT\_DROP (callback); CLR reads 0. |
| STATUS @ 0x0C | CNT\_DROP[7:0] · RX\_LVL[11:8] · TX\_LVL[19:16], all RO | Hardware-updated, so the model `predict()`s them. Any write → pslverr. |
| IRQEN @ 0xF0 | 5 × RW enables | Plain RW, read by the model to gate the expected irq. |
| IRQ @ 0xF4 | 5 × W1C sticky bits | Model sets on events. UVM's W1C policy clears the mirror on write-1. |

### 5.2Code walkthrough

```systemverilog
// cfs_algn_reg_ctrl: legality lives in the register itself
constraint legal_size { SIZE.value != 0; }
constraint legal_size_offset {
  ((ALGN_DATA_WIDTH / 8) + OFFSET.value) % SIZE.value == 0;
  OFFSET.value + SIZE.value <= (ALGN_DATA_WIDTH / 8);
}

// cfs_apb_reg_adapter::bus2reg (monitor items carry the real response)
if($cast(item_mon, bus_item)) begin
  rw.kind   = item_mon.dir == CFS_APB_WRITE ? UVM_WRITE : UVM_READ;
  rw.addr   = item_mon.addr;
  rw.data   = item_mon.data;
  rw.status = item_mon.response == CFS_APB_OKAY ? UVM_IS_OK
                                                : UVM_NOT_OK;
end

// cfs_algn_clr_cnt_drop: a write to one field changes another
virtual function void post_predict(input uvm_reg_field fld,
    input uvm_reg_data_t previous, inout uvm_reg_data_t value,
    input uvm_predict_e kind, input uvm_path_e path,
    input uvm_reg_map map);
  if(kind == UVM_PREDICT_WRITE && value == 1) begin
    void'(cnt_drop.predict(0));   // side effect on STATUS
    value = 0;                    // CLR itself reads back 0
  end
endfunction
```

1. **Constraints in the register** mean every `CTRL.randomize()` anywhere is legal by default. To test illegal writes, turn the constraint off (`constraint_mode(0)`) or write raw values.
2. **Monitor items carry truth.** The adapter maps `pslverr` to `UVM_NOT_OK`, and the predictor uses that to skip the mirror update and to check the error was expected.
3. **Field callbacks model side effects.** UVM knows RW/RO/W1C on their own field, but not "write CLR, clear CNT\_DROP". `uvm_reg_cbs::post_predict` is the standard hook.

### 5.3Hidden concepts

Desired · mirrored · actual

**Desired** is what you intend (set by `set()`/`randomize()`). **Mirrored** is what the TB believes the DUT holds. **Actual** is in the RTL. `update()` writes only where desired ≠ mirrored. A read with `check_on_read` compares actual vs mirrored, and that's how STATUS gets checked for free.

The mirror is the model's state

The model never keeps its own CNT\_DROP or FIFO levels. It calls `STATUS.CNT_DROP.predict(n+1)`. Every later STATUS read then checks the model's prediction against the DUT. One state store, two uses.

check\_on\_read is on

`default_map.set_check_on_read(1)` makes every frontdoor read compare against the mirror. Turn it off and STATUS bugs become invisible, with no other change in the log.

Frontdoor status is always OK

The APB driver returns no response, so `CTRL.write(status, …)` reports `UVM_IS_OK` even when the DUT said pslverr. Never branch test logic on that status here. The predictor is the judge.

`void'(randomize())` in reg2bus

If the inline constraints ever conflict, randomization fails silently and a random APB item goes out. Use `` if(!item.randomize() with {…}) `uvm_fatal(…) ``. That's a one-line review comment that marks you as careful.

lock\_model() before use

Locking builds the address lookup tables. Skip it and `get_reg_by_offset` returns null, so the predictor would call every access "unmapped".

### 5.4Finding: the RAL is not parameterized

Real finding · breaks at ALGN\_DATA\_WIDTH = 64

The RTL computes field widths: `ALGN_SIZE_WIDTH = $clog2(W/8)+1` and `ALGN_OFFSET_WIDTH = $clog2(W/8)`. At W=64 that's SIZE 4 bits and OFFSET 3 bits. `cfs_algn_reg_ctrl` hard-codes `.size(3)` and `.size(2)`, so at 64 bits the mirror can't hold SIZE=8 or OFFSET≥4. The functional coverage bins are also fixed to `[0:3]`/`[1:4]`. Changing `` `CFS_ALGN_TEST_ALGN_DATA_WIDTH `` compiles but verifies the wrong thing.

Also: `ALGN_DATA_WIDTH` inside the register defaults to 8 until the model's `end_of_elaboration_phase` sets it. Randomize CTRL any earlier and you only get width-8 legal values.

### 5.5Bug hunt

**Q: BUG 1 After CTRL.write() with CLR=1, the next STATUS read fails: mirror says CNT\_DROP=37, DUT says 0.**

**Root cause:** the `cfs_algn_clr_cnt_drop` callback isn't registered (see `model.connect_phase`). UVM updated CTRL.CLR but knew nothing about the side effect on STATUS.

**Q: BUG 2 A test writes an illegal CTRL value via CTRL.write() , gets UVM\_IS\_OK , and then waits forever for traffic aligned to that config.**

**Root cause:** the frontdoor status is meaningless here (no driver response). The DUT rejected the write, the predictor correctly left the mirror alone, but the test trusted the returned status.

**Q: BUG 3 IRQ register reads mismatch right after a write-1 to clear.**

**Likely cause:** the IRQ fields were configured as `"RW"` instead of `"W1C"`. The mirror then stores the 1 you wrote. Another candidate: a new event re-set the bit in the same cycle, an unspecified priority from Module 0.

### 5.6Interview drill

**Q: Q1 "Explain implicit, explicit and passive prediction. Which do you use and why?"**

Implicit (auto-predict) updates the mirror from the register call itself. It's simple, but blind to accesses not made through RAL and to bus errors. Explicit: a predictor fed by the bus monitor updates the mirror from observed transfers, so it catches everything on the bus. Passive is the same predictor with no RAL-driven traffic, i.e. SoC level. This env uses explicit prediction with a custom predictor that also checks the response and skips errored accesses.

Cross-questions

- What's `mirror()` vs `read()`? (`mirror(UVM_CHECK)` reads and compares against the mirror. `read()` returns the value and, with check\_on\_read, also compares.)
- Backdoor access: when is it dangerous? (It bypasses the bus, so you skip protocol and side effects like W1C, read-clear and CLR.)
- How do you handle a volatile field? (Mark it volatile and update via predict from a model, or exclude it from compare with `set_compare(UVM_NO_CHECK)`.)

**Q: Q2 "How would you verify a sticky W1C interrupt register?"**

Model sets the bit on the triggering *event* (edge, not level) via `predict(1)`. W1C policy clears the mirror on write-1. Reads compare via check\_on\_read. Coverage: set → read → clear while condition persists → confirm it stays 0 → re-trigger → confirm set. Plus the same-cycle race: clear and set in the same cycle. Ask the designer which wins and code the model to match.

### 5.7Lab

- Run with `+uvm_set_verbosity=*,REG_PREDICT,UVM_HIGH,time,0` (already in your `messages.f`) and follow one CTRL write from adapter to mirror in the log.
- Write a sequence that turns `legal_size_offset` off and writes size 3 at offset 2. Confirm the predictor expects pslverr and the mirror is unchanged.
- Comment out `set_check_on_read(1)`, inject a STATUS bug in `cfs_regs.v` (e.g. RX\_LVL off by one), and see whether anything fails.
