# UVM from Zero: Levels 0–11 (beginner track)

> Diagrams and toys are in `pages/uvm-from-zero.html`.

0

## What is verification?

Why chips need testers, and what a testbench does · 8 min

Think of it like…

A toy company makes a new robot. One team **builds** it (designers). Another team **tries to break it** before it reaches shops (testers). If a broken robot reaches a child, the company must recall thousands of toys. That's expensive and embarrassing.

Chips are the same, only worse: once a chip is manufactured, you **cannot fix it**. A new set of masks can cost millions of dollars and months of time. So chip companies pay verification engineers to find every bug while the chip is still just code.

### Two kinds of engineers, one chip

The **designer** writes the chip in a hardware language (Verilog or SystemVerilog). This code is called **RTL** (Register Transfer Level). The chip under test is called the **DUT** (Design Under Test).

The **verification engineer** writes a second program, the **testbench**, that plays with the DUT in a simulator and checks that it behaves exactly as the specification (the "spec" or datasheet) says.

*[Diagram: A testbench drives the DUT, watches it, and judges it. Open the HTML page to see it.]*

Every testbench in the world, from a 10-line school project to NVIDIA's GPU testbenches, does these three jobs. UVM is just a well-organised way to do them.

**Remember:** Drive → Watch → Judge. If you forget everything else, keep these three words. Every UVM part you'll meet does one of them.

---

1

## Clock and reset: the chip's heartbeat

Why everything happens "on the tick" · 10 min

Think of it like…

A rowing team. The coach shouts "**ROW!**" again and again, and every rower pulls at the same moment. Nobody rows between shouts. The **clock** is that shout. It goes 0, 1, 0, 1… and on each **rising edge** (0 → 1) every memory cell in the chip updates at once.

**Reset** is the coach saying "everyone back to the start position". Our chip's reset is called `reset_n`. The `_n` means "active low": reset happens when the wire is **0**.

> Interactive: Try it · a 4-bit counter. Open the HTML page to use it.

### The same counter in Verilog

```systemverilog
module counter(input clk, input reset_n, output reg [3:0] count);
  always @(posedge clk or negedge reset_n) begin  // wake up on a rising clock (or reset)
    if (!reset_n)                                 // reset is active when reset_n == 0
      count <= 0;                                 // go back to the start
    else
      count <= count + 1;                         // otherwise add 1 on every tick
  end
endmodule
// 4 bits can hold 0..15, so after 15 it "wraps" back to 0
```

**Common mistake:** using `=` instead of `<=` inside a clocked block. `<=` (non-blocking) means "everyone updates together on the tick", like the rowers. `=` updates immediately and can make two flip-flops race each other. In clocked logic and when driving DUT pins from a testbench, use `<=`.

---

2

## Meet our chip: the Aligner

What it does, and how it talks · 15 min

Think of it like…

A candy-packing machine. Bags of candy arrive in different sizes: 1, 2 or 4 candies. The machine must put them into **boxes that all have the same size** (the setting is called `CTRL.SIZE`). If a bag doesn't fit in the space left in a box, the machine **cuts the bag**: part goes in this box, the rest starts the next box. Order never changes.

Why would a chip do this? Memories like writes of one fixed size. The Aligner turns messy, uneven data into neat, equal chunks.

> Interactive: Try it · the candy packer. Open the HTML page to use it.

### How data moves: the valid/ready handshake

Every bag travels over a set of wires called the **MD interface**. The sender raises `valid` ("I'm holding a bag out"). The receiver raises `ready` ("my hands are open"). The bag moves only on a clock tick when **both** are 1. The sender must keep holding the bag (keep `valid` high, data unchanged) until it's taken.

> Interactive: Try it · pass the parcel. Open the HTML page to use it.

### The one rule that decides "good bag" or "bad bag"

On a 4-byte bus, each bag says where it starts (`offset`, 0–3) and how many bytes it has (`size`). The datasheet rule: `(4 + offset) % size == 0`. Size 1 is always fine. Size 2 must start at 0 or 2. Size 4 must start at 0. A bad bag is refused with `err = 1` and a counter called `CNT_DROP` goes up by one.

