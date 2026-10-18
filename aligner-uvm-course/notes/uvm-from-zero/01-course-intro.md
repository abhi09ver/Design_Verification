# Lecture companion: Course intro

> Card-by-card notes for Cristian Slav's course. Diagrams and toys are in `pages/uvm-from-zero.html`.

Part 2 · Lecture companion

## Following Cristian Slav's video course

The course *Design Verification with SystemVerilog and UVM Library* builds a 5000+ line UVM environment for the Aligner in lecture/practice pairs. Each card below matches one video. It gives the key ideas as pictures, the facts worth memorising, and the questions an interviewer would ask about that video's topic, with model answers. Watch the video first, then come here.

All 112 videos covered69 cards180+ interview questions7 toys

---

V0

## Course introduction

What the course builds, and what you must already know

goal 1

#### Learn the UVM library

All the main features of the UVM SystemVerilog library, in depth.

goal 2

#### Verify a real design

Build an environment from scratch and find the **hidden bugs** in the Aligner yourself.

format

#### Lecture → practice

20+ hours. Theory video, then a coding video on EDA Playground. Final project: 5000+ lines.

prerequisites

#### Digital design + SV/OOP

SystemVerilog itself isn't taught. Verilog plus any OOP language (C++, Java, Python) is enough to pick it up as you go. Part 1 of this page covers the basics.

Interview angle

This project becomes your answer to **"Tell me about a UVM environment you built."** Interviewers want structure, not a file list. Use the template below, and fill in the numbers from your own run.

**Q: "Walk me through a UVM testbench you built."**

**Shape your answer in 4 parts:** (1) the DUT in one sentence: "an aligner that repacks unaligned byte streams into fixed-size chunks, with APB registers and interrupts". (2) The architecture: one APB agent, two MD agents (master on RX, reactive slave on TX) built on a shared extension library, a reference model that holds the RAL register model, an explicit predictor, a scoreboard, coverage and a virtual sequencer. (3) The tests: register access, random traffic, illegal traffic, and what each one proved. (4) A bug you found and how. End with what you'd improve.

**Q: "Why UVM rather than a plain SystemVerilog testbench?"**

Reuse and scale. Standard component roles (agent, monitor, scoreboard) mean anyone can read the testbench. The factory lets tests change behaviour without editing the environment. Phasing gives a fixed build/connect/run order. config\_db passes settings without hard-wiring. TLM ports decouple components. Agents move unchanged to the next project or to SoC level.

---

V1

## What is design verification?

Where module-level UVM work fits in a chip's life

A chip is printed many times on a round silicon **wafer**. Testing the real chips on the wafer is **post-silicon** verification. This course is about **pre-silicon** verification: checking the RTL code before any wafer exists, when bugs are still cheap to fix.

*[Diagram: Tree of verification types, with the course's path highlighted. Open the HTML page to see it.]*

The highlighted path is this course: **pre-silicon → module level → simulation → SystemVerilog + UVM**.

*[Diagram: Module-level environment: agents, DUT, model, scoreboard. Open the HTML page to see it.]*

Facts to remember

- **DUT** = Device (or Design) Under Test. You may also see **DUV**, Device Under Verification. Same thing.
- **RTL** = Register Transfer Level: the Verilog/VHDL the designers write.
- An **agent** drives and monitors one interface. The **model** computes the correct outputs from the same inputs. The **scoreboard** compares and reports a **DUT error** when they differ. The designer fixes the RTL.
- Verification's goal: find inputs for which the DUT's function is wrong.

**Q: "Pre-silicon vs post-silicon verification?"**

Pre-silicon checks the RTL in simulation, formal or emulation, before tape-out. Bugs are cheap to fix and you have full visibility of every signal. Post-silicon tests the manufactured chip (on the wafer, then packaged). Visibility is limited to pins and debug logic. It catches manufacturing defects and bugs that escaped pre-silicon, and a fix needs a respin. That's why pre-silicon effort is so large.

**Q: "Module-level vs system-level: why do both?"**

Module level gives you full control of a block's inputs, so you can hit corner cases (illegal transfers, FIFO full, counter saturation) quickly. At system level those are hard to reach through other blocks. System level finds integration bugs: wrong connections, address maps, clock/reset interactions, end-to-end flows. Module-level components (agents in passive mode, models, scoreboards) are reused at system level.

**Q: "Simulation vs formal verification?"**

Simulation drives chosen (often random) inputs and checks outputs. It scales to big designs and long scenarios, but only proves the cases you ran. Formal mathematically checks assertions against all possible inputs within bounds. It's exhaustive for small, control-heavy logic (arbiters, protocol rules, the Aligner's legality check) but struggles with deep data paths. Teams use both: formal for small exhaustive properties, simulation for end-to-end data.

