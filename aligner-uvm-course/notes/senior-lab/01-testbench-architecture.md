# Testbench architecture

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 1 · the big picture

## Testbench architecture

Every component in your `cfs_algn_env`, what it owns, and how one transaction travels through it. Click any box on the map. The wires are drawn from your actual `connect_phase`.

analysis portsconfig\_db pathsbuild ↓ connect ↑reset-aware envparameter firewall

### 1.1Architecture map

*[Diagram: UVM testbench architecture for the aligner. Open the HTML page to see it.]*

analysis (write) path
register prediction
handles / pins

### 1.2Life of one RX transfer

Trace this out loud in an interview. It shows you understand data flow, not just class names.

1. **Test → virtual sequence**The test creates `cfs_algn_virtual_sequence_rx` via the factory, randomizes it, starts it on `env.virtual_sequencer`.
2. **Virtual → agent sequence**It starts `cfs_md_sequence_simple_master` on `p_sequencer.md_rx_sequencer`; `` `uvm_send(item) `` hands the item over.
3. **Driver → pins**The master driver pulls the item, waits `pre_drive_delay`, drives valid/data/offset/size, holds them until `ready`.
4. **DUT decides**`cfs_rx_ctrl` checks legality: legal goes into the RX FIFO, illegal raises `md_rx_err` and bumps CNT\_DROP.
5. **Monitor observes**The RX monitor rebuilds a `cfs_md_item_mon` including the response and writes it to `output_port`, a broadcast to every subscriber.
6. **Model predicts**`model.write_in_rx()` computes the expected response, then splits/aligns the bytes using the mirrored CTRL into expected TX items.
7. **Scoreboard compares**RX response: model vs agent. Later, every TX item the DUT sends is compared, in order, against the model's queue.
8. **Coverage samples**The model publishes `split_info`, i.e. how this RX item was cut, and coverage samples it.

### 1.3Phases, and what this env does in each

buildtop-down ↓

test makes env; env makes config, agents, model, predictor, scoreboard, coverage, vseqr. Sets md\_tx config *before* creating the agent.

connectbottom-up ↑

Gets algn vif, wires monitors → model/scoreboard, predictor ← APB mon, map ↔ APB sqr, fills vseqr handles.

end\_of\_elabbottom-up ↑

Hierarchy is frozen. Best place for `print_topology()` and sanity checks.

runparallel · time

Test raises the objection and runs sequences. Env runs `forever`: wait reset → `handle_reset()` → wait release.

extract / check / reportbottom-up ↑

Scoreboard should flag leftover expected items here, so a silent DUT can't pass.

### 1.4Code walkthrough: the env's `connect_phase`

```systemverilog
//Configure the predictor with an address map and an adapter
predictor.map     = model.reg_block.default_map;
predictor.adapter = adapter;

//Connect the APB monitor with the predictor
apb_agent.monitor.output_port.connect(predictor.bus_in);

//Connect the APB sequencer to the address map
model.reg_block.default_map.set_sequencer(apb_agent.sequencer, adapter);

predictor.env_config = env_config;
model.env_config     = env_config;

//Pass the information from the MD agents to the model
md_rx_agent.monitor.output_port.connect(model.port_in_rx);
md_tx_agent.monitor.output_port.connect(model.port_in_tx);

model.port_out_rx.connect(scoreboard.port_in_model_rx);
model.port_out_tx.connect(scoreboard.port_in_model_tx);
md_rx_agent.monitor.output_port.connect(scoreboard.port_in_agent_rx);
md_tx_agent.monitor.output_port.connect(scoreboard.port_in_agent_tx);

virtual_sequencer.md_rx_sequencer =
    cfs_md_sequencer_base_master'(md_rx_agent.sequencer);