| offset ↓ size → | 1 | 2 | 4 |
| --- | --- | --- | --- |
| 0 | ✅ good | ✅ good | ✅ good |
| 1 | ✅ good | ❌ err | ❌ err |
| 2 | ✅ good | ✅ good | ❌ err |
| 3 | ✅ good | ❌ err | ❌ err |

**Remember:** The Aligner has three doors. **APB** is the control door (registers like CTRL and STATUS). **MD RX** is where bags come in. **MD TX** is where boxes go out. A testbench needs one helper per door.

---

3

## Your first testbench, without UVM

Drive, watch, judge with plain Verilog, and why it stops working · 12 min

Before UVM, let's test something tiny: a module that adds two numbers. A testbench is just another module with no ports. It creates the DUT, wiggles its inputs and checks its outputs.

```systemverilog
module tb;                               // a testbench has no ports
  reg  [7:0] a, b;                       // things WE drive
  wire [8:0] sum;                        // things the DUT drives

  adder dut(.a(a), .b(b), .sum(sum));    // put the DUT on the table

  initial begin
    a = 3;  b = 4;                       // 1. DRIVE
    #10;                                 //    wait 10 time units
    if (sum !== 7)                       // 2. WATCH + 3. JUDGE
      $display("BUG! 3+4 gave %0d", sum);
    else
      $display("pass");
    $finish;
  end
endmodule
```

### That works. So why do we need UVM?

Imagine doing this for the Aligner: three doors, a handshake on each, 4 registers, random bag sizes, back-pressure, interrupts, reset in the middle of traffic. With plain code you would:

#### Copy-paste forever

Every test re-writes the same "wiggle valid, wait for ready" code. Fix a bug in one place, it stays broken in twenty others.

#### Hand-pick every value

You'd test only the cases you thought of. Bugs live in the cases nobody thought of. You want the computer to pick random values, within the rules.

#### Checks tangled with stimulus

The "is it right?" logic lives inside each test. A new test means rewriting the judge too.

#### Nothing reusable

Your APB code can't be reused on the next chip, or at the full-chip level, because it's glued to this one test.

**UVM's big idea:** split the testbench into small, reusable members, each with one job. Tests then just say *what* to do; the members know *how*.

---

4

## SystemVerilog classes and randomness

The only programming ideas UVM needs · 18 min

Think of it like…

A **class** is a cookie cutter. An **object** is a cookie you cut with it. You can cut many cookies from one cutter, each with its own sprinkles (values). A **handle** is a sticky note with the cookie's location written on it; two notes can point at the same cookie.

**Inheritance** means making a new cutter that's the old one plus something extra: "a star cutter, but with a hole in the middle".

```systemverilog
class bag;                         // the cookie cutter
  rand bit [1:0] offset;           // "rand" = let the computer pick it
  rand int       size;

  constraint good_size { size inside {1, 2, 4}; }        // rule 1
  constraint fits      { (4 + offset) % size == 0; }     // rule 2 (the datasheet rule!)

  function void show();
    $display("bag: offset=%0d size=%0d", offset, size);
  endfunction
endclass

bag b1;                 // a handle (sticky note), points to nothing yet
b1 = new();             // cut a cookie: now b1 points to a real object
if (!b1.randomize())    // pick random values that obey ALL constraints
  $fatal("could not satisfy the rules!");
b1.show();              // e.g. "bag: offset=2 size=2"

class bad_bag extends bag;          // inheritance: a bag, plus one more rule
  constraint must_fail { (4 + offset) % size != 0; }     // always breaks the datasheet rule?
endclass
```

**Trap in that last class:** `bad_bag` keeps the parent's `fits` rule *and* adds the opposite. Both can't be true, so `randomize()` fails. To make an always-bad bag, turn the parent rule off: `b.fits.constraint_mode(0)`, or override the constraint by giving it the **same name** in the child.

> Interactive: Try it · a die with rules. Open the HTML page to use it.

### One more word: virtual

When a function is `virtual`, calling it through a parent-type handle runs the **child's** version. UVM uses this everywhere: the UVM library calls `run_phase()` on your component, and your version runs. Without `virtual`, the parent's empty version would run.

---

5

## Transactions: from wires to parcels

Thinking in "items" instead of 0s and 1s · 10 min

