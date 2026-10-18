# Lecture companion: UVM extension library

> Card-by-card notes for Cristian Slav's course. Diagrams and toys are in `pages/uvm-from-zero.html`.

Chapter · the UVM extension library (14 videos)

## uvm\_ext\_pkg: write agent plumbing once

After two agents, the same code appears twice: same fields, same reset handling, same build/connect logic. Only the protocol-specific parts differ. This chapter moves the common code into base classes in a package called `uvm_ext_pkg`. APB loses a third of its code, MD a quarter, and the next agent you write starts much further ahead.

*[Diagram: Three-layer package structure. Open the HTML page to see it.]*

Each layer extends the one below. Protocol packages only fill in what's genuinely different: items, `drive_transaction()`, `collect_transaction()`, covergroups, reset wait tasks.

---

X1

## Why build a base library?

The advanced technique for building agents · lecture

Put the APB and MD monitors side by side and nearly everything is identical: the reset-handler interface, the agent\_config pointer, the output port, the process handle, run\_phase, the reset logic. Only `collect_transaction()` differs. The same is true for every agent component. Copying that code from agent to agent is "boilerplate", and copy-paste caused real bugs in this course (forgetting to rename APB to MD).

moves to the base

#### Behaviour

Fields, getters/setters, phase methods, reset handling, process control, port wiring.

stays in each agent

#### Protocol specifics

Items, drive/collect tasks, covergroups, protocol knobs (stuck threshold), interface-specific reset waits.

can't be removed

#### Language boilerplate

Every class still needs its `` `uvm_*_utils `` macro and a constructor: SystemVerilog and UVM require it.

**Q: "Your team builds a new agent every project. How would you speed that up?"**

Two steps. (1) A base-class library: parameterized base agent, config, driver, monitor, sequencer and coverage that implement reset handling, active/passive, vif plumbing and wiring once. (2) A code generator: templates for common agent shapes (master-only, master+slave) and a script that stamps out the files with the right prefixes. Engineers then write only the protocol: items, drive and collect logic, coverage. Fewer lines, fewer copy-paste bugs, consistent structure.

**Q: "Isn't this just rebuilding UVM?"**

No. UVM provides generic roles (`uvm_driver` has no reset handling and no idea where the vif lives). The extension layer encodes your team's conventions on top: how reset works, how config is passed, how checks and coverage are switched. It's the layer every mature DV team ends up building.

---

X2

## uvm\_ext\_agent\_config #(VIRTUAL\_INTF)

What moves, what stays, and why · lecture + practice

| Item | Where | Reason |
| --- | --- | --- |
| vif, active\_passive, has\_coverage, has\_checks + getters/setters | ✅ base | Every agent has them. The vif **type** becomes the class parameter. |
| Field initialization in `new()` | ✅ base | Same defaults everywhere (active, coverage on, checks on). |
| `start_of_simulation_phase` "vif not set" fatal | ✅ base | Generic sanity check. |
| `wait_reset_start()` / `wait_reset_end()` | ⚠️ base, "abstract" | Every agent needs them, but the signal differs (preset\_n vs reset\_n). Base body = `` `uvm_fatal("implement me") ``. |
| `stuck_threshold` | ❌ stays | Only protocols that wait for a response need it. Not every future agent will. |
| has\_checks sync with the interface (run\_phase watcher) | ❌ stays | It touches `vif.has_checks`, and interfaces can't inherit from a common base, so the base can't know that field exists. |

Practice notes

- Fields move from `local` to **`protected`**: children need to reach them, outside code still can't.
- Child setters call `super.set_vif()` / `super.set_has_checks()` and then add their own extra step (pushing has\_checks into the interface).
- `cfs_apb_pkg` and `cfs_md_pkg` both `` `include `` and `import uvm_ext_pkg`.

**Q: "local vs protected vs public members?"**

`local`: only this class (not even subclasses). `protected`: this class and subclasses. Public: anyone. A base class meant to be extended uses protected state plus public getters/setters, so subclasses can work with fields while users go through validated accessors.

**Q: "How do you make a method 'abstract' in a UVM base class?"**

True `pure virtual` forces the class to be `virtual` (non-instantiable), which breaks factory creation of the base. The convention is a `virtual` method whose body is `` `uvm_fatal("…", "implement me") ``. If a subclass forgets to override, the simulation fails loudly at the first call.

**Q: "Why can't the has\_checks interface sync live in the base?"**

