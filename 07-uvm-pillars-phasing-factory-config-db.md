# Challenge 07: The Three UVM Pillars — Phasing, Factory, and `uvm_config_db`, Without the Myths

> **Level:** Fresher → Senior DV interview
> **Topics:** common vs. run-time phases, function vs. task phases, objections and end-of-test, races inside `run_phase`, factory registration and overrides, `config_db` precedence and performance, virtual interfaces
> **Related:** [Challenge 01](01-uvm-config-db-phasing-trap.md) covers `config_db` lookup failures and build-phase order in depth.

---

## 1. The Post (summary)

A LinkedIn post explains UVM's "three pillars":

1. **Phasing**: "UVM defines **8** built-in phases"; phases run in a deterministic order so "a driver's `run_phase` never collides with a monitor's `check_phase`"; on Xcelium the phase separation can "**shrink compile-to-run turnaround to under 2 minutes**".
2. **Factory**: replaces `new` with `uvm_factory::create`; you can "swap a mock driver for a **high-performance RTL model**" with a single `type_name` change; VCS "scales to **10,000 objects** per run while keeping memory predictable, because the factory reuses type information".
3. **config_db**: global key-value store; set a **clock period** in the test and read it in every driver, monitor and scoreboard; change one entry to "**retarget a different ASIC or FPGA platform**".

Choosing these three pillars is right; they're the core of UVM. **Almost every specific claim is wrong.**

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| "8 built-in phases" | **9 common phases** (build, connect, end_of_elaboration, start_of_simulation, run, extract, check, report, final) **plus 12 run-time phases** that run in parallel with `run_phase` (pre_reset … post_shutdown) |
| "run_phase never collides with check_phase" | True but meaningless: they never overlap in time. The real races are **inside `run_phase`**, where all components' `run_phase` tasks run **in parallel** (e.g., driver and monitor on the same clock edge). Phasing does nothing about those |
| "Phasing shrinks compile-to-run to under 2 minutes" | Phasing is a **runtime** mechanism. It has no effect on compile time |
| "Swap a mock driver for an RTL model via the factory" | The factory only substitutes **classes derived from the requested type**. RTL is a module, not a class. Factory can swap a driver for a **derived driver** |
| "`uvm_factory::create`" | Normal usage is `my_type::type_id::create("name", parent)` |
| "10,000 objects, memory predictable because factory reuses type info" | Invented. The factory adds a small lookup cost; it doesn't save memory. Object count depends on your testbench, not the factory |
| "Set a clock period in config_db, read it in every driver/monitor/scoreboard" | Clocks are generated in the **top module**; components sync to the clock through the **virtual interface / clocking block**. Spreading a period value through config_db invites mismatch |
| "Retarget ASIC/FPGA with one config entry" | Overstated. Config can change parameters; it can't retarget a platform |
| "Run on Xcelium and measure compile-time gain" | The changes suggested don't affect compile time; the measurement proves nothing |

---

## 3. Pillar 1: Phasing

### 3.1 The common phases

| # | Phase | Type | Order | Typical use |
|---|---|---|---|---|
| 1 | `build_phase` | function | **top-down** | Create children, `get` config |
| 2 | `connect_phase` | function | bottom-up | Connect TLM ports/exports |
| 3 | `end_of_elaboration_phase` | function | bottom-up | Print topology, final checks of structure |
| 4 | `start_of_simulation_phase` | function | bottom-up | Print config, set verbosity, banners |
| 5 | `run_phase` | **task** | **parallel** | Drive, monitor, check: consumes time |
| 6 | `extract_phase` | function | bottom-up | Collect final data from scoreboards |
| 7 | `check_phase` | function | bottom-up | End-of-test checks (e.g., queues empty) |
| 8 | `report_phase` | function | bottom-up | Print results, pass/fail |
| 9 | `final_phase` | function | top-down | Close files, cleanup |

**Why only `run_phase` is a task:** it's the only phase that consumes simulation time. All others are zero-time functions, so they can't `#delay` or `@(posedge clk)`.

### 3.2 Run-time sub-phases (12)
`pre_reset → reset → post_reset → pre_configure → configure → post_configure → pre_main → main → post_main → pre_shutdown → shutdown → post_shutdown`

