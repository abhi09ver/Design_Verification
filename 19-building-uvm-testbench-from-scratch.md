# Challenge 19: Building a UVM Testbench From Scratch — Order, Structure, and a Working Skeleton

> **Level:** Fresher → Senior DV interview
> **Topics:** bring-up order, file/package structure, interface + virtual interface, transaction, driver/sequencer/monitor/agent, independent reference model, scoreboard, coverage, base test, objections, reset, regression scripts
> **Related:** [01](01-uvm-config-db-phasing-trap.md), [03](03-verification-ip-reuse.md), [05](05-virtual-sequences.md), [07](07-uvm-pillars-phasing-factory-config-db.md), [16](16-uvm-tlm-ports-exports-fifos.md), [18](18-coverage-architecture.md)

---

## 1. The Post (summary)

A LinkedIn post gives a "roadmap" from a blank testbench:

1. A **3-tier hierarchy**: top env → **a sub-env per protocol interface** → agent; pass bus width etc. via `config_db`; "VCS and Xcelium both honor the same lifecycle".
2. Driver implements "a request → grant handshake" with a transaction class that "**mirrors Intel's Xeon memory-controller protocol**"; one sequence covers single-beat to bursts.
3. Scoreboard compares DUT output against "**the expected model you derived from the same transaction class**", logging to CSV; add "a **cross to capture illegal address-data combos**"; "**aim for 90%**" coverage before calling the env green.
4. "Run in both VCS and Xcelium to **verify phase alignment**."

The general order (agent → scoreboard → coverage) is right. Several pieces of advice would create a weak testbench.

---

## 2. What's Wrong With the Post

| Claim | Reality |
|---|---|
| A **sub-env for every protocol interface** | Usually overkill. An env contains **agents** (one per interface) + scoreboard + coverage. Sub-envs are for **reusing a whole block env** inside a bigger env (block → SoC, Challenge 03) |
| Transaction "mirrors Intel's Xeon memory-controller protocol" | The transaction models **your DUT's** interface from **its** spec |
| Expected model "**derived from the same transaction class**" | The expected values must come from an **independent reference model** written from the **spec**, not from DUT internals or the same code path. Otherwise the model and the DUT share the same bug and the scoreboard agrees with both |
| Use a **cross** to capture **illegal** combos | Coverage measures, it doesn't check. Illegal combinations are caught by **assertions/scoreboard** (or `illegal_bins` as a bonus) |
| "**90%**" before green | "Green" means: tests pass with checkers active, and coverage reviewed against the plan (Challenges 06, 09) |
| Run on two simulators to "**verify phase alignment**" | Phasing is UVM library behaviour; it's the same on any simulator. If results differ, look for **races** in your code (Challenge 10, Section 7) |
| One sequence "covers everything without rewriting" | Better: a **sequence library** of small sequences (base → read/write → burst → error) composed by tests and virtual sequences |

---

## 3. The Bring-Up Order (what interviewers want to hear)

Build in **small, runnable steps**. Each step compiles and runs before the next starts.

| Step | Build | "Done" when |
|---|---|---|
| 1 | `interface`, `tb_top` with clock/reset, DUT instance | Compiles; reset toggles in waveform |
| 2 | Transaction (`uvm_sequence_item`) | Randomizes, prints |
| 3 | Driver + sequencer + one simple sequence, agent, env, **base test** | One write and one read appear correctly on the waveform |
| 4 | Monitor → analysis port | Monitor prints the same transactions the driver sent |
| 5 | **Reference model + scoreboard** | Smoke test passes; a **deliberately injected bug** makes it fail |
| 6 | Assertions on the interface (`bind`) | Protocol rules checked; covers hit |
| 7 | Functional coverage subscriber | Coverage report generated |
| 8 | Sequence library + test library (random, error, stress) | Tests run from the command line with `+UVM_TESTNAME` |
| 9 | Scripts: compile, run, regression, coverage merge | Nightly regression runs unattended |

**Senior points:**
- **Prove the scoreboard can fail** (step 5) before trusting any pass. A scoreboard that never compares anything passes everything.
- Add **end-of-test checks** (`check_phase`: queues empty, expected count == actual count).

---

## 4. File and Package Structure