The base only knows the vif as a type parameter. It can't assume the interface has a `has_checks` signal, because SystemVerilog interfaces have no inheritance to guarantee a common member. Anything that touches specific interface members belongs in the protocol subclass.

---

X3

## uvm\_ext\_monitor #(VIRTUAL\_INTF, ITEM\_MON)

One abstract task, everything else shared · lecture + practice

```systemverilog
interface class uvm_ext_reset_handler;                 // moved here: nothing protocol-specific about it
  pure virtual function void handle_reset(uvm_phase phase);
endclass

class uvm_ext_monitor#(type VIRTUAL_INTF = int, type ITEM_MON = uvm_sequence_item)
      extends uvm_monitor implements uvm_ext_reset_handler;
  uvm_ext_agent_config#(VIRTUAL_INTF) agent_config;
  uvm_analysis_port#(ITEM_MON) output_port;          // typed by the parameter
  protected process process_collect_transactions;

  virtual task run_phase(uvm_phase phase);           // the restartable loop, shared
    forever begin
      fork begin wait_reset_end(); collect_transactions(); disable fork; end join
    end
  endtask

  protected virtual task collect_transaction();      // the ONLY thing a protocol writes
    `uvm_fatal("ALGORITHM_ISSUE", "One must implement collect_transaction() task")
  endtask
  ...                                                 // collect_transactions, wait_reset_end, handle_reset
endclass

class cfs_apb_monitor extends uvm_ext_monitor#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_MON(cfs_apb_item_mon));
  cfs_apb_agent_config agent_config;                 // typed handle, to reach APB-only knobs
  protected virtual task collect_transaction(); /* APB timing only */ endtask
endclass
```

Practice notes

- The child keeps its own, more specific `agent_config` handle (to reach `get_stuck_threshold()` etc.). For now it's filled by casting the parent's pointer in `end_of_elaboration_phase`, marked "temporary". In X7 the agent base creates the config, so the cast direction flips.
- The cost of parameterized bases: each specialization is a different class, so `` `uvm_component_param_utils `` is needed and casts must name the exact parameters.

**Q: "How do you write a generic monitor base class?"**

Parameterize by vif type and item type. The base owns the analysis port, the run loop (wait for reset release, collect forever), a process handle so reset can kill an in-flight collection, and a reset handler. Subclasses implement only `collect_transaction()`, one transfer's worth of protocol timing, and call `output_port.write()`.

**Q: "Template method pattern: where is it here?"**

The base defines the algorithm skeleton (`run_phase` → `collect_transactions` loop → `collect_transaction` step) and leaves one step to subclasses. The same pattern appears in the driver base (`drive_transaction`). Naming the pattern in an interview shows you understand the design, not just the code.

---

X4

## uvm\_ext\_coverage #(VIRTUAL\_INTF, ITEM\_MON)

Shared wrappers, shared port, protocol covergroups stay · lecture + practice

moved, unchanged

#### Bit-toggle wrappers

`uvm_ext_cover_index_wrapper_base` and `…wrapper#(MAX_VALUE_PLUS_1)`: identical in APB and MD apart from the prefix.

moved

#### Plumbing

`` `uvm_analysis_imp_decl(_item) ``, `port_item`, an empty `write_item()` (required by the port), an empty `handle_reset()` (required by the interface class).

moved

#### Reporting

The loop over wrapper children in `coverage2string()`, plus printing coverage in `report_phase` (from MD), so every agent gets it.

stays

#### Protocol content

`cover_item`/`cover_reset`, how many wrappers to create and what `write_item` samples. Children add `super.coverage2string()` to their own text.

**Moment from the practice video:** after moving `report_phase` into the base, the MD coverage printout *disappeared*, because the MD coverage didn't extend the base yet. Refactor one consumer at a time and compare logs before and after each step.

**Q: "Why does the base declare empty write\_item() and handle\_reset()?"**

The analysis imp in the base calls `write_item()` on its parent, so the method must exist on the base type. The interface class requires `handle_reset()`. Empty virtual bodies satisfy the compiler; subclasses override them with real sampling and reset coverage.

**Q: "How do you refactor shared code out of two working components safely?"**

Move one piece at a time, convert one consumer, and run a regression comparing logs and coverage before and after. Then convert the second consumer. Keep behaviour identical (pure refactor) and fix bugs in a separate change. In the video, missing output was the clue that one consumer hadn't been converted yet.

---

X5

## uvm\_ext\_sequencer #(ITEM\_DRV)

The smallest base class, and a class deleted · lecture + practice

```systemverilog
class uvm_ext_sequencer#(type ITEM_DRV = uvm_sequence_item)
      extends uvm_sequencer#(.REQ(ITEM_DRV)) implements uvm_ext_reset_handler;
  virtual function void handle_reset(uvm_phase phase);   // identical for every protocol
    int objections_count;
    stop_sequences();
    objections_count = uvm_test_done.get_objection_count(this);
    if(objections_count > 0)
      uvm_test_done.drop_objection(this, $sformatf("Dropping %0d objections at reset", objections_count), objections_count);
    start_phase_sequence(phase);
  endfunction