```

1. **Explicit prediction.** The mirror is updated from what the APB *monitor* saw, not from what the register API asked for. That way it also tracks accesses you didn't start through RAL.
2. **Same adapter both ways.** `reg2bus` for the sequencer path, `bus2reg` for the predictor. One bug in the adapter breaks both, and that's a common interview trap.
3. **Config by handle.** `env_config` is assigned directly, not through config\_db. It's faster and type-safe, but it couples parent and child. Know both ways.
4. **One port, many subscribers.** The RX monitor's analysis port fans out to the model and the scoreboard. Analysis `write()` is a function, so subscribers must not consume time or block.
5. **Why `_imp_decl`?** The scoreboard has five inputs, so it needs five distinct `write_*` methods. `` `uvm_analysis_imp_decl(_in_agent_rx) `` generates them.
6. **Parameter firewall.** The agent is `#(32)`, but the vseqr stores the unparameterized base. Sequences then compile once, independent of bus width.

### 1.5Hidden concepts in this architecture

config\_db paths are strings

`run_test("")` always names the test `uvm_test_top`, which is why `testbench.sv` hard-codes `"uvm_test_top.env.apb_agent"`. A typo isn't a compile error. You only find it at the `get()`, which is why every agent should `` `uvm_fatal("NO_VIF", …) `` on a failed get.

Monitors feed checkers, not drivers

Expected values come from what the monitor *observed*, never from what the sequence *intended*. If the driver had a bug, intent-based checking would hide it. That's also why the model works in a passive env at SoC level.

Model ≠ scoreboard

The model predicts and the scoreboard compares. Keeping them separate lets you swap the model (C/DPI golden model, or a different config) without touching compare logic, and reuse the scoreboard for other DUTs.

Reset is a first-class event

The env's `run_phase` loops on reset and calls `handle_reset()` on model, scoreboard and coverage through an *interface class* (`uvm_ext_reset_handler`). That's SystemVerilog's way to give unrelated classes a shared API without multiple inheritance.

White-box probes trade portability

`algn_if.rx_fifo_push = dut.core.rx_fifo.push_valid & …` gives the model exact FIFO timing for IRQ checks, but ties the TB to RTL hierarchy. A renamed instance or a gate-level netlist breaks it. Know when to say "I'd use bind instead".

Errored writes must not update the mirror

The custom predictor checks the APB status first and only calls `super.write()` on `UVM_IS_OK`. A stock predictor would mirror an illegal CTRL write, and every later alignment prediction would be wrong.

Build order inside one build\_phase

The env sets the md\_tx agent's config *before* `create("md_tx_agent")`. Strictly it only has to be set before the agent's own `build_phase` runs, which happens later (top-down), but setting first reads correctly and survives refactors.

Optional components

Coverage is created only if `has_coverage`, and `connect_phase` null-checks it. Regressions turn coverage off for speed, and the env must still elaborate cleanly.

### 1.6Bug hunt: symptom → root cause

Each is a one-line change in your env. Guess the root cause first, then reveal. Better still, inject it on EDA Playground and read the log.

**Q: BUG 1 After a CTRL write of SIZE=2, scoreboard reports TX size mismatches: expected 1, got 2. Meanwhile the unmapped-access test, which should check APB errors, passes with no checks at all.**

**Root cause:** `apb_agent.monitor.output_port.connect(predictor.bus_in)` removed. The mirror never sees the write, so the model aligns with the reset value SIZE=1. Worse, the predictor's `write()` is never called, so every pslverr check it does silently disappears. A missing connection produces both a false failure and a false pass.

**Lesson:** when the model disagrees with the DUT, check the model's *inputs* (mirror, ports) before you blame the RTL.

**Q: BUG 2 Test fails at time 0 with NO\_VIF fatal from md\_rx\_agent, but the interface is clearly instantiated.**

**Root cause:** path string mismatch, e.g. `"uvm_test_top.env.md_rx_agnt"`, or the agent renamed in `create()`. Debug with `+UVM_CONFIG_DB_TRACE`, which prints every set/get and the path it matched or missed.

**Q: BUG 3 A test with a mid-sim reset ends with "N expected items never received" from the scoreboard.**