```
tb/
├── mem_if.sv                 interface (+ clocking blocks)
├── mem_pkg.sv                package: `include all classes below, in dependency order
│   ├── mem_txn.sv
│   ├── mem_agent_cfg.sv
│   ├── mem_sequencer.sv      (or a typedef)
│   ├── mem_driver.sv
│   ├── mem_monitor.sv
│   ├── mem_agent.sv
│   ├── mem_ref_model.sv
│   ├── mem_scoreboard.sv
│   ├── mem_cov.sv
│   ├── mem_env.sv
│   ├── seq/  mem_base_seq.sv, mem_rw_seq.sv, mem_burst_seq.sv, mem_err_seq.sv
│   └── test/ mem_base_test.sv, mem_smoke_test.sv, mem_rand_test.sv
├── mem_sva.sv                assertions, attached with bind
└── tb_top.sv                 clock, reset, DUT, interface, config_db set, run_test()
```
- **Classes go in a package**; interfaces and modules don't (they're not classes).
- Agent pieces (txn, cfg, driver, monitor, agent, sequences) form a reusable **agent package**; DUT-specific scoreboard/env/tests stay outside (Challenge 03).

---

## 5. Working Skeleton (simple memory DUT)

**DUT interface (example spec):** `valid/ready` request with `we`, `addr[7:0]`, `wdata[31:0]`; read data returned with `rvalid`, `rdata[31:0]` one or more cycles later; out-of-range address returns `err`.

### 5.1 Interface and `tb_top`
```systemverilog
interface mem_if (input logic clk, input logic rst_n);
  logic        valid, ready, we, rvalid, err;
  logic [7:0]  addr;
  logic [31:0] wdata, rdata;

  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output valid, we, addr, wdata;
    input  ready, rvalid, rdata, err;
  endclocking
  clocking mon_cb @(posedge clk);
    default input #1step;
    input valid, ready, we, addr, wdata, rvalid, rdata, err;
  endclocking
endinterface

module tb_top;
  import uvm_pkg::*;
  import mem_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  initial begin repeat (5) @(posedge clk); rst_n = 1; end

  mem_if vif(clk, rst_n);
  mem_dut dut(.clk, .rst_n, .valid(vif.valid), .ready(vif.ready), .we(vif.we),
              .addr(vif.addr), .wdata(vif.wdata), .rvalid(vif.rvalid),
              .rdata(vif.rdata), .err(vif.err));

  initial begin
    uvm_config_db#(virtual mem_if)::set(null, "uvm_test_top.env.agt*", "vif", vif);
    run_test();
  end