- They run **in parallel with `run_phase`**.
- Useful for structured flows (e.g., re-entering reset mid-test with phase jumping).
- Many teams avoid them and do everything in `run_phase` with sequences, because mixing the two styles and phase jumps make end-of-test hard to reason about. Know they exist; be able to say why your team did or didn't use them.

### 3.3 Objections: how the run phase ends
- `run_phase` ends when **no objections remain raised** (plus any drain time).
- If nobody raises: run_phase ends at time 0 and nothing runs.
- If someone never drops: the sim **hangs** until the global timeout.
- Best practice: **the test** (or top virtual sequence) raises/drops. Drivers and monitors don't.
- `phase.phase_done.set_drain_time(this, 100ns)`: lets in-flight transactions finish after the last drop.
- `phase_ready_to_end()`: a component (e.g., scoreboard) can re-raise if it's still waiting for expected transactions.

```systemverilog
function void my_scoreboard::phase_ready_to_end(uvm_phase phase);
  if (phase.get_name() != "run") return;
  if (expected_q.size() != 0) begin
    phase.raise_objection(this, "waiting for pending transactions");
    fork begin
      wait (expected_q.size() == 0);
      phase.drop_objection(this);
    end join_none
  end
endfunction
```

### 3.4 The races phasing does NOT fix
All `run_phase`s run in parallel at the same time steps. Classic race: the driver writes a signal and the monitor samples it on the same edge; the result depends on scheduling order.

**Fix: clocking blocks**, which define *when* inputs are sampled (before the edge) and outputs driven (after the edge):

```systemverilog
interface bus_if(input logic clk);
  logic valid, ready; logic [31:0] data;
  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output valid, data; input ready;
  endclocking
  clocking mon_cb @(posedge clk);
    default input #1step;
    input valid, ready, data;
  endclocking
endinterface
```
Driver uses `vif.drv_cb`, monitor uses `vif.mon_cb`. Now both see consistent values regardless of process order.

---

## 4. Pillar 2: The Factory

### 4.1 What it is
A central registry that decides **which class actually gets built** when you ask for one. It lets tests change the testbench **without editing** the env.

### 4.2 Three requirements
1. **Register** the class: `` `uvm_component_utils(my_driver) `` or `` `uvm_object_utils(my_txn) ``.
2. **Create via the factory**: `drv = my_driver::type_id::create("drv", this);`
   Using `new()` **bypasses** the factory; overrides silently do nothing.
3. **Override type must extend the original**: `err_driver extends my_driver`.

### 4.3 Override types

```systemverilog
// Type override: every my_driver in the TB becomes err_driver
my_driver::type_id::set_type_override(err_driver::get_type());

// Instance override: only this path
my_driver::type_id::set_inst_override(err_driver::get_type(), "env.agt_a.drv", this);
```

Command line (no recompile):
```
+uvm_set_type_override=my_driver,err_driver
+uvm_set_inst_override=my_driver,err_driver,uvm_test_top.env.agt_a.drv
```

**Rules that bite:**
- Overrides must be set **before** the object is created: in the test's `build_phase` **before** `env` is created (or before `super.build_phase` creates it).
- Instance override wins over type override for that path.
- Override by **type** (`get_type()`) is checked at compile time; by **name** (string) only fails at runtime.

### 4.4 Debugging
```systemverilog
uvm_factory::get().print();          // all registered types and active overrides
uvm_top.print_topology();             // what actually got built
```
If the override "doesn't work": check `new` vs. `create`, inheritance, timing of the override, and the instance path string.

### 4.5 Parameterized classes
Use `` `uvm_component_param_utils(my_drv#(W)) ``. These are registered by **type only**, not by name, so string-based overrides don't work for them.

---

## 5. Pillar 3: `uvm_config_db`

(See Challenge 01 for lookup rules and failures.)

### 5.1 What to pass through it

| Pass | Example |
|---|---|
| **Virtual interfaces** (most important use) | set in `tb_top` module, get in agent/driver/monitor |
| **Config objects** | `agent_cfg` with `is_active`, widths, knobs |
| Simple knobs from command line | `+uvm_set_config_int=*.agt,num_txn,100` (type is `uvm_bitstream_t`) |

**Don't** pass a clock period for components to "agree" on. The clock lives in `tb_top`; components sync via the interface.

```systemverilog
module tb_top;
  logic clk = 0; always #5 clk = ~clk;   // clock generated here
  bus_if vif(clk);
  dut u_dut(.clk(clk), .valid(vif.valid), ...);
  initial begin
    uvm_config_db#(virtual bus_if)::set(null, "uvm_test_top.env.agt*", "vif", vif);
    run_test();
  end
