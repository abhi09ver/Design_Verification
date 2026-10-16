# The reference model

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 6 · the golden reference

## The reference model

`cfs_algn_model` is about 850 lines and the heart of the checking. It's a transaction-level model of the RX FIFO, the aligner and the TX FIFO, kept in step with the DUT through four white-box probes. You'll see the alignment algorithm run, then the timing tricks that make it match RTL.

split / merge algorithmthreads per pipeline stageuvm\_wait\_for\_nba\_regionborrowed timingreset-safe processes

### 6.1Alignment simulator: the model's algorithm, live

Pick a CTRL setting and push RX transfers (lane 0 is on the right, as in the datasheet figures). Bytes keep their colour from the RX transfer they came from. Amber-framed TX words contain a piece of a *split* RX transfer, which is exactly when the model publishes `split_info` to coverage.

CTRL (offset, size)

MD RX

MD TX

split\_info

### 6.2Inside the model: one thread per hardware stage

1. **write\_in\_rx()**At the *start* of an RX transfer: compute the expected response. ERR → bump CNT\_DROP (saturating) and publish ERR. OKAY → fork `push_to_rx_fifo`.
2. **push\_to\_rx\_fifo**Waits for the RTL's `rx_fifo_push` probe (or 10 cycles of room, then a warning), then `rx_fifo.put`, RX\_LVL+1, maybe FIFO-full IRQ.
3. **build\_buffer**While the buffered bytes are ≤ CTRL.SIZE, pop the next RX item into `buffer[$]`, synced to `rx_fifo_pop`.
4. **align**While buffered bytes ≥ CTRL.SIZE: build a TX item of exactly SIZE bytes at CTRL.OFFSET, splitting the head item when it doesn't fit.
5. **tx\_ctrl**Pop from the TX FIFO model, publish the expected TX item, then wait for `tx_complete` (end of the TX monitor item) before the next.
6. **send\_exp\_irq**At each negedge, if any enabled IRQ event fired this cycle, publish one expected irq pulse.

### 6.3Code walkthrough: the timing tricks

```systemverilog
// RX FIFO became full: decide AFTER everything else at this time step
protected virtual function void set_rx_fifo_full();
  fork begin
    process_set_rx_fifo_full = process::self();
    repeat(2) begin
      uvm_wait_for_nba_region();
    end
    void'(reg_block.IRQ.RX_FIFO_FULL.predict(1));
    if(reg_block.IRQEN.RX_FIFO_FULL.get_mirrored_value() == 1)
      exp_irq = 1;
  end join_none
endfunction

// ...and cancel it if a pop happens in the same time step
protected virtual function void kill_set_rx_fifo_full();
  fork begin
    uvm_wait_for_nba_region();
    kill_process(process_set_rx_fifo_full);
  end join_none
endfunction

// borrow timing from the RTL, with a safety net
fork
  @(posedge vif.clk iff(vif.rx_fifo_push));
  begin
    repeat(10) @(posedge vif.clk iff(RX_LVL < rx_fifo.size()));
    `uvm_warning("DUT_WARNING",
                 "RX FIFO push did NOT synchronize with RTL")
  end
join_any
disable fork;
```

1. **Same-timestep ordering.** Push and pop can happen at the same edge in different threads. Waiting two NBA regions lets every thread at that time step finish before the "became full" verdict is taken.
2. **Cancel by kill.** If a pop arrives in the same step, the pending "set full" process is killed. The FIFO was never observably full, so there's no IRQ. That's the "became" (edge) semantics from Module 0, done in a TLM model.
3. **Borrowed timing.** The model waits for the DUT's own push strobe to decide *when* it happened, so cycle-level IRQ timing lines up without a cycle-accurate model. The fallback branch prevents a hang if the DUT never pushes.

### 6.4Hidden concepts and findings

Finding · a DUT bug becomes a warning

If the RTL never pushes, the sync fallback only prints `DUT_WARNING` and the model carries on as if it had. A stuck RX FIFO shows up later, and indirectly, as a TX watchdog error, or not at all if the test ends first. Rule: `grep DUT_WARNING` in every regression, or promote it to an error.

Finding · hard-coded FIFO depth

`rx_fifo = new("rx_fifo", this, 8)`. FIFO\_DEPTH is a DUT parameter (§2), but the TB copies the default. Build the DUT with depth 16 and the model predicts FIFO-full IRQs at 8.

Predict at start, compare at end

The model reacts to the *start* of the RX transfer (`is_active()`) because the DUT decides err in that same cycle. The scoreboard compares at the *end*. The model is never later than the DUT.

Every thread has a handle

Each forked loop stores `process::self()`, and `handle_reset()` kills them all, flushes the FIFOs, resets the reg block and restarts the threads. Forgetting one handle means a zombie thread from before reset keeps producing expectations.

Transaction-level, cycle-aware

No clocks inside the algorithm, only around it (probe syncs, negedge irq). That's the usual compromise: easier to write than cycle-accurate, tighter than pure TLM. Be ready to defend it.

Reconfig mid-traffic is untested

`align()` re-reads CTRL every loop. A CTRL write while bytes sit in the buffer changes the rule half-way through a TX word. The spec is silent, and `cfs_algn_test_random` avoids it with `if(model.is_empty())`. Ask the designer.

### 6.5Interview drill

**Q: Q1 "Cycle-accurate or transaction-level reference model?"**

Transaction-level for data (what bytes, in what order), plus cycle-awareness only where the spec defines timing (here: IRQ pulses and FIFO levels visible through STATUS). Cycle-accurate models duplicate the RTL's micro-architecture, so they get the same bugs and break on every pipeline change. When timing is loosely specified, check windows (watchdogs) rather than exact cycles.

Cross-questions

- Is using DUT probes for timing cheating? (It's a trade-off. The data is still predicted independently, but a probe bug or RTL rename silently desynchronises the model. Keep the fallback and make its warning an error.)
- How would you plug in a C model? (DPI-C call inside `align()` taking the byte stream and CTRL and returning TX words; keep the SV threads for timing.)

**Q: Q2 "Push and pop hit a full FIFO in the same cycle. Is a FIFO\_FULL interrupt raised?"**

It depends on the definition of "became full". If it means the level register reached MAX at a clock edge, then simultaneous push+pop at MAX−1 never reaches MAX: no interrupt. The model enforces it by deferring the decision with `uvm_wait_for_nba_region()` and cancelling on a same-step pop. The senior part of the answer is naming the ambiguity and getting the spec to state it.

### 6.6Lab

- In the simulator, find a CTRL setting where an RX transfer of size 4 is split twice. Then find the RX/CTRL pair that produces `num_bytes_needed = 3`.
- Search your `xrun.log` for `DUT_WARNING`. Then change `repeat(10)` to `repeat(1)` in `sync_push_to_rx_fifo` and see whether warnings appear (they show how tightly the model tracks the RTL).
- Pass FIFO\_DEPTH through `env_config` into the model instead of the hard-coded 8.
