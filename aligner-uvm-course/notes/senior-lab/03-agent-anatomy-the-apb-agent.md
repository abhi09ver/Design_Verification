# Agent anatomy: the APB agent

> From the *Aligner UVM Lab* (senior track). Diagrams and toys are in `pages/aligner-uvm-lab.html`.

Module 3 · the building block

## Agent anatomy: the APB agent

Your agents are built in two layers. `uvm_ext_pkg` holds protocol-agnostic bases that own reset, phasing and wiring. `cfs_apb_pkg` fills in only the protocol. Understanding that split is what makes you able to write VIP, not just use it.

base-class layeringfactory inst overridesdriver/monitor timingactive vs passiveprocess-based reset

### 3.1Two layers: generic engine, protocol plug-ins

*[Diagram: uvm\_ext base classes overridden by cfs\_apb classes. Open the HTML page to see it.]*

The base agent creates `uvm_ext_driver#(…)::type_id::create("driver")`. Because `cfs_apb_agent`'s constructor registered an *instance* override first, the factory hands back a `cfs_apb_driver`. The base never knows APB exists.

### 3.2Driver and monitor, side by side

```systemverilog
// cfs_apb_driver::drive_transaction
for(int i = 0; i < item.pre_drive_delay; i++)
  @(posedge vif.pclk);

vif.psel   <= 1;                    // SETUP phase
vif.pwrite <= bit'(item.dir);
vif.paddr  <= item.addr;
if(item.dir == CFS_APB_WRITE) vif.pwdata <= item.data;
@(posedge vif.pclk);
vif.penable <= 1;                   // ACCESS phase
@(posedge vif.pclk);
while(vif.pready !== 1)             // wait states
  @(posedge vif.pclk);
vif.psel <= 0; vif.penable <= 0;    // back to IDLE

// cfs_apb_monitor::collect_transaction
while(vif.psel !== 1) begin
  @(posedge vif.pclk); item.prev_item_delay++;
end
item.addr = vif.paddr;  item.dir = cfs_apb_dir'(vif.pwrite);
@(posedge vif.pclk); item.length++;
while(vif.pready !== 1) begin
  @(posedge vif.pclk); item.length++;
  if(item.length >= agent_config.get_stuck_threshold())
    `uvm_error("PROTOCOL_ERROR", "stuck")
end
item.response = cfs_apb_response'(vif.pslverr);
if(item.dir == CFS_APB_READ) item.data = vif.prdata;
output_port.write(item);
```

1. **Delays live in the item.** `pre_drive_delay`/`post_drive_delay` are random fields with `soft` ≤5 limits, so a test can stretch idle gaps with one inline constraint and no driver change.
2. **NBA everywhere.** Every pin write is `<=`. Mixing in one blocking write creates a race with the DUT's flops at the same edge.
3. **`!== 1`, not `!= 1`.** With X on pready, `!= 1` evaluates to X (treated false), so the loop exits on an unknown. `!==` keeps waiting, and the X assertion reports it.
4. **The monitor is independent of the driver.** It rebuilds the transfer from pins alone, which is why it works in passive mode and why it catches driver bugs.
5. **The monitor measures, it doesn't judge.** `length` and `prev_item_delay` are recorded for coverage. The only check it makes is the stuck threshold.
6. **Response data sampled at completion.** `prdata`/`pslverr` are only valid in the cycle pready is high. Sampling them earlier is the classic monitor bug (Bug 2).

### 3.3Hidden concepts

Agent config is a component

`uvm_ext_agent_config` extends `uvm_component`, not `uvm_object`. That gives it phases, so it can run the has\_checks watchdog and host `wait_reset_start/end`. The cost is that it appears in the topology and can't be created freely at run time.

Reset by killing processes

The driver saves `process::self()` and `kill()`s it in `handle_reset()`, then pins go to idle. The sequencer calls `stop_sequences()` and drops stray objections. Without both halves you get "get\_next\_item called twice without item\_done".

vif arrives in connect, used after end\_of\_elab

The base agent fetches the vif in `connect_phase` and `set_vif` fatals if it's set twice. Subclasses `$cast` the config in `end_of_elaboration_phase`. Each phase has one job, and errors surface before time 0.

Active vs passive is one if

Passive mode skips creating the driver and sequencer. Monitor and coverage always exist. At SoC level the same agent becomes a pure observer, and the predictor, model and scoreboard keep working.

Per-bit coverage wrappers

`uvm_ext_cover_index_wrapper` samples "bit i was 0" and "bit i was 1" for every address and data bit, i.e. toggle coverage at transaction level. It proves every address line and data lane moved.

The driver never returns a response

There's no `put_response`, so frontdoor RAL calls always return `UVM_IS_OK`. Bus errors are judged only by the predictor (Module 5). That's a design choice worth defending, or criticising, in an interview.

### 3.4Bug hunt

**Q: BUG 1 After a refactor, every test dies at time 0 with One must implement collect\_transaction() task .**

**Root cause:** the `set_inst_override` calls were moved from `new()` into `build_phase()` after `super.build_phase()`. The base already created the generic monitor. Overrides must be registered before the `create()` they're meant to affect.

**Q: BUG 2 Register reads with 0 wait states compare fine. Reads with wait states return stale data.**

**Root cause:** the monitor samples `prdata` on the first access cycle instead of after the `pready` loop. With 0 wait states the two cycles coincide, so only longer transfers expose it. That's why coverage on `length` matters: without the 3–10 bins, you'd never know whether the bug could be hit.

**Q: BUG 3 PENABLE\_AT\_SETUP\_PHASE\_A fires on every transfer after someone "optimised" the driver.**

**Root cause:** `psel` and `penable` are now driven in the same cycle, so the setup phase was skipped. The interface assertion caught a driver bug that no scoreboard would, because the DUT may still respond correctly.

### 3.5Interview drill

**Q: Q1 "Walk me through what's inside a UVM agent and what changes in passive mode."**

Config (vif, knobs), sequencer (arbitrates sequences), driver (item → pins), monitor (pins → item, broadcast on an analysis port), optional coverage. Passive keeps the monitor and coverage and drops the driver and sequencer. In this codebase the base agent does all of that generically, and protocol classes only implement `drive_transaction` and `collect_transaction`.

Cross-questions

- Why does the monitor write to an analysis port instead of calling the scoreboard? (Decoupling: zero or many subscribers, no knowledge of who listens.)
- `get_next_item/item_done` vs `get/put`? (The first holds the sequence until the item is done and suits pipelined-off protocols. `get`/`put` lets the driver return a response object later, as pipelined drivers do.)

**Q: Q2 "Type override vs instance override vs set\_type\_override\_by\_name : when do you use each?"**

Type override replaces every creation of that type, which is right for "all MD sequences become error sequences" (your rx\_err test). An instance override replaces it under one hierarchy path, which is what the agents use so the APB and MD agents can both extend the same generic base without colliding. By-name overrides avoid a compile-time dependency, but they don't work for parameterized classes, which register without a name.

### 3.6Lab

- Add `factory.print()` in `end_of_elaboration_phase` of the test and find the four APB instance overrides and the MD ones.
- Make the APB agent passive (`agent_config.set_active_passive(UVM_PASSIVE)` set before build) and see which component the register sequences now fail on.
- Inject BUG 2 in the monitor and run `cfs_algn_test_reg_access`. Note which component reports first: predictor, RAL check-on-read or scoreboard.
