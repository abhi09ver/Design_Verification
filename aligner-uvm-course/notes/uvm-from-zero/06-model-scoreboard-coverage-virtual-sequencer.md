# Lecture companion: Model, scoreboard, coverage, virtual sequencer

> Card-by-card notes for Cristian Slav's course. Diagrams and toys are in `pages/uvm-from-zero.html`.

Chapter · modeling and checking (32 videos)

## Model, scoreboard, coverage, virtual sequencer

The environment's "brain". The **model** watches the Aligner's inputs and predicts its three outputs: the RX response, the TX transfers and the IRQ pulses. The **scoreboard** compares those predictions with what the agents see. A **coverage** component records which split scenarios were exercised, and a **virtual sequencer** coordinates the APB, RX and TX agents from one sequence. The most valuable part for interviews is the middle of the chapter: three **synchronization bugs in the testbench itself**, and how each was debugged and fixed.

*[Diagram: Model architecture mirroring the Aligner block diagram, with three outputs to the scoreboard. Open the HTML page to see it.]*

The model copies the datasheet's block diagram (RX controller → RX FIFO → controller → TX FIFO → TX controller), not the RTL code. Dashed boxes are "logic clouds": tasks and functions inside one `cfs_algn_model` component, not separate classes. Every push or pop also updates RX\_LVL/TX\_LVL and the IRQ flags in the register model.

---

C1

## What the model and scoreboard do

Section introduction + model architecture · 2 lectures

Think of it like…

A cooking contest. The **model** is a judge with the recipe book: from the ingredients that went in, it writes down what should come out. The **scoreboard** is the judge's table, where the predicted dish and the chef's dish are compared plate by plate. **Coverage** is the checklist of recipes tried so far. The **virtual sequencer** is the head waiter who tells all the kitchen stations what to do together.

| Aligner output | Model predicts with | DUT value comes from |
| --- | --- | --- |
| RX response (OKAY/ERR) | RX controller logic → `port_out_rx` (`cfs_md_response`) | RX agent monitor |
| TX transfer (data, offset) | tx\_ctrl → `port_out_tx` (`cfs_md_item_mon`) | TX agent monitor |
| IRQ pulse | flag setters → `port_out_irq` (`bit`) | the `irq` wire, read through a vif (no agent) |

Lecturer's advice

- Read the datasheet's "Flow Control" and "Interrupt requests" chapters before modeling. Knowing the spec thoroughly is part of the job.
- The model's structure mirrors the spec's block diagram, so each piece of logic is easy to locate and debug.
- FIFOs use `uvm_tlm_fifo` because its blocking `put()`/`get()` model back-pressure for free.

**Q: "What's the difference between a reference model and a scoreboard?"**

The model **predicts**: it consumes DUT inputs and produces expected outputs, and it holds behavioural state (FIFOs, buffer, registers). The scoreboard **compares**: it pairs expected with actual, handles ordering and timing (queues, watchdogs) and reports mismatches. Keeping them separate means you can swap the model (for example for a C model through DPI) or reuse the comparison logic.

**Q: "How do you decide the model's structure?"**

Start from the spec's functional blocks and their observable effects, not the RTL's implementation. Model at transaction level where the spec allows it, and add timing only where an output depends on it (here, the IRQs depend on FIFO levels). Keep it as untimed as possible, because every bit of timing you add is a chance to get out of sync with the RTL.

---

C2

## The model's interface: 2 inputs, 3 outputs

Model interface · lecture + practice

```systemverilog
`uvm_analysis_imp_decl(_in_rx)          // one write_in_rx() and one write_in_tx() in the same class
`uvm_analysis_imp_decl(_in_tx)
class cfs_algn_model extends uvm_component implements uvm_ext_reset_handler;
  cfs_algn_env_config env_config;
  cfs_algn_reg_block  reg_block;
  uvm_analysis_imp_in_rx#(cfs_md_item_mon, cfs_algn_model) port_in_rx;   // from RX monitor
  uvm_analysis_imp_in_tx#(cfs_md_item_mon, cfs_algn_model) port_in_tx;   // from TX monitor
  uvm_analysis_port#(cfs_md_response) port_out_rx;    // expected RX response
  uvm_analysis_port#(cfs_md_item_mon) port_out_tx;    // expected TX item (data + offset)
  uvm_analysis_port#(bit)             port_out_irq;   // "expect one irq pulse"
endclass
// env connect_phase
md_rx_agent.monitor.output_port.connect(model.port_in_rx);
md_tx_agent.monitor.output_port.connect(model.port_in_tx);
```

Notes

- Expected outputs use the **simplest type that carries the information**: a 2-value enum for the RX response, a `bit` for the IRQ, and the monitor item for TX (its length and response fields are simply ignored).
- The practice checks the wiring with a `` `uvm_info `` in each write function before any logic exists. Build in small steps you can verify.
- Each monitor item arrives **twice**: at `begin_tr` (is\_active = 1) and at `end_tr`. Every consumer must choose which one it acts on.

**Q: "Why `uvm\_analysis\_imp\_decl?"**

An analysis imp calls a method named `write()` on its parent. With two inputs of the same type you'd need two `write()` methods, which SystemVerilog forbids. The macro declares a new imp class, `uvm_analysis_imp_in_rx`, that calls `write_in_rx()` instead. The alternative is `uvm_tlm_analysis_fifo`s with a run\_phase that calls `get()`, which changes the timing semantics.

**Q: "Analysis port vs imp vs export?"**