Think of it like…

When you send a parcel, you don't describe the truck's engine, the road and the gear changes. You write a label: *to, from, contents*. A **transaction** is that label for a bus transfer. Instead of "valid went high at 35 ns, data was 0x44332211…", you say "an MD item: offset 0, 4 bytes, response OKAY".

*[Diagram: Wires on the left become one transaction object on the right. Open the HTML page to see it.]*

```systemverilog
class md_item extends uvm_sequence_item;    // UVM's base class for transactions
  rand bit [7:0] data[$];                    // a list of bytes (1, 2 or 4 of them)
  rand int       offset;                     // where on the bus the bytes start
  md_response    response;                   // OKAY or ERR, filled in by the monitor

  `uvm_object_utils(md_item)                 // register with the UVM factory (Level 7)

  function new(string name = "md_item");
    super.new(name);
  endfunction

  virtual function string convert2string();  // how to print me in the log
    return $sformatf("offset=%0d size=%0d resp=%s", offset, data.size(), response.name());
  endfunction
endclass
```

**Remember:** the driver turns items *into* wires; the monitor turns wires *back into* items. Everything in between (sequences, scoreboard, coverage) only ever sees items. That's what makes it easy to think about.

---

6

## The UVM team: a restaurant

Every UVM part, and who passes what to whom · 18 min

Think of it like…

A restaurant. The **test** picks today's menu. A **sequence** is an order slip ("3 random bags, then 1 bad bag"). The **sequencer** is the waiter who queues order slips. The **driver** is the chef who actually cooks: it puts real signals on the wires. The **monitor** is a food critic at the table who writes down exactly what was served. The **scoreboard** is the judge: it compares what was served with what the recipe book (the **reference model**) says should be served. **Coverage** is a checklist of dishes tried so far.

uvm\_sequence\_item

#### Item

One parcel (Level 5).

uvm\_sequence

#### Sequence

Makes items, often random, in a planned order. Drive.

uvm\_sequencer

#### Sequencer

Queues items and hands them to the driver one at a time.

uvm\_driver

#### Driver

Turns an item into wire wiggles that follow the protocol. Drive.

uvm\_monitor

#### Monitor

Only listens to wires, rebuilds items, shouts them to everyone. Watch.

uvm\_agent

#### Agent

A box holding sequencer + driver + monitor for **one door** of the chip.

model

#### Reference model

Predicts what the chip *should* output, from what went in.

uvm\_scoreboard

#### Scoreboard

Compares predicted vs. actual. Prints UVM\_ERROR on mismatch. Judge.

uvm\_env

#### Environment

The whole restaurant: all agents + model + scoreboard + coverage.

uvm\_test

#### Test

Builds the env and picks which sequences to run.

> Interactive: Try it · follow one bag through the testbench. Open the HTML page to use it.

### How members talk: analysis ports

The monitor doesn't know who's listening. It has an **analysis port**, like a radio station. Anyone with a matching receiver (an **analysis imp**) that's connected gets a copy of every item. One monitor can feed the model, the scoreboard and coverage at the same time, without knowing any of them.

---

7

## Building the team: phases, config\_db, factory

The three UVM "magic" words, without magic · 15 min

Think of it like…

Putting on a school play. First you **build** the set and cast actors (top to bottom: director, then groups, then each actor). Then you **connect**: run cables, give everyone their walkie-talkies. Then the **run**: the play happens, and time moves. Finally you **report**: who forgot lines?

build\_phaseBuild the set

Create children with `type_id::create`. Runs top-down: the test first, then the env, then the agents.

connect\_phaseRun the cables

Connect monitor ports to scoreboard and model. Runs bottom-up.

run\_phaseThe show

The only phase where simulation time passes. Drivers drive, monitors watch, tests start sequences.

check / reportApplause or boos

Final checks and the summary: how many UVM\_ERRORs?

### config\_db: the notice board

The top module owns the real wires (interfaces), but classes can't see modules. So the top pins a note on a shared notice board: "the APB wires are here, for whoever is at `uvm_test_top.env.apb_agent`". The agent later reads the board.

```systemverilog
// in the top module (testbench.sv): pin the note
uvm_config_db#(virtual cfs_apb_if)::set(null, "uvm_test_top.env.apb_agent", "vif", apb_if);

