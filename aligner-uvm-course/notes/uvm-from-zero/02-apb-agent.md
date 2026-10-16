# Lecture companion: APB agent

> Card-by-card notes for Cristian Slav's course. Diagrams and toys are in `pages/uvm-from-zero.html`.

Chapter · the APB agent (16 videos)

## Building the APB agent

These cards merge each lecture with its practice video. The code shown is the finished version from your own `cfs_apb_pkg.sv` and `cfs_apb_if.sv`. By the end of this chapter you've written about 1200 lines: a complete, reusable agent for a standard protocol. The lecturer points out that companies value exactly this skill.

*[Diagram: The finished APB agent. Open the HTML page to see it.]*

The agent's blueprint. Each label points to the card that builds that part.

---

A1

## Agent infrastructure and config\_db

Interface, agent config, getting the interface to a class · lecture + practice

Key idea

An interface is a static, hardware-like thing: it can't be created inside a class. So it's instantiated in the **testbench module**, and a **virtual interface** (a pointer to it) is passed to the agent through `uvm_config_db`, a key–value store parameterized by the value's type.

```systemverilog
// testbench.sv: context is null because a module is not a component
uvm_config_db#(virtual cfs_apb_if)::set(null, "uvm_test_top.env.apb_agent", "vif", apb_if);
//                                       ctx    instance path (who may read)  key    value

// in the agent (connect_phase): context = this, path = "" (myself)
if(!uvm_config_db#(virtual cfs_apb_if)::get(this, "", "vif", vif))   // returns 1/0
  `uvm_fatal("NO_VIF", "Could not get the virtual interface")
else
  agent_config.set_vif(vif);
```

> Interactive: Try it · write the set() call from anywhere. Open the HTML page to use it.

**The catch the lecturer warns about.** If the testbench sets `bus_width = 32` and the test sets `bus_width = 64` for the same component, which value does `get()` return? **During build**, the set from the **higher context** wins (testbench beats test), so you get 32. **During run**, the **last** set wins. "It might cause you to lose a lot of debug time." Debug with `+UVM_CONFIG_DB_TRACE`.

From the practice video

- Agents for standard protocols use `cfs_apb_…`, with no DUT name, because they'll be reused across projects.
- Bus widths are `` `define ``s guarded by `` `ifndef `` so another project can override them. Parameters would be more flexible but much more complex.
- The interface file is included **outside** the package: interfaces can't live inside packages.
- Reset moves into the APB interface (`apb_if.preset_n`) so tests can drive reset later.
- The agent config here is a **component**, not an object. That's the lecturer's preference, so it can use phases and overrides. Both styles are common.
- The vif is `local` with a getter/setter. The setter fatals if it's set twice, and `start_of_simulation_phase` fatals if it was never set: "The APB virtual interface is not configured".
- `cfs_apb_agent` extends `uvm_agent` rather than plain `uvm_component`.

**Q: "Why can't a class instantiate an interface? How does the agent reach the pins?"**

Interfaces are elaborated statically, like modules, while classes are created dynamically at run time. The testbench instantiates the interface and connects it to the DUT, then stores a `virtual` interface handle in `uvm_config_db`. The agent gets it with `get()` and hands it to the driver and monitor (here via the agent config).

**Q: "Explain the four arguments of uvm\_config\_db::set."**

**context**: the component the path is relative to (`null` from a module, else usually `this`). **inst\_name**: the hierarchical path of the components allowed to read it, with wildcards allowed. **field\_name**: the key string. **value**: the data, typed by the class parameter. The reader's type, path and key must all match, or `get` returns 0.

**Q: "Two set() calls for the same field from different levels: which wins?"**

During build, a set() from higher in the hierarchy wins: the top module (null context), then the test, then the env. That's what lets a test override an env default. After build (e.g. in run phase), the most recent set() wins. Check with `+UVM_CONFIG_DB_TRACE`, and avoid setting the same field from several levels.

**Q: "Agent config as uvm\_object or uvm\_component?"**

An object is lighter: created anywhere, passed by config\_db, no phases. That's the most common style. A component (this project) gets phases, so it can validate settings in `start_of_simulation` and police knobs in `run_phase`, and it can be factory-overridden per instance easily. The cost is that it's part of the hierarchy and must be created in build. Either is fine if you can justify it.

**Q: "Why getters and setters instead of public fields?"**

The setter can validate (vif set only once; stuck threshold ≥ 2) and keep things in sync (has\_checks copied to the interface). Public fields allow silent misuse. It's the same encapsulation argument as in any OOP language.

---

A2

## The APB driving item

What a master can control, as a randomizable class · lecture + practice

**How to choose the fields:** look at the APB transfer and remove what the master doesn't drive. PRDATA, PREADY and PSLVERR come from the slave. PSEL and PENABLE always follow the same pattern, so they're the driver's job, not the item's. What's left: **direction, address, write data**, plus two timing knobs, **pre\_drive\_delay** and **post\_drive\_delay** (clock cycles the agent keeps the bus busy).

*[Diagram: Item class inheritance. Open the HTML page to see it.]*

UVM requires driven items to extend `uvm_sequence_item`. The extra `item_base` layer holds the fields shared with the monitor's item, which is added in A6.

```systemverilog
typedef enum bit {CFS_APB_READ = 0, CFS_APB_WRITE = 1} cfs_apb_dir;   // matches PWRITE