The **port** is the initiator; it calls `write()` and can broadcast to zero or more subscribers. The **imp** is the terminal, implemented by the component that owns the `write()`. An **export** forwards through hierarchy, for example an agent exposing its monitor's port. `write()` is a function, so subscribers must not block. That's why the model starts tasks with fork/join\_none.

---

C3

## Modeling illegal RX transfers

Model illegal RX accesses · lecture

```systemverilog
virtual function void write_in_rx(cfs_md_item_mon item_mon);
  if(item_mon.is_active()) begin                 // decide at the START of the transfer
    cfs_md_response exp_response = get_exp_response(item_mon);
    case(exp_response)
      CFS_MD_ERR  : begin inc_cnt_drop(exp_response); port_out_rx.write(exp_response); end
      CFS_MD_OKAY : push_to_rx_fifo_nb(item_mon); // response sent only after the FIFO accepts it
    endcase
  end
endfunction

protected virtual function void inc_cnt_drop(cfs_md_response response);
  uvm_reg_data_t max_value = ('h1 << reg_block.STATUS.CNT_DROP.get_n_bits()) - 1;   // 255
  if(reg_block.STATUS.CNT_DROP.get_mirrored_value() < max_value) begin         // saturate
    void'(reg_block.STATUS.CNT_DROP.predict(reg_block.STATUS.CNT_DROP.get_mirrored_value() + 1));
    if(reg_block.STATUS.CNT_DROP.get_mirrored_value() == max_value) set_max_drop();
  end
endfunction
```

Behaviour being modeled

- Illegal: size 0, (bytes + offset) % size ≠ 0, or offset + size > bytes (the rule added after the R8 bug). The RTL drops the transfer, answers ERR and increments CNT\_DROP.
- CNT\_DROP **saturates** at 255. The 254 → 255 step sets IRQ.MAX\_DROP. If IRQEN.MAX\_DROP is 1, an irq pulse is expected.
- `max_value` comes from `get_n_bits()`, not a hard-coded 255, so the model follows the register definition if it changes.
- This is the "proper" place for the `CNT_DROP.predict()` that R9's test temporarily hacked in.

**Connects to a real bug.** In this project's RTL, the MAX\_DROP source never reaches the `irq` output (found in the senior Aligner lab). The model above predicts the pulse, and the IRQ check in C10 is what flags the missing one. You need a test that drops 255 transfers with IRQEN.MAX\_DROP = 1, which is what the rx\_err exercise does.

**Q: "How do you model a saturating hardware counter in RAL?"**

Keep the field non-volatile and call `predict()` from the model on each event, with a guard at the maximum computed from `get_n_bits()`. Trigger side effects (like the MAX\_DROP flag) on the transition to max, not on every event at max, which matches the "becomes 255" wording in the spec.

**Q: "When should the model predict the RX response: at the start or the end of the transfer?"**

At the start, as soon as the inputs are known (it only depends on offset and size). But the OKAY prediction is only **sent** after the RX FIFO accepts the item, because a full FIFO delays the RTL's ready. The scoreboard compares at the end of the transfer. Predicting early and comparing late is a common, robust pattern.

---

C4

## Legal RX transfers and the RX FIFO

Model legal RX accesses · lecture + practice

| `uvm_tlm_fifo#(T)` API | Use in the model |
| --- | --- |
| `new(name, parent, size)` | Depth 8, like the RTL. It's a uvm\_component (via `uvm_tlm_fifo_base`). |
| `put(t)`: **task**, blocks while full | Models the RTL holding RX `ready` low while its FIFO is full. This is why the class was chosen. |
| `get(t)`: task, blocks while empty | The consumer waits for data with no polling. |
| `flush()` | Empties the FIFO in `handle_reset()`. |
| `size()` vs `used()` | `size()` is the **capacity** (8), not the fill level. Use `used()` (or RX\_LVL) for the level. |

```systemverilog
protected virtual task push_to_rx_fifo(cfs_md_item_mon item);
  rx_fifo.put(item);              // may block: back-pressure
  inc_rx_lvl();                   // RX_LVL++; == rx_fifo.size() → set_rx_fifo_full()
  port_out_rx.write(CFS_MD_OKAY); // only now: the RTL's ready came late too
endtask
local virtual function void push_to_rx_fifo_nb(cfs_md_item_mon item);
  if(process_push_to_rx_fifo != null) `uvm_fatal("ALGORITHM_ISSUE", "two instances")
  fork begin
    process_push_to_rx_fifo = process::self();
    push_to_rx_fifo(item);
    process_push_to_rx_fifo = null;
  end join_none
endfunction
```

The "\_nb + process pointer" pattern used throughout this chapter

- The **task** does the timed work. A **function** `xxx_nb()` starts it with fork/join\_none, because analysis `write()`s are functions.
- A **process pointer** lets `handle_reset()` kill the task mid-flight, and lets a null check catch a second, impossible instance (the MD protocol never overlaps transfers).
- `kill_process(ref process p)`: kill it if it's not null, then set it to null. `ref` is required so the caller's pointer is cleared.
- IRQ flags are **sticky**: they stay 1 after the condition goes away, until software writes 1 to clear (W1C, as in R3).
- Afterwards the lecturer made `rx_fifo` `protected`: internal state shouldn't be public.

**Q: "How do you model back-pressure in a transaction-level model?"**

Use a bounded blocking channel, for example `uvm_tlm_fifo` with the DUT's depth. The producer's `put()` blocks while it's full, so the "accepted" event (here, the OKAY response) happens only when space frees up, just like the RTL's ready. No cycle counting is needed in the model.

**Q: "Why can't you just call a task from write()?"**

`write()` is a function, and functions can't consume time or call blocking tasks. Wrap the call in `fork … join_none` inside a function. Keep a handle (`process::self()`) so reset can kill it and you can assert that there's only one instance.

---

C5

## The intermediate buffer and build\_buffer()

Model intermediate buffer · lecture + practice

```systemverilog
protected cfs_md_item_mon buffer[$];      // no blocking needed: a plain queue