endmodule
```

### 5.2 Transaction
```systemverilog
class mem_txn extends uvm_sequence_item;
  rand bit        we;
  rand bit [7:0]  addr;
  rand bit [31:0] wdata;
  bit      [31:0] rdata;   // filled by monitor
  bit             err;     // filled by monitor

  constraint c_legal_default { soft addr < 8'hF0; }   // tests may override to hit error range

  `uvm_object_utils_begin(mem_txn)
    `uvm_field_int(we, UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(wdata, UVM_ALL_ON)
    `uvm_field_int(rdata, UVM_ALL_ON)
    `uvm_field_int(err, UVM_ALL_ON)
  `uvm_object_utils_end
  function new(string name = "mem_txn"); super.new(name); endfunction
endclass
```
(Field macros are convenient; many teams hand-write `do_copy`/`do_compare`/`convert2string` for speed and control.)

### 5.3 Driver (pull from sequencer, drive through clocking block)
```systemverilog
class mem_driver extends uvm_driver #(mem_txn);
  `uvm_component_utils(mem_driver)
  virtual mem_if vif;
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mem_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.valid <= 0;
    wait (vif.rst_n);
    forever begin
      seq_item_port.get_next_item(req);
      @(vif.drv_cb);
      vif.drv_cb.valid <= 1;
      vif.drv_cb.we    <= req.we;
      vif.drv_cb.addr  <= req.addr;
      vif.drv_cb.wdata <= req.wdata;
      do @(vif.drv_cb); while (!vif.drv_cb.ready);   // hold until accepted
      vif.drv_cb.valid <= 0;
      seq_item_port.item_done();
    end
  endtask
endclass
```
Note: no objections here (the test owns them, Challenge 01).

### 5.4 Monitor (independent of the driver; sees only pins)
```systemverilog
class mem_monitor extends uvm_monitor;
  `uvm_component_utils(mem_monitor)
  virtual mem_if vif;
  uvm_analysis_port #(mem_txn) ap;
  mem_txn pending_rd[$];

  function new(string name, uvm_component parent); super.new(name, parent); ap = new("ap", this); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual mem_if)::get(this, "", "vif", vif)) `uvm_fatal("NOVIF", "")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.valid && vif.mon_cb.ready) begin
        mem_txn t = mem_txn::type_id::create("t");          // new object per txn (Challenge 16)
        t.we = vif.mon_cb.we; t.addr = vif.mon_cb.addr; t.wdata = vif.mon_cb.wdata;
        if (t.we) ap.write(t); else pending_rd.push_back(t);
      end
      if (vif.mon_cb.rvalid && pending_rd.size() > 0) begin
        mem_txn t = pending_rd.pop_front();
        t.rdata = vif.mon_cb.rdata; t.err = vif.mon_cb.err;
        ap.write(t);                                          // read published when complete
      end
    end
  endtask
endclass
```
(Assumes in-order read responses and no write response channel. Adapt to your spec. The `@(vif.mon_cb)` loop is checked every cycle, so an accept and a response in the same cycle both get handled.)

### 5.5 Agent and config
```systemverilog
class mem_agent_cfg extends uvm_object;
  `uvm_object_utils(mem_agent_cfg)
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  function new(string name = "mem_agent_cfg"); super.new(name); endfunction
endclass

class mem_agent extends uvm_agent;
  `uvm_component_utils(mem_agent)
  mem_agent_cfg cfg;
  uvm_sequencer #(mem_txn) sqr;
  mem_driver  drv;
  mem_monitor mon;
  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(mem_agent_cfg)::get(this, "", "cfg", cfg)) cfg = mem_agent_cfg::type_id::create("cfg");
    mon = mem_monitor::type_id::create("mon", this);
    if (cfg.is_active == UVM_ACTIVE) begin
      sqr = uvm_sequencer#(mem_txn)::type_id::create("sqr", this);
      drv = mem_driver::type_id::create("drv", this);
    end
  endfunction
  function void connect_phase(uvm_phase phase);
    if (cfg.is_active == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
```

### 5.6 Independent reference model + scoreboard
```systemverilog
class mem_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(mem_scoreboard)
  uvm_analysis_imp #(mem_txn, mem_scoreboard) imp;
  bit [31:0] model_mem [bit [7:0]];        // reference model written from the SPEC
  int n_checked, n_errors;

  function new(string name, uvm_component parent); super.new(name, parent); imp = new("imp", this); endfunction

  function void write(mem_txn t);
    bit exp_err = (t.addr >= 8'hF0);                     // spec: 0xF0–0xFF are unmapped
    if (t.we) begin
      if (!exp_err) model_mem[t.addr] = t.wdata;
      return;
    end
    n_checked++;
    if (t.err != exp_err)
      begin n_errors++; `uvm_error("SB", $sformatf("addr %0h: err exp %0b got %0b", t.addr, exp_err, t.err)) end
    else if (!exp_err) begin
      bit [31:0] exp = model_mem.exists(t.addr) ? model_mem[t.addr] : 32'h0;   // spec reset value
      if (t.rdata !== exp)
        begin n_errors++; `uvm_error("SB", $sformatf("addr %0h: exp %0h got %0h", t.addr, exp, t.rdata)) end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("reads checked: %0d, errors: %0d", n_checked, n_errors), UVM_NONE)
    if (n_checked == 0) `uvm_error("SB", "scoreboard checked nothing")   // catch silent passes
  endfunction
endclass
```
The model encodes **spec rules** (address map, reset value, error range), not DUT internals.

`mem_cov` (used below) is a `uvm_subscriber #(mem_txn)` with a covergroup sampled in `write()`; see Challenge 18, Section 3 for the pattern.

### 5.7 Env, base test, smoke test
```systemverilog
class mem_env extends uvm_env;
  `uvm_component_utils(mem_env)
  mem_agent agt; mem_scoreboard sb; mem_cov cov;
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = mem_agent::type_id::create("agt", this);
    sb  = mem_scoreboard::type_id::create("sb", this);
    cov = mem_cov::type_id::create("cov", this);
  endfunction
  function void connect_phase(uvm_phase phase);
    agt.mon.ap.connect(sb.imp);
    agt.mon.ap.connect(cov.analysis_export);
  endfunction
endclass

class mem_base_test extends uvm_test;
  `uvm_component_utils(mem_base_test)
  mem_env env;
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = mem_env::type_id::create("env", this);
  endfunction
  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction
endclass

class mem_smoke_test extends mem_base_test;
  `uvm_component_utils(mem_smoke_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    mem_rw_seq seq = mem_rw_seq::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.agt.sqr);
    phase.drop_objection(this);
  endtask
endclass
```
Run: `+UVM_TESTNAME=mem_smoke_test +UVM_VERBOSITY=UVM_MEDIUM`

### 5.8 Sequence library
```systemverilog
class mem_base_seq extends uvm_sequence #(mem_txn);
  `uvm_object_utils(mem_base_seq)
  function new(string name = "mem_base_seq"); super.new(name); endfunction
endclass

class mem_rw_seq extends mem_base_seq;           // write then read back same address
  `uvm_object_utils(mem_rw_seq)
  rand int unsigned n = 10;
  function new(string name = "mem_rw_seq"); super.new(name); endfunction
  task body();
    repeat (n) begin
      bit [7:0] a;
      `uvm_do_with(req, { we == 1; })
      a = req.addr;
      `uvm_do_with(req, { we == 0; addr == a; })
    end
  endtask
endclass
// mem_err_seq: `uvm_do_with(req, { addr >= 8'hF0; })  overrides the soft legal constraint
```

---

## 6. Things a Senior Adds Early
- **Reset handling**: driver idles during reset; scoreboard clears its model on reset (or the test avoids mid-test reset until supported).
- **End-of-test**: drain time, scoreboard `check_phase` for outstanding reads.
- **Error-path tests** from day one (unmapped address), not just the happy path (Challenge 13).
- **Reporting**: use `uvm_error`/`uvm_info` (counted in the UVM summary), plus `+UVM_MAX_QUIT_COUNT`. CSV/log export is fine for triage, but the pass/fail must come from UVM error counts.
- **Seed logging** and reproducible command lines.
- **Assertions** on the interface via `bind` (Challenge 10).
- **One regression script** that compiles once and runs many tests/seeds, merges coverage, and summarizes pass/fail.

---

## 7. Likely Follow-ups (with model answers)

**Q. You're given a new DUT and a spec. What do you build first?**
Interface, tb_top and DUT compile with reset; then transaction, driver, sequencer, one directed sequence and a base test, to see one transfer on the waveform. Then monitor, then reference model and scoreboard, proven by injecting a bug. Then assertions, coverage, more sequences and tests, and regression scripts.

**Q. Where do expected values come from?**
An independent reference model written from the spec (SV, or C/C++ via DPI). Never from DUT internals or the same code that generates stimulus.

**Q. How do you know your scoreboard works?**
Inject a bug (force a wrong data bit or skip a write) and confirm it fails; report the number of checks done and fail if zero.

**Q. Sub-env per interface?**
Not by default. An env has one agent per interface. Sub-envs are for reusing a complete block env at a higher level.

**Q. Why does the monitor not get data from the driver?**
The monitor must observe the **pins** independently, so it also works in passive mode and catches cases where the driver and DUT disagree.

---

## 8. Common Fresher Mistakes
- Writing every component before running anything.
- Scoreboard expected values copied from the DUT's behaviour.
- Monitor reading data from the driver instead of the interface.
- No proof that the scoreboard can fail; no "checked nothing" guard.
- Objections in the driver.
- Driving raw signals at the clock edge without clocking blocks (races).

---

## 9. 60-Second Interview Pitch

> "I build in small runnable steps. First the interface with clocking blocks, tb_top with clock, reset and the DUT. Then the transaction, driver, sequencer, a directed sequence and a base test, until one transfer looks right on the waveform. Next a monitor that observes only the pins and publishes completed transactions on an analysis port.
>
> Then the scoreboard, with an independent reference model written from the spec, not from the DUT. I prove it can fail by injecting a bug, and it reports how many checks it made, failing if it made none. After that come interface assertions through bind, a coverage subscriber, a sequence library from base to error and stress sequences, and a test library selected with +UVM_TESTNAME.
>
> Agent components go in a reusable package; the scoreboard, env and tests are DUT-specific. The test owns the objections. And from day one I include error-path tests, reset behaviour and a regression script with seed logging and coverage merge."

---

## 10. Self-Check
- [ ] Can I list the 9 bring-up steps in order?
- [ ] Can I write a driver and monitor that use clocking blocks?
- [ ] Can I explain why the reference model must be independent?
- [ ] Can I prove a scoreboard works?
- [ ] Can I explain package vs. module placement of TB pieces?

---

## 11. Addendum: A Second "TB From Scratch" Post

Several of its structural claims would produce a broken testbench. Compare each with the skeleton in Section 5.

| Claim | Reality |
|---|---|
| `tb_top` "instantiates the DUT, **the UVM environment**, and two clocks (**clk and rst_n**)" | `tb_top` instantiates the **DUT, interface(s), clock and reset**, sets the virtual interface in `config_db`, and calls `run_test()`. The **env is created by the test**, not by `tb_top`. And `rst_n` is a **reset**, not a clock (Section 5.1) |
| The env "builds **three agents (drv, mon, sb)**" | Driver, monitor and scoreboard aren't agents. An **agent** contains driver + sequencer + monitor; the **env** contains agents + scoreboard + coverage (Section 5.5, 5.7) |
| In the **agent's** `connect_phase`, connect "the monitor's **analysis_export** to the scoreboard" | The monitor has an analysis **port**, and the scoreboard lives in the **env**, so that connection is made in the **env's** `connect_phase` (Section 5.7). The agent only connects driver ↔ sequencer |
| The scoreboard is "**a plain SystemVerilog class**" | It's a `uvm_scoreboard` (a `uvm_component`) with analysis imps or FIFOs, so it gets phases, reporting and factory support (Section 5.6) |
| 10,000 random packets give "**statistical confidence**" | Confidence comes from **checkers that can fail** plus **coverage** of the planned scenarios, not packet count (Section 3, step 5) |
| "Clone the **uvm-starter-kit** repo"; view coverage "in **Cadence Incisive**" | Not a known reference repo; Incisive is now Xcelium. Section 5 has a complete skeleton to start from |
| "UVM's phases: build, connect, run, and **extract**" do the heavy lifting | Also `check` and `report` (end-of-test checks live there) (Challenge 07) |

The exercise in the post (4-bit bus, cover all 16 values) is fine as a first step: the coverpoint is `coverpoint bus_val;` with automatic bins for all 16 values.

---

## 12. Worked Review: Two Snippets From a Third "TB From Scratch" Post

This post still contained its generator's template text ("One short sentence. One long descriptive sentence…"), a reminder to read such posts critically. Its "myth vs. reality" list is mostly fine (don't copy a TB blindly; track coverage from the start). Its code isn't.

### 12.1 The transaction class: missing constructor

```systemverilog
class my_trans extends uvm_sequence_item;
  rand bit [31:0] addr, data;
  rand bit        we;
  `uvm_object_utils_begin(my_trans) ... `uvm_object_utils_end
endclass                                   // no new() !
```
`` `uvm_object_utils `` generates a factory `create()` that calls **`new(name)`**. Without a constructor taking a `name` argument, the class only has an implicit `new()` with **no arguments**, so this **doesn't compile**. Always add:
```systemverilog
function new(string name = "my_trans");
  super.new(name);
endfunction
```
(Components need `new(string name, uvm_component parent)`.)

### 12.2 The "protocol check embedded in the monitor"

```systemverilog
property p_write_seq;
  @(posedge vif.clk) disable iff (!vif.rst_n)
  (vif.we && vif.addr == $past(vif.addr)) |-> (vif.data == $past(vif.data));
endproperty
```
Three problems:
1. **Location:** a concurrent assertion **can't be placed in a class** like a monitor. Put it in the interface or a bound checker module (Challenge 08, Section 16).
2. **Wrong rule:** it says "a write to the same address as last cycle must carry the same data". Back-to-back writes to the same address with **different data are normally legal**, so this flags correct behaviour. The post claims it catches "illegal back-to-back writes", but nothing in the property defines what's illegal.
3. **Sloppy antecedent:** `$past(vif.addr)` is compared whether or not the previous cycle was a **valid write**; idle-cycle address values trigger checks too.

If the spec really forbids back-to-back writes to the same address, write **that** rule:
```systemverilog
a_no_b2b_same_addr: assert property (@(posedge clk) disable iff (!rst_n)
  (valid && we) ##1 (valid && we) |-> addr != $past(addr));
```

### 12.3 Other claims
| Claim | Reality |
|---|---|
| `uvm_test` "configures **seeds**" | Seeds come from the simulator command line (Challenge 02, Section 11) |
| Driving stimulus from `initial` blocks "collapses under **race conditions**" | You lose objections, reporting and reuse, which is reason enough. **Races** come from how signals are driven at clock edges (fix: clocking blocks, Challenge 07, Section 3.4), not from skipping phases |