**Root cause:** `scoreboard.handle_reset()` not called, or it doesn't flush its expected queues. Items predicted before the reset are still waiting, and the DUT flushed its FIFOs. The model's `uvm_tlm_fifo`s need flushing too.

**Q: BUG 4 Your cfs\_algn\_test\_random\_rx\_err runs, but the log shows legal transfers with CFS\_MD\_OKAY.**

**Root cause candidates:** (a) the override is registered after the sequence was already created; (b) the sequence was built with `new()` instead of `type_id::create()`, which bypasses the factory; (c) the override names the wrong type, e.g. the parameterized vs base class. Check with `factory.print()` in `end_of_elaboration_phase`.

**Q: BUG 5 Regression is 100% green, coverage is 100%, yet a silicon bug: the DUT drops the last TX chunk when RX traffic stops.**

**Root cause:** the scoreboard compares what arrives but never checks for *missing* items at end of test. Add a `check_phase` that errors when the expected queue isn't empty, plus a drain time before dropping the objection. Also note the coverage model covered *inputs*, not "all predicted outputs were seen".

### 1.7Interview drill

**Q: Q1 "Draw your testbench and walk me through it."**

Draw the map above from memory in this order: interfaces and DUT, the three agents (say *why* each is master, slave or reactive), the model fed only from monitors, the scoreboard comparing model vs agents, the RAL plus explicit predictor, coverage, and the virtual sequencer. Then trace one RX transfer (1.2). Finish with reset handling. Most candidates forget reset entirely.

Cross-questions

- Why is the scoreboard not just inside the model?
- What changes if this env is reused at SoC level where the CPU drives APB? (APB agent goes passive, the predictor still works because it's monitor-driven, and the white-box `algn_if` probes need a bind or must go.)
- Where would a C++ golden model plug in? (Behind the model's `write_in_rx` via DPI-C. Ports and scoreboard stay unchanged.)

**Q: Q2 "Analysis port vs TLM FIFO vs uvm\_tlm\_analysis\_fifo: when do you use each here?"**

Analysis port: monitor broadcast, non-blocking, zero-time, any number of subscribers. `uvm_tlm_fifo`: inside the model, to buffer items and let a separate thread consume them with blocking `get()`, which is how the model mimics the DUT's FIFOs and back-pressure. `uvm_tlm_analysis_fifo`: when a subscriber must do time-consuming work per item, because it decouples `write()` from processing.

Cross-question

- What happens if a subscriber's `write()` calls a task? (Compile error, since `write` is a function. If someone forks inside it, ordering between items is lost.)

**Q: Q3 "How does your environment handle reset in the middle of traffic?"**

The env's `run_phase` runs forever: wait reset assert → `handle_reset()` on every stateful component (model flushes FIFOs and resets the mirror, scoreboard clears queues, coverage resets sampling state) → wait deassert. Agents do the same internally: drivers stop and release the bus, sequencers drop pending items, monitors abandon a half-captured item. Tests must also tolerate killed sequences.

Cross-questions

- Why not use UVM's reset/configure/main phases? (Runtime sub-phases are fragile with multiple resets and with VIP from different vendors. Most teams use an event-driven reset like this one.)
- How do you test it? (A test that asserts reset at random points with FIFOs non-empty, then checks registers equal reset values and traffic resumes cleanly.)

### 1.8Lab before Module 2

- Add `uvm_top.print_topology();` in the test's `end_of_elaboration_phase`, run, and match every line of the printout to a box on the map.
- Run with `+UVM_CONFIG_DB_TRACE` and find the four `vif` sets and their matching gets in `xrun.log`.
- Inject BUG 1 (comment out the predictor connect), run `cfs_algn_test_random`, and paste me the first `UVM_ERROR`. I'll walk the debug with you.
- Run your `cfs_algn_test_random_rx_err` and confirm every RX item reports `CFS_MD_ERR` and STATUS.CNT\_DROP saturates at 255.
- Draw the architecture on paper from memory in under 4 minutes, then explain it out loud. That's the interview format.
