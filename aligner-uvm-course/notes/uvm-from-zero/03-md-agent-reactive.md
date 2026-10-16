# Lecture companion: MD agent (reactive)

> Card-by-card notes for Cristian Slav's course. Diagrams and toys are in `pages/uvm-from-zero.html`.

Chapter · the MD agents (14 videos)

## Building the MD RX (master) and TX (slave) agents

One agent class family, two "aspects": a **master** on RX that starts transfers, and a reactive **slave** on TX that answers the DUT. New skills on top of the APB agent: extracting a protocol from a DUT spec, parameterized classes, inheritance between master and slave, a reactive slave, and portable code across three simulators. The MD agent is about 1276 lines versus about 940 for APB: just 350 more lines for two aspects.

---

M1

## The MD protocol: extracting rules from a DUT spec

No protocol document exists, so you build one · lecture

Real-life skill

"Not all the time your DUT will have standard interfaces." The recipe the lecturer gives: **(1) identify the signals, (2) identify the rules that govern them**, by reading the DUT's datasheet sentence by sentence. Each sentence like "it must remain constant until ready becomes high" becomes one rule, and later one assertion.

RX side

#### Agent = master, DUT = slave

The agent drives valid, data, offset, size. The DUT answers with ready, err.

TX side

#### DUT = master, agent = slave

The DUT drives valid, data, offset, size. The agent answers with ready, err.

widths

#### All from DATA\_WIDTH

offset = max(1, log2(W/8)) bits, size = log2(W/8)+1 bits. At W=32: offset 2 bits, size 3 bits.

| # | Rule | Source |
| --- | --- | --- |
| 1 | DATA\_WIDTH is a power of 2 | datasheet, ALGN\_DATA\_WIDTH |
| 2 | DATA\_WIDTH ≥ 8 |
| 3 | Once valid is high, it stays high until ready is high | md\_\*\_valid |
| 4–5 | data is valid while valid is high · data constant until ready | md\_\*\_data |
| 6–7 | offset valid while valid · constant until ready | md\_\*\_offset |
| 8–10 | size valid while valid · constant until ready · **size ≠ 0** | md\_\*\_size |
| 11–12 | err valid only when valid & ready · err high only when valid & ready | md\_\*\_err |
| 13 | valid never X/Z | added by the verifier; "check with the designer and architect" |
| 14 | ready valid (not X) while valid is high |
| 15 | offset + size ≤ DATA\_WIDTH/8 |
| 16 | a transfer can't last forever (stuck threshold) |

**The key distinction:** the `(W/8 + offset) % size == 0` rule is **not** a protocol rule. It's the Aligner's own behaviour. The protocol allows size 3 at offset 0; the *Aligner* rejects it and increments CNT\_DROP. So the agent must be able to drive "Aligner-illegal" transfers, otherwise you can't test the rejection. Rule 15 (offset + size fits on the bus) is a physical limit, so the agent enforces it.

Three transfer shapes to remember

- **No wait states:** ready already high when valid rises, so the transfer starts and ends in one cycle.
- **With wait states:** the slave holds ready low; the master keeps valid, data, offset and size constant.
- **With error:** err high together with ready, e.g. offset 1, size 2 on the Aligner's RX side.

**Q: "Your DUT has a custom interface with no spec. How do you build its VIP?"**