// in the agent: read the note
if (!uvm_config_db#(virtual cfs_apb_if)::get(this, "", "vif", vif))
  `uvm_fatal("NO_VIF", "Nobody pinned my wires on the notice board!")
```

### The factory: the substitute player

When you create objects with `type_id::create` instead of `new`, you let the UVM **factory** make them. A test can then say "whenever anyone asks for a normal RX sequence, give them the error version instead", without changing any other file. That's exactly how your `cfs_algn_test_random_rx_err` test works.

```systemverilog
// in the test's build_phase: swap the player
cfs_algn_virtual_sequence_rx::type_id::set_type_override(
    cfs_algn_virtual_sequence_rx_err::get_type());

// later, deep inside cfs_algn_test_random:
seq = cfs_algn_virtual_sequence_rx::type_id::create("seq");  // you actually get the _err one!
```

**Common mistake:** writing `seq = new("seq");`. `new` skips the factory, so the swap silently doesn't happen. Always use `type_id::create`.

---

8

## Writing each team member

Tiny real code for driver, monitor, sequence, scoreboard · 20 min

These are shortened versions of the real files in your Aligner testbench. Read the comments like a story, top to bottom.

### The sequence (writes the order slip)

```systemverilog
class my_rx_sequence extends uvm_sequence #(md_item);
  `uvm_object_utils(my_rx_sequence)
  function new(string name = "my_rx_sequence"); super.new(name); endfunction

  virtual task body();                       // body() is what runs when the sequence starts
    repeat (5) begin                         // make 5 random bags
      md_item item = md_item::type_id::create("item");
      start_item(item);                      // ask the waiter (sequencer) for a turn
      if (!item.randomize()) `uvm_fatal("RAND", "randomize failed")
      finish_item(item);                     // hand it over; waits until the driver is done
    end
  endtask
endclass
```

### The driver (the chef)

```systemverilog
class my_md_driver extends uvm_driver #(md_item);
  virtual cfs_md_if vif;                         // the wires (from the notice board)

  virtual task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);          // wait for the next order slip
      vif.valid  <= 1;                           // "I'm holding a bag out"
      vif.data   <= pack_bytes(req);             // put the bytes on the bus
      vif.offset <= req.offset;
      vif.size   <= req.data.size();
      @(posedge vif.clk);
      while (vif.ready !== 1) @(posedge vif.clk); // wait until the receiver takes it
      vif.valid  <= 0;                           // let go
      seq_item_port.item_done();                 // tell the waiter: done, next please
    end
  endtask
endclass
```

### The monitor (the critic)

```systemverilog
class my_md_monitor extends uvm_monitor;
  virtual cfs_md_if vif;
  uvm_analysis_port #(md_item) output_port;      // the radio station

  virtual task run_phase(uvm_phase phase);
    forever begin
      md_item item = md_item::type_id::create("item");
      @(posedge vif.clk iff vif.valid);          // a transfer has started
      item.offset = vif.offset;                  // copy what's on the wires
      // ...unpack data bytes...
      while (vif.ready !== 1) @(posedge vif.clk);
      item.response = md_response'(vif.err);     // was it refused?
      output_port.write(item);                   // broadcast to everyone listening
    end
  endtask
endclass
```

### The scoreboard (the judge)

```systemverilog
class my_scoreboard extends uvm_scoreboard;
  md_response expected[$];                       // a queue of predictions

  function void write_expected(md_response r);   // the model calls this
    expected.push_back(r);
  endfunction

  function void write_actual(md_item item);      // the monitor calls this
    md_response exp = expected.pop_front();
    if (item.response != exp)
      `uvm_error("DUT_ERROR", $sformatf("expected %s, got %s", exp.name(), item.response.name()))
  endfunction
endclass
```

**Notice:** the driver never checks anything, and the scoreboard never touches a wire. Each member does one job. That's why you can reuse the same agent on the next chip.

---

9

## Tests: running the show

Objections, test names, and reading the log · 12 min

Think of it like…

A party that ends when the last person leaves. Each part of the testbench that's still busy **raises an objection** ("don't turn off the lights, I'm still here"). When everyone has **dropped** their objection, the run phase ends. Forget to raise one and the party ends at time 0: nothing happens, and the test "passes".

```systemverilog
class my_test extends cfs_algn_test_base;            // base test builds the env
  `uvm_component_utils(my_test)
  function new(string name = "", uvm_component parent); super.new(name, parent); endfunction

  virtual task run_phase(uvm_phase phase);
    my_rx_sequence seq = my_rx_sequence::type_id::create("seq");
    phase.raise_objection(this);                     // lights ON
    seq.start(env.md_rx_agent.sequencer);            // run the order slip on the RX door
    #500ns;                                          // let the last boxes come out
    phase.drop_objection(this);                      // lights OFF
  endtask
endclass
```

### Running it

On EDA Playground you add `+UVM_TESTNAME=my_test` to the run options. The top module calls `run_test()`, which creates the test by name. At the end the log prints a summary. This one is from your own run:

```systemverilog
--- UVM Report Summary ---
** Report counts by severity
UVM_INFO :  386
UVM_WARNING :    0
UVM_ERROR :    0        <-- the number that matters
UVM_FATAL :    0
```

**Common mistake:** "0 errors, so my test passed." Also check that something actually happened: count the `ITEM_END` lines (your run had 374). A test that sends nothing also has 0 errors.

---

10

## Your first real task: send only bad bags

The "Illegal RX Traffic" exercise, step by step · 15 min

**The job:** make a test where every RX bag breaks the datasheet rule, send 300 of them, and check the chip refuses all of them.

### Step 1. Ask: what already exists?

There's already a test (`cfs_algn_test_random`) that sends random *good* bags using a sequence called `cfs_algn_virtual_sequence_rx`. We won't copy it. We'll make children of both and change only what's different.

### Step 2. A sequence that only makes bad bags

```systemverilog
class cfs_algn_virtual_sequence_rx_err extends cfs_algn_virtual_sequence_rx;  // child = parent + 1 rule
  local int unsigned data_width_in_bytes;           // 4 on a 32-bit bus

  constraint rx_err {                                // the NEW rule: break the datasheet rule
    ((data_width_in_bytes + seq.item.offset) % seq.item.data.size()) != 0;
  }

  `uvm_object_utils(cfs_algn_virtual_sequence_rx_err)
  function new(string name = ""); super.new(name); endfunction

  function void pre_randomize();                     // runs just before randomize()
    super.pre_randomize();
    data_width_in_bytes = p_sequencer.md_rx_sequencer.get_data_width() / 8;
  endfunction
endclass
```

### Step 3. A test that swaps the sequence and sends 300

```systemverilog
class cfs_algn_test_random_rx_err extends cfs_algn_test_random;
  `uvm_component_utils(cfs_algn_test_random_rx_err)

  function new(string name = "", uvm_component parent);
    super.new(name, parent);
    num_md_rx_transactions = 300;                    // the parent's knob
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfs_algn_virtual_sequence_rx::type_id::set_type_override(   // the substitute player
        cfs_algn_virtual_sequence_rx_err::get_type());
  endfunction
endclass
```

### Step 4. Tell the packages the new files exist

Add `` `include "cfs_algn_virtual_sequence_rx_err.sv" `` in `cfs_algn_pkg.sv` and `` `include "cfs_algn_test_random_rx_err.sv" `` in `cfs_algn_test_pkg.sv`, then run with `+UVM_TESTNAME=cfs_algn_test_random_rx_err`.

### Step 5. What should you see?

Every RX line in the log ends with `response: CFS_MD_ERR`. CNT\_DROP counts up and stops at 255 (it never wraps). If an interrupt error appears for some random seeds, that isn't your mistake: it's a real chip bug, explained in the senior course.

**The habit to keep:** change the smallest thing. You wrote about 30 lines and reused thousands, because the original authors built for reuse (classes, factory, knobs).

---

11

## Your word list, and what's next

Every term from this course in one place

### Finished? You're ready for the senior course.

The Aligner UVM Lab takes the same testbench to interview level: assertions, the register model, the reference model, coverage holes, and real bugs found in this chip's code.

Want to practise talking about it? Say "quiz me on level 6" in chat, or "mock interview" when you've done both courses.

---

