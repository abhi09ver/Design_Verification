# Lecture companion: Debug and tests

> Card-by-card notes for Cristian Slav's course. Diagrams and toys are in `pages/uvm-from-zero.html`.

Chapter · debug and tests (13 videos)

## Debugging faster, and tests that really are random

With the environment complete, the work becomes regressions: run thousands of random seeds, then triage every failure as an RTL bug or a testbench bug. This chapter gives three debug techniques (message filtering, transaction "bubbles" in the waveforms, and tracking the source of expected data) and a way to organize tests as a tree of constraint-only children. The rewritten tests then find **two more RTL bugs**, and one of them is the MAX\_DROP interrupt bug this course already predicted from your project.

*[Diagram: Test inheritance tree. Open the HTML page to see it.]*

Only the two blue tests contain traffic-starting logic. Every test below them changes **only constraints or factory overrides**. Solid boxes are built in the course, dashed ones are the lecturer's suggestions. Children exist for two reasons: reach coverage faster, and give designers a test that targets the feature they're working on.

---

T1

## Regressions, triage, and why debug speed matters

Section introduction

technique 1 · UVM

#### Message filtering

IDs and verbosities, plus `+uvm_set_verbosity`, so the log shows only what this failure needs.

technique 2 · UVM

#### Transaction recording

Readable "bubbles" in the waveform instead of raw protocol signals.

technique 3 · personal

#### Track the source

Expected items remember which inputs produced them, and the error message says so.

then

#### Organize and rewrite tests

Truly random register and traffic tests, plus a targeted test made only of constraints.

**Q: "A regression has 40 failures. How do you approach it?"**

Group the failures by first error message or signature, since many are the same root cause. Take the simplest, earliest-failing seed from each group, pin the seed, and debug that. For each one, decide whether it's an RTL bug (report it with a reproducer and the spec reference) or a testbench bug (fix it, and add a check or coverage if the miss was systematic). Rerun the group with the fix. Track this in the bug database so trends, such as a block with rising failures, are visible.

---

T2

## UVM messages: IDs, verbosity and a .f file

UVM messages · lecture + practice