endmodule
```

### 5.2 Precedence
- During `build_phase`: a `set` from a **higher** component in the hierarchy wins (test beats env).
- Same level or after build: **last set wins**.
- `set(null, ...)` from the top module counts as the highest context.

### 5.3 Performance and design
- `get` is a string-matched lookup. Calling it **inside `run_phase` loops** is slow at scale. Get once in `build_phase`, keep the handle.
- Prefer **one config object** per agent/env over dozens of scalar entries.
- Keep wildcards narrow; `"*"` matches everything.
- For runtime changes, share a **config object handle** (changes are visible immediately) or use `wait_modified()`.
- `uvm_config_db` is a convenience layer on top of `uvm_resource_db`; you rarely need the latter directly.

### 5.4 Debug switches
```
+UVM_CONFIG_DB_TRACE     // every set/get
+UVM_RESOURCE_DB_TRACE
```
plus `uvm_top.check_config_usage()` in `report_phase` to find sets nobody read.

---

## 6. How the Three Work Together (one timeline)

```
tb_top initial:    config_db set(vif)  →  run_test()
build (top-down):  test: set overrides, set cfg objects, create env (factory)
                   env:  get cfg, create agents (factory applies overrides)
                   agent: get cfg, build driver/sequencer only if ACTIVE
                   driver/monitor: get vif
connect:           TLM connections (driver↔sequencer, monitor→scoreboard)
end_of_elab:       print topology / factory
run (parallel):    test raises objection, starts vseq; driver/monitor loop
                   last drop + drain time → run ends
extract/check/report: scoreboard final checks, pass/fail summary
final:             close files
```

---

## 7. Likely Follow-ups (with model answers)

**Q. Why is build top-down but connect bottom-up?**
Build: a parent must create children before they can be built. Connect: lower-level ports must exist and be wired before higher levels connect through them.

**Q. Can `build_phase` contain `#10`?**
No. It's a function; time-consuming statements won't compile.

**Q. Your factory override has no effect. Why?**
Object created with `new`; override set after creation; override class doesn't extend the original; wrong instance path; parameterized class overridden by name.

**Q. Why not get config in `run_phase` every transaction?**
Lookup cost (string matching across the resource pool) and unpredictable behaviour if someone changes it mid-run. Get once, store the handle.

**Q. How does the test end?**
When all run-phase objections are dropped and drain time passes. Then extract/check/report/final run.

**Q. How do you avoid driver/monitor races?**
Clocking blocks with input skew `#1step` (sample just before the edge) and an output skew; never sample and drive raw signals at the same edge without them.

**Q. Type override vs. instance override?**
Type: all instances of that type. Instance: only at the given path. Instance wins when both apply.

---

## 8. Common Fresher Mistakes
- Using `new()` for components/objects that should be overridable.
- Setting factory overrides after `env` is created.
- Raising objections in drivers/monitors.
- Forgetting `super.build_phase()` in derived classes.
- Getting config inside `run_phase` loops.
- Passing clock periods instead of using interfaces and clocking blocks.
- Saying "UVM has 8 phases".

---

## 9. 60-Second Interview Pitch

> "UVM has nine common phases. build is top-down, connect and the later function phases are bottom-up, and run_phase is the only task, running in parallel across all components, with twelve optional run-time sub-phases alongside it. The run phase ends when every objection is dropped, so I keep objections in the test, use drain time, and let scoreboards extend via phase_ready_to_end. Phasing orders setup and cleanup, but it doesn't remove races inside run_phase. For that I use clocking blocks.
>
> The factory decides which class gets built. Classes must be registered and created with `type_id::create`, overrides must extend the original and be set before creation, and I can apply them from the command line without recompiling.
>
> config_db passes virtual interfaces from tb_top and config objects from the test. I get them once in build_phase, keep scopes narrow, and debug with `+UVM_CONFIG_DB_TRACE` and `check_config_usage`."

---

