# The reactive slave: MD TX agent

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 4 · when the DUT is the master

## The reactive slave: MD TX agent

On the TX side the DUT starts every transfer. The agent can't push items; it has to *notice* a transfer and *answer* it. That loop from monitor to sequencer to driver is the most-asked agent topic after the basics.

monitor → sequencer feedbackis\_active() start/end itemsforever response sequencesback-pressure control

### 4.1The reactive loop

*[Diagram: Reactive slave loop. Open the HTML page to see it.]*

### 4.2Code walkthrough

```systemverilog
// cfs_md_sequencer_base_slave
virtual function void write(cfs_md_item_mon item);
  if(item.is_active()) begin              // only START events
    if(pending_items.is_full())
      `uvm_fatal("ALGORITHM_ISSUE", "no sequence pulls this FIFO")
    void'(pending_items.try_put(item));
  end
endfunction

// cfs_md_sequence_slave_response
virtual task body();
  cfs_md_item_mon item_mon;
  p_sequencer.pending_items.get(item_mon);  // block until DUT starts
  `uvm_do_with(seq, {})                     // answer it
endtask

// cfs_md_sequence_slave_response_forever (started by the test)
forever `uvm_do_on(seq, p_sequencer)

// cfs_md_driver_slave::drive_transaction
if(vif.valid !== 1)
  `uvm_error("ALGORITHM_ISSUE", "slave item without master item")
vif.ready <= 0;
for(int i = 0; i < item.length; i++) @(posedge vif.clk);
vif.ready <= 1;
vif.err   <= bit'(item.response);
@(posedge vif.clk);
vif.ready <= item.ready_at_end;           // may stay high
vif.err   <= 0;
```

1. **The monitor writes the same transfer twice.** Once at start (`begin_tr`, so `is_active()==1`) and once at end. The sequencer reacts only to starts. The scoreboard compares only ends.
2. **Depth-1 FIFO + fatal** turns a silent hang ("nobody answered") into an immediate, self-explaining error. Defensive VIP design.
3. **Responses are sequences, not driver logic.** A test can replace the default responder with one that stalls 50 cycles or returns err on the last chunk, as `virtual_sequence_slow_pace` does.
4. **`ready_at_end` and `ready_at_reset`** let ready be high *before* valid, which the MD protocol allows. Without them you never test zero-latency acceptance.

### 4.3Hidden concepts

One object, two meanings

Subscribers receive the *same handle* at start and end, and it mutates in between (length, response). Anyone storing it at start sees its later values. If you need a snapshot, `clone()` it. A subtle source of "the scoreboard saw the wrong response".

Response is unconstrained

`cfs_md_item_drv_slave.response` has no constraint, so random TX traffic gets `err` about half the time. The datasheet says nothing about what the aligner does on `md_tx_err`, and the scoreboard doesn't check it. Ask: is that a coverage point with no checker?

Back-pressure is a test knob

`length` is soft ≤5. To fill the TX FIFO (8 entries) and then the RX FIFO, a test must make the slave much slower than the master. Default traffic rarely does, so FIFO-full IRQs stay rare.

Parameter firewall again

The sequencer's useful API lives in the unparameterized `cfs_md_sequencer_base_slave`, so response sequences declare `p_sequencer` of that type and work at any data width.

### 4.4Bug hunt

**Q: BUG 1 New test: first TX transfer → fatal FIFO … pending\_items is full .**

**Root cause:** the test never started `cfs_md_sequence_slave_response_forever` on `env.md_tx_agent.sequencer`. Compare with `cfs_algn_test_random`, which forks it at the top of `run_phase`.

**Q: BUG 2 After a cleanup, two responses are queued per DUT transfer and the run stalls on a fatal.**

**Root cause:** the `is_active()` filter was removed from the sequencer's `write()`, so the end-of-transfer write also queues a request.

**Q: BUG 3 100% pass, but STATUS.TX\_LVL never exceeds 2 and the TX\_FIFO\_FULL IRQ is never seen.**

**Root cause:** not a bug, a stimulus hole. The responder is too fast. Add a sequence with `length dist {[0:2]:/80, [20:60]:/20}` and watch TX\_LVL climb. "All tests pass" says nothing about what was exercised.

### 4.5Interview drill

**Q: Q1 "How do you build a slave agent that responds to the DUT?"**

The monitor detects the start of a transfer and publishes it. The sequencer has an analysis imp that queues those requests. A forever "responder" sequence blocks on that queue, then sends a response item whose fields (latency, error, data) are randomizable, and the driver applies it to the handshake. The responder sequence is the knob tests override.

Cross-questions

- Why not let the driver watch `valid` itself? (Then response policy lives in the driver and tests can't shape it without overrides.)
- How would you handle a memory slave that must return read data? (The responder looks up a memory model keyed by address from the monitored request; the memory is shared by handle with the scoreboard.)
- What if the DUT can have several outstanding requests? (A deeper queue, ID-based matching, out-of-order responses.)

### 4.6Lab

- Write `cfs_md_sequence_slave_response_slow` that sets `length` to 20–60 for 20% of responses, override the forever responder's inner sequence with it, and read STATUS.TX\_LVL in the log.
- Constrain `response == CFS_MD_OKAY` in your responder. Does anything in the scoreboard change? Why not?