class cfs_apb_item_drv extends cfs_apb_item_base;      // base has: rand dir, addr, data
  rand int unsigned pre_drive_delay;
  rand int unsigned post_drive_delay;

  constraint pre_drive_delay_default  { soft pre_drive_delay  <= 5; }   // "_default" = soft
  constraint post_drive_delay_default { soft post_drive_delay <= 5; }   // tests can override

  `uvm_object_utils(cfs_apb_item_drv)              // OBJECT utils, not component
  function new(string name = "");                  // objects: name only, no parent
    super.new(name);
  endfunction

  virtual function string convert2string();        // print data only for writes
    string result = super.convert2string();
    if(dir == CFS_APB_WRITE) result = $sformatf("%s, data: %0x", result, data);
    return $sformatf("%s, pre_drive_delay: %0d, post_drive_delay: %0d", result, pre_drive_delay, post_drive_delay);
  endfunction
endclass

// quick check in a test: create and randomize 10 times
cfs_apb_item_drv item = cfs_apb_item_drv::type_id::create("item");   // no parent for objects
void'(std::randomize(item));     // the video's approach; prefer item.randomize() and check it
```

Facts to remember

- Objects: `` `uvm_object_utils `` + `new(string name)`. Components: `` `uvm_component_utils `` + `new(string name, uvm_component parent)`.
- Unconstrained `int unsigned` delays would be huge (billions of cycles), hence the soft limits.
- Types (direction enum, address and data widths) go in a separate `cfs_apb_types.sv` for readability.
- Bug from the video: data printed in decimal, fixed to hex. Print the way engineers read it.

**Q: "How do you decide what goes in a sequence item?"**

Everything the stimulus side controls and nothing the protocol fixes. Remove signals driven by the other side and signals whose behaviour is fully determined by the protocol (PSEL/PENABLE). Add timing knobs (delays) so tests can create back-to-back and idle traffic. Response fields go in the monitor item, not the drive item.

**Q: "Soft vs hard constraints?"**

A soft constraint is a default that's dropped if it conflicts with another constraint, e.g. a test's inline `with {pre_drive_delay == 50;}`. A hard constraint can't be overridden. A conflict means randomize fails. Use soft for preferences and hard for legality and physical limits.

**Q: "Why separate drive and monitor items?"**

They carry different information. The driver needs intent (delays); the monitor records what happened (response, length, gap since the previous item). A shared base avoids duplicating address, direction and data. It also stops anyone from accidentally checking intent against intent.

**Q: "What is convert2string for, versus print()/sprint()?"**

`convert2string` is a user-written, compact one-line summary for logs. `print`/`sprint` use UVM's printer and field macros to produce tables, which are verbose and slower. Most teams implement `convert2string` by hand.

---

A3

## The sequence mechanism

Sequence → sequencer → driver, step by step · lecture + practice

This is the most-asked UVM topic in interviews. The test calls `seq.start(sequencer)`, which calls the sequence's `body()`. Inside body, `start_item` + `finish_item` send an item to the sequencer. The driver pulls it with `get_next_item` and releases it with `item_done`. The driver's `seq_item_port` is connected to the sequencer's `seq_item_export` in the agent's connect\_phase.