**Q: "Why separate the model from the scoreboard?"**

The model predicts; the scoreboard compares. Keeping them apart lets you replace the model (e.g. with a C++ golden model) without touching compare logic, reuse the scoreboard, and tell "prediction bug" apart from "compare bug" when debugging.

---

V2

## The Aligner DUT in depth

Every feature you'll have to verify (27-minute video)

Lecturer's advice

"Go through the datasheet on your own." In a real job nobody explains the DUT to you. Reading the spec and listing every feature is the first task on any project, and interviewers test it: "here's a spec, what would you verify?"

### 1. Lanes, size and offset

Both the RX and TX data buses are 32 bits = 4 byte **lanes** (0 to 3). `size` = how many lanes carry valid bytes, `offset` = the first valid lane.

*[Diagram: All legal size and offset combinations on four lanes. Open the HTML page to see it.]*

The 7 legal combinations. Size 3 is illegal at every offset. Any other combination must be rejected with an error, and your tests must send those too.

### 2. Alignment, controlled by CTRL

`CTRL.SIZE` = bytes per TX transfer, `CTRL.OFFSET` = first TX lane. With OFFSET=2, SIZE=2 the Aligner places the first received byte on lane 2, waits for one more byte, then sends lanes 2–3. With OFFSET=0, SIZE=4, once 5 bytes are inside it must **split** the last RX transfer: send 4 bytes, keep 1 for the next TX transfer. The lecturer calls splitting "an important feature that we will have to verify". Try it in Level 2's candy packer.

### 3. Registers

| Register | Address | Fields | Access | What to remember |
| --- | --- | --- | --- | --- |
| **CTRL** | `0x00` | SIZE, OFFSET, CLR | RW, RW, WO | CLR is write-only: reads always return 0. Writing 1 clears CNT\_DROP. |
| **STATUS** | `0x0C` | CNT\_DROP, RX\_LVL, TX\_LVL | RO | Status only; writing it gives an APB error. |
| **IRQEN** | `0xF0` | 5 enable bits | RW | One enable per interrupt type. |
| **IRQ** | `0xF4` | 5 status bits | W1C | Sticky: stays 1 until you write 1 to it. Writing 0 does nothing. |

### 4. Drop counter

Every illegal RX transfer gets an error response and `STATUS.CNT_DROP` goes up by 1. It's 8 bits, so it **stops at 255** and never wraps to 0. Writing `CTRL.CLR = 1` clears it.

### 5. FIFO levels

Legal RX transfers go into the RX FIFO. The Controller pops them, aligns, and pushes into the TX FIFO. The TX Controller pops and sends. `RX_LVL`/`TX_LVL` count **transactions, not bytes**. Play with it:

> Interactive: Try it · FIFO levels and interrupts. Open the HTML page to use it.

### 6. Interrupts

Five events: CNT\_DROP reached max, TX FIFO became full, TX FIFO became empty, RX FIFO became full, RX FIFO became empty. Each event sets its sticky IRQ bit (W1C). The `irq` output is a **one-cycle pulse**: each event is ANDed with its IRQEN bit, then all five are ORed.

### 7. Register access: APB