| Verbosity | Value | Lecturer's use |
| --- | --- | --- |
| UVM\_NONE | 0 | **Never** used for messages, so that "everything off" really silences everything. |
| UVM\_LOW | 100 | Item start/end, FIFO push/pop, CNT\_DROP increments |
| UVM\_MEDIUM | 200 | The default threshold. FIFO became full/empty, CNT\_DROP reached max (IRQ debugging) |
| UVM\_HIGH | 300 | CNT\_DROP cleared, REG\_PREDICT (from UVM's predictor) |
| UVM\_FULL | 400 | CONFIG (one-time setup messages) |
| UVM\_DEBUG | 500 | COVERAGE printouts. It exists even though the docs' list omits it. |

```systemverilog
// +uvm_set_verbosity=<comp>,<id>,<verbosity>,<phase>       or  ...,time,<t>
// comp accepts * wildcards. id does NOT: use the exact ID, or _ALL_ for every ID.
// messages.f (passed with -f messages.f), applied in order:
+uvm_set_verbosity=uvm_test_top*,_ALL_,UVM_NONE,time,0             // silence everything
+uvm_set_verbosity=*,REG_PREDICT,UVM_HIGH,time,0                   // register updates
+uvm_set_verbosity=*md_*agent.monitor*,ITEM_END,UVM_LOW,time,0     // MD traffic only
//+uvm_set_verbosity=*,RX_FIFO,UVM_MEDIUM,time,0                    // switch on per failure
```

Lecturer's message scheme

- IDs by **feature**: ITEM\_START, ITEM\_END (all agents), RX\_FIFO, TX\_FIFO, CNT\_DROP (model), COVERAGE, CONFIG. The old "DEBUG" ID with UVM\_NONE is gone everywhere.
- The result in the practice: a clean log showing register writes, then each RX item followed by the TX bytes it produced. The UVM report summary at the end shows message counts per ID, which confirms the filters worked.
- To debug a failure, switch on its feature's ID in the .f file. There's no recompile.
- For one message under several IDs, the lecturer's article introduces a `` `uvm_infos `` macro; standard UVM can't do this.

> Interactive: Try it · which lines survive your messages.f?. Open the HTML page to use it.

**Q: "How do you control UVM message verbosity without recompiling?"**

Use the command line: `+UVM_VERBOSITY=UVM_HIGH` for the global threshold, and `+uvm_set_verbosity=comp,id,verb,phase|time,t` for targeted settings (wildcards in the component, an exact ID or `_ALL_`). Collect them in a .f file per debug scenario. Also `+uvm_set_action` (e.g. make an ID UVM\_NO\_ACTION, or count it) and `+uvm_set_severity` (demote or promote). In code: `set_report_id_verbosity_hier`, or a `uvm_report_catcher`.

**Q: "Why never use UVM\_NONE for informational messages?"**

A message is printed when its verbosity ≤ the threshold. UVM\_NONE (0) is ≤ every threshold, so it can never be filtered out by verbosity, only by changing its action. Reserve UVM\_NONE for things that must always appear, and give everything else LOW or higher, so that "\_ALL\_ at UVM\_NONE" gives a truly quiet log.

**Q: "What's a uvm\_report\_catcher used for?"**

It's a callback on every report before it's processed. It can change severity, ID or verbosity, modify the text, or swallow the message. Typical uses: demote a known, waived error from a third-party VIP, or turn an expected error into a pass in a negative test. Use it carefully and with documentation, because it can hide real failures.

---

T3

## UVM transactions: bubbles on the waveform

UVM transactions · lecture (EDA Playground's viewer can't show them, so there's no practice)

Think of it like…

Subtitles on a foreign film. The raw signals (PSEL, PENABLE, valid, offset…) are the speech. Recording adds a subtitle bar above them: *"WRITE CTRL ← 0x202"*, *"MD offset 2 data {34, AB} OKAY"*. For serial protocols like I2C, the subtitles are the only practical way to follow the waveform.

```systemverilog
// 1) what goes in the bubble: override do_record (preferred, since you control the format)
virtual function void do_record(uvm_recorder recorder);
  super.do_record(recorder);
  recorder.record_field("offset", offset, 32);
  recorder.record_string("data", get_data_as_string());   // e.g. "{34, AB}"
  recorder.record_string("response", response.name());
endfunction
//    or field macros: `uvm_object_utils_begin ... `uvm_field_int(offset, UVM_RECORD) ... _end

// 2) in the monitor's collect_transaction()
item.enable_recording(get_tr_stream("MD_ITEM"));   // stream name shown in the design browser
void'(begin_tr(item, "MD_ITEM"));                   // bubble starts at this sim time
item.record();                                      // optional: fills a half bubble if sim ends mid-item
// ... wait for the end of the item ...
end_tr(item);                                       // bubble ends here (also calls record())

// 3) switch recording on, preferably without code changes:
//    +uvm_set_config_int=uvm_test_top.env.*,recording_detail,400      (400 = UVM_FULL)
```

Notes

- This works with any item, because `uvm_sequence_item` extends `uvm_transaction`, which provides the recording API.
- The lecturer's article "Look at the bubbles" extends this to **driver items and even sequences**, so you can see on the waves which test sequence was active.
- This ties back to the MD chapter: `begin_tr`/`end_tr` already set the item's begin/end times that the model and split code rely on.

**Q: "How do you get transactions visible in the waveform viewer?"**

Make the item record its fields (`do_record` or `UVM_RECORD` field flags). In the component, open a stream (`get_tr_stream`), and call `begin_tr` and `end_tr` at the protocol's start and end. Then enable `recording_detail` (config\_db or `+uvm_set_config_int`). The simulator's recorder (e.g. SimVision, Verdi, Visualizer) maps the streams into the waveform database.

**Q: "do\_record vs `uvm\_field\_\* macros?"**

Field macros auto-implement copy, compare, print, pack and record from one declaration: quick, but slower at runtime and with a fixed format. The do\_\* overrides (do\_copy, do\_compare, convert2string, do\_record) are explicit, faster and fully customizable. Many teams ban field macros for performance and debuggability; the lecturer prefers do\_record for format control.

---

T4

## "Track the source": expected items that remember their inputs

Track the source · lecture

The pain: "TX data mismatch: expected {12, 34}, received {12, AB}." The bytes 12 34 appear twice in the RX stream, and neither occurrence is preceded by the correctly sent C4 3B. Hours later you discover {12, 34} was built from **two** RX transfers, so it was never visible as one sequence in the log. Had the error listed its sources (time and data of each RX transfer), you'd have seen it immediately and handed the designer an exact starting point.

```systemverilog
// an env-owned item: the agent's class isn't yours to change on real projects
class cfs_algn_data_item extends uvm_object;
  int unsigned offset;  bit[7:0] data[$];  cfs_md_response response;
  uvm_object sources[$];                    // what produced me (any type)
endclass

// adapter between agents and env: mon2env() copies the fields, then records the origin
function cfs_algn_data_item mon2env(cfs_md_item_mon item_mon);
  cfs_algn_data_item result = cfs_algn_data_item::type_id::create("result");
  result.offset = item_mon.offset; result.data = item_mon.data; result.response = item_mon.response;
  result.sources.push_back(item_mon);       // source = the monitored transfer
  return result;
endfunction

// in align(): every buffer piece used in a TX item → tx_item.sources.push_back(piece)
// in the scoreboard error: foreach(exp.sources[i]) msg = {msg, "\n  source: ", exp.sources[i].convert2string()};
```

Why it's worth the coding effort

- Saves time on **every** data mismatch, which is the most common failure type in a data-path block.
- Your bug report becomes concrete: "RX transfers at t1 and t2 produced this TX item; RTL output differs at byte 2."
- The tricky part is `align()`: split pieces must carry their parent's sources, so every path that builds a TX item needs to append correctly. The lecturer's article "Always Remember the Cause" has more detail.

**Q: "How do you make scoreboard errors easier to debug?"**

Print both values and the field-level difference, the time each one was produced, and the **cause**: the input transactions (with times) the expected value was built from, and why a status was expected (like the predictor's status\_info "reason" from the register chapter). Add a stable error ID per check so failures can be grouped in regression triage.

**Q: "Why insert an adapter between agent and env instead of extending the monitor item?"**

Third-party or shared VIP items can't be modified per project, and extending them (with factory overrides) couples the env to the VIP's internals. An env-owned item behind a `mon2env()` translation decouples the model and scoreboard from the agent. You can swap the VIP, add debug fields like `sources`, or normalize several protocols into one data type.

---

T5

## Test organization: one random parent, constraint-only children

Tests organization · lecture

anti-pattern

#### Many flat tests

N classes directly under uvm\_test, each repeating how traffic is started. Changing the start logic means editing all N.

pattern

#### Random parent

One test owns the traffic logic and, given enough seeds, covers everything.

pattern

#### Targeted children

Extend the parent and add **only constraints** (usually by a factory override of one virtual sequence) to reach a feature fast.

| Target | Constrain the random test to… |
| --- | --- |
| Drop counter + MAX\_DROP IRQ | only illegal RX transfers, at least 255 of them |
| RX/TX FIFOs full | RX size always 4 (max input) and CTRL.SIZE = 1 (min output): the Aligner becomes a bottleneck |
| Unmapped-address logic | reg-access test with `num_reg_accesses = 0` |
| Read paths | reg-access test with `get_random_access()` overridden to READ |

Notes

- "An ideal you won't fully reach on real projects, but get as close as you can."
- The real tree has `cfs_algn_test_base` (env only) in between, which is left out of the diagram so it doesn't look like there's only one real test.
- Make parent knobs **protected fields set in the constructor** (e.g. `num_md_rx_transactions`), so children change them by assignment.

**Q: "How do you structure tests in a UVM environment?"**

A base test that builds and configures the env. A small number of random "traffic" tests that start virtual sequences and expose knobs. Then targeted tests that only change constraints, knobs or factory overrides, never the traffic logic. Directed tests are kept for bring-up, very specific corners, or timing-sensitive features (like IRQ timing). Sequences carry the behaviour and tests stay thin, which makes regression lists easy to build.

**Q: "How do you add a new targeted test without touching existing code?"**

Extend the virtual sequence that generates the relevant traffic, adding a constraint block, and in the new test's constructor or build\_phase call `parent_vseq::type_id::set_type_override(child_vseq::get_type())`. Any `type_id::create` of the parent now returns the child. This is the open/closed principle, applied with the UVM factory.

---

T6

## A truly random register test, which finds an IRQEN reset bug

Register access test · lecture + practice

```systemverilog
// test: two vseqs racing for the APB sequencer
fork
  begin seq_rand.randomize() with { num_accesses == num_reg_accesses; };      seq_rand.start(env.virtual_sequencer); end
  begin seq_unm.randomize()  with { num_accesses == num_unmapped_accesses; }; seq_unm.start(env.virtual_sequencer);  end
join   // both knobs default to 100 in the constructor

// reg_access_random body: random register, random direction, random gap
p_sequencer.model.reg_block.get_registers(registers);
for(int unsigned i = 0; i < num_accesses; i++) begin
  int unsigned reg_idx = $urandom_range(registers.size() - 1, 0);
  case(get_random_access(registers[reg_idx], i))      // virtual: children can bias it
    UVM_READ  : registers[reg_idx].read(status, data);
    UVM_WRITE : begin void'(registers[reg_idx].randomize()); registers[reg_idx].update(status); end
  endcase
  wait_random_time();                                  // 0..20 clocks
end

// reg_access_unmapped: every byte address of every register, then avoid them all
foreach(registers[r]) for(int b = 0; b < registers[r].get_n_bits() / 8; b++)
  addresses.push_back(registers[r].get_address() + b);
`uvm_do_on_with(seq, p_sequencer.apb_sequencer, { !(item.addr inside {addresses}); })
```

Details

- `get_random_access` uses `std::randomize(result) with {result inside {UVM_READ, UVM_WRITE};}`. The constraint is needed because `uvm_access_e` also has UVM\_BURST\_READ and UVM\_BURST\_WRITE.
- `num_accesses` has a **soft** default inside the sequence, so the test's inline `==` overrides it without a conflict.
- Unmapped addresses exclude **all four bytes** of each register (an assumption that register widths are multiples of 8).

Bug #2 of the course: IRQEN resets to 0x1F

Run 1 passed. Run 2 failed: the read of IRQEN returned `0x1F` but the mirror said `0x00`. It was the first IRQEN access in that seed, so both sides were showing reset values. The datasheet says reset = 0, so the **RTL** is wrong (`cfs_regs.v`, the reset branch set every irqen bit to 1). Run 1 passed only because its first IRQEN access happened to be a write. The lecturer pinned the seed, fixed the RTL, and confirmed access #5 now reads 0. *(Your project copy already contains this fix.)*

**Q: "Why did one seed find the bug and another not?"**

The bug was only observable if a **read** of IRQEN came before any write to it. Random ordering makes that a probability per seed. That's why you run many seeds, and why coverage should include "first access after reset is a read" for every register. A built-in UVM sequence, `uvm_reg_hw_reset_seq`, checks all reset values directly. It's a good first test in any register bring-up.

**Q: "Which built-in UVM register sequences do you know?"**

`uvm_reg_hw_reset_seq` (reset values), `uvm_reg_bit_bash_seq` (walks 1s and 0s through every RW bit), `uvm_reg_access_seq` (front door vs back door consistency, which needs HDL paths), `uvm_mem_walk_seq` and `uvm_mem_access_seq` for memories, and `uvm_reg_mem_built_in_seq` to run them all. Exclude registers with side effects using resource attributes like `NO_REG_BIT_BASH_TEST`.

---

T7

## The random traffic test, and two traps it uncovered

Random traffic test · lecture + practice

```systemverilog
repeat(2) begin                                   // loop: CLR and W1C clears get exercised too
  if(env.model.is_empty()) begin                  // never reconfigure while data is inside
    cfs_algn_virtual_sequence_reg_config seq = ...;  // writable regs ("RW"/"WO"), shuffled, randomize + update
    void'(seq.randomize()); seq.start(env.virtual_sequencer);
  end
  repeat(num_md_rx_transactions) begin            // protected knob, 300 by default
    cfs_algn_virtual_sequence_rx seq = ...;       // ONE random MD RX transfer per vseq
    seq.set_sequencer(env.virtual_sequencer);     // before randomize: constraints read p_sequencer
    void'(seq.randomize()); seq.start(env.virtual_sequencer);
  end
  repeat(100) @(posedge vif.clk);                 // let TX drain: levels are volatile right after traffic
  cfs_algn_virtual_sequence_reg_status ...;       // read-only regs ("RO"), shuffled, read
end
```

**Trap 1: "IRQ is never written."** `update()` after `randomize()` never touched IRQ (W1C fields). Root cause in UVM's `uvm_reg_field::configure()`: for non-writable-style accesses (including W1C) it forces `is_rand = 0` and `value.rand_mode(0)`, **silently ignoring your is\_rand = 1**. Randomize leaves desired == mirrored, so `update()` sees nothing to do. Fix: after configure, call `FIELD.value.rand_mode(1)` for every IRQ field (it's in your `cfs_algn_reg_irq::build()`). The lecturer: "even experienced verification engineers are not aware of this".

**Trap 2: TX data mismatch on seed 11.** The second loop iteration reconfigured CTRL while bytes still sat in the intermediate buffer (waiting for enough bytes to align). Changing SIZE or OFFSET with data inside is unpredictable, so the test must not do it. Fix: `cfs_algn_model::is_empty()` (RX FIFO, TX FIFO and buffer all empty) guards the config step.

Senior-level follow-ups

- **The guard silently skips work.** Leftover bytes smaller than SIZE never drain, so when they're present the second config is *skipped*, not delayed. Reconfiguration coverage then depends on luck. Better: drain on purpose (send filler bytes until `is_empty()`, with a timeout), then reconfigure, and cover "reconfigured with an empty pipeline".
- **What's still untested** (the lecturer's challenge): multiple resets mid-traffic (does the DUT recover?), and the two features fixed by the loop, which are clearing CNT\_DROP via CTRL.CLR and clearing IRQ flags via W1C.
- EDA Playground limits: wave dump size, about 5000 log lines, about 1 minute of CPU. That's why `num_md_rx_transactions` was cut to 100 there.
- The lecturer's honest summary: tests pass on a few seeds and fail in regressions on cases nobody anticipated. Incremental test fixes are part of the job, and coverage may still show untested features afterwards.

**Q: "randomize() + update() on a register does nothing. Why?"**

Three usual causes. The randomized value equals the mirror, so `needs_update()` is 0. The field isn't randomizable: its access is RO or W1C-like and configure() turned rand\_mode off, or is\_rand was 0. Or randomization failed and the result was voided. Check `get()` vs `get_mirrored_value()` and `FIELD.value.rand_mode()`, and always check the randomize result.

**Q: "Why wait before reading the status registers?"**

Right after traffic, RX\_LVL and TX\_LVL change every few cycles, and the model and RTL can legitimately differ by a cycle in when they update. Reading in a quiet period makes the read check deterministic. Reading *during* traffic is also valuable, but needs volatile-tolerant checking or tighter synchronization.

**Q: "Your random test passes 10 seeds. What would you add before calling it good?"**

Reset in the middle of traffic. Reconfiguration with the pipeline drained. Back-pressure extremes (a slow TX slave, all-max RX). Interrupt clears and CLR. Error-response mixes. Then a regression of thousands of seeds with coverage, triaging every failure.

---

T8

## Illegal RX traffic test: the MAX\_DROP bug, confirmed

Illegal RX traffic test · lecture + practice

```systemverilog
class cfs_algn_virtual_sequence_rx_err extends cfs_algn_virtual_sequence_rx;
  local int unsigned algn_data_width;            // set in pre_randomize() from env_config
  constraint rx_err {
    ((algn_data_width / 8) + seq.item.offset) % seq.item.data.size() != 0 ||
    (seq.item.data.size() + seq.item.offset) > (algn_data_width / 8);
  }
endclass

class cfs_algn_test_random_rx_err extends cfs_algn_test_random;
  function new(string name = "", uvm_component parent);
    super.new(name, parent);
    num_md_rx_transactions = 300;                // > 255: CNT_DROP must saturate
    cfs_algn_virtual_sequence_rx::type_id::set_type_override(cfs_algn_virtual_sequence_rx_err::get_type());
  endfunction
endclass
```

| Debug step | What happened |
| --- | --- |
| First run | Every RX transfer answered ERR, no TX traffic, passes. |
| Some later seed | Fails: an expected IRQ was not received after 10 clocks. |
| Use T2's filter | In `messages.f`, swap the MD item messages for the IRQ-related IDs (CNT\_DROP, etc.). Rerun the pinned seed: "drop counter reached max value", and IRQEN.MAX\_DROP was 1. |
| Waves | The RTL's drop counter hits 255 and its IRQ.MAX\_DROP bit sets, but `irq` stays 0 even though irqen\_max\_drop is 1. |
| Root cause | `cfs_regs.v`: the `assign irq = …` ORs four sources and **forgets** `edge_max_drop & irqen_max_drop`. "Quite a common bug." |

You saw this one coming

The senior Aligner lab spotted this exact omission by reading your project's RTL, and the rx\_err exercise files written earlier in this conversation were predicted to expose it on roughly half the seeds: those where the random IRQEN config enables MAX\_DROP. The lecture confirms both. Your project copy still has the bug. To fix it, add the fifth term to the `irq` assign in `cfs_regs.v`:  
`| (edge_max_drop & irqen_max_drop)`

Comparing the lecture's code with your exercise files

- The lecture's second constraint branch (`size + offset > bytes`) can never be chosen: the MD item's own `item_hard` constraint (the protocol rule, also an interface SVA) forbids it. So all illegal traffic comes from the modulo rule. Your version states this in a comment and keeps only the reachable branch.
- The lecture registers the override in the **constructor**, yours in **build\_phase**. Both work, because the override only has to exist before the first `type_id::create` of the sequence in run\_phase.

**Q: "Create a test for a feature without touching the existing tests."**

Here's the drop counter as an example. Extend the RX virtual sequence with a constraint for illegal transfers, extend the random test, raise its traffic knob above the counter's maximum, and factory-override the RX vseq with the new one. That's about 30 lines, all additive. It exercises the saturation, the MAX\_DROP flag and the IRQ path, and it found a real bug.

**Q: "How do you make sure a test actually exercised what it targets?"**

Use coverage on the feature (e.g. CNT\_DROP reached 255 with IRQEN.MAX\_DROP = 0 and = 1, and CLR after saturation), not just a pass result. This bug escaped the plain random test because it never produced 255 drops. And it was only visible when MAX\_DROP was enabled, so the IRQEN value must be in the cross too.

---

T9

## Wrap-up: you can build an environment from scratch

Conclusions video

| # | Bug | Found by | Kind |
| --- | --- | --- | --- |
| 1 | SIZE + OFFSET > bus width accepted (R8) | RAL randomization + MD interface SVA | Spec **and** RTL |
| 2 | IRQEN resets to 0x1F (T6) | Random register test, read before write | RTL |
| 3 | MAX\_DROP missing from `irq` (T8) | Illegal-RX test + IRQ scoreboard check | RTL |
| +3 | IRQ synchronization issues (C10–C13) | IRQ scoreboard check | Testbench |

The lecturer's closing points

- Message control and transaction recording make debug faster, and tracking sources in the model's expected data pays off every time.
- Inheritance plus constraints maximize test reuse. The illegal-RX test is proof.
- "There might be other bugs hidden inside the DUT." Run the tests and look for them.

Interview line: the whole project in 45 seconds

"I verified a parameterized data aligner from spec to regression in UVM 1.2: APB and MD agents (the MD one reactive, with master and slave), a shared base-class library, a register model with a custom predictor that also checks bus responses, a spec-shaped reference model with TLM FIFOs and register prediction, a scoreboard with watchdogs for data, responses and a bare IRQ wire, split coverage, and virtual sequences. I solved three model-vs-RTL synchronization problems. Constrained-random and targeted constraint-only tests found three RTL bugs, one of them also a spec hole. For debug I used ID-based message control, transaction recording, and expected items that carry their sources."

---