> Interactive: Try it · the handshake, one call at a time. Open the HTML page to use it.

```systemverilog
// your cfs_apb_pkg.sv
class cfs_apb_sequence_base extends uvm_sequence#(.REQ(cfs_apb_item_drv));
  `uvm_declare_p_sequencer(uvm_ext_sequencer#(.ITEM_DRV(cfs_apb_item_drv)))   // typed p_sequencer
  ...
endclass

class cfs_apb_sequence_simple extends cfs_apb_sequence_base;   // one item, set by the caller
  rand cfs_apb_item_drv item;                                  // created in new(), randomized with the sequence
  virtual task body();
    `uvm_send(item)          // NOT `uvm_do: that would re-randomize and lose the caller's constraints
  endtask
endclass

class cfs_apb_sequence_rw extends cfs_apb_sequence_base;       // read an address, then write it
  rand cfs_apb_addr addr;
  rand cfs_apb_data wr_data;
  virtual task body();
    cfs_apb_item_drv item;
    `uvm_do_with(item, { dir == CFS_APB_READ;  addr == local::addr; })   // local:: = the SEQUENCE's addr
    `uvm_do_with(item, { dir == CFS_APB_WRITE; addr == local::addr; data == wr_data; })
  endtask
endclass

class cfs_apb_sequence_random extends cfs_apb_sequence_base;   // a sequence that runs sequences
  rand int unsigned num_items;
  constraint num_items_default { soft num_items inside {[1:10]}; }
  virtual task body();
    for(int i = 0; i < num_items; i++) begin
      cfs_apb_sequence_simple seq = cfs_apb_sequence_simple::type_id::create("seq");
      `uvm_do(seq)           // create (already done) + randomize + start on m_sequencer
    end
  endtask
endclass
```

**Two bugs the lecturer hits on purpose.**  
1. `` `uvm_do(item) `` inside the simple sequence: the test constrained `addr == 'h222`, but the macro **re-randomized** the item and the address came out random. Use `` `uvm_send `` when the item is already randomized.  
2. `addr == addr` inside a `with {}` block: both names resolve to the **item's** field, so the constraint is always true and is ignored. `local::addr` forces the sequence's field. "A very common problem and very difficult to debug." (`data == wr_data` needs no `local::` because the item has no `wr_data`.)

More from the videos

- `uvm_sequence#(REQ, RSP)`: REQ is the item type sent; RSP (responses back) isn't used in this project.
- `m_sequencer` is set automatically by `start()`. `` `uvm_declare_p_sequencer `` adds `p_sequencer`, the same pointer cast to your sequencer type.
- Active vs passive is a config field (`uvm_active_passive_enum`, default UVM\_ACTIVE). Only active agents create the driver and sequencer.
- Macros: `` `uvm_do `` = create + randomize + send. `` `uvm_do_with `` adds inline constraints. `` `uvm_send `` = send only. Read their source in UVM's `macros/uvm_sequence_defines.svh`.
- Three sequences in a `fork…join` on one sequencer interleave item by item: the sequencer **arbitrates**. Print `item.get_full_name()` in the driver to see which sequence sent what.

**Q: "Walk me through what happens when finish\_item is called."**

`start_item` waits for the sequencer to grant this sequence (arbitration). Then you randomize or set fields. `finish_item` hands the item to the sequencer and blocks. The driver's pending `get_next_item` returns that item. The driver drives it and calls `item_done`, which unblocks `finish_item`, and body continues to the next item.

**Q: "`uvm\_do vs `uvm\_send vs `uvm\_do\_with?"**

`` `uvm_do ``: create, randomize, start/finish. `` `uvm_do_with ``: the same with inline constraints. `` `uvm_send ``: just start/finish, so it keeps whatever values the item already has. Using `` `uvm_do `` on an item a caller already constrained silently discards those constraints. Many teams avoid the macros and write start\_item/randomize/finish\_item explicitly so it's clear what happens.

**Q: "What does local:: do in an inline constraint?"**

Inside `obj.randomize() with {…}`, names resolve to the object being randomized first. `local::x` forces `x` to resolve in the calling scope (the sequence). Without it, `addr == addr` compares the item's addr with itself, which is always true and constrains nothing.

**Q: "m\_sequencer vs p\_sequencer?"**

`m_sequencer` is the generic `uvm_sequencer_base` handle, always set by `start()`. `p_sequencer` exists only if you use `` `uvm_declare_p_sequencer(T) ``. It's the same object, cast to `T`, so you can reach custom fields (e.g. the virtual sequencer's handles to other sequencers).

**Q: "Several sequences on one sequencer: what decides order, and how do you keep one atomic?"**

Arbitration per item: default FIFO (request order), or weighted, random, strict priority (`set_arbitration`). To keep several items uninterrupted, `lock()` or `grab()` the sequencer, then `unlock`/`ungrab`. In the video's fork, the read and write of the rw sequence get separated by other sequences' items.

**Q: "Active vs passive agent?"**

Active creates sequencer + driver + monitor and drives the bus. Passive has only the monitor (and coverage) and just observes, e.g. at SoC level where a CPU or another block drives that bus. Controlled by `get_is_active()` or a config field like here.

---

A4

## The APB driver

Turning an item into a real APB transfer · lecture + practice

The structure prepares for reset handling (A8): `run_phase` calls `drive_transactions()` (initialize signals, then loop forever), which calls `drive_transaction(item)` once per item. The driver reaches the interface through a pointer to the agent config, connected in the agent's connect\_phase.

```systemverilog
protected virtual task drive_transaction(cfs_apb_item_drv item);
  cfs_apb_vif vif = agent_config.get_vif();
  for(int i = 0; i < item.pre_drive_delay; i++) @(posedge vif.pclk);   // 1. idle before

  vif.psel   <= 1;                                     // 2. SETUP phase
  vif.pwrite <= bit'(item.dir);
  vif.paddr  <= item.addr;
  if(item.dir == CFS_APB_WRITE) vif.pwdata <= item.data;
  @(posedge vif.pclk);

  vif.penable <= 1;                                    // 3. ACCESS phase
  @(posedge vif.pclk);
  while(vif.pready !== 1) @(posedge vif.pclk);         // 4. wait states until PREADY

  vif.psel <= 0; vif.penable <= 0; vif.pwrite <= 0;   // 5. back to idle defaults
  vif.paddr <= 0; vif.pwdata <= 0;

  for(int i = 0; i < item.post_drive_delay; i++) @(posedge vif.pclk);  // 6. idle after
endtask
```

Facts to remember

- "Always use **non-blocking** assignments when driving signals from the driver." This ensures the DUT samples correctly at the clock edge.
- Initialize all master signals to 0 before the first item. Otherwise they're X until the first transfer, which you can see on the waveform.
- The waveform check from the video: post-drive delay 4 + next pre-drive delay 3 = **7 idle cycles** between transfers. Verify your own driver this way.
- Random addresses mostly hit unmapped space, so the DUT correctly returns PSLVERR. Constrain to 0x0 (CTRL) and 0xC (STATUS): reading STATUS is OK, writing STATUS gives an error. That's two spec rules seen on the first run.
- EDA Playground: tick *Open EPWave after run* → Get Signals → `dut` → pick signals.

**Q: "Why non-blocking assignments in the driver?"**

The DUT's flops sample on the same clock edge the driver wakes up on. A blocking write could land before or after the DUT samples, depending on process order: a race. NBAs update in the NBA region after all active-region sampling, so the DUT always sees the previous value at the edge. Clocking blocks formalize the same thing.

**Q: "Why split drive\_transactions and drive\_transaction?"**

The outer task owns the loop and the process that reset can kill and restart. The inner task owns one protocol transfer. Subclasses override only `drive_transaction` for protocol variants, and the reset plumbing stays in one place. That's exactly how the later `uvm_ext_driver` base class is built.

**Q: "How would you add a response back to the sequence?"**

Clone the request, fill in response fields (PRDATA, PSLVERR), call `set_id_info(req)`, then `item_done(rsp)` or `seq_item_port.put(rsp)`. The sequence calls `get_response(rsp)`. This driver doesn't, so RAL frontdoor calls always return OK and bus errors are judged by the predictor instead (see the senior course).

---

A5

## APB protocol checks

5 rules: 4 as assertions in the interface, 1 in the monitor · practice video

| # | Rule | Where | How |
| --- | --- | --- | --- |
| 1 | PENABLE asserted in the 2nd cycle of the transfer | interface | setup phase → PENABLE==0 now, and `|=>` PENABLE==1 next cycle |
| 2 | PENABLE deasserted at the end of the transfer | interface | access phase and PREADY `|=>` PENABLE==0 |
| 3 | Master signals constant during the transfer | interface | `$stable` on PENABLE, PWRITE, PADDR, PWDATA (writes only) during access |
| 4 | No unknown (X/Z) values | interface | `$isunknown`, gated: PSEL always; others only when PSEL=1; PRDATA only on OK reads with PREADY |
| 5 | A transfer can't last forever | monitor | error when length ≥ `stuck_threshold` (1000; setter refuses < 2) |

```systemverilog
sequence setup_phase_s;     // first cycle: PSEL rose, OR back-to-back after a completed transfer
  (psel == 1) && (($past(psel) == 0) || ($past(psel) == 1 && $past(pready) == 1));
endsequence
sequence access_phase_s;
  (psel == 1) && (penable == 1);
endsequence

property penable_entering_access_phase_p;
  @(posedge pclk) disable iff(!preset_n || !has_checks)
  setup_phase_s |=> penable == 1;            // |=> = "in the NEXT cycle"
endproperty
PENABLE_ENTERING_SETUP_PHASE_A : assert property(penable_entering_access_phase_p) else
  $error("PENABLE when entering \"Access Phase\" did not became 1");   // $error, not `uvm_error
```

Design decisions worth explaining in an interview

- **has\_checks lives in two places** (agent config and interface) and is kept in sync: the config's setters push the value to the interface, and the config's run\_phase reports an error if someone changes the interface copy directly.
- **`$error` instead of `` `uvm_error ``** in interfaces: the same assertions can be reused in **formal** tools, which may not load the UVM package.
- **Prove every assertion can fail:** the lecturer breaks the driver on purpose (PENABLE in setup, no PENABLE in access, flipping PWRITE) and watches each assertion fire. An assertion never seen failing might be checking nothing.
- `+UVM_MAX_QUIT_COUNT=1` stops the simulation at the first error, so you debug the cause, not the echoes.

**Q: "|-> vs |=>?"**

`a |-> b`: if a matches, b must hold in the same cycle. `a |=> b`: b must hold in the next cycle (same as `a |-> ##1 b`). Rule 1 uses both: in setup, PENABLE==0 now (`|->`) and ==1 next (`|=>`).

**Q: "Why does the setup-phase sequence need the back-to-back case?"**

With back-to-back transfers PSEL never drops, so "PSEL rose" doesn't mark the new setup cycle. The second term catches "PSEL was high and PREADY was high last cycle", i.e. the previous transfer just ended and a new one starts now. Miss it and every back-to-back transfer escapes the PENABLE checks.

**Q: "Why are some X-checks gated by PSEL?"**

The protocol only cares about address and data while a transfer is happening. X on PADDR when idle is legal, and flagging it would be noise. PSEL itself must never be X. PRDATA only matters on a successful read once PREADY is high. The skill is knowing when each signal must be valid.

**Q: "Where should a check live: assertion, monitor or scoreboard?"**

Cycle-level signal rules → assertions in the interface (reusable, formal-friendly). Rules needing transaction context or counters (stuck transfer length) → monitor. Data correctness vs a model → scoreboard. Protocol checks belong in the agent so they travel with it to every project.

**Q: "How do you know an assertion actually works?"**

Make it fail: inject the violation (as the lecturer does in the driver), see it fire, then revert. Add `cover property` for the antecedent so you know it was evaluated with real traffic. A vacuously passing assertion is a common hole.

---

A6

## The APB monitor

Pins back into items, broadcast to the environment · lecture + practice

The monitor item adds what only an observer can know: **response** (PSLVERR), **length** of the transfer in cycles (minimum 2 for APB), and **prev\_item\_delay** (idle cycles since the previous transfer). Direction, address and data move to `item_base`, shared with the drive item. For data, the monitor picks PWDATA on writes and PRDATA on reads.

```systemverilog
uvm_analysis_port#(cfs_apb_item_mon) output_port;   // created in new(): output_port = new("output_port", this);

protected virtual task collect_transaction();
  cfs_apb_vif vif = agent_config.get_vif();
  cfs_apb_item_mon item = cfs_apb_item_mon::type_id::create("item");

  while(vif.psel !== 1) begin @(posedge vif.pclk); item.prev_item_delay++; end   // count idle cycles

  item.addr = vif.paddr;  item.dir = cfs_apb_dir'(vif.pwrite);   // setup phase: request info
  item.length = 1;
  if(item.dir == CFS_APB_WRITE) item.data = vif.pwdata;

  @(posedge vif.pclk); item.length++;
  while(vif.pready !== 1) begin @(posedge vif.pclk); item.length++; /* + stuck check (A5) */ end

  item.response = cfs_apb_response'(vif.pslverr);              // end of transfer: response info
  if(item.dir == CFS_APB_READ) item.data = vif.prdata;

  output_port.write(item);                                      // broadcast to all subscribers
  @(posedge vif.pclk);                                          // step past this transfer
endtask
```

Facts to remember

- `uvm_monitor` adds nothing to `uvm_component`, but use it anyway: it documents the role and tools recognise it.
- `uvm_analysis_port#(T)`: `write(item)` broadcasts to every connected subscriber (0, 1 or many). It's a function, so it doesn't consume time.
- The video's check: the monitor reports prev\_item\_delay = 7, which matches post 4 + pre 3 from the driver. Use your driver's known values to verify the monitor.
- Bug from the video: `convert2string` forgot to print data. Logs are your first debug tool, so make them complete.

**Q: "Why must the monitor be independent of the driver?"**

It must report what really happened on the pins, including driver bugs and transfers from other masters. It must also work in a passive agent where no driver exists. Taking data from the driver would make the checkers trust the stimulus.

**Q: "Analysis port vs TLM put/get port?"**

An analysis port is one-to-many, non-blocking, with no acknowledgement: perfect for broadcasting observations. Put/get ports are one-to-one and can block (flow control between producer and consumer). Monitors always use analysis ports. A slow consumer adds a `uvm_tlm_analysis_fifo` on its side.

**Q: "Why record length and prev\_item\_delay at all?"**

For coverage. They prove you exercised back-to-back transfers, long idle gaps and wait-state lengths, the timing corners where DUT bugs hide. The monitor measures; coverage decides if it was enough.

**Q: "Where exactly do you sample PRDATA and PSLVERR?"**

In the cycle where PSEL, PENABLE and PREADY are all 1, the transfer's completion. Sampling earlier works with zero wait states but returns stale data with wait states. That's a classic monitor bug, found only if your stimulus has wait states.

---

A7

## APB coverage

A database of what was verified, across all simulations · lecture + practice

The lecture's mental model

Coverage = a set of **tables** filled in as transfers are seen. The tables persist across thousands of simulations, so at the end you know what the whole regression exercised. Agent coverage must be **DUT-independent** so the agent stays reusable.

| Table | SystemVerilog construct | Bins in your code |
| --- | --- | --- |
| direction | `coverpoint item.dir` | READ, WRITE |
| response | `coverpoint item.response` | OKAY, ERR |
| length | coverpoint with ranges | ==2 · [3:10] in 8 bins · >10 · illegal <2 |
| prev\_item\_delay | coverpoint with ranges | 0 (back-to-back) · [1:5] · >5 |
| response × direction | `cross` | 4 combinations |
| direction transitions | `bins t[] = (R,W => R,W)` | RR, RW, WR, WW |
| every PADDR bit was 0 / 1 | wrapper component × 2 | 16 indices each |
| every PWDATA / PRDATA bit was 0 / 1 | wrapper component × 4 | 32 indices each |
| reset during a transfer | `cover_reset` on PSEL at reset | 0, 1 |

```systemverilog
`uvm_analysis_imp_decl(_item)                      // creates class uvm_analysis_imp_item
uvm_analysis_imp_item#(cfs_apb_item_mon, cfs_apb_coverage) port_item;

covergroup cover_item with function sample(cfs_apb_item_mon item);   // custom sample() argument
  option.per_instance = 1;                         // separate numbers per agent instance
  direction : coverpoint item.dir;
  ...
  response_x_direction : cross response, direction;
endgroup

function new(string name = "", uvm_component parent);
  super.new(name, parent);
  cover_item = new();                              // covergroups are built in the constructor
  cover_item.set_inst_name($sformatf("%s_%s", get_full_name(), "cover_item"));  // name used in the vPlan
endfunction

virtual function void write_item(cfs_apb_item_mon item);   // "_item" suffix comes from the macro
  cover_item.sample(item);
  for(int i = 0; i < `CFS_APB_MAX_ADDR_WIDTH; i++)          // one item samples 16 address bins
    if(item.addr[i]) wrap_cover_addr_1.sample(i); else wrap_cover_addr_0.sample(i);
endfunction
```

Clever tricks from the practice video

- **Why a wrapper component for bit coverage?** One item must sample many bins (every address bit), and the six tables differ only in size. A covergroup can't take a class parameter for its range, so it's wrapped in a component parameterized by `MAX_VALUE_PLUS_1` and instantiated 6 times.
- **Why a non-parameterized virtual base for the wrapper?** Each parameter value is a different class, so you can't `$cast` to "any wrapper". A virtual base with pure virtual `sample()`/`coverage2string()` lets `get_children()` + one `$cast` find them all.
- Coverage needs the compile option `-coverage functional` on Xcelium, otherwise you get 0% plus a tool warning.
- `coverage2string()` printing percentages is for EDA Playground only. Real projects use the vendor's coverage GUI.
- **Verification plan:** coverage tables are organised into a tree (vPlan: XML, mind map, or Cadence's vPlanx), with each leaf mapped to a covergroup instance name. There's no standard; every company does it differently. Watch table sizes: crosses grow multiplicatively.

**Q: "Coverpoint, cross, transition: give an example of each."**

Coverpoint: values of one field (direction READ/WRITE). Cross: combinations of coverpoints (a write that got an error). Transition: order over consecutive samples (a read followed by a write). Crosses multiply bin counts, so filter with `ignore_bins`/`binsof` and cross only what matters to the spec.

**Q: "Why cover address bits rather than address values in an agent?"**

The agent doesn't know the DUT's address map. Toggling every bit to 0 and 1 proves every address line was exercised, which is protocol-level and reusable. Covering specific registers belongs in DUT-level (environment or RAL) coverage.

**Q: "What does option.per\_instance do?"**

It keeps coverage per covergroup instance instead of merged per type. With two agents of the same type (e.g. MD RX and MD TX) you can see which interface missed a bin. You also name instances (`set_inst_name`) to map them in the verification plan.

**Q: "What's a verification plan and how does coverage connect to it?"**

A tree of features from the spec, each leaf with how it's checked and which coverage proves it. Leaves map to covergroups, coverpoints or assertions. Merged regression coverage is annotated back onto the tree, so sign-off reviews show per-feature percentages, not one meaningless total.

**Q: "Why cover 'reset during a transfer'?"**

Reset mid-transfer is a classic corner: the DUT must abort cleanly and the testbench must not hang or mis-report. If coverage never sees it, you have no evidence it was tested. In the video it stays 50% until a test actually injects reset during an access.

---

A8

## Reset handling in the agent

Stop, clean up, restart · lecture + practice

Without reset handling, the driver keeps driving through reset and the monitor stitches the start of an old transfer to the end of a new one. In the video it reports a transfer to `B1A4` that never completed. Wanted behaviour: at reset the driver stops immediately and drives defaults, the sequencer is cleared, the monitor drops its half-collected item, and all restart when reset ends.

*[Diagram: Agent reset loop calls handle\_reset on every child implementing the interface class. Open the HTML page to see it.]*

Each component declares `implements cfs_apb_reset_handler`. The agent never hard-codes which children need reset. Note: `get_children()` returns sub-**components** in the hierarchy, not subclasses.

```systemverilog
// driver: restartable loop
virtual task run_phase(uvm_phase phase);
  forever begin
    fork
      begin
        wait_reset_end();          // don't drive while in reset
        drive_transactions();      // saves process::self(); runs forever
        disable fork;              // kill anything drive_transactions spawned
      end
    join
  end
endtask

virtual function void handle_reset(uvm_phase phase);
  if(process_drive_transactions != null) begin
    process_drive_transactions.kill();             // stop mid-transfer, immediately
    process_drive_transactions = null;
  end
  vif.psel <= 0; vif.penable <= 0; ...             // signals to their defaults
endfunction

// sequencer: forget the half-finished handshake
virtual function void handle_reset(uvm_phase phase);
  int objections_count;
  stop_sequences();                                 // kill running sequences, clear the queue
  objections_count = uvm_test_done.get_objection_count(this);
  if(objections_count > 0)
    uvm_test_done.drop_objection(this, "Dropping objections at reset", objections_count);
  start_phase_sequence(phase);                      // restart the default sequence, if any
endfunction
```

**Problems hit in the video, in order:**  
1. **X on PSEL at 5 ns**: the first clock edge came before reset was asserted, and the driver now initializes signals only *at* reset. Fixed by asserting reset earlier (3 ns) or initializing at time 0.  
2. **"get\_next\_item called twice without item\_done"**: the killed driver never called item\_done. Fixed by resetting the sequencer too.  
3. **Test ended right after reset**: resetting the sequencer also ended the test's sequences. The test must restart traffic after reset.  
4. **Monitor reported a phantom transfer**: fixed by killing its collect process at reset.

Facts to remember

- Reset **start** is detected asynchronously (`@(negedge preset_n)`). Reset **end** is detected synchronously (wait for a clock edge with reset released).
- `process::self()` inside a fork gives a handle you can `kill()` later.
- An **interface class** can be implemented by any number of classes alongside their normal parent: SystemVerilog's answer to multiple inheritance.
- The test injects reset mid-transfer by waiting for the 3rd rising edge of PSEL, then 11 ns, then holding reset for 4 clocks.

**Q: "How does your agent handle reset in the middle of a transfer?"**

The agent's run\_phase loops: wait for reset assertion (async), call `handle_reset` on every child implementing the reset-handler interface class, wait for release (sync). The driver kills its drive process and drives idle values. The sequencer stops sequences and drops stray objections. The monitor kills its collect process. Coverage samples "transfer in progress at reset". After release, driver and monitor restart their loops.

**Q: "Why must the sequencer be reset too?"**

The driver was killed between `get_next_item` and `item_done`, so the sequencer still thinks an item is outstanding. The next `get_next_item` errors ("called twice without item\_done") or the sequence hangs. `stop_sequences()` clears that state.

**Q: "What is an interface class and why use it here?"**

A class with only pure virtual methods that other classes `implements`, in addition to their one `extends`. Driver, monitor, sequencer and coverage have different UVM parents but share a `handle_reset()` contract. The agent loops over children, `$cast`s to the interface class, and calls it. Adding a new resettable child needs no agent change.

**Q: "Why not use UVM's reset\_phase?"**

Run-time sub-phases assume reset happens once at the start and are awkward to jump back to. A mid-test reset needs every component to react at any time. An event-driven loop on the reset signal handles any number of resets and works with VIPs that don't use sub-phases. Most teams do it this way.

**Q: "process::kill vs disable fork?"**

`kill()` terminates one process you hold a handle to, from anywhere (e.g. from the reset function). `disable fork` terminates all child processes of the current process, used here to clean up anything `drive_transactions` might have forked, so no zombie threads keep driving after reset.

---

A9

## APB agent: what you can now say in an interview

Conclusions video

architecture

#### UVM agent structure

Config, sequencer, driver, monitor, coverage; active/passive.

stimulus

#### Items and sequences

Drive vs monitor items; simple, read-write and random sequences; macros and their traps.

observation

#### Collecting transactions

Monitor timing, response sampling, analysis ports.

checks

#### Protocol checks from a spec

Reading the APB spec and turning rules into SVA plus monitor checks.

coverage

#### Protocol coverage

Coverpoints, crosses, transitions, bit-toggle wrappers, reset coverage, the vPlan.

robustness

#### Reset handling

Killable processes, sequencer cleanup, interface classes.

Interview line

"I built a complete APB master agent from scratch, about 900 lines of classes plus 300 lines of interface assertions: protocol assertions reusable in formal, bit-level and timing coverage, and mid-transfer reset handling through a reset-handler interface class. Then I factored the common code into a base library so the next two agents took a fraction of the time."

Note from the video

From here on the practice projects put the whole APB agent in one file (`cfs_apb_pkg.sv`) only to keep EDA Playground's file list short. In a real project, keep one class per file.

---