protected virtual task build_buffer();
  cfs_algn_vif vif = env_config.get_vif();
  forever begin
    int unsigned ctrl_size = reg_block.CTRL.SIZE.get_mirrored_value();
    if((buffer.sum() with (item.data.size())) <= ctrl_size) begin   // not enough bytes yet
      cfs_md_item_mon rx_item;
      pop_from_rx_fifo(rx_item);    // get() + RX_LVL-- (== 0 → set_rx_fifo_empty())
      buffer.push_back(rx_item);
    end
    else @(posedge vif.clk);        // enough: wait a cycle, let align() consume
  end
endtask
```

Infrastructure added

- A new `cfs_algn_if` with just `clk` for now (it later gains `reset_n`, `irq` and four FIFO probes). Because it's an interface, its file is included **outside** the package.
- A types file holds `typedef virtual cfs_algn_if cfs_algn_vif;`. The testbench puts the vif in config\_db, the env gets it into `env_config`, and `start_of_simulation` checks that it's set.
- `build_buffer_nb()` is called at the end of `handle_reset()`: kill on reset, restart afterwards.
- `buffer.sum() with (item.data.size())` is the SystemVerilog array-reduction idiom for "bytes in the buffer".

**Q: "Why does a forever loop that never waits hang the simulator?"**

It never yields, so simulation time can't advance. Every path through a forever loop must block: here either `pop_from_rx_fifo` (which blocks in `get()` when empty) or `@(posedge clk)`. That's why the else branch exists.

**Q: "Why does the model need a clock at all?"**

The data path could be untimed, but polling loops need a time base, and later the IRQ prediction needs cycle-level alignment with the RTL (C11–C13). A minimal "env interface" carrying the clock (plus probes later) is the usual approach.

---

C6

## align() and split(): the core algorithm

Model align logic · lecture + practice

The candy packer from Level 2, as code. While the buffer holds at least SIZE bytes, build a TX item at OFFSET. Take whole buffer items while they fit. When one doesn't fit, **split** it, push both halves back to the **front** (second half first), and loop again.

```systemverilog
forever begin
  int unsigned ctrl_size = reg_block.CTRL.SIZE.get_mirrored_value();
  uvm_wait_for_nba_region();                    // let build_buffer() push first at this edge
  if(ctrl_size <= (buffer.sum() with (item.data.size()))) begin
    while(ctrl_size <= (buffer.sum() with (item.data.size()))) begin
      tx_item = create; tx_item.offset = CTRL.OFFSET;
      while(tx_item.data.size() != ctrl_size) begin
        buffer_item = buffer.pop_front();
        if(tx_item.data.size() + buffer_item.data.size() <= ctrl_size) begin
          tx_item.data += buffer_item.data;         // whole item fits
          if(tx_item.data.size() == ctrl_size) push_to_tx_fifo(tx_item);
        end else begin
          num_bytes_needed = ctrl_size - tx_item.data.size();
          split(num_bytes_needed, buffer_item, splitted_items);
          buffer.push_front(splitted_items[1]);     // remainder goes back first...
          buffer.push_front(splitted_items[0]);     // ...so the exact-fit half is popped next
          port_out_split_info.write(info);          // → coverage (C14)
        end
      end
    end
  end else @(posedge vif.clk);
end
```

split(num\_bytes, item, ref items[$])

- It's an algorithm error (fatal) if `num_bytes == 0` or `num_bytes ≥ item.data.size()`, since there'd be nothing to split.
- Half 0: same offset, first `num_bytes` bytes. Half 1: `offset + num_bytes`, the remaining bytes.
- Both halves copy prev\_item\_delay, length, response, and the begin/end times from the original.
- Check from the practice log: SIZE 1, OFFSET 1, one 4-byte RX item → four TX pushes FE, 60, B4, 3B, which match what the TX monitor later reports.

**Q: "What does uvm\_wait\_for\_nba\_region() do and why use it here?"**

It waits until the current time step's NBA region has passed (implemented with a nonblocking update and a wait), so the code resumes after same-time activity has settled. Here it orders two threads that both wake at the same clock edge: build\_buffer pushes first, and align then sees the updated buffer. Without it, the result depends on the scheduler's arbitrary thread order, a classic same-time race.

**Q: "Why push the split halves back in reverse order?"**

`push_front` prepends, so pushing half 1 and then half 0 leaves the buffer as [half0, half1, …]. The next `pop_front` returns half 0, which by construction fits exactly and completes the TX item. Byte order is preserved, which is the Aligner's main promise.

**Q: "What would you randomize to stress this algorithm?"**

Every legal (SIZE, OFFSET) setting crossed with RX size and offset sequences that force splits at every possible `num_bytes_needed`, reconfiguring CTRL while data is buffered, and back-to-back traffic with a slow TX side so both FIFOs fill. Then measure it with exactly the split coverage built in C14.

---

C7

## TX controller and uvm\_event: the model is complete

Model TX controller · lecture + practice

```systemverilog
protected uvm_event tx_complete;          // new("tx_complete") in the constructor; reset() in handle_reset()