## 10. Hands-on Exercise (corrected version of the post's "do this next")
1. Add `phase_started`/`phase_ended` prints in one component and log the actual phase order, including run-time sub-phases.
2. Create `err_driver extends my_driver`; apply it once with `set_type_override` and once with `+uvm_set_inst_override`; confirm with `factory.print()`.
3. Change one `type_id::create` to `new` and watch the override silently stop working.
4. Pass the virtual interface via `config_db` from `tb_top`; add a clocking block and remove a driver/monitor race.
5. Add `check_config_usage()` and deliberately misspell a `set` path to see it reported.

---

## 11. Self-Check
- [ ] Can I list all 9 common phases with function/task and order?
- [ ] Can I explain how run_phase ends, drain time, and `phase_ready_to_end`?
- [ ] Can I explain why phasing doesn't fix races, and how clocking blocks do?
- [ ] Can I list 4 reasons a factory override doesn't work?
- [ ] Can I explain config_db precedence and why to `get` only in build?

---

## 12. Addendum: A Combined Factory / Virtual-Sequence / TLM Post

A later post mixes three topics. Corrections, with links to the full explanations:

| Claim | Reality | See |
|---|---|---|
| Factory is the "**single source of truth**" for the testbench | The factory decides **which class** gets built. **Configuration** (config objects, `config_db`, generated config) is the source of truth for **settings** | 03 §11, 07 §4–5 |
| Three steps: "register the override, set the type, then instantiate" | Correct order: (1) **register the class** (`` `uvm_component_utils ``), (2) **set the override** before creation, (3) **create** with `type_id::create` | 07 §4.2 |
| Factory gives substitution "**without recompiling**" | Only **command-line** overrides (`+uvm_set_type_override`) and test selection (`+UVM_TESTNAME`) avoid recompiling. Overrides written in a test are code; they need that test compiled in (normally all tests are compiled once) | 07 §4.3 |
| Factory overrides give ">20% **compile-time** reduction" | The factory has nothing to do with compile time | — |
| Swap an Ethernet driver "on a **7nm ASIC**" | Process node is irrelevant to testbench components | 03 §2.1 |
| Sequences "launched on a `uvm_virtual_sequencer` that **arbitrates** multiple agents" | In UVM 1.x, `uvm_virtual_sequencer` is just a **typedef of `uvm_sequencer`**. It holds handles; **arbitration happens in each real sequencer** | 05 §2–3 |
| Call `start_item()`/`finish_item()` in the virtual-sequence flow | `start_item`/`finish_item` are for sequences that **generate items** on a real sequencer. A **virtual** sequence **starts sub-sequences** (`seq.start(p_sequencer.x_sqr)`) | 05 §2.1 |
| "The **virtual sequencer's `run_phase`** drives both sequences" | Sequences are started from the **test** (or a parent sequence). You don't write stimulus in a sequencer's `run_phase` | 05 §3.3 |
| `uvm_blocking_put_port` is "the safe choice for **back-pressure-aware drivers**" | Drivers **pull** items through `seq_item_port` (`get_next_item`/`item_done`); back-pressure from the DUT is handled in the driver's pin-level code | 16 §7 |
| `uvm_tlm_fifo` depth 4–8 "hides latency spikes in a **multi-clock domain** design" | TLM is **untimed** and has no clock domains. FIFO depth is about testbench producer/consumer behaviour | 16 §2, §6 |
| "Dual-clock environment" races with a virtual sequencer | Races are **signal-level** (driving/sampling at clock edges); fixed with **clocking blocks**, not sequencer changes | 07 §3.4 |
| "Scoreboard with `uvm_analysis_imp` + `uvm_tlm_fifo` of depth 6" | For monitor → scoreboard, use **analysis imps** or **analysis FIFOs** (unbounded). A sized `uvm_tlm_fifo` can't be connected to an analysis port's `write()` | 16 §5–6 |

### The correct item flow inside a normal (non-virtual) sequence
```systemverilog
task body();
  repeat (n) begin
    req = mem_txn::type_id::create("req");
    start_item(req);                                   // wait for sequencer grant (arbitration)
    if (!req.randomize() with { kind == WRITE; })      // late randomization: after grant
      `uvm_fatal("RAND", "randomize failed")
    finish_item(req);                                  // hand to driver; returns after item_done
  end
endtask
// `uvm_do_with(req, { kind == WRITE; }) does the same create/start/randomize/finish steps
```
Why randomize **after** `start_item`: the item is randomized at the moment it's granted, so it can react to the latest state (e.g., values from a previous response).