A transfer has a **Setup phase** (PSEL=1, PENABLE=0, always one cycle) and an **Access phase** (PSEL=1, PENABLE=1) that lasts until **PREADY=1**. Extra Access cycles are **wait states**. Address, PWRITE and PWDATA must stay constant for the whole transfer. PRDATA and PSLVERR are only valid when PREADY=1.

> Interactive: Try it · APB waveforms. Open the HTML page to use it.

The three APB error cases (memorise)

- Access to an **unmapped address**.
- **Write to STATUS** (read-only register).
- **Illegal SIZE/OFFSET** written to CTRL, e.g. SIZE=3 OFFSET=1 or SIZE=2 OFFSET=1.

The lecture's key scenario: write CTRL = (1,1) → OK. Read → (1,1). Write CTRL = (2,1) → **error**. Read again → **still (1,1)**. A test must prove the errored write changed nothing.

### 8. MD protocol (RX and TX)

A made-up protocol for this course (no online docs). A transfer starts when `valid`=1 and ends when `ready`=1. It can last one cycle (both high together) or longer, in which case valid, data, offset and size must stay constant. `err` is valid when ready=1. The example: RX receives 11, 22, then 33 44 in separate transfers; with SIZE=4, OFFSET=0, TX sends 11 22 33 44 in one transfer.

**Q: "What is a W1C sticky register, and how would you verify it?"**

The bit is set by hardware when an event happens, stays 1 after the condition goes away (sticky), and is cleared only by writing 1 (W1C). Writing 0 does nothing. Verify: trigger the event and read 1; remove the condition and still read 1; write 0 and still read 1; write 1 and read 0; clear while the condition persists and check it doesn't immediately re-set (it's an edge event); re-trigger and check it sets again.

**Q: "Why must your tests send illegal transfers?"**

Rejecting them is a spec feature: error response, drop counter increment, saturation at 255, MAX\_DROP interrupt. Legal-only traffic leaves all of that unverified. Error-handling paths are where bugs hide because designers test them least.

**Q: "After an APB write returns PSLVERR, what do you check?"**

That the register kept its old value: read it back and compare against the value before the failed write. In UVM, the predictor must **not** update the register mirror for an errored access. Otherwise every later prediction is wrong.

**Q: "Do FIFO levels count bytes or transactions? Why does it matter?"**

Transactions. A 2-byte RX transfer adds 1 to RX\_LVL. With CTRL.SIZE=1 it becomes two TX entries, so TX\_LVL grows by 2. Your model must count the same way, or every STATUS read and FIFO-full interrupt prediction will be off.

**Q: "Explain APB setup and access phases, and wait states."**

Setup: PSEL=1, PENABLE=0 for exactly one cycle, with address/direction/data valid. Access: PENABLE=1, and the transfer completes on the first cycle PREADY=1. Each cycle with PREADY=0 is a wait state. Signals must stay stable until completion. The Aligner spec says no more than 5 wait states, which is a good assertion to write.

**Q: "The IRQ output is a pulse but the IRQ register is sticky. How do you check both?"**

Two checks. The register: the model predicts the IRQ bit (set on event, W1C clear) and register reads compare. The pin: on each event, if its IRQEN bit is 1, expect exactly one one-cycle pulse within a small window. If IRQEN is 0, no pulse, but the IRQ bit is still set. Cover every event × enable combination.

---

V3

## Environment architecture

What gets built, and in which order

The course builds the environment in this order. Each step reuses the previous ones, which is also a good order for your own projects.

1. **APB agent**interface (signals) → sequencer + driver (drive transactions) → monitor (collect transactions into a class, broadcast them) → coverage (database of what happened on this interface) → config (tweak the agent).
2. **MD RX and TX agents, together**Same protocol, so common code is written once and inheritance adds the RX (master) and TX (slave) differences.
3. **UVM extension library**After three agents, the shared code becomes a library (`uvm_ext_pkg`) and all agents are rebuilt on it. New agents then take minutes.
4. **Model + register model + predictor**The model predicts the Aligner's outputs from agent data. UVM's register layer models the 4 registers, and the predictor updates and checks them.
5. **Scoreboard**Compares DUT outputs with model outputs and raises errors on differences.
6. **Environment coverage**The full picture of Aligner scenarios, unlike agent coverage, which only knows one interface.
7. **Virtual sequencer**One place to control all agents together from a sequence.
8. **Environment config**Knobs for the whole environment.
9. **Tests + testbench**A base test creates the env; every test inherits from it. The testbench module holds the DUT and starts UVM.