protected virtual task tx_ctrl();
  cfs_md_item_mon item;
  forever begin
    pop_from_tx_fifo(item);                 // get() + TX_LVL-- (== 0 → set_tx_fifo_empty())
    port_out_tx.write(item);                // tell the scoreboard what to expect
    tx_complete.wait_trigger();             // until the RTL's transfer is acknowledged
  end
endtask

virtual function void write_in_tx(cfs_md_item_mon item_mon);
  if(!item_mon.is_active()) tx_complete.trigger();   // end of a TX transfer
endfunction
```

uvm\_event#(T)

#### A better event

A `uvm_object` wrapping an SV event: `trigger(data)`, `wait_trigger()`, `wait_ptrigger()`, `reset()`, optional **data** passed with the trigger, and **callbacks** on trigger.

milestone

#### The model is finished

Groups of functions: flag setters, level inc/dec, push/pop tasks, and the main logic (`build_buffer`, `split`, `align`, `tx_ctrl`), each started by a `_nb()` and killed on reset.

foreshadowing

#### "Problems with synchronization"

The data path already matches the RTL byte for byte. The lecturer hints that IRQ prediction won't, which C10–C13 cover.

**Q: "uvm\_event vs SystemVerilog event?"**

A uvm\_event is an object, so it can be passed around, stored in a pool (`uvm_event_pool`, shared by name), and reset. It can carry data with the trigger, supports callbacks, and offers both edge (`wait_trigger`) and persistent (`wait_ptrigger`, avoids the same-time race when the trigger fires just before the wait) styles. A plain `->`/`@` event can miss a trigger that happens in the same time step before the wait starts.

**Q: "Why wait for the TX transfer to complete before popping the next item?"**

The RTL's TX controller holds one item until the slave asserts ready, then pops the next. Mirroring that hand-off keeps the model's TX\_LVL, and therefore its TX empty/full flags, close to the RTL's. The data order alone wouldn't need it.

---

C8

## Scoreboard architecture and its ports

Scoreboard architecture · scoreboard interface lecture + practice

check 1

#### Match

When the DUT output arrives, pop the oldest expected entry and compare. Different means `DUT_ERROR`.

check 2

#### Not too late

Each expected entry starts a **watchdog**. If the DUT hasn't produced it within N clocks, the DUT is stuck (threshold 10, in env\_config).

check 3

#### Not too many

A bounded queue depth: RX ≤ 1 and TX ≤ 1 (MD never overlaps), IRQ ≤ 5 (the model runs ahead of the RTL).

```systemverilog
`uvm_analysis_imp_decl(_in_model_rx)   `uvm_analysis_imp_decl(_in_agent_rx)
`uvm_analysis_imp_decl(_in_model_tx)   `uvm_analysis_imp_decl(_in_agent_tx)
`uvm_analysis_imp_decl(_in_model_irq)
class cfs_algn_scoreboard extends uvm_component implements uvm_ext_reset_handler;
  cfs_algn_env_config env_config;      // → vif.irq: no agent needed for a single wire
  uvm_analysis_imp_in_model_rx #(cfs_md_response, cfs_algn_scoreboard) port_in_model_rx;
  uvm_analysis_imp_in_model_tx #(cfs_md_item_mon, cfs_algn_scoreboard) port_in_model_tx;
  uvm_analysis_imp_in_model_irq#(bit,             cfs_algn_scoreboard) port_in_model_irq;
  uvm_analysis_imp_in_agent_rx #(cfs_md_item_mon, cfs_algn_scoreboard) port_in_agent_rx;
  uvm_analysis_imp_in_agent_tx #(cfs_md_item_mon, cfs_algn_scoreboard) port_in_agent_tx;
endclass
```

Wiring notes

- The env connects five ports (3 from the model, 2 from the agents) plus the env\_config pointer.
- The lecturer warns about copy-paste: when duplicating a port line, update the type, the macro suffix **and** the name.
- The scoreboard implements the reset handler: on reset it clears every queue and kills every watchdog.

**Q: "Design a scoreboard for a DUT with latency."**

Store expected transactions in an ordered queue (or per-ID associative arrays if the DUT can reorder). On each actual: pop and compare, with an error if nothing was expected. Add a per-entry timeout so a stuck DUT fails instead of hanging, bound the queue depth to catch runaway prediction, check that every queue is empty in `check_phase` (end-of-test leftovers), and clear everything on reset.

**Q: "In-order vs out-of-order scoreboards?"**

In-order: a FIFO compare, as here, valid because the Aligner preserves order. Out-of-order: key expected items by ID or address in an associative array and match on arrival. You still need timeouts, and usually a way to detect duplicates. Pick based on the spec's ordering guarantees, never on what the RTL happens to do.

---

C9

## RX response and TX item checks

RX response check · lecture + practice · TX item check · lecture

```systemverilog
virtual function void write_in_model_rx(cfs_md_response response);
  if(exp_rx_responses.size() >= 1) `uvm_error("ALGORITHM_ISSUE", "already 1 expected entry")   // check 3
  exp_rx_responses.push_back(response);
  exp_rx_response_watchdog_nb(response);                       // check 2: starts a timer
endfunction

virtual function void write_in_agent_rx(cfs_md_item_mon item_mon);
  if(!item_mon.is_active()) begin                              // end of the transfer
    cfs_md_response exp_response = exp_rx_responses.pop_front();
    process_exp_rx_response_watchdog[0].kill();                // stop the timer
    void'(process_exp_rx_response_watchdog.pop_front());
    if(item_mon.response != exp_response) `uvm_error("DUT_ERROR", "Mismatch ...")   // check 1
  end
endfunction

virtual function void kill_processes_from_queue(ref process processes[$]);
  while(processes.size() > 0) begin processes[0].kill(); void'(processes.pop_front()); end
endfunction
```