Extract the protocol from the DUT spec: list signals with direction and width, then turn every behavioural sentence into a numbered rule. Separate **protocol** rules (true for any device on this bus, go into the agent) from **DUT** rules (this device's behaviour, go into the model/scoreboard). Add implied rules (no X, bounded length) and confirm them with the designer. Then build the agent so it can also violate DUT-level rules, for negative testing.

**Q: "Why shouldn't an agent refuse to send transfers the DUT considers illegal?"**

Because rejecting them is DUT behaviour you must verify (error response, counter, interrupt). The agent's legality must match the **protocol**, not the DUT. Bake the DUT's rules into the agent and the error-handling logic can never be stimulated.

**Q: "Who decides an implied rule like 'offset + size ≤ bus bytes' is real?"**

The designer and system architect, not the verifier. Write the assumption down, ask, and record the answer in the spec or vPlan. In this project the rule isn't in the datasheet; the RTL enforces it on CTRL writes but not on the RX port. That's a gap you only find by asking (see the senior course).

---

M2

## Agent architecture: one family, two aspects

What's shared, what's split · lecture

*[Diagram: Which MD classes are common and which split into master and slave. Open the HTML page to see it.]*

Why the split falls where it does

- **Monitor and coverage are common**: observing a bus is the same whichever side drives it.
- **The driver is split**: the base holds the loop, reset handling and process control; subclasses implement only `drive_transaction()`.
- **The config is split** because each side may need its own knobs (e.g. ready value at reset).
- **DATA\_WIDTH is a parameter**, not a `` `define `` like APB. It's more flexible (two widths in one simulation), but every class that touches the interface must carry it.

**Q: "How would you structure a VIP that supports both master and slave modes?"**

Shared interface, monitor, coverage and sequencer base. Driver, drive item, config and agent each get a common base and two subclasses. The agent subclass uses factory instance overrides to pick its driver, config and sequencer. The env just instantiates `agent_master` or `agent_slave`. Shared code is written once, and a fix applies to both modes.

**Q: "`define vs parameter for a bus width?"**

A `` `define `` is global and compile-time: simple, but one value for the whole simulation. A parameter is per instance, so two agents of different widths can coexist. The cost is that every dependent class must be parameterized too, and mistakes cause type-mismatch compile errors (which the course runs into). Rule of thumb: parameters for reusable VIP, defines for one-off code.

---

M3

## Infrastructure and the factory override

Parameterized interface, two instances, set\_inst\_override · lecture + practice

```systemverilog
// testbench: two instances of the same interface, both stored under the key "vif"
cfs_md_if#(`CFS_ALGN_TEST_ALGN_DATA_WIDTH) md_rx_if(.clk(clk));
cfs_md_if#(`CFS_ALGN_TEST_ALGN_DATA_WIDTH) md_tx_if(.clk(clk));
assign md_rx_if.reset_n = apb_if.preset_n;            // one reset source
uvm_config_db#(virtual cfs_md_if#(ALGN_DATA_WIDTH))::set(null, "uvm_test_top.env.md_rx_agent", "vif", md_rx_if);
uvm_config_db#(virtual cfs_md_if#(ALGN_DATA_WIDTH))::set(null, "uvm_test_top.env.md_tx_agent", "vif", md_tx_if);
// the PATH, not the key, decides which agent gets which interface

// agent master: swap the config type for this instance only
function new(string name = "", uvm_component parent);
  super.new(name, parent);                            // overrides go in new(): before build_phase calls create()
  cfs_md_agent_config#(DATA_WIDTH)::type_id::set_inst_override(
      cfs_md_agent_config_master#(DATA_WIDTH)::get_type(), "agent_config", this);
endfunction
// base agent's build_phase: agent_config = cfs_md_agent_config#(W)::type_id::create("agent_config", this);
// ...now returns a cfs_md_agent_config_master
```

How the override works

`set_inst_override(new_type, "agent_config", this)` says: "when something under *me* creates an instance named `agent_config` of the original type, build `new_type` instead". It only works because the base agent uses `type_id::create`, and because the override is registered **before** that create runs. The lecturer recommends reading UVM User Guide §6.2, "The Built-in Factory and Overrides" (about 3 pages).

From the practice video

- The interface has `parameter DATA_WIDTH = 32` plus `localparam` widths for offset and size, copied from the datasheet formulas.
- The vif typedef depends on the parameter, so it's declared **inside** the parameterized class, not in a shared types file.
- Parameterized classes use `` `uvm_component_param_utils ``.
- Lots of copy-paste from the APB agent ("very prone to error"). A copy-paste bug left `virtual` on an already-virtual typedef. This duplication is what the later UVM extension library removes.
- The value 32 appeared in many places. Fixed with one `` `define CFS_ALGN_TEST_ALGN_DATA_WIDTH `` for the testbench, and a **parameter** on the env so two Aligner envs of different widths could coexist.

**Q: "Type override vs instance override?"**

`set_type_override`: every creation of type A anywhere becomes B. `set_inst_override`: only creations under a given hierarchical path (and optionally a given instance name) become B. The MD agents need instance overrides: the master and slave agents swap the same base types for *different* subclasses. A type override would make both the same.

**Q: "Why put the override in the constructor?"**

The parent's build\_phase calls `create()` on its children, and the override must already exist at that moment. A component's constructor runs while its parent is in build, before this component's own build\_phase. Overrides registered after the create silently do nothing.

**Q: "Two agents need two different interfaces stored under the same name. How?"**

Use the same key ("vif") but different instance paths in `set()`: `…env.md_rx_agent` vs `…env.md_tx_agent`. Each agent's `get(this, "", "vif", …)` matches only its own path. The agent code stays generic and doesn't need to know whether it's RX or TX.

---

M4

## Master driving: items without parameters

A byte list, a parameter firewall, a common driver · lecture + practice

The design problem

A natural item would have `bit [DATA_WIDTH-1:0] data`, `offset`, `size`. But items are created in **sequences**, outside the agent, so every sequence would need the width parameter too. The fix: store the bytes as a **list** (`rand bit[7:0] data[$]`). Size becomes `data.size()` and the width disappears from the item.

```systemverilog
class cfs_md_item_drv_master extends cfs_md_item_drv;
  rand int unsigned pre_drive_delay, post_drive_delay;
  rand bit[7:0]     data[$];                 // size = data.size()
  rand int unsigned offset;
  constraint data_default   { soft data.size() == 1; }   // works at ANY bus width
  constraint data_hard      { data.size() > 0; }
  constraint offset_default { soft offset == 0; }        // works at ANY bus width
endclass

class cfs_md_sequence_simple_master extends cfs_md_sequence_base_master;
  rand cfs_md_item_drv_master item;
  local int unsigned data_width;             // copied from the sequencer in pre_randomize
  constraint item_hard {                     // bus-width limits live in the SEQUENCE
    item.data.size() > 0;
    item.data.size() <= data_width / 8;
    item.offset < data_width / 8;
    item.data.size() + item.offset <= data_width / 8;
  }
  function new(string name = "");
    super.new(name);
    item = cfs_md_item_drv_master::type_id::create("item");
    item.data_default.constraint_mode(0);    // switch off the item's soft defaults
    item.offset_default.constraint_mode(0);
  endfunction
  function void pre_randomize();
    data_width = p_sequencer.get_data_width();   // a virtual call: no parameter needed here
  endfunction
endclass
```

*[Diagram: Sequencer hierarchy that hides the data width parameter. Open the HTML page to see it.]*

The "parameter firewall": sequences declare `p_sequencer` as the unparameterized base, and polymorphism reaches the parameterized implementation. The senior course points out this same pattern.

**Why not `pure virtual`?** UVM must be able to create the base class through the factory, and a class with pure virtual methods must be `virtual` (abstract) and can't be instantiated. So the base methods get an empty body with a `` `uvm_fatal `` "implement me" reminder.  
**Gotcha in the test:** `seq.set_sequencer(env.md_rx_agent.sequencer)` must be called **before** `randomize()`, because `pre_randomize` uses `p_sequencer`.

Driver and first run

- `cfs_md_driver#(W, ITEM)` holds everything from the APB driver except `drive_transaction`. `cfs_md_driver_master` implements it: pre-delay, valid=1, pack the bytes at the offset into the data word, wait for ready, clear, post-delay.
- The agent gets a second parameter, the drive item type, because the sequencer handle's type depends on it.
- First waveform check: `{A0, C0}` at offset 2 got OKAY. `{34, 29}` at offset 1, size 2 got **err**, as the Aligner spec says.

**Q: "How do you keep a parameter out of sequences?"**

Make the item width-independent (a byte list), put width-dependent constraints in the sequence using a value read at `pre_randomize`, and type `p_sequencer` as a non-parameterized base whose virtual `get_data_width()` is implemented by the parameterized subclass. Sequences then compile once for any width.

**Q: "Where should constraints live: item or sequence?"**

The item has universal defaults (soft, safe at any configuration) and true invariants (size > 0). The sequence has context-dependent limits (bus width, DUT state) and scenario intent. The item stays reusable, and each sequence can disable soft defaults with `constraint_mode(0)`.

**Q: "What is pre\_randomize used for?"**

It's called automatically just before the solver runs. Use it to compute non-random state that constraints depend on: here, reading the bus width from the sequencer into a local variable. It also avoids calling functions inside constraints, which one simulator rejected (M7).

---

M5

## The MD monitor: two broadcasts per transfer

begin\_tr / end\_tr / is\_active, and sampling 1 ns late · lecture + practice

Unlike APB, the MD monitor calls `output_port.write(item)` **twice**: at the **start** of a transfer (so the slave can respond and the model can predict early) and at the **end** (complete with response and length). Subscribers tell them apart with `uvm_transaction`'s timing API.

```systemverilog
item.offset = vif.offset;                         // known at the START
for(int i = 0; i < vif.size; i++)
  item.data.push_back((vif.data >> ((item.offset + i) * 8)) & 8'hFF);
void'(begin_tr(item));                            // sets begin_time → is_active() == 1
output_port.write(item);                          // broadcast #1: "a transfer started"

@(posedge vif.clk);
while(vif.ready !== 1) begin @(posedge vif.clk); item.length++; end
item.response = cfs_md_response'(vif.err);
end_tr(item);                                     // sets end_time → is_active() == 0
output_port.write(item);                          // broadcast #2: "it finished"
```

*[Diagram: Sampling one nanosecond after the clock edge. Open the HTML page to see it.]*

With zero wait states, ready is already high when valid rises, so start and end land in the same cycle. If the monitor saw "start" exactly at the edge, the slave would have no time to choose a response. Sampling `sample_delay_start_tr` (1 ns) after the edge reports the start in the cycle *before* the handshake completes.

Facts to remember

- The monitor item has prev\_item\_delay, length, data (byte list), offset and response.
- `get_end_time()` returns −1 while active, so `convert2string` prints the end time only when `!is_active()`.
- Video check: item begins at **116 ns** (the edge at 115 plus 1 ns) and ends at 125 ns.
- The 1 ns is a config field, not hard-coded: "having this one nanosecond here is not ideal".
- begin\_tr/end\_tr also enable **transaction recording**: simulators can draw items as "bubbles" on the waveform. That's not available on EDA Playground; the lecturer wrote an article, "Debugging tip: look at the bubbles".

**Senior note:** because every transfer is written twice, every subscriber must filter on `is_active()`. Your MD *coverage* doesn't, so it samples each transfer twice, the first time with a default OKAY response and length 1. That inflates those bins. (Senior course, Module 8.)

**Q: "Why would a monitor publish a transaction at its start?"**

Reactive agents and predictive models need to act during the transfer: a slave must decide ready/err latency based on the request; a model can predict the response or occupancy right away. End-only publication works for passive checking, but not for reacting.

**Q: "How do subscribers tell the start event from the end event?"**

With `uvm_transaction::is_active()`: true after `begin_tr` and before `end_tr`. Alternatives are two separate analysis ports, or a phase field in the item. Note that both writes pass the **same object handle**, which keeps changing, so subscribers that store it must clone it.

**Q: "Why sample 1 ns after the clock edge? Isn't that a hack?"**

It gives the testbench a decision window in the same cycle a transfer starts, needed for zero-latency responses. It's the same thing as a clocking-block input skew, done by hand. Making it a config field keeps it adjustable. The risk: it must be smaller than the clock period and robust to timescale changes.

---

M6

## The reactive slave: answering the DUT

The hardest part of the course so far · lecture + practice

Why a normal sequence fails here

The slave item has **length** (cycles before ready; 0 = one-cycle transfer), **response** (err) and **ready\_at\_end** (keep ready high after the transfer, like a "FIFO not full" signal). If a sequence sends such items at random times, two things break. It decides the response *before* it knows what the DUT is sending (it can't answer an offset-2 size-1 transfer with OKAY on purpose). And a length-0 item arriving mid-transfer looks identical to a longer one, so you lose control of timing.

*[Diagram: Reactive slave flow. Open the HTML page to see it.]*

```systemverilog
// sequencer_base_slave: a sequence can't own an analysis imp (imps need a component parent), so the sequencer does
uvm_analysis_imp#(cfs_md_item_mon, cfs_md_sequencer_base_slave) port_from_mon;
uvm_tlm_fifo#(cfs_md_item_mon) pending_items;          // new("pending_items", this, 1): one transfer at a time

virtual function void write(cfs_md_item_mon item);
  if(item.is_active()) begin                            // react to START events only
    if(pending_items.is_full())
      `uvm_fatal("ALGORITHM_ISSUE", "FIFO is full - no sequence pulls from it?")
    void'(pending_items.try_put(item));
  end
endfunction
virtual function void handle_reset(uvm_phase phase);
  super.handle_reset(phase); pending_items.flush();     // forget requests on reset
endfunction

// slave response sequence: the request decides the response
virtual task body();
  cfs_md_item_mon item_mon;
  p_sequencer.pending_items.get(item_mon);              // blocks until the DUT starts a transfer
  `uvm_do_with(seq, { /* e.g. item.response == (item_mon.data[0] == 'h85 ? ERR : OKAY); */ })
endtask
```

**Lessons from the practice video:**  
1. Before any slave sequence existed: `UVM_FATAL … FIFO is full` at 176 ns. ready was high from reset, two transfers started back to back, and nobody pulled. The fatal is a deliberate early warning.  
2. The slave driver forced ready to 0 after every transfer. The fix was to use `item.ready_at_end`, otherwise that field does nothing.  
3. **Variable hiding:** the slave driver re-declares `agent_config` with the more specific slave type (to reach `get_ready_at_reset()`) and fills it with `$cast` in `end_of_elaboration_phase`, after the parent's pointer was connected.  
4. The monitor-to-sequencer connection lives in its own virtual function, so a future subclass can turn it off.

**Q: "Design a slave agent whose response depends on the request."**

The monitor publishes the request at its start. An analysis imp in the slave sequencer pushes it into a TLM FIFO. A forever "responder" sequence blocks on `get()`, then randomizes a response item constrained by the request (e.g. err for illegal offset/size, latency from a distribution) and sends it to the driver. Tests change behaviour by overriding the responder sequence. The FIFO depth matches the protocol's maximum outstanding requests (1 here).

**Q: "Why put the analysis imp in the sequencer rather than the sequence?"**

Analysis imps are TLM components that need a `uvm_component` parent and must be connected in connect\_phase. Sequences are short-lived `uvm_object`s created at run time. The sequencer is a component, lives in the agent next to the monitor, and every sequence reaches it through `p_sequencer`.

**Q: "What is uvm\_tlm\_fifo and which methods matter?"**

A bounded FIFO component with TLM put/get interfaces. Blocking `put`/`get` (tasks), non-blocking `try_put`/`try_get` (return success), `peek`, `is_full`, `is_empty`, `used`, `flush`. The lecturer notes that some methods appear in the source code but not the HTML reference: read the source.

**Q: "What's variable hiding and when is it acceptable?"**

A subclass declares a member with the same name as a parent member. Inside the subclass the new one is used; the parent's code still sees its own. Here it gives a more specific type for the same object (filled via `$cast`). It works, but it's error-prone: two handles must be kept in sync. A typed getter or a parameterized base is cleaner.

---

M7

## MD protocol checks, and making code run on three simulators

16 rules, elaboration-time checks, Xcelium vs Questa vs VCS · lecture + practice

Rules 3–15 become assertions in `cfs_md_if` (reusable in formal). Rule 16 (stuck transfer) is a monitor check with a `stuck_threshold`; unlike APB there's no lower limit, since an MD transfer can be one cycle. Rules 1–2 are about a **parameter**, which never changes, so checking them every clock is pointless. They're checked **once, when the interface is elaborated**.

```systemverilog
// final, portable version (outside any initial block → runs at elaboration)
if($log10(DATA_WIDTH)/$log10(2) - $clog2(DATA_WIDTH) != 0) begin
  $error("DATA_WIDTH is not a power of two - value in binary: 'b%0b, in hex is 'h%0h, in dec is %0d",
         DATA_WIDTH, DATA_WIDTH, DATA_WIDTH);
end
if(DATA_WIDTH < 8) begin
  $error($sformatf("DATA_WIDTH must be bigger than 8 but detected value %0d", DATA_WIDTH));
end
```

| Attempt | Xcelium (Cadence) | Questa (Siemens) | VCS (Synopsys) |
| --- | --- | --- | --- |
| `$countones(W) != 1` in an `initial` block | works, but only at time 0 and the sim continues | not tried in this form | |
| `$countones` in elaboration context | ❌ "unsupported context" | runs, but `$sformatf` inside `$error` printed garbage; fixed by passing the format directly | needs a compile option for elaboration system tasks |
| Function call inside a constraint (`p_sequencer.get_data_width()`) | ✅ | ✅ | ❌ → copy into a local var in `pre_randomize` |
| `$log10(W)/$log10(2) - $clog2(W)` | ✅ | ✅ | ✅ |

More lessons from the practice video

- **Parameter-passing bugs:** setting W=33 exposed classes declared without `#(DATA_WIDTH)` (monitor's and driver's agent\_config). They silently defaulted to 32 and failed to connect. "Be very, very careful to pass all the parameters."
- **Forcing the scenario:** to test "valid stays high until ready", ready must actually go low. Sending 11 max-size items with zero delay fills the 8-deep RX FIFO, so the DUT back-pressures. Watch `push_fifo_level` inside the FIFO.
- Break the driver on purpose (drop valid early, change data, offset or size mid-transfer, size 0, err at reset, offset+1 with size 4) and confirm each assertion fires at the expected time.
- `$error` in an interface doesn't stop the simulation, while `` `uvm_error `` plus `+UVM_MAX_QUIT_COUNT=1` does.

**Q: "How do you validate a parameter value?"**

With an elaboration-time check: a generate-style `if` with `$error`/`$fatal` outside procedural code, which fires once during elaboration before simulation starts. A concurrent assertion would re-check a constant every clock. An initial block works but runs only after elaboration and doesn't stop the build.

**Q: "Your VIP works on one simulator and fails on another. What do you do?"**

Expect it: language support differs in corners (system functions in constant contexts, functions in constraints, formatting in elaboration tasks). Keep a regression on every supported simulator, stick to widely supported constructs, isolate tool workarounds behind macros (`` `ifdef VCS ``…), and prefer simple equivalent forms like the $log10/$clog2 trick.

**Q: "How do you prove an assertion like 'valid stays high until ready' is not vacuous?"**

Its antecedent must actually occur: valid high with ready low. Normal traffic never produced that because the DUT was always ready. You must create back-pressure (fill the FIFO), then inject a violation to see it fire. Add a `cover property` for "valid high, ready low" to prove the scenario happens in regressions.

---

M8

## MD coverage

Protocol-legal crosses, data-lane toggles, coverage-driven stimulus · lecture + practice

*[Diagram: MD verification plan tree. Open the HTML page to see it.]*

```systemverilog
offset : coverpoint item.offset    { bins values[] = {[0:(DATA_WIDTH/8)-1]}; }
size   : coverpoint item.data.size() { bins values[] = {[1:(DATA_WIDTH/8)]}; }
length : coverpoint item.length    { bins length_eq_1 = {1}; bins length_le_10[9] = {[2:10]};
                                     bins length_gt_10 = {[11:$]}; illegal_bins length_lt_1 = {0}; }
offset_x_size : cross offset, size {
  ignore_bins ignore_offset_plus_size_gt_data_width = offset_x_size with (offset + size > (DATA_WIDTH / 8));
}
// data toggle index on the full bus: lane offset + byte position + bit
wrap_cover_data_1.sample((item.offset * 8) + (byte_index * 8) + bit_index);
```

Coverage-driven stimulus, live in the video

- The RX agent showed **26%**: the earlier test forced max-size items (to fill the FIFO), so offset and size coverage were stuck at 25%.
- Removing those constraints raised it to **72%**, but size was still 75%. Searching the log showed size 4 never occurred in 11 items.
- Raising the item count from 11 to 100 gave **84%** and every size covered. That's the closure loop: measure, find the hole, change stimulus, re-measure.
- The TX agent stays around 25% on offset and size by design: the DUT only outputs the one CTRL configuration. Environment-level tests must vary CTRL.
- Coverage is printed once in `report_phase` instead of after every item.

**Q: "Your coverage is stuck at 72%. How do you close it?"**

Find which bins are empty (GUI or report), then ask why. Is the bin unreachable (fix with an ignore\_bin plus justification)? Is it reachable but the stimulus is constrained away from it (relax constraints or add a directed sequence)? Is it just too rare (more seeds or items, or bias with `dist`)? Then re-run and confirm. In the video: an over-constrained test, then too few items.

**Q: "Why does TX coverage of offset/size look bad, and is that a problem?"**

The DUT's TX output is determined by CTRL.SIZE/OFFSET, so one configuration produces one combination. It's not an agent problem; it's a **test** coverage gap: tests must reprogram CTRL across all legal settings. Agent coverage reveals what the environment's stimulus didn't do.

**Q: "ignore\_bins vs illegal\_bins in this cross?"**

offset + size beyond the bus is physically impossible, so `ignore_bins` removes it from the target. `illegal_bins` would raise an error if hit, turning coverage into a checker; that job belongs to the interface assertion (rule 15). Aligner-illegal combos stay as normal bins because they must be exercised.

---

M9

## MD agent: what you can now say in an interview

Conclusions video

spec reading

#### Protocol from a DUT spec

16 rules extracted, protocol rules separated from DUT rules.

architecture

#### Master + slave from one family

Common bases, split subclasses, factory instance overrides.

flexibility

#### Parameterized agent

DATA\_WIDTH everywhere it must be, hidden where it mustn't be (parameter firewall).

reactivity

#### Reactive slave

Monitor → sequencer FIFO → responder sequence.

checks

#### Constant-context checks

Elaboration-time parameter validation.

portability

#### Three simulators

Real syntax differences found and worked around.

Interview line

"For a custom memory-data protocol with no spec, I extracted 16 protocol rules from the DUT datasheet, built a parameterized agent with master and slave modes from shared base classes, and made the slave reactive: the monitor publishes transfer starts into a FIFO in the sequencer, and a responder sequence answers each request. I validated parameters at elaboration and kept the code running on Xcelium, Questa and VCS."

What's next in the course

All three agents are done, so the environment now works with transactions instead of signals. The next section revisits the agents with an "advanced technique": the `uvm_ext_pkg` base library that removes the APB/MD copy-paste. Your project already contains its final form.

---