**Q: "Agent coverage vs environment coverage: what's the difference?"**

Agent coverage is protocol-level and reusable: APB read/write, error responses, wait-state lengths, MD sizes and offsets. Environment coverage is DUT-feature level: alignment cases (CTRL setting × RX transfer × split), drop counter saturation, interrupts. Agent coverage proves the bus was exercised. Environment coverage proves the *features* were. You need both.

**Q: "Why a virtual sequencer?"**

Real scenarios coordinate several interfaces: configure CTRL over APB, then send RX traffic, while the TX side applies back-pressure. A virtual sequencer holds handles to all agent sequencers (and, in this project, the model), so one virtual sequence can drive them in order or in parallel.

**Q: "How would you structure two agents for the same protocol, one master and one slave?"**

Common base classes for item, monitor, coverage, config and agent, parameterized where needed (e.g. data width). Then master and slave subclasses for the driver, sequencer and drive item. The monitor is identical on both sides because it only watches. Factory overrides inside each agent pick the right subclasses.

**Q: "What goes in a base test?"**

Creating the environment and anything every test shares: default config, common objections and drain time, a topology print, end-of-test checks. Specific tests extend it and only change stimulus and knobs. That avoids copying env setup into every test.

---

V4

## Environment coding kick-off: lecture

Testbench, run\_test, the 9 phases, base test

### The testbench module needs three things

A clock generator, an initial reset generator, and one call: `run_test()`. That call does two jobs: it **creates the test** and **runs the UVM phases**. You never write `new` for the test yourself.

### Two ways to choose the test

option 1

#### `run_test("cfs_algn_test_reg_access")`

Test name hard-coded in the testbench. To change test you edit and recompile.

option 2 · used in real projects

#### `run_test("")` + `+UVM_TESTNAME=…`

The name comes from a simulator command-line argument (Cadence, Synopsys and Siemens all support it). One compile, many tests, which regressions need.

**Requirement:** every test must inherit (directly or through a base test) from `uvm_test`, or UVM can't create it.

### The 9 UVM phases

Phases are functions UVM calls on every component, one phase at a time across the whole hierarchy. Only `run_phase` is a **task**, because it consumes simulation time. Day to day you use three: build, connect, run.

| # | Phase | Kind | Order | Typical use |
| --- | --- | --- | --- | --- |
| 1 | `build_phase` | function | top-down | Create child components (`type_id::create`), read config. |
| 2 | `connect_phase` | function | bottom-up | Connect ports: monitor → model / scoreboard. |
| 3 | `end_of_elaboration_phase` | function | bottom-up | Hierarchy is final: print topology, sanity checks. |
| 4 | `start_of_simulation_phase` | function | bottom-up | Last setup before time starts; banners. |
| 5 | `run_phase` | **task** | all in parallel | Drive, monitor, run sequences. Time passes. |
| 6 | `extract_phase` | function | bottom-up | Gather final values (coverage, counters). |
| 7 | `check_phase` | function | bottom-up | End-of-test checks: leftover expected items. |
| 8 | `report_phase` | function | bottom-up | Print results. |
| 9 | `final_phase` | function | top-down | Close files, final cleanup. |

The top-down/bottom-up column isn't in the video, but interviewers ask it. Build must go top-down because a parent creates its children. The UVM 1.2 run phase also has 12 optional sub-phases (reset, configure, main, shutdown…) that most teams don't use.

Facts from the lecture