Details

- The watchdog task: `repeat(threshold) @(posedge vif.clk);` then `DUT_ERROR` "expected from time %t, not received after N clocks". It's killed when the matching actual arrives.
- A **queue of process pointers** (one per pending entry), not a single pointer. The `_nb()` wrapper fatals if the queue is unexpectedly empty when a watchdog ends.
- The TX check is the same structure with `exp_tx_items`. It compares `data` (the whole queue, so the size too) and `offset`.
- Forced-failure test: make the model send ERR instead of OKAY and confirm "expected ERR, received OKAY", then revert.
- `exp_rx_response_threshold`, `exp_tx_item_threshold` and `exp_irq_threshold` live in env\_config (default 10, with getters and setters).

**Bug hunt in your scoreboard.** `write_in_agent_rx` and `write_in_agent_tx` never check that something is expected. If the RTL produces a TX transfer the model didn't predict, `pop_front()` on the empty queue returns null and `process_…[0].kill()` dereferences a null handle. You get a simulator crash instead of a clear "Unexpected TX item" DUT\_ERROR. Add `` if(exp_tx_items.size() == 0) begin `uvm_error("DUT_ERROR", "Unexpected TX item …"); return; end ``. The IRQ check (C10) already does this correctly. Also worth adding: a `check_phase` that reports leftover expected entries at the end of the test.

**Q: "How do you detect a DUT that just stops responding?"**

Use a timeout per expected item: start a watchdog thread when the prediction is queued, kill it when the actual is matched, and error if it expires. Make the threshold configurable, and size it from the spec's worst-case latency plus margin. Also have an end-of-test check for anything still pending, and a global timeout (`set_timeout`) as a last resort.

**Q: "Why does write\_in\_agent\_rx only act when !is\_active()?"**

The monitor publishes each transfer twice, at start and at end. The response is only valid at the end, so acting on the start publication would compare a not-yet-sampled response and also pop the queue twice.

---

C10

## The IRQ check, and debugging "7 expected, 6 received"

IRQ check · lecture + practice

```systemverilog
protected virtual task rcv_irq();             // no agent: watch the wire directly
  cfs_algn_vif vif = env_config.get_vif();
  forever begin
    @(posedge vif.clk iff(vif.irq & vif.reset_n));
    if(exp_irqs.size() == 0) `uvm_error("DUT_ERROR", "Unexpected IRQ detected")
    else begin
      void'(exp_irqs.pop_front());
      process_exp_irq_watchdog[0].kill(); void'(process_exp_irq_watchdog.pop_front());
    end
  end
endtask   // write_in_model_irq allows up to 5 queued expectations
```

Setup the test needed

- `cfs_algn_if` gains `reset_n` and `irq`, connected in the testbench.
- All IRQs are **disabled after reset** (datasheet, IRQEN). The test must write `IRQEN` = all 1s before traffic, or the check has nothing to check.

| Debug step | What the lecturer did |
| --- | --- |
| 1. Freeze the failure | The run used `-svseed random`. Find the seed in the log and pin it so the failure reproduces at the same time (825 ns). |
| 2. Count | Waves show 6 RTL irq pulses. Searching the log for "expected IRQ" finds 7. |
| 3. Don't match by time | Model and RTL fire at different times (256 vs a few clocks later), so close pulses can't be paired one-to-one by time. |
| 4. Count by cause | Model: 4 × RX-empty + 3 × TX-empty. RTL's internal `edge_*` signals (in `regs`): 4 × RX-empty + **2** × TX-empty. |
| 5. Zoom in | Add TX\_LVL and the TX FIFO's push/pop valid & ready. At one point the RTL pushes and pops in the same cycle, so the level stays at 1 and there's no 1→0 edge. |
| 6. Find the model's version | In the log at 645 ns, the model does push+pop at the same time, but its level goes 0→1→0, which fires TX-empty. |
| 7. Decide who's right | It's debatable, so it's the concept engineer's call. The decision: the flag fires only when the **level** goes 1→0 (and 7→8 for full). The testbench is wrong. |

**Q: "Walk me through how you debug a scoreboard mismatch."**

Reproduce it with a pinned seed. Quantify it (how many expected vs actual, and which ones). If timing can't pair the events, classify them by cause, using design-internal signals where available (asking the designer which signals is normal and expected). Narrow down to the first divergence, then decide against the **spec** who's wrong. If the spec is ambiguous, the architect or concept owner decides. Fix the side that's wrong, and add coverage for the corner you found.

**Q: "Why does the IRQ queue allow 5 entries but RX/TX only 1?"**

RX and TX expectations are tied to MD transfers, which never overlap, so at most one is pending. IRQ predictions come from a transaction-level model that runs ahead of the RTL's pipeline, so several can legitimately be in flight. The bound still catches runaway prediction.

---

C11

## Sync fix #1: no flag on same-time push and pop

Model synchronization: FIFO flags · lecture + practice

Push and pop are independent threads, and the simulator orders same-time threads arbitrarily. The fix: **delay** each flag-setter by 2 "ticks" in a killable process, and have the opposite operation **kill** it 1 tick later. Push kills a pending "empty"; pop kills a pending "full".

```systemverilog
protected virtual function void set_rx_fifo_empty();
  fork begin
    process_set_rx_fifo_empty = process::self();
    repeat(2) uvm_wait_for_nba_region();     // 2 ticks: room for a same-time push to cancel us
    void'(reg_block.IRQ.RX_FIFO_EMPTY.predict(1));
    if(reg_block.IRQEN.RX_FIFO_EMPTY.get_mirrored_value() == 1) exp_irq = 1;
    process_set_rx_fifo_empty = null;
  end join_none
