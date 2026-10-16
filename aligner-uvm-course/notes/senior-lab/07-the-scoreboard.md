# The scoreboard

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 7 · the judge

## The scoreboard

`cfs_algn_scoreboard` compares three channels: RX response, TX items and the irq pin. Instead of an end-of-test check, each expectation gets its own watchdog. Learn the pattern, then find the two holes it leaves.

expected queuesper-item watchdogsin-order compareend-of-test hygiene

### 7.1One expectation's life, two endings

*[Diagram: Watchdog timeline for an expected TX item. Open the HTML page to see it.]*

### 7.2Code walkthrough

```systemverilog
virtual function void write_in_model_tx(cfs_md_item_mon item_mon);
  if(exp_tx_items.size() >= 1)              // TB sanity check
    `uvm_error("ALGORITHM_ISSUE", "already 1 pending")
  exp_tx_items.push_back(item_mon);
  exp_tx_item_watchdog_nb(item_mon);         // fork a timer
endfunction

virtual function void write_in_agent_tx(cfs_md_item_mon item_mon);
  if(!item_mon.is_active()) begin            // END of transfer only
    cfs_md_item_mon exp_item = exp_tx_items.pop_front();
    process_exp_tx_item_watchdog[0].kill();
    void'(process_exp_tx_item_watchdog.pop_front());
    if(env_config.get_has_checks()) begin
      if(item_mon.data   != exp_item.data)   `uvm_error("DUT_ERROR", ...)
      if(item_mon.offset != exp_item.offset) `uvm_error("DUT_ERROR", ...)
    end
  end
endfunction

// IRQ: sample the pin every clock
forever begin
  @(posedge vif.clk iff(vif.irq & vif.reset_n));
  if(exp_irqs.size() == 0) `uvm_error("DUT_ERROR", "Unexpected IRQ detected")
  else begin void'(exp_irqs.pop_front()); /* kill its watchdog */ end
end
```

1. **The TB checks itself.** The model publishes one TX item at a time (it waits for `tx_complete`), so more than one pending means the TB is broken. That's reported as `ALGORITHM_ISSUE`, distinct from `DUT_ERROR`, so triage starts on the right side.
2. **Watchdogs give latency checks for free.** "Must arrive within N cycles" catches dropped and stuck items at the moment they go missing, not at end of test.
3. **In-order compare.** The aligner can't reorder, so `pop_front` is right. A DUT with IDs or multiple channels needs an associative array keyed by ID.
4. **Data and offset only.** Size is implied by `data.size()`. TX `response` and latency are not checked, since the spec defines neither.
5. **The IRQ checker assumes a pulse.** Every clock with irq high consumes one expectation. A level-style irq held 3 cycles would report two "Unexpected IRQ" errors. That's the Module 0 ambiguity, resolved in code.

### 7.3Findings in your scoreboard

No end-of-test check

There's no `check_phase`. If the test drops its objection within 10 cycles of a prediction, the watchdog thread dies with the run phase and a missing item is never reported. Today's tests happen to wait long enough (100 clocks + 500 ns), but nothing enforces it.

Unexpected item = crash, not error

If the DUT emits a TX item nobody predicted, `exp_tx_items.pop_front()` on an empty queue returns `null` and the compare dereferences it, giving a null-object fatal. Similarly `process_exp_tx_item_watchdog[0]` on an empty queue. The real DUT bug gets reported as a TB crash.

Checks off ≠ silent

`has_checks=0` skips compares but still pops queues, so the bookkeeping stays aligned and checks can be turned back on mid-test. That's a good pattern to copy.

### 7.4Interview drill

**Q: Q1 "In-order vs out-of-order scoreboard: how do you build each?"**

In-order: a queue per stream, push expected, pop and compare on actual. Out-of-order: an associative array keyed by a match key (ID, address, tag), with a search on arrival and an error for an unknown key. Both need end-of-test emptiness checks, plus timeouts if latency is bounded. The hard part is choosing the key when the DUT can merge or split items, as this one does. Then compare at byte-stream level, not item level.

Cross-questions

- Why not compare inside the model? (Separation: swap models, reuse the comparator, and keep "prediction bug" separate from "compare bug".)
- When would you compare at end of test only? (When order and latency are unspecified, e.g. memory contents after a DMA. Compare final state.)

**Q: Q2 "How do you guarantee nothing was silently dropped?"**

Three layers: per-item timeouts while running, a `check_phase` that errors on any non-empty expected queue, and a drain time (or `phase_ready_to_end`) so the test doesn't end with traffic in flight. Plus coverage on "items compared", so a test with zero compares can't count as a pass.

### 7.5Lab

```systemverilog
// 1) report leftovers at end of test
virtual function void check_phase(uvm_phase phase);
  super.check_phase(phase);
  if(env_config.get_has_checks()) begin
    if(exp_rx_responses.size() != 0)
      `uvm_error("DUT_ERROR", $sformatf("%0d RX responses never received", exp_rx_responses.size()))
    if(exp_tx_items.size() != 0)
      `uvm_error("DUT_ERROR", $sformatf("%0d TX items never received", exp_tx_items.size()))
    if(exp_irqs.size() != 0)
      `uvm_error("DUT_ERROR", $sformatf("%0d IRQs never received", exp_irqs.size()))
  end
endfunction

// 2) at the top of write_in_agent_tx's END branch
if(exp_tx_items.size() == 0) begin
  `uvm_error("DUT_ERROR", $sformatf("Unexpected TX item: %0s", item_mon.convert2string()))
  return;
end
```

- Add both fixes. Then cut `#(500ns)` and the 100-clock wait from `cfs_algn_test_random` and see whether `check_phase` now catches in-flight items.
- Add a counter of successful compares per channel and print it in `report_phase`. A test with 0 TX compares should fail.