- Every class in the environment diagram is a **component**: it inherits from `uvm_component` (so does `uvm_test`).
- Components can only be created in the **build phase**. After that, the structure is fixed until the end of simulation.
- Naming convention: `<company>_<dut>_<name>`, here `cfs_algn_…`. It avoids name clashes when many teams' code is compiled together.
- A **base test** creates the env once; register-access, random and illegal-RX tests all extend it.

**Q: "List the UVM phases. Which consume time?"**

build, connect, end\_of\_elaboration, start\_of\_simulation, run, extract, check, report, final. Only run (and its optional sub-phases) is a task that consumes time; the rest are zero-time functions. Build is top-down, most others bottom-up.

**Q: "How does UVM know which test to run?"**

`run_test()` reads `+UVM_TESTNAME` (it wins over the string argument), asks the factory to create that class by name as `uvm_test_top`, then starts the phases. The class must be registered with `` `uvm_component_utils `` and extend `uvm_test`. A misspelt name gives a fatal "cannot create a component" error.

**Q: "Why can components only be created in build\_phase?"**

UVM needs a fixed hierarchy before connecting ports and running. Connections, config lookups by path and phase scheduling all depend on it. Objects that come and go during simulation (transactions, sequences) are `uvm_object`s, not components, and can be created any time.

**Q: "uvm\_component vs uvm\_object?"**

Components are permanent parts of the testbench tree: they have a parent, a hierarchical name and phases (agents, drivers, scoreboards). Objects are temporary data: no parent and no phases (transactions, sequences, config objects). Components use the constructor `new(string name, uvm_component parent)`; objects use `new(string name)`.

---

V5

## Environment coding kick-off: practice

The first working UVM skeleton on EDA Playground

### Setup

EDA Playground needs a **full account** registered with a school or work email (not Gmail or Yahoo) to unlock the commercial simulators. Settings used: *SystemVerilog/Verilog*, *UVM 1.2*, Cadence Xcelium. The UVM reference is Accellera's UVM 1.2 **Class Reference**, plus the User Guide for background.

### The whole video, as code

```systemverilog
// ---------- testbench.sv ----------
`include "cfs_algn_test_pkg.sv"            // the test package (which includes the env package)

module testbench();
  import uvm_pkg::*;                        // without this: "run_test not found"
  import cfs_algn_test_pkg::*;              // without this: UVM can't see your tests

  reg clk;
  initial begin
    clk = 0;
    forever clk = #5ns ~clk;               // toggles every 5 ns → 10 ns period = 100 MHz
  end

  reg reset_n;
  initial begin
    reset_n = 1;                            // start inactive (active-low reset)
    #6ns  reset_n = 0;                      // assert: registers take their reset values
    #30ns reset_n = 1;                      // release at 36 ns
  end

  initial begin
    $dumpfile("dump.vcd"); $dumpvars;       // + tick "Open EPWave after run" to see waves
    run_test("");                           // test name comes from +UVM_TESTNAME
  end

  cfs_aligner dut(.clk(clk), .reset_n(reset_n) /* , ...other ports */);
endmodule
```

```systemverilog
// ---------- cfs_algn_test_pkg.sv ----------
`ifndef CFS_ALGN_TEST_PKG_SV                 // include guard: parse this file only once
  `define CFS_ALGN_TEST_PKG_SV
  `include "uvm_macros.svh"                  // defines `uvm_component_utils, `uvm_info, ...
  `include "cfs_algn_pkg.sv"                 // the environment package
  package cfs_algn_test_pkg;
    import uvm_pkg::*;
    import cfs_algn_pkg::*;
    `include "cfs_algn_test_base.sv"
    `include "cfs_algn_test_reg_access.sv"
  endpackage
`endif