endfunction

protected virtual function void kill_set_rx_fifo_empty();   // called right after rx_fifo.put()
  fork begin
    uvm_wait_for_nba_region();               // 1 tick: the setter may not have started yet
    kill_process(process_set_rx_fifo_empty);
  end join_none
endfunction
```

| Same-time order | Why it still works |
| --- | --- |
| pop first, then push | The setter is waiting (tick 1 of 2) when the killer wakes at tick 1, so it's killed before setting the flag. |
| push first, then pop | A kill *right now* would find a null pointer (the setter doesn't exist yet). Waiting 1 tick lets the setter start, and then it's killed. |

Rules and the result

- The only real requirement: setter delay > killer delay. With different push and pop clocks, use small real delays (e.g. #1ps) that are still less than a clock period.
- Applied to all four flags. RX/TX × empty/full.
- Rerun with the same seed: it now fails **earlier**, "Unexpected IRQ". At 256 ns the model pushes and pops RX in the same time step, but the RTL pops one clock after the push (it can't pop data that isn't stored yet). So the RTL's level goes 1→0 and it raises RX-empty. The model is "too fast": it even pushes 4 items into the TX FIFO and pops 1 at 265 ns, which no real FIFO can do. That's issue #2.

**Q: "How do you resolve a race between two threads at the same simulation time?"**

Don't rely on scheduler order. Options: impose an explicit order with delta delays (`uvm_wait_for_nba_region`, `#0` is weaker), merge the decision into one thread that sees both events, use a semaphore or mailbox handshake, or (as here) a deferred, cancellable action. Then verify both orderings by reasoning, as the lecturer does, not just by one passing seed.

**Q: "Why did the fix make the test fail earlier?"**

It removed one symptom and exposed a deeper cause. The model and RTL disagree about *when* FIFO operations happen, not just about how flags are computed. Fixing symptom-level discrepancies often reveals the structural one. That's progress, not regression.

---

C12

## Sync fix #2: align push/pop timing by probing, as a hint

Model synchronization: push & pop · lecture + practice

Example from the lecture, with SIZE 1 and three 4-byte RX transfers. After 4 clocks the **model's** TX FIFO is full and its RX FIFO empty, while the **RTL** has 1 TX entry and 2 RX entries. The data out will still match, but four of the five IRQ sources depend on FIFO levels, so the IRQs won't.

option A · avoid

#### Add delays to the model

"A synchronization nightmare": real latencies depend on internal state, so you end up with special-case waits everywhere.

option B · never

#### Copy the RTL

Then you're no longer verifying, you're re-running the same bugs.

option C · chosen

#### Probe, as a hint

Wait for the RTL's internal push/pop, but with a time limit, so the model never *depends* on the DUT.

```systemverilog
// testbench: rx_fifo_push = dut.core.rx_fifo.push_valid & dut.core.rx_fifo.push_ready  (×4 probes)
protected virtual task sync_push_to_rx_fifo();
  cfs_algn_vif vif = env_config.get_vif();
  fork begin                                    // wrapper so 'disable fork' only hits these two
    fork
      @(posedge vif.clk iff(vif.rx_fifo_push));                      // RTL pushed: go
      begin
        repeat(10) @(posedge vif.clk iff(RX_LVL < rx_fifo.size()));  // 10 clocks where a push was possible
        `uvm_warning("DUT_WARNING", "RX FIFO push did NOT synchronize with RTL")
      end
    join_any
    disable fork;
  end join
endtask   // called at the start of push_to_rx_fifo(); same pattern for the other 3
```

| Sync task | Count a clock only if… | Limit |
| --- | --- | --- |
| push RX | RX FIFO not full | 10 |
| pop RX | RX FIFO not empty **and** TX FIFO not full (the popped data must have somewhere to go) | 10 |
| push TX | TX FIFO not full | 10 |
| pop TX | TX FIFO not empty | **200**: the pop waits for the randomized TX slave's ready |

Result

- The same seed runs much longer. The new failure: at 3665 ns the RTL raises RX-empty **and** TX-empty in the same cycle and outputs **one** pulse (the irq is an OR of the sources). The model queued **two** expectations. That's issue #3.
- The lecturer suggests the timeout branch could raise an error instead of a warning to be stricter, since reaching it probably means an RTL problem.

**Q: "Is it OK for a testbench to probe DUT internals?"**

For **synchronization hints**, yes, carefully: use the internal event to align timing but keep an independent fallback (a timeout plus a warning or error), so a broken or missing RTL event can't silently drive the prediction. Never use internal state as the **expected value**, since that turns the check into "RTL equals RTL". Probes also tie the testbench to internal names, so keep them in one place (the testbench module and interface).

**Q: "Why the outer fork…join around fork…join\_any + disable fork?"**

`disable fork` kills **all** child processes of the current thread, including unrelated ones started earlier. Wrapping it in its own fork…join creates a fresh parent, so `disable fork` only kills the two racing branches. This is a standard idiom.

**Q: "Why are the data checks unaffected by this whole issue?"**

Data order and content don't depend on timing. Only level-derived outputs (FIFO flags, and therefore IRQs) do. Good modeling separates untimed functional prediction, which is robust, from timing-sensitive prediction, which needs synchronization or directed tests.

---

C13

## Sync fix #3: overlapping IRQs become one pulse

Model synchronization: overlapping IRQs · lecture + practice

```systemverilog
protected bit exp_irq;                       // every flag setter now just does: exp_irq = 1;