endclass
// APB: cfs_apb_sequencer had nothing else in it, so it was DELETED.
//      The APB agent now uses uvm_ext_sequencer#(cfs_apb_item_drv) directly.
// MD:  cfs_md_sequencer_base extends uvm_ext_sequencer and keeps only get_data_width().
```

**Q: "When should a class be deleted rather than kept as an empty subclass?"**

When it adds nothing (no fields, no overrides) and nobody needs its distinct type for overrides or casting. An empty subclass is still useful as a stable extension point for future customization, or to give sequences a protocol-named `p_sequencer` type. APB had no such need; MD did (`get_data_width`, the slave FIFO).

---

X6

## uvm\_ext\_driver #(VIRTUAL\_INTF, ITEM\_DRV)

Shared loop and reset, plus a real debugging story · lecture + practice

The base takes the process handle, `run_phase`, `drive_transactions()` (the get\_next\_item / item\_done loop), `wait_reset_end()` and the generic part of `handle_reset()` (kill the process). `drive_transaction()` becomes "abstract". The APB driver keeps `drive_transaction()` and a `handle_reset()` that calls `super` then drives APB idle values. The MD base driver shrinks to just its config cast; master and slave implement the rest.

**The bug in the practice video (a great interview story):** after switching the APB driver to the base class, an assertion fired at time 0: **PSEL is unknown**.  
**Why:** the driver now implemented `uvm_ext_reset_handler`, but the APB *agent's* `handle_reset()` only called children that could be cast to the old `cfs_apb_reset_handler`. The `$cast` failed silently, the driver was never reset, and PSEL was never initialized.  
**Fix:** delete the protocol-specific interface classes and use `uvm_ext_reset_handler` everywhere.  
**Lesson:** a failed `$cast` used as a filter fails silently, and a protocol assertion caught a testbench refactoring bug.

**Q: "Tell me about a testbench bug you introduced and how you found it."**

Use this one. While factoring drivers into a base class, the driver switched to a new reset-handler interface class, but the agent still dispatched reset only to children implementing the old one. The `$cast`-based dispatch silently skipped the driver, so the bus was never initialized. An X-check assertion on PSEL fired at time 0. Root cause in minutes; fix by unifying on one interface class. What I changed afterwards: refactor in small steps, regression after each, and a warning when a component that should be resettable isn't found.

**Q: "How should a subclass extend handle\_reset()?"**

Call `super.handle_reset(phase)` first, so the generic cleanup happens (kill the drive process, base state), then add protocol-specific actions (drive idle values). Skipping `super` leaves the old process running, and two drive loops fight over the bus after reset.

---

X7

## uvm\_ext\_agent #(VIF, ITEM\_MON, ITEM\_DRV), and config from above

Protocol agents shrink to a constructor · lecture + practice

```systemverilog
// the base builds everything by BASE type...
virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  if(!uvm_config_db#(uvm_ext_agent_config#(VIRTUAL_INTF))::get(this, "", "agent_config", agent_config))
    agent_config = uvm_ext_agent_config#(VIRTUAL_INTF)::type_id::create("agent_config", this);  // fallback
  monitor = uvm_ext_monitor#(VIRTUAL_INTF, ITEM_MON)::type_id::create("monitor", this);
  if(agent_config.get_has_coverage())
    coverage = uvm_ext_coverage#(VIRTUAL_INTF, ITEM_MON)::type_id::create("coverage", this);
  if(agent_config.get_active_passive() == UVM_ACTIVE) begin
    driver    = uvm_ext_driver#(VIRTUAL_INTF, ITEM_DRV)::type_id::create("driver", this);
    sequencer = uvm_ext_sequencer#(ITEM_DRV)::type_id::create("sequencer", this);
  end
endfunction

// ...and the protocol agent only says "use MY classes" (factory instance overrides)
class cfs_apb_agent extends uvm_ext_agent#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_MON(cfs_apb_item_mon), .ITEM_DRV(cfs_apb_item_drv));
  function new(string name = "", uvm_component parent);
    super.new(name, parent);
    uvm_ext_agent_config#(.VIRTUAL_INTF(cfs_apb_vif))::type_id::set_inst_override(cfs_apb_agent_config::get_type(), "agent_config", this);
    uvm_ext_monitor#(.VIRTUAL_INTF(cfs_apb_vif), .ITEM_MON(cfs_apb_item_mon))::type_id::set_inst_override(cfs_apb_monitor::get_type(), "monitor", this);
    // ...coverage and driver likewise; no sequencer override, APB uses the base sequencer
  endfunction
endclass

// env: configure the TX agent from ABOVE and hand the config down
cfs_md_agent_config_slave#(W) agent_config = cfs_md_agent_config_slave#(W)::type_id::create("agent_config", this);
agent_config.set_stuck_threshold(100);
uvm_config_db#(uvm_ext_agent_config#(.VIRTUAL_INTF(virtual cfs_md_if#(W))))::set(this, "md_tx_agent", "agent_config", agent_config);
md_tx_agent = cfs_md_agent_slave#(W)::type_id::create("md_tx_agent", this);
```

Things to notice

- **The cast flips direction.** Now the base agent creates the config, so each component's typed handle is filled by `$cast(agent_config, super.agent_config)` in `end_of_elaboration_phase`.
- **Both config styles are supported**: if a config is in the database, use it; otherwise create one. The env sets only the TX agent's config, and RX and APB keep the old way.
- The config\_db **type must be the base type** the agent uses in `get()` (`uvm_ext_agent_config#(VIF)`), not the subclass type, or the lookup misses.
- Demo: setting the TX `stuck_threshold` to 3 from the env immediately triggered the stuck-transfer error on a longer TX transfer, proving the config came from above.

Config as object vs component: the lecturer's take

Industry practice: the config is usually a `uvm_object`, created in the env and passed by config\_db. The lecturer prefers a `uvm_component` for three reasons: **easier overrides**, **access to phases** (e.g. checks in end\_of\_elaboration), and **simulator GUIs** show components in the hierarchy tree with their field values. "It is up to you whichever version you prefer." Be ready to argue either side.

**Q: "How do you configure an agent from the environment?"**

In the env's build\_phase, before creating the agent: create the config object, set its fields (active/passive, thresholds, coverage on/off) using env knowledge, and `uvm_config_db::set(this, "agent_path", "agent_config", cfg)` with the **exact type** the agent will get. The agent's build\_phase gets it (falling back to a default if absent) and hands it to its children.

**Q: "The base agent creates base types. How do protocol agents get their own classes?"**

Factory instance overrides registered in the protocol agent's constructor: "under me, an instance named 'driver' of type `uvm_ext_driver#(...)` should be `cfs_apb_driver`". When the base build\_phase calls `create`, the factory returns the protocol class. The base never names a protocol.

**Q: "Why is the config\_db type in set() so important?"**

config\_db entries are keyed by type as well as path and name. If the env sets a `cfs_md_agent_config_slave#(32)` but the agent gets a `uvm_ext_agent_config#(virtual cfs_md_if#(32))`, they're different keys and `get` returns 0, so the agent silently falls back to defaults. Set using the reader's type (handles are upcast automatically).

---

X8

## Results, and where to take the library

Conclusions video

*[Diagram: Lines of code before and after the extension library. Open the HTML page to see it.]*

Lines of code per package, as counted in the video. APB 940 → 617 (−323, −34%). MD 1278 → 953 (−325, −25%). Almost the same absolute saving: that's the plumbing an agent no longer has to carry.

### The lecturer's roadmap for the library

rule 1

#### Grow it with your career

Any class you find yourself rewriting across projects belongs in `uvm_ext_pkg`. Treat it as "a compendium of your experience".

rule 2

#### Generate what inheritance can't remove

Turn APB into **template #0** (single-aspect agent) and MD into **template #1** (master + slave), with protocol content stripped out.

example

#### A generator script

`gen_agent.py --company ifx --protocol ahb --template 0` creates the `ifx_ahb_*` files. You only add the items, drive/collect code and coverage. The same idea applies to the register layer and environments.

Three advantages, in the lecturer's words

- Less repetitive code.
- Lower probability of introducing errors.
- Faster development.

Interview line

"After building APB and MD agents, I factored their common behaviour (config, reset handling, run loops, wiring, coverage helpers) into a parameterized base library. The protocol agents shrank by 25–34%, and a new agent became mostly items plus drive and collect logic. I'd add a template-based generator on top for new protocols."

---