// ---------- cfs_algn_test_base.sv ----------
class cfs_algn_test_base extends uvm_test;
  cfs_algn_env env;                           // a handle to the environment

  `uvm_component_utils(cfs_algn_test_base)    // MANDATORY: register with the factory

  function new(string name = "", uvm_component parent);   // MANDATORY constructor signature
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);                 // MANDATORY for build_phase
    env = cfs_algn_env::type_id::create("env", this);      // not new(): use the factory
  endfunction
endclass

// ---------- cfs_algn_test_reg_access.sv ----------
class cfs_algn_test_reg_access extends cfs_algn_test_base;
  `uvm_component_utils(cfs_algn_test_reg_access)
  function new(string name = "", uvm_component parent); super.new(name, parent); endfunction

  virtual task run_phase(uvm_phase phase);    // a TASK: time passes here
    phase.raise_objection(this, "TEST_DONE"); // counter +1: "don't end yet"
    `uvm_info("DEBUG", "start of test", UVM_LOW)
    #100ns;
    `uvm_info("DEBUG", "end of test", UVM_LOW)
    phase.drop_objection(this, "TEST_DONE");  // counter -1: at 0 the run phase ends
  endtask
endclass
```

### The errors hit in the video, and why

| What you see | Cause | Fix |
| --- | --- | --- |
| Compile error: `run_test` not found | `run_test` lives in `uvm_pkg` | `import uvm_pkg::*;` |
| UVM\_FATAL: no test / could not create components | No test name given | Add `+UVM_TESTNAME=cfs_algn_test_reg_access` to run options |
| Fatal: can't create the named test | Class not declared, not in an imported package, or name misspelt | Declare it, include it in the test package, import the package in the testbench |
| Syntax error near `endclass` | Copy-paste carried an `endfunction` typo into the next file | The lecturer's warning: "very dangerous copy paste". Re-read every replaced name. |
| `` `uvm_component_utils `` unknown | Macros file not included | `` `include "uvm_macros.svh" `` |

Facts from the practice

- **Mandatory in every component:** `` `uvm_component_utils(<class>) `` plus a constructor `new(string name, uvm_component parent)` calling `super.new(name, parent)`.
- Create with `type_id::create("env", this)`, not `new`. Use the same string as the handle name (good practice). `this` is the parent.
- **Objections** are a counter: raise = +1, drop = −1, and UVM ends the run phase when it reaches 0.
- `` `uvm_info(ID, message, verbosity) `` beats `$display`: filename, time, component path, filterable by ID and verbosity (UVM\_NONE, LOW, MEDIUM, HIGH, FULL, DEBUG).
- Two packages: one for tests, one for the environment. Include guards (`` `ifndef/`define/`endif ``) on every file.

**Q: "What does `uvm\_component\_utils do?"**

It registers the class with the factory (creating the `type_id` proxy so `type_id::create` and overrides work) and adds utility methods like `get_type_name()`. Objects use `` `uvm_object_utils ``. For parameterized classes you use the `_param_` variants.

**Q: "Why type\_id::create instead of new?"**

`create` goes through the factory, so a test can override the type (e.g. swap a sequence for an error-injecting one) without editing the code that creates it. `new` bypasses the factory and overrides silently don't apply.

**Q: "Explain objections. What goes wrong if you get them wrong?"**

The run phase ends when the objection count reaches zero. Never raised: the test ends at time 0 and "passes" with nothing done. Never dropped: the simulation hangs until a timeout. Dropped too early: traffic still in flight isn't checked. Fix with drain time (`set_drain_time`) or by waiting for the scoreboard to empty before dropping.

**Q: "`uvm\_info vs $display? How do you control verbosity?"**

`` `uvm_info `` adds file, line, time and component path, and is filtered by verbosity: a message prints only if its level is ≤ the component's setting. Change globally with `+UVM_VERBOSITY=UVM_HIGH`, or per component/ID with `+uvm_set_verbosity`, as your `messages.f` does. Errors use `` `uvm_error ``/`` `uvm_fatal ``, which are counted in the final report.

**Q: "Why include guards and packages?"**

Guards stop a file being compiled twice when several packages include it, which would cause duplicate-definition errors. Packages give a namespace and a single compile unit: tests import the env, the testbench imports tests, and names don't leak or clash.

---