protected virtual task send_exp_irq();
  cfs_algn_vif vif = env_config.get_vif();
  forever begin
    @(negedge vif.clk);                      // setters all act around posedge; sample half a cycle later
    if(exp_irq == 1) begin
      port_out_irq.write(exp_irq);           // ONE expectation per cycle, like the RTL's OR gate
      exp_irq = 0;
    end
  end
endtask   // killed and restarted in handle_reset(); exp_irq cleared there too
```

Why it works

- Five parallel threads (MAX\_DROP from write\_in\_rx, plus the four FIFO flag processes) used to each call `port_out_irq.write()`.
- Now they all set one shared bit, which **is** an OR. A single sampler sends at most one expectation per clock.
- Strictly this was a **modeling** gap (the spec describes the OR), which showed up as a synchronization symptom.
- Result: the same seed passes, and several random seeds pass. The lecturer's next step: run about 1000 seeds in a regression, because a few passing seeds prove little.

> Interactive: Try it · predict the irq pulses for one clock. Open the HTML page to use it.

**Q: "Your DUT ORs several interrupt sources onto one pin. How do you check it?"**

Model each source's flag separately (in RAL, IRQ status and enable) for register checks. For the pin, combine all enabled sources that become active in the same cycle into one expected assertion: an OR with a sampling point after all sources have settled (here the negedge). Better still, also check the per-source status register after each pulse, so you know *which* source fired, not just that the pin went high.

**Q: "The lecturer says the test passes on a few seeds. Is it done?"**

No. Run a regression of hundreds to thousands of seeds, triage every failure, and close coverage. Some IRQ timing corners only appear rarely. The conclusions also suggest a **directed IRQ test** as a complement to cycle-accurate prediction in random tests.

---

C14

## DUT functional coverage and the verification plan

DUT functional coverage · lecture + practice

| vplan branch | Example leaf for the Aligner |
| --- | --- |
| Registers → each register → each field | CTRL.SIZE: written value × current value |
| Features | RX FIFO: level when push and pop happen in the same cycle (the C10 corner!) · Align: **split** cross |
| Interfaces | The reusable agent vplans: APB ×1, MD ×2, the **same** MD vplan bound to the RX and TX instances |

```systemverilog
covergroup cover_split with function sample(cfs_algn_split_info info);
  option.per_instance = 1;
  ctrl_offset : coverpoint info.ctrl_offset { bins values[] = {[0:3]}; }
  ctrl_size   : coverpoint info.ctrl_size   { bins values[] = {[1:4]}; }
  md_offset   : coverpoint info.md_offset   { bins values[] = {[0:3]}; }
  md_size     : coverpoint info.md_size     { bins values[] = {[1:4]}; }
  num_bytes_needed : coverpoint info.num_bytes_needed { bins values[] = {[1:3]}; }
  all : cross ctrl_offset, ctrl_size, md_offset, md_size, num_bytes_needed {
    ignore_bins ignore_ctrl = /* the 9 illegal (OFFSET, SIZE) pairs */;
    //TODO: other combinations should be ignored from this cross
  }
endgroup
```

Plumbing

- `cfs_algn_split_info` (uvm\_object, 5 fields) is filled in `align()` after each split and sent through `port_out_split_info`.
- `cfs_algn_coverage` (component + reset handler) has an imp whose write calls `cover_split.sample(info)`.
- `env_config.has_coverage` decides whether the env creates it. When it doesn't, check for null before calling its `handle_reset()`.
- A `coverage2string()` printout in report\_phase is **for EDA Playground only**. Real projects use the tool's coverage GUI.

**Why the cross shows 1.39%: reachability, worked out.** After the ignore bins, 7 legal CTRL settings × 4 × 4 × 3 = **336** bins remain. But only legal RX items (and their split remainders) ever reach the buffer, and a split needs `md_size > num_bytes_needed`. Enumerating every reachable combination for a 32-bit Aligner gives just **35** bins, about **10%**. (The senior lab's per-cell upper bound of 52 used only the necessary conditions.) Until the other ~300 impossible bins are excluded, the percentage measures your cross definition, not your stimulus. This is exactly the "TODO" the lecturer left.

**Q: "How do you build a verification plan?"**

Go through the spec statement by statement and turn each into a feature with checks and coverage goals. Organize them as a tree (registers / features / interfaces), bind each leaf to an implementation (a covergroup, assertion or test), reuse sub-plans for agents, and review it with design and architecture **before** coding. Track closure against it. The format varies (XML, mind map, vManager vPlan), but the idea is the same.

**Q: "Your cross is at 10% after thousands of seeds. What do you do?"**

First check reachability: list which bins are illegal or impossible (by analysis or a small script) and exclude them with ignore/illegal bins, or restructure the cross with `binsof` filters. Then look at the remaining holes and add constraints or directed sequences for them. Never "close" coverage by waiving bins you haven't proven unreachable.

**Q: "Why is the split coverage sampled from the model, not from a monitor?"**

The split is an internal decision. No interface shows "num\_bytes\_needed". The model computes it while predicting, so it's the natural sampling point. The risk is that model coverage reflects what the **model** did. That's acceptable here because the scoreboard independently confirms the model matches the RTL's output.

---

C15

## Virtual sequencer and the "slow pace" virtual sequence

Virtual sequencer · lecture + practice

```systemverilog
class cfs_algn_virtual_sequencer extends uvm_sequencer;   // no item type: drives nothing itself
  uvm_sequencer_base           apb_sequencer;    // nothing special needed → base type
  cfs_md_sequencer_base_master md_rx_sequencer;
  cfs_md_sequencer_base_slave  md_tx_sequencer;  // typed: need its pending_items FIFO
  cfs_algn_model               model;            // for env_config + register mirror
endclass
// base vseq: `uvm_declare_p_sequencer(cfs_algn_virtual_sequencer)

virtual task body();                              // cfs_algn_virtual_sequence_slow_pace
  fork
    begin   // RX: one legal transfer, at least CTRL.SIZE bytes, so it fully leaves the buffer
      `uvm_do_on_with(rx_sequence, p_sequencer.md_rx_sequencer, {
        ((algn_data_width / 8) + item.offset) % item.data.size() == 0;
        (item.data.size() + item.offset) <= (algn_data_width / 8);
        item.data.size() >= ctrl_size; })
    end
    begin   // TX: answer every resulting transfer, ERR only on the last one
      do begin
        p_sequencer.md_tx_sequencer.pending_items.get(item_mon);     // wait for the TX start
        num_tx_items = rx_sequence.item.data.size() / CTRL.SIZE;
        `uvm_do_on_with(tx_sequence, p_sequencer.md_tx_sequencer, {
          num_tx_items == 1                                    -> item.response == CFS_MD_OKAY;
          num_tx_items > 1 && tx_item_idx <  num_tx_items - 1 -> item.response == CFS_MD_OKAY;
          num_tx_items > 1 && tx_item_idx == num_tx_items - 1 -> item.response == CFS_MD_ERR; })
        tx_item_idx++;
      end while(tx_item_idx < num_tx_items);
    end
  join
endtask
```

Notes

- Definition: "a sequencer that is not attached to a driver and does not process items itself". A virtual sequence is any sequence started on it: `seq.start(env.virtual_sequencer)`.
- The env connects the handles in connect\_phase. The MD sequencers need a `$cast` because the agent declares its sequencer with the uvm\_ext base type.
- `` `uvm_do_on(seq, sqr) `` and `` `uvm_do_on_with(seq, sqr, {constraints}) `` run a sub-sequence on a specific sequencer.
- Practice check with 100 iterations: RX\_LVL never goes above 1 ("slow pace"). SIZE 1 + a 4-byte RX gives 4 TX transfers, with ERR only on the 4th.

**Hidden assumption:** `num_tx_items = rx_size / SIZE` is only correct because this sequence guarantees the intermediate buffer is **empty** when the RX transfer starts (slow pace, and rx\_size ≥ SIZE with legal sizes 1/2/4 always dividing evenly). In a back-to-back scenario, leftover buffered bytes change the count. That's why it's a dedicated, reusable scenario and not a general responder.

**Q: "Virtual sequencer vs just passing sequencer handles to the sequence?"**

Both work. The virtual sequencer centralizes the handles (and shared helpers like the model) in one component that the env wires once, so every virtual sequence finds them through `p_sequencer`, and system-level environments can re-point them. Passing handles directly (a "virtual sequence without a virtual sequencer") avoids p\_sequencer casts but spreads the wiring into every test.

**Q: "What is p\_sequencer and how is it declared?"**

`m_sequencer` is the generic `uvm_sequencer_base` the sequence runs on. `` `uvm_declare_p_sequencer(T) `` adds a typed handle `p_sequencer` and a `$cast` from m\_sequencer (fatal if the type is wrong), giving typed access to the sub-sequencer handles.

**Q: "Why does the TX branch wait on pending\_items before choosing the response?"**

The MD slave is reactive. It must not answer until the master (the Aligner) has started a transfer, which its monitor reports through the sequencer's `pending_items` FIFO (see the MD chapter). Only then is it valid to compute how many TX items this RX produced and which one is last.

---

C16

## Wrap-up: the environment is complete

Conclusions video

learned

#### Model a DUT

A spec-shaped, mostly untimed model with TLM FIFOs, a buffer, align and split, and register prediction.

learned

#### Check outputs

Queues, watchdogs and depth limits for three output types, one of them a bare wire.

learned

#### Fix sync issues

Cancellable delayed actions, probing as a hint, and an OR-and-sample. Three bugs, all in the testbench.

learned

#### Coverage and virtual sequences

Coverage is slow work: plan for it. Virtual sequences package reusable multi-agent scenarios.

Other sync techniques the lecturer mentions

- **Isolate** the troublesome sub-block (e.g. an internal arbiter) and verify it separately.
- **Directed tests** for timing-sensitive features. IRQ timing could have been verified in dedicated tests instead of cycle-accurate prediction in random tests.
- You'll collect more techniques over time. Choose per DUT.

Interview line

"I built a transaction-level reference model shaped like the spec's block diagram: TLM FIFOs for back-pressure, an intermediate buffer, align and split logic, and register prediction for levels and sticky IRQ flags. The scoreboard checks RX responses, TX transfers and the IRQ wire with in-order queues, per-entry watchdogs and depth limits. The data checks matched from day one, but IRQ prediction exposed three testbench synchronization problems. I fixed same-cycle push/pop with cancellable deferred flag updates, aligned FIFO timing using RTL handshake probes with a timeout fallback, and modeled the IRQ OR with a single sampler. Then I moved to regressions and split-coverage closure."

---

