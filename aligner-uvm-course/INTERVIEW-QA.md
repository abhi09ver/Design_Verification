# Interview Q&A: every question from both pages

> 244 questions with model answers. Cover the answer, say yours out loud, then compare.


## Senior Aligner UVM Lab


### Read the spec like a verifier  
*Notes: [notes/senior-lab/00-read-the-spec-like-a-verifier.md](notes/senior-lab/00-read-the-spec-like-a-verifier.md)*

<details><summary><b>"Here's the aligner datasheet. You have 10 minutes. How would you verify it?"</b></summary>


Strong answer shape  
Start from the plan, not the tools. (1) Interfaces: APB slave, MD RX (DUT is the slave), MD TX (DUT is the master), irq. That gives one APB agent, one MD master agent, one MD reactive slave agent. (2) Behaviour splits into a transform (alignment), rules (legality, APB errors, protocol) and state (FIFO levels, counters, IRQs). (3) Transforms go to a reference model plus a scoreboard. Rules go to SVA and the register predictor. State goes to the RAL mirror. (4) Coverage on the config × traffic cross. (5) Tests: register access, random legal, all-illegal, back-pressure, IRQ, reset-mid-traffic.

Cross-questions they'll push

- Why is the TX agent reactive instead of just driving `ready=1`? (You need back-pressure to fill the FIFOs and to hit full/empty IRQs.)
- Would you use formal for any of this? (Yes: the legality rule and the APB error conditions are small, closed-form properties. Formal proves all (offset, size) combos in minutes.)
- What's the riskiest feature? (IRQ edge semantics and CNT\_DROP/CLR races. These are timing interactions that a random test rarely hits by chance.)

</details>

<details><summary><b>"Your constraints only generate legal-by-construction traffic. Is that a problem?"</b></summary>


Yes, if the constraint is narrower than the spec. Your constraints define what the DUT is *never* asked to handle. Here, `item_hard` removes the overflow cells, so the RTL's missing overflow check in `cfs_rx_ctrl.v` can't be found. A senior engineer keeps constraints that model *physical* limits (here the bus cannot carry byte 4) apart from constraints that model *legality*. Legality belongs in the checker, and illegal stimulus gets its own test, as you did with `rx_err`.

Cross-question

- Then how would you drive size 3 at offset 2 if the driver fatals? (Override the driver check behind a config knob, or decide with the designer that it's a protocol violation and cover it with an assertion on the DUT input.)

</details>


### Testbench architecture  
*Notes: [notes/senior-lab/01-testbench-architecture.md](notes/senior-lab/01-testbench-architecture.md)*

<details><summary><b>BUG 1 After a CTRL write of SIZE=2, scoreboard reports TX size mismatches: expected 1, got 2. Meanwhile the unmapped-access test, which should check APB errors, passes with no checks at all.</b></summary>


**Root cause:** `apb_agent.monitor.output_port.connect(predictor.bus_in)` removed. The mirror never sees the write, so the model aligns with the reset value SIZE=1. Worse, the predictor's `write()` is never called, so every pslverr check it does silently disappears. A missing connection produces both a false failure and a false pass.

**Lesson:** when the model disagrees with the DUT, check the model's *inputs* (mirror, ports) before you blame the RTL.

</details>

<details><summary><b>BUG 2 Test fails at time 0 with NO_VIF fatal from md_rx_agent, but the interface is clearly instantiated.</b></summary>


**Root cause:** path string mismatch, e.g. `"uvm_test_top.env.md_rx_agnt"`, or the agent renamed in `create()`. Debug with `+UVM_CONFIG_DB_TRACE`, which prints every set/get and the path it matched or missed.

</details>

<details><summary><b>BUG 3 A test with a mid-sim reset ends with "N expected items never received" from the scoreboard.</b></summary>


**Root cause:** `scoreboard.handle_reset()` not called, or it doesn't flush its expected queues. Items predicted before the reset are still waiting, and the DUT flushed its FIFOs. The model's `uvm_tlm_fifo`s need flushing too.

</details>

<details><summary><b>BUG 4 Your cfs_algn_test_random_rx_err runs, but the log shows legal transfers with CFS_MD_OKAY.</b></summary>


**Root cause candidates:** (a) the override is registered after the sequence was already created; (b) the sequence was built with `new()` instead of `type_id::create()`, which bypasses the factory; (c) the override names the wrong type, e.g. the parameterized vs base class. Check with `factory.print()` in `end_of_elaboration_phase`.

</details>

<details><summary><b>BUG 5 Regression is 100% green, coverage is 100%, yet a silicon bug: the DUT drops the last TX chunk when RX traffic stops.</b></summary>


**Root cause:** the scoreboard compares what arrives but never checks for *missing* items at end of test. Add a `check_phase` that errors when the expected queue isn't empty, plus a drain time before dropping the objection. Also note the coverage model covered *inputs*, not "all predicted outputs were seen".

</details>

<details><summary><b>"Draw your testbench and walk me through it."</b></summary>


Draw the map above from memory in this order: interfaces and DUT, the three agents (say *why* each is master, slave or reactive), the model fed only from monitors, the scoreboard comparing model vs agents, the RAL plus explicit predictor, coverage, and the virtual sequencer. Then trace one RX transfer (1.2). Finish with reset handling. Most candidates forget reset entirely.

Cross-questions

- Why is the scoreboard not just inside the model?
- What changes if this env is reused at SoC level where the CPU drives APB? (APB agent goes passive, the predictor still works because it's monitor-driven, and the white-box `algn_if` probes need a bind or must go.)
- Where would a C++ golden model plug in? (Behind the model's `write_in_rx` via DPI-C. Ports and scoreboard stay unchanged.)

</details>

<details><summary><b>"Analysis port vs TLM FIFO vs uvm_tlm_analysis_fifo: when do you use each here?"</b></summary>


Analysis port: monitor broadcast, non-blocking, zero-time, any number of subscribers. `uvm_tlm_fifo`: inside the model, to buffer items and let a separate thread consume them with blocking `get()`, which is how the model mimics the DUT's FIFOs and back-pressure. `uvm_tlm_analysis_fifo`: when a subscriber must do time-consuming work per item, because it decouples `write()` from processing.

Cross-question

- What happens if a subscriber's `write()` calls a task? (Compile error, since `write` is a function. If someone forks inside it, ordering between items is lost.)

</details>

<details><summary><b>"How does your environment handle reset in the middle of traffic?"</b></summary>


The env's `run_phase` runs forever: wait reset assert → `handle_reset()` on every stateful component (model flushes FIFOs and resets the mirror, scoreboard clears queues, coverage resets sampling state) → wait deassert. Agents do the same internally: drivers stop and release the bus, sequencers drop pending items, monitors abandon a half-captured item. Tests must also tolerate killed sequences.

Cross-questions

- Why not use UVM's reset/configure/main phases? (Runtime sub-phases are fragile with multiple resets and with VIP from different vendors. Most teams use an event-driven reset like this one.)
- How do you test it? (A test that asserts reset at random points with FIFOs non-empty, then checks registers equal reset values and traffic resumes cleanly.)

</details>


### Interfaces & protocol assertions  
*Notes: [notes/senior-lab/02-interfaces-protocol-assertions.md](notes/senior-lab/02-interfaces-protocol-assertions.md)*

<details><summary><b>BUG 1 You rewrite the stability check as valid & !ready |=> $stable(data) . Back-to-back legal transfers now pass, but a DUT bug where data changes in the same cycle ready rises is missed.</b></summary>


**Root cause:** `|=>` checks the *next* cycle and only while ready is low now. The original form looks at the previous cycle's handshake state, so it covers every cycle up to and including the accept cycle. Draw the waveform before choosing `|->` vs `|=>`.

</details>

<details><summary><b>BUG 2 Your error-injection test sets vif.has_checks = 0 from the test to drive illegal traffic, and gets an ALGORITHM_ISSUE error.</b></summary>


**Root cause:** the agent config owns the knob. Call `agent_config.set_has_checks(0)`, which updates both the class flag and the interface. Interviewers like this one: "who owns a knob that lives in two places?"

</details>

<details><summary><b>BUG 3 A reset in the middle of a transfer fires VALID_HIGH_UNTIL_READY_A .</b></summary>


**Root cause:** it would, without `disable iff(!reset_n)`. Valid legally drops during reset. The `disable iff` is evaluated asynchronously, so it also aborts attempts that started before reset. Remove it and see the false failure.

</details>

<details><summary><b>"What's the difference between |-> and |=> , and when does $past beat both?"</b></summary>


`|->` checks the consequent in the same cycle the antecedent matches; `|=>` checks it one cycle later. `$past` lets you trigger on the *effect* (valid fell) and check the *cause* (ready last cycle), so the assertion only does work at violation points. It's cheaper and its failure message points at the exact cycle.

Cross-questions

- What does `$past` return at the first clock after reset? (The initial value. Guard with reset or `disable iff`.)
- Why are sampled values taken in Preponed? (So the assertion sees a stable, race-free snapshot regardless of process ordering at the edge.)

</details>

<details><summary><b>"Assertions in the interface, in a bind -ed checker, or in the monitor: which and why?"</b></summary>


Pure signal-level protocol goes in the interface or a bound checker: zero-time, reusable at SoC level, and formal-friendly. `bind` wins when you can't edit the interface, or need to reach internal RTL signals. The monitor (procedural checks) is for things needing transaction context, like the stuck-transfer threshold. Data correctness goes to the scoreboard, never SVA.

Cross-question

- How would you formally prove the legality rule? (Assume the APB and MD protocols as constraints, assert `md_rx_err == !legal(offset,size)` at handshake. With 4×8 input combos, it converges in seconds.)

</details>

<details><summary><b>"Why does your TB work without clocking blocks? Would you add them?"</b></summary>


Drivers write with NBAs and sample right after the edge, which reads pre-edge values. The monitor adds a 1 ns skew. That's correct but fragile: a blocking assignment or a `#0` somewhere breaks it. Clocking blocks encode input/output skew in one place and make the synchronisation contract explicit. I'd add them in a production VIP, and keep this pattern only for teaching.

</details>


### Agent anatomy: the APB agent  
*Notes: [notes/senior-lab/03-agent-anatomy-the-apb-agent.md](notes/senior-lab/03-agent-anatomy-the-apb-agent.md)*

<details><summary><b>BUG 1 After a refactor, every test dies at time 0 with One must implement collect_transaction() task .</b></summary>


**Root cause:** the `set_inst_override` calls were moved from `new()` into `build_phase()` after `super.build_phase()`. The base already created the generic monitor. Overrides must be registered before the `create()` they're meant to affect.

</details>

<details><summary><b>BUG 2 Register reads with 0 wait states compare fine. Reads with wait states return stale data.</b></summary>


**Root cause:** the monitor samples `prdata` on the first access cycle instead of after the `pready` loop. With 0 wait states the two cycles coincide, so only longer transfers expose it. That's why coverage on `length` matters: without the 3–10 bins, you'd never know whether the bug could be hit.

</details>

<details><summary><b>BUG 3 PENABLE_AT_SETUP_PHASE_A fires on every transfer after someone "optimised" the driver.</b></summary>


**Root cause:** `psel` and `penable` are now driven in the same cycle, so the setup phase was skipped. The interface assertion caught a driver bug that no scoreboard would, because the DUT may still respond correctly.

</details>

<details><summary><b>"Walk me through what's inside a UVM agent and what changes in passive mode."</b></summary>


Config (vif, knobs), sequencer (arbitrates sequences), driver (item → pins), monitor (pins → item, broadcast on an analysis port), optional coverage. Passive keeps the monitor and coverage and drops the driver and sequencer. In this codebase the base agent does all of that generically, and protocol classes only implement `drive_transaction` and `collect_transaction`.

Cross-questions

- Why does the monitor write to an analysis port instead of calling the scoreboard? (Decoupling: zero or many subscribers, no knowledge of who listens.)
- `get_next_item/item_done` vs `get/put`? (The first holds the sequence until the item is done and suits pipelined-off protocols. `get`/`put` lets the driver return a response object later, as pipelined drivers do.)

</details>

<details><summary><b>"Type override vs instance override vs set_type_override_by_name : when do you use each?"</b></summary>


Type override replaces every creation of that type, which is right for "all MD sequences become error sequences" (your rx\_err test). An instance override replaces it under one hierarchy path, which is what the agents use so the APB and MD agents can both extend the same generic base without colliding. By-name overrides avoid a compile-time dependency, but they don't work for parameterized classes, which register without a name.

</details>


### The reactive slave: MD TX agent  
*Notes: [notes/senior-lab/04-the-reactive-slave-md-tx-agent.md](notes/senior-lab/04-the-reactive-slave-md-tx-agent.md)*

<details><summary><b>BUG 1 New test: first TX transfer → fatal FIFO … pending_items is full .</b></summary>


**Root cause:** the test never started `cfs_md_sequence_slave_response_forever` on `env.md_tx_agent.sequencer`. Compare with `cfs_algn_test_random`, which forks it at the top of `run_phase`.

</details>

<details><summary><b>BUG 2 After a cleanup, two responses are queued per DUT transfer and the run stalls on a fatal.</b></summary>


**Root cause:** the `is_active()` filter was removed from the sequencer's `write()`, so the end-of-transfer write also queues a request.

</details>

<details><summary><b>BUG 3 100% pass, but STATUS.TX_LVL never exceeds 2 and the TX_FIFO_FULL IRQ is never seen.</b></summary>


**Root cause:** not a bug, a stimulus hole. The responder is too fast. Add a sequence with `length dist {[0:2]:/80, [20:60]:/20}` and watch TX\_LVL climb. "All tests pass" says nothing about what was exercised.

</details>

<details><summary><b>"How do you build a slave agent that responds to the DUT?"</b></summary>


The monitor detects the start of a transfer and publishes it. The sequencer has an analysis imp that queues those requests. A forever "responder" sequence blocks on that queue, then sends a response item whose fields (latency, error, data) are randomizable, and the driver applies it to the handshake. The responder sequence is the knob tests override.

Cross-questions

- Why not let the driver watch `valid` itself? (Then response policy lives in the driver and tests can't shape it without overrides.)
- How would you handle a memory slave that must return read data? (The responder looks up a memory model keyed by address from the monitored request; the memory is shared by handle with the scoreboard.)
- What if the DUT can have several outstanding requests? (A deeper queue, ID-based matching, out-of-order responses.)

</details>


### The register model (RAL)  
*Notes: [notes/senior-lab/05-the-register-model-ral.md](notes/senior-lab/05-the-register-model-ral.md)*

<details><summary><b>BUG 1 After CTRL.write() with CLR=1, the next STATUS read fails: mirror says CNT_DROP=37, DUT says 0.</b></summary>


**Root cause:** the `cfs_algn_clr_cnt_drop` callback isn't registered (see `model.connect_phase`). UVM updated CTRL.CLR but knew nothing about the side effect on STATUS.

</details>

<details><summary><b>BUG 2 A test writes an illegal CTRL value via CTRL.write() , gets UVM_IS_OK , and then waits forever for traffic aligned to that config.</b></summary>


**Root cause:** the frontdoor status is meaningless here (no driver response). The DUT rejected the write, the predictor correctly left the mirror alone, but the test trusted the returned status.

</details>

<details><summary><b>BUG 3 IRQ register reads mismatch right after a write-1 to clear.</b></summary>


**Likely cause:** the IRQ fields were configured as `"RW"` instead of `"W1C"`. The mirror then stores the 1 you wrote. Another candidate: a new event re-set the bit in the same cycle, an unspecified priority from Module 0.

</details>

<details><summary><b>"Explain implicit, explicit and passive prediction. Which do you use and why?"</b></summary>


Implicit (auto-predict) updates the mirror from the register call itself. It's simple, but blind to accesses not made through RAL and to bus errors. Explicit: a predictor fed by the bus monitor updates the mirror from observed transfers, so it catches everything on the bus. Passive is the same predictor with no RAL-driven traffic, i.e. SoC level. This env uses explicit prediction with a custom predictor that also checks the response and skips errored accesses.

Cross-questions

- What's `mirror()` vs `read()`? (`mirror(UVM_CHECK)` reads and compares against the mirror. `read()` returns the value and, with check\_on\_read, also compares.)
- Backdoor access: when is it dangerous? (It bypasses the bus, so you skip protocol and side effects like W1C, read-clear and CLR.)
- How do you handle a volatile field? (Mark it volatile and update via predict from a model, or exclude it from compare with `set_compare(UVM_NO_CHECK)`.)

</details>

<details><summary><b>"How would you verify a sticky W1C interrupt register?"</b></summary>


Model sets the bit on the triggering *event* (edge, not level) via `predict(1)`. W1C policy clears the mirror on write-1. Reads compare via check\_on\_read. Coverage: set → read → clear while condition persists → confirm it stays 0 → re-trigger → confirm set. Plus the same-cycle race: clear and set in the same cycle. Ask the designer which wins and code the model to match.

</details>


### The reference model  
*Notes: [notes/senior-lab/06-the-reference-model.md](notes/senior-lab/06-the-reference-model.md)*

<details><summary><b>"Cycle-accurate or transaction-level reference model?"</b></summary>


Transaction-level for data (what bytes, in what order), plus cycle-awareness only where the spec defines timing (here: IRQ pulses and FIFO levels visible through STATUS). Cycle-accurate models duplicate the RTL's micro-architecture, so they get the same bugs and break on every pipeline change. When timing is loosely specified, check windows (watchdogs) rather than exact cycles.

Cross-questions

- Is using DUT probes for timing cheating? (It's a trade-off. The data is still predicted independently, but a probe bug or RTL rename silently desynchronises the model. Keep the fallback and make its warning an error.)
- How would you plug in a C model? (DPI-C call inside `align()` taking the byte stream and CTRL and returning TX words; keep the SV threads for timing.)

</details>

<details><summary><b>"Push and pop hit a full FIFO in the same cycle. Is a FIFO_FULL interrupt raised?"</b></summary>


It depends on the definition of "became full". If it means the level register reached MAX at a clock edge, then simultaneous push+pop at MAX−1 never reaches MAX: no interrupt. The model enforces it by deferring the decision with `uvm_wait_for_nba_region()` and cancelling on a same-step pop. The senior part of the answer is naming the ambiguity and getting the spec to state it.

</details>


### The scoreboard  
*Notes: [notes/senior-lab/07-the-scoreboard.md](notes/senior-lab/07-the-scoreboard.md)*

<details><summary><b>"In-order vs out-of-order scoreboard: how do you build each?"</b></summary>


In-order: a queue per stream, push expected, pop and compare on actual. Out-of-order: an associative array keyed by a match key (ID, address, tag), with a search on arrival and an error for an unknown key. Both need end-of-test emptiness checks, plus timeouts if latency is bounded. The hard part is choosing the key when the DUT can merge or split items, as this one does. Then compare at byte-stream level, not item level.

Cross-questions

- Why not compare inside the model? (Separation: swap models, reuse the comparator, and keep "prediction bug" separate from "compare bug".)
- When would you compare at end of test only? (When order and latency are unspecified, e.g. memory contents after a DMA. Compare final state.)

</details>

<details><summary><b>"How do you guarantee nothing was silently dropped?"</b></summary>


Three layers: per-item timeouts while running, a `check_phase` that errors on any non-empty expected queue, and a drain time (or `phase_ready_to_end`) so the test doesn't end with traffic in flight. Plus coverage on "items compared", so a test with zero compares can't count as a pass.

</details>


### Functional coverage  
*Notes: [notes/senior-lab/08-functional-coverage.md](notes/senior-lab/08-functional-coverage.md)*

<details><summary><b>"You have 100% functional and code coverage, and a bug escaped to silicon. How?"</b></summary>


Coverage proves stimulus reached a state, not that a checker looked at it. Typical escapes: (1) the plan missed the feature, so there's no bin; (2) the bins were sampled at the wrong time or double-counted (your MD coverage); (3) crosses missing the dangerous combination (same-cycle CLR and err); (4) checks disabled or too weak; (5) the bug is in an interaction across features each covered alone. Fix the process: tie each bin to a check, review the plan with designers, and add cross and temporal coverage for interactions.

</details>

<details><summary><b>"Code coverage vs functional coverage: which do you sign off on?"</b></summary>


Both, for different questions. Code coverage asks "did we execute the RTL?" and finds dead code and untested branches, but knows nothing about the spec. Functional coverage asks "did we exercise the spec's scenarios?" but only what you thought to write. A line never hit is a real hole. A functional bin never hit is a hole or a wrong bin. Sign-off needs both reviewed, with documented waivers.

</details>


### Sequences, virtual sequences & tests  
*Notes: [notes/senior-lab/09-sequences-virtual-sequences-tests.md](notes/senior-lab/09-sequences-virtual-sequences-tests.md)*

<details><summary><b>"Virtual sequence vs virtual sequencer: do you need the sequencer?"</b></summary>


A virtual sequence only needs handles to the real sequencers. It can get them from a virtual sequencer (`p_sequencer`, as here), from fields set by the test, or from config\_db. The virtual sequencer is convenient and lets vseqs nest, but it's an extra component. Some teams pass handles directly and start vseqs with `start(null)`. Either is fine; consistency matters.

Cross-questions

- `p_sequencer` vs `m_sequencer`? (`m_sequencer` is the base handle that's always set. `` `uvm_declare_p_sequencer `` adds a typed, cast copy for access to custom fields.)
- How do you stop a forever sequence at end of test? (Let the phase end kill it, or `sequencer.stop_sequences()`; never hold an objection inside it.)

</details>

<details><summary><b>"How would you write a test that reconfigures CTRL while traffic is in flight?"</b></summary>


First get the spec to define it: does a new CTRL apply to bytes already in the buffer? Then the model must snapshot CTRL per TX word (or per RX item, as the spec says). The test forks MD traffic and a delayed CTRL write without the `is_empty()` guard, and coverage records "CTRL changed with N bytes buffered". Without the spec decision this test can only find disagreements, not bugs.

</details>


### Bug-hunting lab  
*Notes: [notes/senior-lab/10-bug-hunting-lab.md](notes/senior-lab/10-bug-hunting-lab.md)*

<details><summary><b>STAR Use it as your "hardest bug" interview story</b></summary>


**Situation:** stream aligner with five interrupt sources; random regression was green. **Task:** close IRQ verification. **Action:** wrote a test that saturates the drop counter. It failed only on some seeds; I bucketed the failing seeds by IRQEN value, traced the scoreboard's expected IRQ to the model's MAX\_DROP prediction, checked IRQ.MAX\_DROP in the register (set correctly), then found the missing OR term on the pin. **Result:** RTL fix, a new covergroup on event × enable, and a rule to run IRQ tests across ≥20 seeds. Point out *why* random tests missed it: the event needed 255 errors *and* a 50% enable bit.

</details>

<details><summary><b>INJ 1 cfs_rx_ctrl.v : change the legality test from != 0 to == 0 .</b></summary>


**Fires:** scoreboard `Mismatch detected for the RX response` on the very first item. Then the model pushes legal items the DUT dropped, so TX watchdogs fire too. Fix the first error only.

</details>

<details><summary><b>INJ 2 cfs_rx_ctrl.v : remove the saturation check so CNT_DROP wraps at 256.</b></summary>


**Fires:** only in `rx_err` (≥256 errors), and only when STATUS is read afterwards: RAL check-on-read mismatch (mirror 255, DUT 44). `test_random` never catches it, which is a coverage lesson.

</details>

<details><summary><b>INJ 3 cfs_rx_ctrl.v : md_rx_ready = push_valid & push_ready (drop | md_rx_err ).</b></summary>


**Fires:** an illegal transfer is never accepted. RX response watchdog ("not received after 10 clock cycles"), and if the test runs long enough the monitor's stuck threshold (1000 cycles) as `PROTOCOL_ERROR`.

</details>

<details><summary><b>INJ 4 cfs_regs.v : change RESET_VAL of the RX-empty edge detector from 1 to 0.</b></summary>


**Fires:** a fake "became empty" edge right after reset. With IRQEN.RX\_FIFO\_EMPTY=1 you get `Unexpected IRQ detected`, and IRQ.RX\_FIFO\_EMPTY reads 1 unexpectedly (RAL mismatch). The RAL catches it even with IRQEN=0.

</details>

<details><summary><b>INJ 5 cfs_regs.v : a write to STATUS returns pslverr = 0 .</b></summary>


**Fires:** the custom predictor: `Mismatch detected for the bus operation status - expected: UVM_NOT_OK, received: UVM_IS_OK … Write access to a full read-only register`. Only in `test_reg_access`.

</details>

<details><summary><b>INJ 6 cfs_ctrl.v : swap the byte order when packing a TX word.</b></summary>


**Fires:** `Mismatch detected for the TX data`, but only when CTRL.SIZE > 1. With SIZE=1 the bug is invisible. Check whether your seed ever configured SIZE 2 or 4.

</details>

<details><summary><b>INJ 7 Build the DUT with FIFO_DEPTH = 16 .</b></summary>


**Fires:** a TB bug, not a DUT bug. The model (hard-coded depth 8) predicts FIFO-full IRQs and caps RX\_LVL at 8. Under back-pressure you get unexpected/missing IRQ errors and STATUS mismatches. Lesson: an error ID says `DUT_ERROR`, the root cause is in the TB.

</details>

<details><summary><b>INJ 8 cfs_regs.v : stop ignoring paddr[1:0] (decode the full address).</b></summary>


**Fires:** nothing. Register tests use aligned addresses, and the unmapped test excludes 0x01–0x03 etc. (Module 9). A complete escape. Fix: add a sequence that accesses each register at +1, +2, +3 and expects the same result as +0.

</details>


### Interview gauntlet: UVM & SystemVerilog  
*Notes: [notes/senior-lab/11-interview-gauntlet.md](notes/senior-lab/11-interview-gauntlet.md)*

<details><summary><b>Explain the factory. Name three ways an override silently doesn't apply.</b></summary>

**Model answer:** The factory maps a requested type (or instance path) to the type actually constructed, as long as objects are made with type_id::create. Silent failures: (1) the object is built with new(), bypassing the factory; (2) the override is registered after the create() it should affect (e.g. in build_phase after super.build_phase created the child); (3) the override targets a different specialization of a parameterized class, or uses by-name overrides on a param class, which registers without a name. Debug with factory.print() and print_topology().

**Cross-questions:**

- Type vs instance override precedence?
- Why do your agents use instance overrides in the constructor?

</details>

<details><summary><b>Two sequences run on one sequencer. How is the order decided, and how do you make a 3-item register update atomic?</b></summary>

**Model answer:** The sequencer arbitrates per item using its arbitration mode (default FIFO by request time; also weighted, random, strict-priority). Items from both sequences interleave. For atomic multi-item operations, lock() (waits its turn, then exclusive) or grab() (jumps the queue). Release with unlock/ungrab. In test_reg_access, the random and unmapped register sequences interleave on the APB sequencer exactly like this.

**Cross-questions:**

- What happens to a locked sequencer if the sequence is killed at reset?
- Priority on start_item vs sequence priority?

</details>


### Interview gauntlet: RTL design  
*Notes: [notes/senior-lab/11-interview-gauntlet.md](notes/senior-lab/11-interview-gauntlet.md)*

<details><summary><b>cfs_rx_ctrl drives md_rx_ready = (push_valid & push_ready) | md_rx_err. What does that imply, and how would you test it?</b></summary>

**Model answer:** Illegal transfers are accepted immediately even when the RX FIFO is full: errors bypass back-pressure, so CNT_DROP can increment while ready would otherwise be low. That's reasonable (nothing is stored) but worth confirming with the designer. Test: fill the RX FIFO with a stalled TX side, then send illegal items, and check they complete in one cycle with err while legal ones stall. Cover 'err while FIFO full'.

**Cross-questions:**

- Is ready combinationally dependent on valid here? Why does that matter for the master?
- What if a master waits for ready before asserting valid?

</details>

<details><summary><b>This core has md_rx_clk, pclk and md_tx_clk. What would you verify and why does the current TB miss it?</b></summary>

**Model answer:** Every crossing: async FIFOs (Gray pointers, full/empty in the right domain), single-bit syncs (2 flops), multi-bit values (CNT_DROP goes through a single-flop cfs_synch, not safe), and reset/clear crossing domains (clr_cnt_dop as async reset). The TB ties all clocks to one clk, so metastability and ratio effects never happen. Add independent clocks with random ratios and jitter, run a CDC lint tool, and assert gray-code properties on pointers.

**Cross-questions:**

- Why is a multi-bit counter unsafe through 2-flop syncs?
- How do you model metastability in simulation?

</details>


### Interview gauntlet: C/C++ infrastructure  
*Notes: [notes/senior-lab/11-interview-gauntlet.md](notes/senior-lab/11-interview-gauntlet.md)*

<details><summary><b>How would you replace the SV alignment algorithm with a C++ golden model?</b></summary>

**Model answer:** Write the algorithm as a pure C++ function (bytes in, CTRL in, TX words out) and unit-test it with GoogleTest on host. Export it via a thin C wrapper and import it with import "DPI-C" function. Pass open arrays (byte unsigned data[]) and use svSize/svGetArrElemPtr. Keep the SV threads for timing; call DPI only for the data transform. Keep it 'pure' (no static state) where possible for safety; if it must keep state, key it by instance handle. Build it into the sim's shared library in the Makefile.

**Cross-questions:**

- What does 'context' on a DPI import allow, and what does it cost?
- Who owns memory returned from C?

</details>

<details><summary><b>Write the legality rule in C++ and describe a self-check for it.</b></summary>

**Model answer:** bool legal(unsigned W, unsigned off, unsigned size){ unsigned B = W/8; return size != 0 && (B+off) % size == 0 && off+size <= B; }  Self-check: loop over all W in {8,16,32,64}, every off < B and size ≤ 2B−1, and compare against a table derived by hand from the spec. Also compare against the SV model through DPI for the same inputs. Exhaustive is cheap because the space is tiny, so prefer it over random.

**Cross-questions:**

- Where would you put this so SV constraints, model and coverage all use one definition?

</details>


### Interview gauntlet: Coverage  
*Notes: [notes/senior-lab/11-interview-gauntlet.md](notes/senior-lab/11-interview-gauntlet.md)*

<details><summary><b>100% functional and code coverage, yet a bug escaped. Give three concrete reasons from this testbench.</b></summary>

**Model answer:** (1) Bins sampled at the wrong time: MD coverage samples the transfer at start, so the OKAY/length=1 bins fill even with no such transfer. (2) The plan had no bin: nothing covers IRQ source × enable, so MAX_DROP-to-pin was never required. (3) Stimulus guards: test_random never reconfigures under traffic, and the unmapped test never uses paddr[1:0]≠0. Coverage proves reached states, not checked behaviour.

**Cross-questions:**

- How would you tie each covergroup bin to a check?
- What would you put in a coverage review with designers?

</details>

<details><summary><b>illegal_bins vs ignore_bins vs an assertion: when do you use each?</b></summary>

**Model answer:** ignore_bins: unreachable or out-of-scope combinations, documented. illegal_bins: values the DUT must never produce. They error at runtime, so they're effectively checkers and belong only where the coverage sample is DUT output. Assertions: temporal protocol rules, checked every cycle, also usable in formal. Don't use illegal_bins on stimulus you chose not to generate: that encodes TB assumptions as DUT rules.

**Cross-questions:**

- How do you justify an ignore bin in sign-off?

</details>


### Interview gauntlet: Debug  
*Notes: [notes/senior-lab/11-interview-gauntlet.md](notes/senior-lab/11-interview-gauntlet.md)*

<details><summary><b>Nightly regression: 2% of 5000 seeds fail. Walk me through triage.</b></summary>

**Model answer:** Bucket by first-error signature (ID + message stripped of numbers). Biggest bucket first. Reproduce one seed with waves and higher verbosity. Classify: DUT_ERROR vs ALGORITHM_ISSUE vs SVA. Check the spec to decide who's wrong. Correlate failing seeds with config (e.g. IRQEN.MAX_DROP in this TB). Shrink to a minimal directed test, file the bug, then add the test and a covergroup so it can't regress. Track the fail rate per bucket to confirm the fix.

**Cross-questions:**

- Two buckets share a root cause. How would you notice?
- A failure won't reproduce with the same seed. Why?

</details>

<details><summary><b>Scoreboard says TX data mismatch: expected {11,22} got {22,11}. Where do you look, in order?</b></summary>

**Model answer:** Is CTRL.SIZE > 1 (byte order only matters then)? Check the mirror's CTRL vs the DUT at that time (a predictor or callback bug would make the model align differently). Find the RX items that fed this TX word in the model log. Check the monitor's byte extraction (shift by (offset+i)*8). Then the waveform: md_rx_data lanes vs md_tx_data lanes at those times. Decide with the datasheet figure which order is correct.

**Cross-questions:**

- How would you prove it's not the monitor?

</details>


### Interview gauntlet: Methodology  
*Notes: [notes/senior-lab/11-interview-gauntlet.md](notes/senior-lab/11-interview-gauntlet.md)*

<details><summary><b>How do you decide verification of this block is done?</b></summary>

**Model answer:** Every vplan row has a check and a coverage item that's been hit (or a reviewed waiver). Code coverage reviewed: no unexplained holes. Regression stable over N nights with seed variety, bug-discovery rate flattened. Assertions all have covers hit. Spec ambiguities closed with designers. Known-escape analysis done (what classes of bug could this TB never see? e.g. CDC here). Sign-off is a review, not a number.

**Cross-questions:**

- Which of those does this TB fail today?

</details>

<details><summary><b>Simulation or formal for this aligner? Split the work.</b></summary>

**Model answer:** Formal: legality → md_rx_err, APB error rules, protocol stability, IRQ edge/W1C logic, CNT_DROP saturation. Small state spaces, so exhaustive proofs beat random. Simulation: the data path through FIFOs and the alignment transform (deep state, long sequences), end-to-end with a model. Use formal cover to show reachability of corner cases like 'FIFO full and illegal item same cycle'.

**Cross-questions:**

- What assumptions would your formal setup need on the MD RX interface?

</details>


### Interview gauntlet: Advanced scenarios  
*Notes: [notes/senior-lab/11-interview-gauntlet.md](notes/senior-lab/11-interview-gauntlet.md)*

<details><summary><b>Reuse this env at SoC level with four aligner instances behind an interconnect.</b></summary>

**Model answer:** Make the env instantiable per aligner (config object per instance, unique vif names via config_db paths or a vif array). APB agents go passive (the CPU drives), the predictor keeps working off monitors, and the reg block becomes a sub-block of the SoC block with an offset per instance. MD agents become passive monitors on internal interfaces, hooked up via bind. White-box probes (algn_if) must move to bind as well. The model and scoreboard reuse unchanged. Add an SoC-level vseq that coordinates instances.

**Cross-questions:**

- What breaks first if you just copy-paste the env four times?

</details>

<details><summary><b>Regression takes 10 hours. Cut it to 2 without losing quality.</b></summary>

**Model answer:** Measure first: per-test sim time and coverage contribution. Drop or shorten tests with no unique coverage (coverage-driven test ranking). Turn off waves and high verbosity by default. Reduce UVM_INFO string formatting in hot paths (the monitors log every item at UVM_LOW). Compile once and run many (separate compile and elaborate). Parallelize across a farm. Use coverage-guided seed selection. Move exhaustive small spaces (legality, APB errors) to formal.

**Cross-questions:**

- How do you prove the shorter regression didn't lose bug-finding power?

</details>


## Lecture companion: Course intro


### Course introduction  
*Notes: [notes/uvm-from-zero/01-course-intro.md](notes/uvm-from-zero/01-course-intro.md)*

<details><summary><b>"Walk me through a UVM testbench you built."</b></summary>


**Shape your answer in 4 parts:** (1) the DUT in one sentence: "an aligner that repacks unaligned byte streams into fixed-size chunks, with APB registers and interrupts". (2) The architecture: one APB agent, two MD agents (master on RX, reactive slave on TX) built on a shared extension library, a reference model that holds the RAL register model, an explicit predictor, a scoreboard, coverage and a virtual sequencer. (3) The tests: register access, random traffic, illegal traffic, and what each one proved. (4) A bug you found and how. End with what you'd improve.

</details>

<details><summary><b>"Why UVM rather than a plain SystemVerilog testbench?"</b></summary>


Reuse and scale. Standard component roles (agent, monitor, scoreboard) mean anyone can read the testbench. The factory lets tests change behaviour without editing the environment. Phasing gives a fixed build/connect/run order. config\_db passes settings without hard-wiring. TLM ports decouple components. Agents move unchanged to the next project or to SoC level.

</details>


### What is design verification?  
*Notes: [notes/uvm-from-zero/01-course-intro.md](notes/uvm-from-zero/01-course-intro.md)*

<details><summary><b>"Pre-silicon vs post-silicon verification?"</b></summary>


Pre-silicon checks the RTL in simulation, formal or emulation, before tape-out. Bugs are cheap to fix and you have full visibility of every signal. Post-silicon tests the manufactured chip (on the wafer, then packaged). Visibility is limited to pins and debug logic. It catches manufacturing defects and bugs that escaped pre-silicon, and a fix needs a respin. That's why pre-silicon effort is so large.

</details>

<details><summary><b>"Module-level vs system-level: why do both?"</b></summary>


Module level gives you full control of a block's inputs, so you can hit corner cases (illegal transfers, FIFO full, counter saturation) quickly. At system level those are hard to reach through other blocks. System level finds integration bugs: wrong connections, address maps, clock/reset interactions, end-to-end flows. Module-level components (agents in passive mode, models, scoreboards) are reused at system level.

</details>

<details><summary><b>"Simulation vs formal verification?"</b></summary>


Simulation drives chosen (often random) inputs and checks outputs. It scales to big designs and long scenarios, but only proves the cases you ran. Formal mathematically checks assertions against all possible inputs within bounds. It's exhaustive for small, control-heavy logic (arbiters, protocol rules, the Aligner's legality check) but struggles with deep data paths. Teams use both: formal for small exhaustive properties, simulation for end-to-end data.

</details>

<details><summary><b>"Why separate the model from the scoreboard?"</b></summary>


The model predicts; the scoreboard compares. Keeping them apart lets you replace the model (e.g. with a C++ golden model) without touching compare logic, reuse the scoreboard, and tell "prediction bug" apart from "compare bug" when debugging.

</details>


### The Aligner DUT in depth  
*Notes: [notes/uvm-from-zero/01-course-intro.md](notes/uvm-from-zero/01-course-intro.md)*

<details><summary><b>"What is a W1C sticky register, and how would you verify it?"</b></summary>


The bit is set by hardware when an event happens, stays 1 after the condition goes away (sticky), and is cleared only by writing 1 (W1C). Writing 0 does nothing. Verify: trigger the event and read 1; remove the condition and still read 1; write 0 and still read 1; write 1 and read 0; clear while the condition persists and check it doesn't immediately re-set (it's an edge event); re-trigger and check it sets again.

</details>

<details><summary><b>"Why must your tests send illegal transfers?"</b></summary>


Rejecting them is a spec feature: error response, drop counter increment, saturation at 255, MAX\_DROP interrupt. Legal-only traffic leaves all of that unverified. Error-handling paths are where bugs hide because designers test them least.

</details>

<details><summary><b>"After an APB write returns PSLVERR, what do you check?"</b></summary>


That the register kept its old value: read it back and compare against the value before the failed write. In UVM, the predictor must **not** update the register mirror for an errored access. Otherwise every later prediction is wrong.

</details>

<details><summary><b>"Do FIFO levels count bytes or transactions? Why does it matter?"</b></summary>


Transactions. A 2-byte RX transfer adds 1 to RX\_LVL. With CTRL.SIZE=1 it becomes two TX entries, so TX\_LVL grows by 2. Your model must count the same way, or every STATUS read and FIFO-full interrupt prediction will be off.

</details>

<details><summary><b>"Explain APB setup and access phases, and wait states."</b></summary>


Setup: PSEL=1, PENABLE=0 for exactly one cycle, with address/direction/data valid. Access: PENABLE=1, and the transfer completes on the first cycle PREADY=1. Each cycle with PREADY=0 is a wait state. Signals must stay stable until completion. The Aligner spec says no more than 5 wait states, which is a good assertion to write.

</details>

<details><summary><b>"The IRQ output is a pulse but the IRQ register is sticky. How do you check both?"</b></summary>


Two checks. The register: the model predicts the IRQ bit (set on event, W1C clear) and register reads compare. The pin: on each event, if its IRQEN bit is 1, expect exactly one one-cycle pulse within a small window. If IRQEN is 0, no pulse, but the IRQ bit is still set. Cover every event × enable combination.

</details>


### Environment architecture  
*Notes: [notes/uvm-from-zero/01-course-intro.md](notes/uvm-from-zero/01-course-intro.md)*

<details><summary><b>"Agent coverage vs environment coverage: what's the difference?"</b></summary>


Agent coverage is protocol-level and reusable: APB read/write, error responses, wait-state lengths, MD sizes and offsets. Environment coverage is DUT-feature level: alignment cases (CTRL setting × RX transfer × split), drop counter saturation, interrupts. Agent coverage proves the bus was exercised. Environment coverage proves the *features* were. You need both.

</details>

<details><summary><b>"Why a virtual sequencer?"</b></summary>


Real scenarios coordinate several interfaces: configure CTRL over APB, then send RX traffic, while the TX side applies back-pressure. A virtual sequencer holds handles to all agent sequencers (and, in this project, the model), so one virtual sequence can drive them in order or in parallel.

</details>

<details><summary><b>"How would you structure two agents for the same protocol, one master and one slave?"</b></summary>


Common base classes for item, monitor, coverage, config and agent, parameterized where needed (e.g. data width). Then master and slave subclasses for the driver, sequencer and drive item. The monitor is identical on both sides because it only watches. Factory overrides inside each agent pick the right subclasses.

</details>

<details><summary><b>"What goes in a base test?"</b></summary>


Creating the environment and anything every test shares: default config, common objections and drain time, a topology print, end-of-test checks. Specific tests extend it and only change stimulus and knobs. That avoids copying env setup into every test.

</details>


### Environment coding kick-off: lecture  
*Notes: [notes/uvm-from-zero/01-course-intro.md](notes/uvm-from-zero/01-course-intro.md)*

<details><summary><b>"List the UVM phases. Which consume time?"</b></summary>


build, connect, end\_of\_elaboration, start\_of\_simulation, run, extract, check, report, final. Only run (and its optional sub-phases) is a task that consumes time; the rest are zero-time functions. Build is top-down, most others bottom-up.

</details>

<details><summary><b>"How does UVM know which test to run?"</b></summary>


`run_test()` reads `+UVM_TESTNAME` (it wins over the string argument), asks the factory to create that class by name as `uvm_test_top`, then starts the phases. The class must be registered with `` `uvm_component_utils `` and extend `uvm_test`. A misspelt name gives a fatal "cannot create a component" error.

</details>

<details><summary><b>"Why can components only be created in build_phase?"</b></summary>


UVM needs a fixed hierarchy before connecting ports and running. Connections, config lookups by path and phase scheduling all depend on it. Objects that come and go during simulation (transactions, sequences) are `uvm_object`s, not components, and can be created any time.

</details>

<details><summary><b>"uvm_component vs uvm_object?"</b></summary>


Components are permanent parts of the testbench tree: they have a parent, a hierarchical name and phases (agents, drivers, scoreboards). Objects are temporary data: no parent and no phases (transactions, sequences, config objects). Components use the constructor `new(string name, uvm_component parent)`; objects use `new(string name)`.

</details>


### Environment coding kick-off: practice  
*Notes: [notes/uvm-from-zero/01-course-intro.md](notes/uvm-from-zero/01-course-intro.md)*

<details><summary><b>"What does `uvm_component_utils do?"</b></summary>


It registers the class with the factory (creating the `type_id` proxy so `type_id::create` and overrides work) and adds utility methods like `get_type_name()`. Objects use `` `uvm_object_utils ``. For parameterized classes you use the `_param_` variants.

</details>

<details><summary><b>"Why type_id::create instead of new?"</b></summary>


`create` goes through the factory, so a test can override the type (e.g. swap a sequence for an error-injecting one) without editing the code that creates it. `new` bypasses the factory and overrides silently don't apply.

</details>

<details><summary><b>"Explain objections. What goes wrong if you get them wrong?"</b></summary>


The run phase ends when the objection count reaches zero. Never raised: the test ends at time 0 and "passes" with nothing done. Never dropped: the simulation hangs until a timeout. Dropped too early: traffic still in flight isn't checked. Fix with drain time (`set_drain_time`) or by waiting for the scoreboard to empty before dropping.

</details>

<details><summary><b>"`uvm_info vs $display? How do you control verbosity?"</b></summary>


`` `uvm_info `` adds file, line, time and component path, and is filtered by verbosity: a message prints only if its level is ≤ the component's setting. Change globally with `+UVM_VERBOSITY=UVM_HIGH`, or per component/ID with `+uvm_set_verbosity`, as your `messages.f` does. Errors use `` `uvm_error ``/`` `uvm_fatal ``, which are counted in the final report.

</details>

<details><summary><b>"Why include guards and packages?"</b></summary>


Guards stop a file being compiled twice when several packages include it, which would cause duplicate-definition errors. Packages give a namespace and a single compile unit: tests import the env, the testbench imports tests, and names don't leak or clash.

</details>


## Lecture companion: APB agent


### Agent infrastructure and config_db  
*Notes: [notes/uvm-from-zero/02-apb-agent.md](notes/uvm-from-zero/02-apb-agent.md)*

<details><summary><b>"Why can't a class instantiate an interface? How does the agent reach the pins?"</b></summary>


Interfaces are elaborated statically, like modules, while classes are created dynamically at run time. The testbench instantiates the interface and connects it to the DUT, then stores a `virtual` interface handle in `uvm_config_db`. The agent gets it with `get()` and hands it to the driver and monitor (here via the agent config).

</details>

<details><summary><b>"Explain the four arguments of uvm_config_db::set."</b></summary>


**context**: the component the path is relative to (`null` from a module, else usually `this`). **inst\_name**: the hierarchical path of the components allowed to read it, with wildcards allowed. **field\_name**: the key string. **value**: the data, typed by the class parameter. The reader's type, path and key must all match, or `get` returns 0.

</details>

<details><summary><b>"Two set() calls for the same field from different levels: which wins?"</b></summary>


During build, a set() from higher in the hierarchy wins: the top module (null context), then the test, then the env. That's what lets a test override an env default. After build (e.g. in run phase), the most recent set() wins. Check with `+UVM_CONFIG_DB_TRACE`, and avoid setting the same field from several levels.

</details>

<details><summary><b>"Agent config as uvm_object or uvm_component?"</b></summary>


An object is lighter: created anywhere, passed by config\_db, no phases. That's the most common style. A component (this project) gets phases, so it can validate settings in `start_of_simulation` and police knobs in `run_phase`, and it can be factory-overridden per instance easily. The cost is that it's part of the hierarchy and must be created in build. Either is fine if you can justify it.

</details>

<details><summary><b>"Why getters and setters instead of public fields?"</b></summary>


The setter can validate (vif set only once; stuck threshold ≥ 2) and keep things in sync (has\_checks copied to the interface). Public fields allow silent misuse. It's the same encapsulation argument as in any OOP language.

</details>


### The APB driving item  
*Notes: [notes/uvm-from-zero/02-apb-agent.md](notes/uvm-from-zero/02-apb-agent.md)*

<details><summary><b>"How do you decide what goes in a sequence item?"</b></summary>


Everything the stimulus side controls and nothing the protocol fixes. Remove signals driven by the other side and signals whose behaviour is fully determined by the protocol (PSEL/PENABLE). Add timing knobs (delays) so tests can create back-to-back and idle traffic. Response fields go in the monitor item, not the drive item.

</details>

<details><summary><b>"Soft vs hard constraints?"</b></summary>


A soft constraint is a default that's dropped if it conflicts with another constraint, e.g. a test's inline `with {pre_drive_delay == 50;}`. A hard constraint can't be overridden. A conflict means randomize fails. Use soft for preferences and hard for legality and physical limits.

</details>

<details><summary><b>"Why separate drive and monitor items?"</b></summary>


They carry different information. The driver needs intent (delays); the monitor records what happened (response, length, gap since the previous item). A shared base avoids duplicating address, direction and data. It also stops anyone from accidentally checking intent against intent.

</details>

<details><summary><b>"What is convert2string for, versus print()/sprint()?"</b></summary>


`convert2string` is a user-written, compact one-line summary for logs. `print`/`sprint` use UVM's printer and field macros to produce tables, which are verbose and slower. Most teams implement `convert2string` by hand.

</details>


### The sequence mechanism  
*Notes: [notes/uvm-from-zero/02-apb-agent.md](notes/uvm-from-zero/02-apb-agent.md)*

<details><summary><b>"Walk me through what happens when finish_item is called."</b></summary>


`start_item` waits for the sequencer to grant this sequence (arbitration). Then you randomize or set fields. `finish_item` hands the item to the sequencer and blocks. The driver's pending `get_next_item` returns that item. The driver drives it and calls `item_done`, which unblocks `finish_item`, and body continues to the next item.

</details>

<details><summary><b>"`uvm_do vs `uvm_send vs `uvm_do_with?"</b></summary>


`` `uvm_do ``: create, randomize, start/finish. `` `uvm_do_with ``: the same with inline constraints. `` `uvm_send ``: just start/finish, so it keeps whatever values the item already has. Using `` `uvm_do `` on an item a caller already constrained silently discards those constraints. Many teams avoid the macros and write start\_item/randomize/finish\_item explicitly so it's clear what happens.

</details>

<details><summary><b>"What does local:: do in an inline constraint?"</b></summary>


Inside `obj.randomize() with {…}`, names resolve to the object being randomized first. `local::x` forces `x` to resolve in the calling scope (the sequence). Without it, `addr == addr` compares the item's addr with itself, which is always true and constrains nothing.

</details>

<details><summary><b>"m_sequencer vs p_sequencer?"</b></summary>


`m_sequencer` is the generic `uvm_sequencer_base` handle, always set by `start()`. `p_sequencer` exists only if you use `` `uvm_declare_p_sequencer(T) ``. It's the same object, cast to `T`, so you can reach custom fields (e.g. the virtual sequencer's handles to other sequencers).

</details>

<details><summary><b>"Several sequences on one sequencer: what decides order, and how do you keep one atomic?"</b></summary>


Arbitration per item: default FIFO (request order), or weighted, random, strict priority (`set_arbitration`). To keep several items uninterrupted, `lock()` or `grab()` the sequencer, then `unlock`/`ungrab`. In the video's fork, the read and write of the rw sequence get separated by other sequences' items.

</details>

<details><summary><b>"Active vs passive agent?"</b></summary>


Active creates sequencer + driver + monitor and drives the bus. Passive has only the monitor (and coverage) and just observes, e.g. at SoC level where a CPU or another block drives that bus. Controlled by `get_is_active()` or a config field like here.

</details>


### The APB driver  
*Notes: [notes/uvm-from-zero/02-apb-agent.md](notes/uvm-from-zero/02-apb-agent.md)*

<details><summary><b>"Why non-blocking assignments in the driver?"</b></summary>


The DUT's flops sample on the same clock edge the driver wakes up on. A blocking write could land before or after the DUT samples, depending on process order: a race. NBAs update in the NBA region after all active-region sampling, so the DUT always sees the previous value at the edge. Clocking blocks formalize the same thing.

</details>

<details><summary><b>"Why split drive_transactions and drive_transaction?"</b></summary>


The outer task owns the loop and the process that reset can kill and restart. The inner task owns one protocol transfer. Subclasses override only `drive_transaction` for protocol variants, and the reset plumbing stays in one place. That's exactly how the later `uvm_ext_driver` base class is built.

</details>

<details><summary><b>"How would you add a response back to the sequence?"</b></summary>


Clone the request, fill in response fields (PRDATA, PSLVERR), call `set_id_info(req)`, then `item_done(rsp)` or `seq_item_port.put(rsp)`. The sequence calls `get_response(rsp)`. This driver doesn't, so RAL frontdoor calls always return OK and bus errors are judged by the predictor instead (see the senior course).

</details>


### APB protocol checks  
*Notes: [notes/uvm-from-zero/02-apb-agent.md](notes/uvm-from-zero/02-apb-agent.md)*

<details><summary><b>"|-> vs |=>?"</b></summary>


`a |-> b`: if a matches, b must hold in the same cycle. `a |=> b`: b must hold in the next cycle (same as `a |-> ##1 b`). Rule 1 uses both: in setup, PENABLE==0 now (`|->`) and ==1 next (`|=>`).

</details>

<details><summary><b>"Why does the setup-phase sequence need the back-to-back case?"</b></summary>


With back-to-back transfers PSEL never drops, so "PSEL rose" doesn't mark the new setup cycle. The second term catches "PSEL was high and PREADY was high last cycle", i.e. the previous transfer just ended and a new one starts now. Miss it and every back-to-back transfer escapes the PENABLE checks.

</details>

<details><summary><b>"Why are some X-checks gated by PSEL?"</b></summary>


The protocol only cares about address and data while a transfer is happening. X on PADDR when idle is legal, and flagging it would be noise. PSEL itself must never be X. PRDATA only matters on a successful read once PREADY is high. The skill is knowing when each signal must be valid.

</details>

<details><summary><b>"Where should a check live: assertion, monitor or scoreboard?"</b></summary>


Cycle-level signal rules → assertions in the interface (reusable, formal-friendly). Rules needing transaction context or counters (stuck transfer length) → monitor. Data correctness vs a model → scoreboard. Protocol checks belong in the agent so they travel with it to every project.

</details>

<details><summary><b>"How do you know an assertion actually works?"</b></summary>


Make it fail: inject the violation (as the lecturer does in the driver), see it fire, then revert. Add `cover property` for the antecedent so you know it was evaluated with real traffic. A vacuously passing assertion is a common hole.

</details>


### The APB monitor  
*Notes: [notes/uvm-from-zero/02-apb-agent.md](notes/uvm-from-zero/02-apb-agent.md)*

<details><summary><b>"Why must the monitor be independent of the driver?"</b></summary>


It must report what really happened on the pins, including driver bugs and transfers from other masters. It must also work in a passive agent where no driver exists. Taking data from the driver would make the checkers trust the stimulus.

</details>

<details><summary><b>"Analysis port vs TLM put/get port?"</b></summary>


An analysis port is one-to-many, non-blocking, with no acknowledgement: perfect for broadcasting observations. Put/get ports are one-to-one and can block (flow control between producer and consumer). Monitors always use analysis ports. A slow consumer adds a `uvm_tlm_analysis_fifo` on its side.

</details>

<details><summary><b>"Why record length and prev_item_delay at all?"</b></summary>


For coverage. They prove you exercised back-to-back transfers, long idle gaps and wait-state lengths, the timing corners where DUT bugs hide. The monitor measures; coverage decides if it was enough.

</details>

<details><summary><b>"Where exactly do you sample PRDATA and PSLVERR?"</b></summary>


In the cycle where PSEL, PENABLE and PREADY are all 1, the transfer's completion. Sampling earlier works with zero wait states but returns stale data with wait states. That's a classic monitor bug, found only if your stimulus has wait states.

</details>


### APB coverage  
*Notes: [notes/uvm-from-zero/02-apb-agent.md](notes/uvm-from-zero/02-apb-agent.md)*

<details><summary><b>"Coverpoint, cross, transition: give an example of each."</b></summary>


Coverpoint: values of one field (direction READ/WRITE). Cross: combinations of coverpoints (a write that got an error). Transition: order over consecutive samples (a read followed by a write). Crosses multiply bin counts, so filter with `ignore_bins`/`binsof` and cross only what matters to the spec.

</details>

<details><summary><b>"Why cover address bits rather than address values in an agent?"</b></summary>


The agent doesn't know the DUT's address map. Toggling every bit to 0 and 1 proves every address line was exercised, which is protocol-level and reusable. Covering specific registers belongs in DUT-level (environment or RAL) coverage.

</details>

<details><summary><b>"What does option.per_instance do?"</b></summary>


It keeps coverage per covergroup instance instead of merged per type. With two agents of the same type (e.g. MD RX and MD TX) you can see which interface missed a bin. You also name instances (`set_inst_name`) to map them in the verification plan.

</details>

<details><summary><b>"What's a verification plan and how does coverage connect to it?"</b></summary>


A tree of features from the spec, each leaf with how it's checked and which coverage proves it. Leaves map to covergroups, coverpoints or assertions. Merged regression coverage is annotated back onto the tree, so sign-off reviews show per-feature percentages, not one meaningless total.

</details>

<details><summary><b>"Why cover 'reset during a transfer'?"</b></summary>


Reset mid-transfer is a classic corner: the DUT must abort cleanly and the testbench must not hang or mis-report. If coverage never sees it, you have no evidence it was tested. In the video it stays 50% until a test actually injects reset during an access.

</details>


### Reset handling in the agent  
*Notes: [notes/uvm-from-zero/02-apb-agent.md](notes/uvm-from-zero/02-apb-agent.md)*

<details><summary><b>"How does your agent handle reset in the middle of a transfer?"</b></summary>


The agent's run\_phase loops: wait for reset assertion (async), call `handle_reset` on every child implementing the reset-handler interface class, wait for release (sync). The driver kills its drive process and drives idle values. The sequencer stops sequences and drops stray objections. The monitor kills its collect process. Coverage samples "transfer in progress at reset". After release, driver and monitor restart their loops.

</details>

<details><summary><b>"Why must the sequencer be reset too?"</b></summary>


The driver was killed between `get_next_item` and `item_done`, so the sequencer still thinks an item is outstanding. The next `get_next_item` errors ("called twice without item\_done") or the sequence hangs. `stop_sequences()` clears that state.

</details>

<details><summary><b>"What is an interface class and why use it here?"</b></summary>


A class with only pure virtual methods that other classes `implements`, in addition to their one `extends`. Driver, monitor, sequencer and coverage have different UVM parents but share a `handle_reset()` contract. The agent loops over children, `$cast`s to the interface class, and calls it. Adding a new resettable child needs no agent change.

</details>

<details><summary><b>"Why not use UVM's reset_phase?"</b></summary>


Run-time sub-phases assume reset happens once at the start and are awkward to jump back to. A mid-test reset needs every component to react at any time. An event-driven loop on the reset signal handles any number of resets and works with VIPs that don't use sub-phases. Most teams do it this way.

</details>

<details><summary><b>"process::kill vs disable fork?"</b></summary>


`kill()` terminates one process you hold a handle to, from anywhere (e.g. from the reset function). `disable fork` terminates all child processes of the current process, used here to clean up anything `drive_transactions` might have forked, so no zombie threads keep driving after reset.

</details>


## Lecture companion: MD agent (reactive)


### The MD protocol: extracting rules from a DUT spec  
*Notes: [notes/uvm-from-zero/03-md-agent-reactive.md](notes/uvm-from-zero/03-md-agent-reactive.md)*

<details><summary><b>"Your DUT has a custom interface with no spec. How do you build its VIP?"</b></summary>


Extract the protocol from the DUT spec: list signals with direction and width, then turn every behavioural sentence into a numbered rule. Separate **protocol** rules (true for any device on this bus, go into the agent) from **DUT** rules (this device's behaviour, go into the model/scoreboard). Add implied rules (no X, bounded length) and confirm them with the designer. Then build the agent so it can also violate DUT-level rules, for negative testing.

</details>

<details><summary><b>"Why shouldn't an agent refuse to send transfers the DUT considers illegal?"</b></summary>


Because rejecting them is DUT behaviour you must verify (error response, counter, interrupt). The agent's legality must match the **protocol**, not the DUT. Bake the DUT's rules into the agent and the error-handling logic can never be stimulated.

</details>

<details><summary><b>"Who decides an implied rule like 'offset + size ≤ bus bytes' is real?"</b></summary>


The designer and system architect, not the verifier. Write the assumption down, ask, and record the answer in the spec or vPlan. In this project the rule isn't in the datasheet; the RTL enforces it on CTRL writes but not on the RX port. That's a gap you only find by asking (see the senior course).

</details>


### Agent architecture: one family, two aspects  
*Notes: [notes/uvm-from-zero/03-md-agent-reactive.md](notes/uvm-from-zero/03-md-agent-reactive.md)*

<details><summary><b>"How would you structure a VIP that supports both master and slave modes?"</b></summary>


Shared interface, monitor, coverage and sequencer base. Driver, drive item, config and agent each get a common base and two subclasses. The agent subclass uses factory instance overrides to pick its driver, config and sequencer. The env just instantiates `agent_master` or `agent_slave`. Shared code is written once, and a fix applies to both modes.

</details>

<details><summary><b>"`define vs parameter for a bus width?"</b></summary>


A `` `define `` is global and compile-time: simple, but one value for the whole simulation. A parameter is per instance, so two agents of different widths can coexist. The cost is that every dependent class must be parameterized too, and mistakes cause type-mismatch compile errors (which the course runs into). Rule of thumb: parameters for reusable VIP, defines for one-off code.

</details>


### Infrastructure and the factory override  
*Notes: [notes/uvm-from-zero/03-md-agent-reactive.md](notes/uvm-from-zero/03-md-agent-reactive.md)*

<details><summary><b>"Type override vs instance override?"</b></summary>


`set_type_override`: every creation of type A anywhere becomes B. `set_inst_override`: only creations under a given hierarchical path (and optionally a given instance name) become B. The MD agents need instance overrides: the master and slave agents swap the same base types for *different* subclasses. A type override would make both the same.

</details>

<details><summary><b>"Why put the override in the constructor?"</b></summary>


The parent's build\_phase calls `create()` on its children, and the override must already exist at that moment. A component's constructor runs while its parent is in build, before this component's own build\_phase. Overrides registered after the create silently do nothing.

</details>

<details><summary><b>"Two agents need two different interfaces stored under the same name. How?"</b></summary>


Use the same key ("vif") but different instance paths in `set()`: `…env.md_rx_agent` vs `…env.md_tx_agent`. Each agent's `get(this, "", "vif", …)` matches only its own path. The agent code stays generic and doesn't need to know whether it's RX or TX.

</details>


### Master driving: items without parameters  
*Notes: [notes/uvm-from-zero/03-md-agent-reactive.md](notes/uvm-from-zero/03-md-agent-reactive.md)*

<details><summary><b>"How do you keep a parameter out of sequences?"</b></summary>


Make the item width-independent (a byte list), put width-dependent constraints in the sequence using a value read at `pre_randomize`, and type `p_sequencer` as a non-parameterized base whose virtual `get_data_width()` is implemented by the parameterized subclass. Sequences then compile once for any width.

</details>

<details><summary><b>"Where should constraints live: item or sequence?"</b></summary>


The item has universal defaults (soft, safe at any configuration) and true invariants (size > 0). The sequence has context-dependent limits (bus width, DUT state) and scenario intent. The item stays reusable, and each sequence can disable soft defaults with `constraint_mode(0)`.

</details>

<details><summary><b>"What is pre_randomize used for?"</b></summary>


It's called automatically just before the solver runs. Use it to compute non-random state that constraints depend on: here, reading the bus width from the sequencer into a local variable. It also avoids calling functions inside constraints, which one simulator rejected (M7).

</details>


### The MD monitor: two broadcasts per transfer  
*Notes: [notes/uvm-from-zero/03-md-agent-reactive.md](notes/uvm-from-zero/03-md-agent-reactive.md)*

<details><summary><b>"Why would a monitor publish a transaction at its start?"</b></summary>


Reactive agents and predictive models need to act during the transfer: a slave must decide ready/err latency based on the request; a model can predict the response or occupancy right away. End-only publication works for passive checking, but not for reacting.

</details>

<details><summary><b>"How do subscribers tell the start event from the end event?"</b></summary>


With `uvm_transaction::is_active()`: true after `begin_tr` and before `end_tr`. Alternatives are two separate analysis ports, or a phase field in the item. Note that both writes pass the **same object handle**, which keeps changing, so subscribers that store it must clone it.

</details>

<details><summary><b>"Why sample 1 ns after the clock edge? Isn't that a hack?"</b></summary>


It gives the testbench a decision window in the same cycle a transfer starts, needed for zero-latency responses. It's the same thing as a clocking-block input skew, done by hand. Making it a config field keeps it adjustable. The risk: it must be smaller than the clock period and robust to timescale changes.

</details>


### The reactive slave: answering the DUT  
*Notes: [notes/uvm-from-zero/03-md-agent-reactive.md](notes/uvm-from-zero/03-md-agent-reactive.md)*

<details><summary><b>"Design a slave agent whose response depends on the request."</b></summary>


The monitor publishes the request at its start. An analysis imp in the slave sequencer pushes it into a TLM FIFO. A forever "responder" sequence blocks on `get()`, then randomizes a response item constrained by the request (e.g. err for illegal offset/size, latency from a distribution) and sends it to the driver. Tests change behaviour by overriding the responder sequence. The FIFO depth matches the protocol's maximum outstanding requests (1 here).

</details>

<details><summary><b>"Why put the analysis imp in the sequencer rather than the sequence?"</b></summary>


Analysis imps are TLM components that need a `uvm_component` parent and must be connected in connect\_phase. Sequences are short-lived `uvm_object`s created at run time. The sequencer is a component, lives in the agent next to the monitor, and every sequence reaches it through `p_sequencer`.

</details>

<details><summary><b>"What is uvm_tlm_fifo and which methods matter?"</b></summary>


A bounded FIFO component with TLM put/get interfaces. Blocking `put`/`get` (tasks), non-blocking `try_put`/`try_get` (return success), `peek`, `is_full`, `is_empty`, `used`, `flush`. The lecturer notes that some methods appear in the source code but not the HTML reference: read the source.

</details>

<details><summary><b>"What's variable hiding and when is it acceptable?"</b></summary>


A subclass declares a member with the same name as a parent member. Inside the subclass the new one is used; the parent's code still sees its own. Here it gives a more specific type for the same object (filled via `$cast`). It works, but it's error-prone: two handles must be kept in sync. A typed getter or a parameterized base is cleaner.

</details>


### MD protocol checks, and making code run on three simulators  
*Notes: [notes/uvm-from-zero/03-md-agent-reactive.md](notes/uvm-from-zero/03-md-agent-reactive.md)*

<details><summary><b>"How do you validate a parameter value?"</b></summary>


With an elaboration-time check: a generate-style `if` with `$error`/`$fatal` outside procedural code, which fires once during elaboration before simulation starts. A concurrent assertion would re-check a constant every clock. An initial block works but runs only after elaboration and doesn't stop the build.

</details>

<details><summary><b>"Your VIP works on one simulator and fails on another. What do you do?"</b></summary>


Expect it: language support differs in corners (system functions in constant contexts, functions in constraints, formatting in elaboration tasks). Keep a regression on every supported simulator, stick to widely supported constructs, isolate tool workarounds behind macros (`` `ifdef VCS ``…), and prefer simple equivalent forms like the $log10/$clog2 trick.

</details>

<details><summary><b>"How do you prove an assertion like 'valid stays high until ready' is not vacuous?"</b></summary>


Its antecedent must actually occur: valid high with ready low. Normal traffic never produced that because the DUT was always ready. You must create back-pressure (fill the FIFO), then inject a violation to see it fire. Add a `cover property` for "valid high, ready low" to prove the scenario happens in regressions.

</details>


### MD coverage  
*Notes: [notes/uvm-from-zero/03-md-agent-reactive.md](notes/uvm-from-zero/03-md-agent-reactive.md)*

<details><summary><b>"Your coverage is stuck at 72%. How do you close it?"</b></summary>


Find which bins are empty (GUI or report), then ask why. Is the bin unreachable (fix with an ignore\_bin plus justification)? Is it reachable but the stimulus is constrained away from it (relax constraints or add a directed sequence)? Is it just too rare (more seeds or items, or bias with `dist`)? Then re-run and confirm. In the video: an over-constrained test, then too few items.

</details>

<details><summary><b>"Why does TX coverage of offset/size look bad, and is that a problem?"</b></summary>


The DUT's TX output is determined by CTRL.SIZE/OFFSET, so one configuration produces one combination. It's not an agent problem; it's a **test** coverage gap: tests must reprogram CTRL across all legal settings. Agent coverage reveals what the environment's stimulus didn't do.

</details>

<details><summary><b>"ignore_bins vs illegal_bins in this cross?"</b></summary>


offset + size beyond the bus is physically impossible, so `ignore_bins` removes it from the target. `illegal_bins` would raise an error if hit, turning coverage into a checker; that job belongs to the interface assertion (rule 15). Aligner-illegal combos stay as normal bins because they must be exercised.

</details>


## Lecture companion: UVM extension library


### Why build a base library?  
*Notes: [notes/uvm-from-zero/04-uvm-extension-library.md](notes/uvm-from-zero/04-uvm-extension-library.md)*

<details><summary><b>"Your team builds a new agent every project. How would you speed that up?"</b></summary>


Two steps. (1) A base-class library: parameterized base agent, config, driver, monitor, sequencer and coverage that implement reset handling, active/passive, vif plumbing and wiring once. (2) A code generator: templates for common agent shapes (master-only, master+slave) and a script that stamps out the files with the right prefixes. Engineers then write only the protocol: items, drive and collect logic, coverage. Fewer lines, fewer copy-paste bugs, consistent structure.

</details>

<details><summary><b>"Isn't this just rebuilding UVM?"</b></summary>


No. UVM provides generic roles (`uvm_driver` has no reset handling and no idea where the vif lives). The extension layer encodes your team's conventions on top: how reset works, how config is passed, how checks and coverage are switched. It's the layer every mature DV team ends up building.

</details>


### uvm_ext_agent_config #(VIRTUAL_INTF)  
*Notes: [notes/uvm-from-zero/04-uvm-extension-library.md](notes/uvm-from-zero/04-uvm-extension-library.md)*

<details><summary><b>"local vs protected vs public members?"</b></summary>


`local`: only this class (not even subclasses). `protected`: this class and subclasses. Public: anyone. A base class meant to be extended uses protected state plus public getters/setters, so subclasses can work with fields while users go through validated accessors.

</details>

<details><summary><b>"How do you make a method 'abstract' in a UVM base class?"</b></summary>


True `pure virtual` forces the class to be `virtual` (non-instantiable), which breaks factory creation of the base. The convention is a `virtual` method whose body is `` `uvm_fatal("…", "implement me") ``. If a subclass forgets to override, the simulation fails loudly at the first call.

</details>

<details><summary><b>"Why can't the has_checks interface sync live in the base?"</b></summary>


The base only knows the vif as a type parameter. It can't assume the interface has a `has_checks` signal, because SystemVerilog interfaces have no inheritance to guarantee a common member. Anything that touches specific interface members belongs in the protocol subclass.

</details>


### uvm_ext_monitor #(VIRTUAL_INTF, ITEM_MON)  
*Notes: [notes/uvm-from-zero/04-uvm-extension-library.md](notes/uvm-from-zero/04-uvm-extension-library.md)*

<details><summary><b>"How do you write a generic monitor base class?"</b></summary>


Parameterize by vif type and item type. The base owns the analysis port, the run loop (wait for reset release, collect forever), a process handle so reset can kill an in-flight collection, and a reset handler. Subclasses implement only `collect_transaction()`, one transfer's worth of protocol timing, and call `output_port.write()`.

</details>

<details><summary><b>"Template method pattern: where is it here?"</b></summary>


The base defines the algorithm skeleton (`run_phase` → `collect_transactions` loop → `collect_transaction` step) and leaves one step to subclasses. The same pattern appears in the driver base (`drive_transaction`). Naming the pattern in an interview shows you understand the design, not just the code.

</details>


### uvm_ext_coverage #(VIRTUAL_INTF, ITEM_MON)  
*Notes: [notes/uvm-from-zero/04-uvm-extension-library.md](notes/uvm-from-zero/04-uvm-extension-library.md)*

<details><summary><b>"Why does the base declare empty write_item() and handle_reset()?"</b></summary>


The analysis imp in the base calls `write_item()` on its parent, so the method must exist on the base type. The interface class requires `handle_reset()`. Empty virtual bodies satisfy the compiler; subclasses override them with real sampling and reset coverage.

</details>

<details><summary><b>"How do you refactor shared code out of two working components safely?"</b></summary>


Move one piece at a time, convert one consumer, and run a regression comparing logs and coverage before and after. Then convert the second consumer. Keep behaviour identical (pure refactor) and fix bugs in a separate change. In the video, missing output was the clue that one consumer hadn't been converted yet.

</details>


### uvm_ext_sequencer #(ITEM_DRV)  
*Notes: [notes/uvm-from-zero/04-uvm-extension-library.md](notes/uvm-from-zero/04-uvm-extension-library.md)*

<details><summary><b>"When should a class be deleted rather than kept as an empty subclass?"</b></summary>


When it adds nothing (no fields, no overrides) and nobody needs its distinct type for overrides or casting. An empty subclass is still useful as a stable extension point for future customization, or to give sequences a protocol-named `p_sequencer` type. APB had no such need; MD did (`get_data_width`, the slave FIFO).

</details>


### uvm_ext_driver #(VIRTUAL_INTF, ITEM_DRV)  
*Notes: [notes/uvm-from-zero/04-uvm-extension-library.md](notes/uvm-from-zero/04-uvm-extension-library.md)*

<details><summary><b>"Tell me about a testbench bug you introduced and how you found it."</b></summary>


Use this one. While factoring drivers into a base class, the driver switched to a new reset-handler interface class, but the agent still dispatched reset only to children implementing the old one. The `$cast`-based dispatch silently skipped the driver, so the bus was never initialized. An X-check assertion on PSEL fired at time 0. Root cause in minutes; fix by unifying on one interface class. What I changed afterwards: refactor in small steps, regression after each, and a warning when a component that should be resettable isn't found.

</details>

<details><summary><b>"How should a subclass extend handle_reset()?"</b></summary>


Call `super.handle_reset(phase)` first, so the generic cleanup happens (kill the drive process, base state), then add protocol-specific actions (drive idle values). Skipping `super` leaves the old process running, and two drive loops fight over the bus after reset.

</details>


### uvm_ext_agent #(VIF, ITEM_MON, ITEM_DRV), and config from above  
*Notes: [notes/uvm-from-zero/04-uvm-extension-library.md](notes/uvm-from-zero/04-uvm-extension-library.md)*

<details><summary><b>"How do you configure an agent from the environment?"</b></summary>


In the env's build\_phase, before creating the agent: create the config object, set its fields (active/passive, thresholds, coverage on/off) using env knowledge, and `uvm_config_db::set(this, "agent_path", "agent_config", cfg)` with the **exact type** the agent will get. The agent's build\_phase gets it (falling back to a default if absent) and hands it to its children.

</details>

<details><summary><b>"The base agent creates base types. How do protocol agents get their own classes?"</b></summary>


Factory instance overrides registered in the protocol agent's constructor: "under me, an instance named 'driver' of type `uvm_ext_driver#(...)` should be `cfs_apb_driver`". When the base build\_phase calls `create`, the factory returns the protocol class. The base never names a protocol.

</details>

<details><summary><b>"Why is the config_db type in set() so important?"</b></summary>


config\_db entries are keyed by type as well as path and name. If the env sets a `cfs_md_agent_config_slave#(32)` but the agent gets a `uvm_ext_agent_config#(virtual cfs_md_if#(32))`, they're different keys and `get` returns 0, so the agent silently falls back to defaults. Set using the reader's type (handles are upcast automatically).

</details>


## Lecture companion: Register model (RAL)


### What is a register model?  
*Notes: [notes/uvm-from-zero/05-register-model-ral.md](notes/uvm-from-zero/05-register-model-ral.md)*

<details><summary><b>"Why use RAL instead of checking registers in the scoreboard?"</b></summary>


RAL gives you, for free: a mirror updated from observed traffic, automatic read checks, access-policy behaviour (W1C, RO, WO…), reset values, randomizable fields with constraints, and a protocol-independent API for tests and sequences. It's also reusable vertically: the module's block becomes a sub-block at system level. Writing that by hand means re-implementing all of it per project.

</details>

<details><summary><b>"What's a uvm_reg_map and when do you need more than one?"</b></summary>


It maps each register to an offset as seen through one bus, with the bus width, endianness and addressing mode, and holds the sequencer/adapter for front-door access. You need one per physical interface that can access the registers, for example a CPU bus and a debug JTAG port with different address layouts.

</details>


### uvm_reg_field: four values per field  
*Notes: [notes/uvm-from-zero/05-register-model-ral.md](notes/uvm-from-zero/05-register-model-ral.md)*

<details><summary><b>"Mirrored vs desired value?"</b></summary>


Mirrored is what the testbench believes the DUT contains; it's updated by observed bus traffic or `predict()` and used to check reads. Desired is what the test wants the DUT to contain; it's changed by `set()`/`randomize()` and pushed by `update()`. `update()` only issues a bus access when `needs_update()` sees desired ≠ mirrored.

</details>

<details><summary><b>"When do you set volatile = 1, and what does it cost?"</b></summary>


When the hardware changes the field in ways you can't predict cycle-accurately, such as a free-running counter. The cost is that read checks are skipped for that field, so you lose checking. The Aligner keeps CNT\_DROP non-volatile and models it precisely instead; your model calls `CNT_DROP.predict(+1)` on every dropped transfer, saturating at 255.

</details>

<details><summary><b>"Why is 'reset' an associative array?"</b></summary>


Designs can have several resets (HARD, SOFT, warm…) with different reset values per field. Each kind is a key. `configure()` fills "HARD"; `set_reset(val, "SOFT")` adds others; `reg_block.reset("SOFT")` applies one.

</details>

<details><summary><b>"What does individually_accessible mean?"</b></summary>


Whether the bus can access just that field without touching its neighbours, for example byte-enabled writes where the field fills whole byte lanes. APB without PSTRB always writes the full register, so it's 0 for every Aligner field, and a field-level `write()` becomes a full-register write.

</details>


### uvm_reg and the four Aligner registers  
*Notes: [notes/uvm-from-zero/05-register-model-ral.md](notes/uvm-from-zero/05-register-model-ral.md)*

<details><summary><b>"Why must custom members of a uvm_reg be uppercase?"</b></summary>


uvm\_reg already has hundreds of lowercase members (`read`, `write`, `get`, `set`, `reset`, `predict`…). A field called `reset` or a method called `write` would silently shadow them and break the register layer. Uppercase is guaranteed collision-free. Register generators follow the same rule.

</details>

<details><summary><b>"Map rights vs field access: what's the difference?"</b></summary>


Field access (RW, RO, WO, W1C, RC, …) defines per-field behaviour on read and write. Map rights (RW, RO, WO only) describe the whole register as seen through that map. STATUS is RO in the map because every field is RO. IRQ is RW in the map even though its fields are W1C, because it can be written.

</details>

<details><summary><b>"Would you hand-write these classes on a real project?"</b></summary>


Rarely. Register descriptions usually live in IP-XACT, SystemRDL or a spreadsheet, and a generator emits the RAL classes, RTL register file, C headers and documentation from one source. Hand-writing them once, as here, is how you learn what the generator produces and how to debug it.

</details>


### The register block, its map, and where it lives  
*Notes: [notes/uvm-from-zero/05-register-model-ral.md](notes/uvm-from-zero/05-register-model-ral.md)*

<details><summary><b>"Front-door vs back-door access?"</b></summary>


Front door goes through the real bus via the map's sequencer and adapter: realistic, takes simulation time, exercises the bus logic. Back door reads or writes the RTL storage directly through HDL paths (`uvm_hdl_deposit`/`read`): zero time, used for fast initialization, and for checking that the front door wrote the right flops. It needs correct `hdl_path`s, and bypasses side effects such as W1C or clear-on-read logic.

</details>

<details><summary><b>"What does lock_model() do and when do you call it?"</b></summary>


After building the whole hierarchy, on the top-level block only. It prevents further structural changes and builds the internal address-to-register lookup tables used by `get_reg_by_offset()` and the predictor. Forgetting it makes those lookups fail, and some versions error when you start using the model.

</details>

<details><summary><b>"Why check reg_block == null before creating it?"</b></summary>


Vertical reuse. At block level this env owns the register model. At subsystem or SoC level, the top env builds the full block hierarchy (this block becomes a sub-block at some base address) and assigns the pointer before build. The module env must use that shared instance, not create its own private one.

</details>


### Connecting the model to the APB monitor  
*Notes: [notes/uvm-from-zero/05-register-model-ral.md](notes/uvm-from-zero/05-register-model-ral.md)*

<details><summary><b>"Explicit vs implicit (auto) vs passive prediction?"</b></summary>


**Implicit**: `map.set_auto_predict(1)`, so the model updates itself when its own API completes an access. It's simple, but misses traffic from other masters or plain sequences. **Explicit**: a uvm\_reg\_predictor on the monitor updates the mirror from everything observed on the bus. This is the recommended approach, and the one used here. **Passive**: no sequencer connected at all; only the monitor path runs, typical at SoC level where the register bus is driven by a CPU. Don't enable auto-predict together with an explicit predictor, or you predict twice.

</details>

<details><summary><b>"Why does the adapter belong in the agent's package?"</b></summary>


The User Guide says the adapter is specific to the bus agent, not to the register model, so it ships as part of a UVM-compliant bus UVC. Any register model of any DUT that sits behind APB reuses the same `cfs_apb_reg_adapter`.

</details>

<details><summary><b>"What is +uvm_set_verbosity's syntax?"</b></summary>


`+uvm_set_verbosity=<comp>,<id>,<verbosity>,<phase>[,<time>]`. It's useful to enable one message ID (here REG\_PREDICT) at high verbosity without flooding the log with everything else.

</details>


### A custom predictor that also checks the response  
*Notes: [notes/uvm-from-zero/05-register-model-ral.md](notes/uvm-from-zero/05-register-model-ral.md)*

<details><summary><b>"The default predictor updated the mirror on a SLVERR write. How do you fix it?"</b></summary>


Extend `uvm_reg_predictor`, override the public virtual `write()` (the imp method behind `bus_in`), convert the item with `adapter.bus2reg()`, and call `super.write(tr)` only when `status == UVM_IS_OK`. Keep BUSTYPE as a parameter so the predictor stays bus-independent.

</details>

<details><summary><b>"Why not just trust PSLVERR?"</b></summary>


The response is DUT output, so it's something to verify, not an input. If the RTL wrongly returns OK for an illegal CTRL write, filtering alone would happily update the mirror and you'd never notice the missing error path. Computing the expected response from the spec turns every APB access into a checked access.

</details>

<details><summary><b>"How do you find which register an address maps to, and its rights?"</b></summary>


`map.get_reg_by_offset(offset, read)` returns the uvm\_reg or null. `map.get_reg_map_info(rg)` returns a `uvm_reg_map_info` whose `rights` string is what you passed to `add_reg()`. Field position comes from `get_lsb_pos()` and `get_n_bits()`.

</details>


### Connecting the model to the APB sequencer  
*Notes: [notes/uvm-from-zero/05-register-model-ral.md](notes/uvm-from-zero/05-register-model-ral.md)*

<details><summary><b>"Walk me through what happens when a test calls CTRL.write(status, 'h202)."</b></summary>


The register builds a `uvm_reg_item` and asks its map. The map turns it into a `uvm_reg_bus_op` (kind=WRITE, addr=0x0 from the map, data), calls `adapter.reg2bus()` to get a `cfs_apb_item_drv`, and runs start\_item/finish\_item on the sequencer from `set_sequencer()`. The driver drives APB. The map then calls `bus2reg()` on the same item to fill in the status. Meanwhile the monitor sees the transfer, and the explicit predictor checks the response and updates the mirror.

</details>

<details><summary><b>"Why does bus2reg() need to handle the driver item too?"</b></summary>


After the access, the map calls `adapter.bus2reg()` on the item it sent (or on the response, if `provides_responses = 1`) to get the final status and read data. Without a branch for `cfs_apb_item_drv`, the `$cast` fails and the fatal fires.

</details>

<details><summary><b>"Can you trust the status returned by CTRL.write() in this testbench?"</b></summary>


No. The driver item has no response field, so bus2reg reports `UVM_IS_OK` even when PSLVERR was 1. The predictor's check is what catches bad responses. To make the API status real, have the driver copy PSLVERR (and PRDATA) back into the item, or send a response with `provides_responses = 1`, and translate it in bus2reg. This is a good senior-level observation to bring up.

</details>

<details><summary><b>"write() vs update() vs set()?"</b></summary>


`set()` only changes desired values; no bus traffic. `update()` writes the register only if desired ≠ mirrored, combining all field values into one access. `write()` always performs the access with the full value you give, so you need the bit layout. Use set+update in tests, so the tests don't depend on bit positions.

</details>


### The first real bug: SIZE 5 on a 4-byte bus  
*Notes: [notes/uvm-from-zero/05-register-model-ral.md](notes/uvm-from-zero/05-register-model-ral.md)*

<details><summary><b>"The spec and the RTL agree, but you think they're both wrong. What do you do?"</b></summary>


Build a minimal reproducing test and waveform. Explain the physical impossibility (5 bytes can't fit a 4-byte bus) and its consequence (an illegal output transfer). Then raise it with the spec owner and the designer together, because only the spec owner can decide the intended behaviour. Don't silently "fix" your model to match the RTL, and don't wait: track it as a spec bug with an owner.

</details>

<details><summary><b>"Why did constrained-random find this when directed tests didn't?"</b></summary>


Directed tests encode what people already thought of, which here were exactly the spec's rules. Random generation within the stated rules explored combinations nobody enumerated, and an independent checker (the interface SVA) judged the result on physical grounds. Good random tests need both broad stimulus and checks that don't share the spec's blind spot.

</details>


### Register field callback: CLR clears CNT_DROP  
*Notes: [notes/uvm-from-zero/05-register-model-ral.md](notes/uvm-from-zero/05-register-model-ral.md)*

<details><summary><b>"How do you model a register side effect, e.g. writing one field clears another?"</b></summary>


A `uvm_reg_cbs` subclass whose `post_predict()` detects the triggering write and calls `predict()` on the affected field, attached with `uvm_callbacks#(uvm_reg_field, MyCb)::add(field, cb)`. It runs on every predicted write, whether from the explicit predictor or auto-prediction, so the side effect follows any source of traffic. Alternatives are a custom field class overriding `do_predict`, or handling it in the reference model; callbacks keep it local to the register layer.

</details>

<details><summary><b>"Why set value = 0 inside post_predict?"</b></summary>


CLR is a self-clearing pulse in the RTL; it never holds 1. If the mirror stored 1, the model would disagree with the hardware, and `update()` logic based on desired vs mirrored would behave oddly the next time someone sets CLR. Because `value` is inout, the callback can correct what gets stored.

</details>

<details><summary><b>"Name other UVM callback uses."</b></summary>


Driver or monitor hooks such as error injection (`` `uvm_register_cb `` / `` `uvm_do_callbacks ``), register pre/post read/write hooks (`pre_write`, `post_read` in `uvm_reg_cbs`), and report catchers (`uvm_report_catcher`, a callback that demotes or rewrites messages). The trade-off versus factory overrides: callbacks add behaviour to existing instances without replacing the class.

</details>


## Lecture companion: Model, scoreboard, coverage, virtual sequencer


### What the model and scoreboard do  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"What's the difference between a reference model and a scoreboard?"</b></summary>


The model **predicts**: it consumes DUT inputs and produces expected outputs, and it holds behavioural state (FIFOs, buffer, registers). The scoreboard **compares**: it pairs expected with actual, handles ordering and timing (queues, watchdogs) and reports mismatches. Keeping them separate means you can swap the model (for example for a C model through DPI) or reuse the comparison logic.

</details>

<details><summary><b>"How do you decide the model's structure?"</b></summary>


Start from the spec's functional blocks and their observable effects, not the RTL's implementation. Model at transaction level where the spec allows it, and add timing only where an output depends on it (here, the IRQs depend on FIFO levels). Keep it as untimed as possible, because every bit of timing you add is a chance to get out of sync with the RTL.

</details>


### The model's interface: 2 inputs, 3 outputs  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"Why `uvm_analysis_imp_decl?"</b></summary>


An analysis imp calls a method named `write()` on its parent. With two inputs of the same type you'd need two `write()` methods, which SystemVerilog forbids. The macro declares a new imp class, `uvm_analysis_imp_in_rx`, that calls `write_in_rx()` instead. The alternative is `uvm_tlm_analysis_fifo`s with a run\_phase that calls `get()`, which changes the timing semantics.

</details>

<details><summary><b>"Analysis port vs imp vs export?"</b></summary>


The **port** is the initiator; it calls `write()` and can broadcast to zero or more subscribers. The **imp** is the terminal, implemented by the component that owns the `write()`. An **export** forwards through hierarchy, for example an agent exposing its monitor's port. `write()` is a function, so subscribers must not block. That's why the model starts tasks with fork/join\_none.

</details>


### Modeling illegal RX transfers  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"How do you model a saturating hardware counter in RAL?"</b></summary>


Keep the field non-volatile and call `predict()` from the model on each event, with a guard at the maximum computed from `get_n_bits()`. Trigger side effects (like the MAX\_DROP flag) on the transition to max, not on every event at max, which matches the "becomes 255" wording in the spec.

</details>

<details><summary><b>"When should the model predict the RX response: at the start or the end of the transfer?"</b></summary>


At the start, as soon as the inputs are known (it only depends on offset and size). But the OKAY prediction is only **sent** after the RX FIFO accepts the item, because a full FIFO delays the RTL's ready. The scoreboard compares at the end of the transfer. Predicting early and comparing late is a common, robust pattern.

</details>


### Legal RX transfers and the RX FIFO  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"How do you model back-pressure in a transaction-level model?"</b></summary>


Use a bounded blocking channel, for example `uvm_tlm_fifo` with the DUT's depth. The producer's `put()` blocks while it's full, so the "accepted" event (here, the OKAY response) happens only when space frees up, just like the RTL's ready. No cycle counting is needed in the model.

</details>

<details><summary><b>"Why can't you just call a task from write()?"</b></summary>


`write()` is a function, and functions can't consume time or call blocking tasks. Wrap the call in `fork … join_none` inside a function. Keep a handle (`process::self()`) so reset can kill it and you can assert that there's only one instance.

</details>


### The intermediate buffer and build_buffer()  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"Why does a forever loop that never waits hang the simulator?"</b></summary>


It never yields, so simulation time can't advance. Every path through a forever loop must block: here either `pop_from_rx_fifo` (which blocks in `get()` when empty) or `@(posedge clk)`. That's why the else branch exists.

</details>

<details><summary><b>"Why does the model need a clock at all?"</b></summary>


The data path could be untimed, but polling loops need a time base, and later the IRQ prediction needs cycle-level alignment with the RTL (C11–C13). A minimal "env interface" carrying the clock (plus probes later) is the usual approach.

</details>


### align() and split(): the core algorithm  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"What does uvm_wait_for_nba_region() do and why use it here?"</b></summary>


It waits until the current time step's NBA region has passed (implemented with a nonblocking update and a wait), so the code resumes after same-time activity has settled. Here it orders two threads that both wake at the same clock edge: build\_buffer pushes first, and align then sees the updated buffer. Without it, the result depends on the scheduler's arbitrary thread order, a classic same-time race.

</details>

<details><summary><b>"Why push the split halves back in reverse order?"</b></summary>


`push_front` prepends, so pushing half 1 and then half 0 leaves the buffer as [half0, half1, …]. The next `pop_front` returns half 0, which by construction fits exactly and completes the TX item. Byte order is preserved, which is the Aligner's main promise.

</details>

<details><summary><b>"What would you randomize to stress this algorithm?"</b></summary>


Every legal (SIZE, OFFSET) setting crossed with RX size and offset sequences that force splits at every possible `num_bytes_needed`, reconfiguring CTRL while data is buffered, and back-to-back traffic with a slow TX side so both FIFOs fill. Then measure it with exactly the split coverage built in C14.

</details>


### TX controller and uvm_event: the model is complete  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"uvm_event vs SystemVerilog event?"</b></summary>


A uvm\_event is an object, so it can be passed around, stored in a pool (`uvm_event_pool`, shared by name), and reset. It can carry data with the trigger, supports callbacks, and offers both edge (`wait_trigger`) and persistent (`wait_ptrigger`, avoids the same-time race when the trigger fires just before the wait) styles. A plain `->`/`@` event can miss a trigger that happens in the same time step before the wait starts.

</details>

<details><summary><b>"Why wait for the TX transfer to complete before popping the next item?"</b></summary>


The RTL's TX controller holds one item until the slave asserts ready, then pops the next. Mirroring that hand-off keeps the model's TX\_LVL, and therefore its TX empty/full flags, close to the RTL's. The data order alone wouldn't need it.

</details>


### Scoreboard architecture and its ports  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"Design a scoreboard for a DUT with latency."</b></summary>


Store expected transactions in an ordered queue (or per-ID associative arrays if the DUT can reorder). On each actual: pop and compare, with an error if nothing was expected. Add a per-entry timeout so a stuck DUT fails instead of hanging, bound the queue depth to catch runaway prediction, check that every queue is empty in `check_phase` (end-of-test leftovers), and clear everything on reset.

</details>

<details><summary><b>"In-order vs out-of-order scoreboards?"</b></summary>


In-order: a FIFO compare, as here, valid because the Aligner preserves order. Out-of-order: key expected items by ID or address in an associative array and match on arrival. You still need timeouts, and usually a way to detect duplicates. Pick based on the spec's ordering guarantees, never on what the RTL happens to do.

</details>


### RX response and TX item checks  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"How do you detect a DUT that just stops responding?"</b></summary>


Use a timeout per expected item: start a watchdog thread when the prediction is queued, kill it when the actual is matched, and error if it expires. Make the threshold configurable, and size it from the spec's worst-case latency plus margin. Also have an end-of-test check for anything still pending, and a global timeout (`set_timeout`) as a last resort.

</details>

<details><summary><b>"Why does write_in_agent_rx only act when !is_active()?"</b></summary>


The monitor publishes each transfer twice, at start and at end. The response is only valid at the end, so acting on the start publication would compare a not-yet-sampled response and also pop the queue twice.

</details>


### The IRQ check, and debugging "7 expected, 6 received"  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"Walk me through how you debug a scoreboard mismatch."</b></summary>


Reproduce it with a pinned seed. Quantify it (how many expected vs actual, and which ones). If timing can't pair the events, classify them by cause, using design-internal signals where available (asking the designer which signals is normal and expected). Narrow down to the first divergence, then decide against the **spec** who's wrong. If the spec is ambiguous, the architect or concept owner decides. Fix the side that's wrong, and add coverage for the corner you found.

</details>

<details><summary><b>"Why does the IRQ queue allow 5 entries but RX/TX only 1?"</b></summary>


RX and TX expectations are tied to MD transfers, which never overlap, so at most one is pending. IRQ predictions come from a transaction-level model that runs ahead of the RTL's pipeline, so several can legitimately be in flight. The bound still catches runaway prediction.

</details>


### Sync fix #1: no flag on same-time push and pop  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"How do you resolve a race between two threads at the same simulation time?"</b></summary>


Don't rely on scheduler order. Options: impose an explicit order with delta delays (`uvm_wait_for_nba_region`, `#0` is weaker), merge the decision into one thread that sees both events, use a semaphore or mailbox handshake, or (as here) a deferred, cancellable action. Then verify both orderings by reasoning, as the lecturer does, not just by one passing seed.

</details>

<details><summary><b>"Why did the fix make the test fail earlier?"</b></summary>


It removed one symptom and exposed a deeper cause. The model and RTL disagree about *when* FIFO operations happen, not just about how flags are computed. Fixing symptom-level discrepancies often reveals the structural one. That's progress, not regression.

</details>


### Sync fix #2: align push/pop timing by probing, as a hint  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"Is it OK for a testbench to probe DUT internals?"</b></summary>


For **synchronization hints**, yes, carefully: use the internal event to align timing but keep an independent fallback (a timeout plus a warning or error), so a broken or missing RTL event can't silently drive the prediction. Never use internal state as the **expected value**, since that turns the check into "RTL equals RTL". Probes also tie the testbench to internal names, so keep them in one place (the testbench module and interface).

</details>

<details><summary><b>"Why the outer fork…join around fork…join_any + disable fork?"</b></summary>


`disable fork` kills **all** child processes of the current thread, including unrelated ones started earlier. Wrapping it in its own fork…join creates a fresh parent, so `disable fork` only kills the two racing branches. This is a standard idiom.

</details>

<details><summary><b>"Why are the data checks unaffected by this whole issue?"</b></summary>


Data order and content don't depend on timing. Only level-derived outputs (FIFO flags, and therefore IRQs) do. Good modeling separates untimed functional prediction, which is robust, from timing-sensitive prediction, which needs synchronization or directed tests.

</details>


### Sync fix #3: overlapping IRQs become one pulse  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"Your DUT ORs several interrupt sources onto one pin. How do you check it?"</b></summary>


Model each source's flag separately (in RAL, IRQ status and enable) for register checks. For the pin, combine all enabled sources that become active in the same cycle into one expected assertion: an OR with a sampling point after all sources have settled (here the negedge). Better still, also check the per-source status register after each pulse, so you know *which* source fired, not just that the pin went high.

</details>

<details><summary><b>"The lecturer says the test passes on a few seeds. Is it done?"</b></summary>


No. Run a regression of hundreds to thousands of seeds, triage every failure, and close coverage. Some IRQ timing corners only appear rarely. The conclusions also suggest a **directed IRQ test** as a complement to cycle-accurate prediction in random tests.

</details>


### DUT functional coverage and the verification plan  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"How do you build a verification plan?"</b></summary>


Go through the spec statement by statement and turn each into a feature with checks and coverage goals. Organize them as a tree (registers / features / interfaces), bind each leaf to an implementation (a covergroup, assertion or test), reuse sub-plans for agents, and review it with design and architecture **before** coding. Track closure against it. The format varies (XML, mind map, vManager vPlan), but the idea is the same.

</details>

<details><summary><b>"Your cross is at 10% after thousands of seeds. What do you do?"</b></summary>


First check reachability: list which bins are illegal or impossible (by analysis or a small script) and exclude them with ignore/illegal bins, or restructure the cross with `binsof` filters. Then look at the remaining holes and add constraints or directed sequences for them. Never "close" coverage by waiving bins you haven't proven unreachable.

</details>

<details><summary><b>"Why is the split coverage sampled from the model, not from a monitor?"</b></summary>


The split is an internal decision. No interface shows "num\_bytes\_needed". The model computes it while predicting, so it's the natural sampling point. The risk is that model coverage reflects what the **model** did. That's acceptable here because the scoreboard independently confirms the model matches the RTL's output.

</details>


### Virtual sequencer and the "slow pace" virtual sequence  
*Notes: [notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md](notes/uvm-from-zero/06-model-scoreboard-coverage-virtual-sequencer.md)*

<details><summary><b>"Virtual sequencer vs just passing sequencer handles to the sequence?"</b></summary>


Both work. The virtual sequencer centralizes the handles (and shared helpers like the model) in one component that the env wires once, so every virtual sequence finds them through `p_sequencer`, and system-level environments can re-point them. Passing handles directly (a "virtual sequence without a virtual sequencer") avoids p\_sequencer casts but spreads the wiring into every test.

</details>

<details><summary><b>"What is p_sequencer and how is it declared?"</b></summary>


`m_sequencer` is the generic `uvm_sequencer_base` the sequence runs on. `` `uvm_declare_p_sequencer(T) `` adds a typed handle `p_sequencer` and a `$cast` from m\_sequencer (fatal if the type is wrong), giving typed access to the sub-sequencer handles.

</details>

<details><summary><b>"Why does the TX branch wait on pending_items before choosing the response?"</b></summary>


The MD slave is reactive. It must not answer until the master (the Aligner) has started a transfer, which its monitor reports through the sequencer's `pending_items` FIFO (see the MD chapter). Only then is it valid to compute how many TX items this RX produced and which one is last.

</details>


## Lecture companion: Debug and tests


### Regressions, triage, and why debug speed matters  
*Notes: [notes/uvm-from-zero/07-debug-and-tests.md](notes/uvm-from-zero/07-debug-and-tests.md)*

<details><summary><b>"A regression has 40 failures. How do you approach it?"</b></summary>


Group the failures by first error message or signature, since many are the same root cause. Take the simplest, earliest-failing seed from each group, pin the seed, and debug that. For each one, decide whether it's an RTL bug (report it with a reproducer and the spec reference) or a testbench bug (fix it, and add a check or coverage if the miss was systematic). Rerun the group with the fix. Track this in the bug database so trends, such as a block with rising failures, are visible.

</details>


### UVM messages: IDs, verbosity and a .f file  
*Notes: [notes/uvm-from-zero/07-debug-and-tests.md](notes/uvm-from-zero/07-debug-and-tests.md)*

<details><summary><b>"How do you control UVM message verbosity without recompiling?"</b></summary>


Use the command line: `+UVM_VERBOSITY=UVM_HIGH` for the global threshold, and `+uvm_set_verbosity=comp,id,verb,phase|time,t` for targeted settings (wildcards in the component, an exact ID or `_ALL_`). Collect them in a .f file per debug scenario. Also `+uvm_set_action` (e.g. make an ID UVM\_NO\_ACTION, or count it) and `+uvm_set_severity` (demote or promote). In code: `set_report_id_verbosity_hier`, or a `uvm_report_catcher`.

</details>

<details><summary><b>"Why never use UVM_NONE for informational messages?"</b></summary>


A message is printed when its verbosity ≤ the threshold. UVM\_NONE (0) is ≤ every threshold, so it can never be filtered out by verbosity, only by changing its action. Reserve UVM\_NONE for things that must always appear, and give everything else LOW or higher, so that "\_ALL\_ at UVM\_NONE" gives a truly quiet log.

</details>

<details><summary><b>"What's a uvm_report_catcher used for?"</b></summary>


It's a callback on every report before it's processed. It can change severity, ID or verbosity, modify the text, or swallow the message. Typical uses: demote a known, waived error from a third-party VIP, or turn an expected error into a pass in a negative test. Use it carefully and with documentation, because it can hide real failures.

</details>


### UVM transactions: bubbles on the waveform  
*Notes: [notes/uvm-from-zero/07-debug-and-tests.md](notes/uvm-from-zero/07-debug-and-tests.md)*

<details><summary><b>"How do you get transactions visible in the waveform viewer?"</b></summary>


Make the item record its fields (`do_record` or `UVM_RECORD` field flags). In the component, open a stream (`get_tr_stream`), and call `begin_tr` and `end_tr` at the protocol's start and end. Then enable `recording_detail` (config\_db or `+uvm_set_config_int`). The simulator's recorder (e.g. SimVision, Verdi, Visualizer) maps the streams into the waveform database.

</details>

<details><summary><b>"do_record vs `uvm_field_* macros?"</b></summary>


Field macros auto-implement copy, compare, print, pack and record from one declaration: quick, but slower at runtime and with a fixed format. The do\_\* overrides (do\_copy, do\_compare, convert2string, do\_record) are explicit, faster and fully customizable. Many teams ban field macros for performance and debuggability; the lecturer prefers do\_record for format control.

</details>


### "Track the source": expected items that remember their inputs  
*Notes: [notes/uvm-from-zero/07-debug-and-tests.md](notes/uvm-from-zero/07-debug-and-tests.md)*

<details><summary><b>"How do you make scoreboard errors easier to debug?"</b></summary>


Print both values and the field-level difference, the time each one was produced, and the **cause**: the input transactions (with times) the expected value was built from, and why a status was expected (like the predictor's status\_info "reason" from the register chapter). Add a stable error ID per check so failures can be grouped in regression triage.

</details>

<details><summary><b>"Why insert an adapter between agent and env instead of extending the monitor item?"</b></summary>


Third-party or shared VIP items can't be modified per project, and extending them (with factory overrides) couples the env to the VIP's internals. An env-owned item behind a `mon2env()` translation decouples the model and scoreboard from the agent. You can swap the VIP, add debug fields like `sources`, or normalize several protocols into one data type.

</details>


### Test organization: one random parent, constraint-only children  
*Notes: [notes/uvm-from-zero/07-debug-and-tests.md](notes/uvm-from-zero/07-debug-and-tests.md)*

<details><summary><b>"How do you structure tests in a UVM environment?"</b></summary>


A base test that builds and configures the env. A small number of random "traffic" tests that start virtual sequences and expose knobs. Then targeted tests that only change constraints, knobs or factory overrides, never the traffic logic. Directed tests are kept for bring-up, very specific corners, or timing-sensitive features (like IRQ timing). Sequences carry the behaviour and tests stay thin, which makes regression lists easy to build.

</details>

<details><summary><b>"How do you add a new targeted test without touching existing code?"</b></summary>


Extend the virtual sequence that generates the relevant traffic, adding a constraint block, and in the new test's constructor or build\_phase call `parent_vseq::type_id::set_type_override(child_vseq::get_type())`. Any `type_id::create` of the parent now returns the child. This is the open/closed principle, applied with the UVM factory.

</details>


### A truly random register test, which finds an IRQEN reset bug  
*Notes: [notes/uvm-from-zero/07-debug-and-tests.md](notes/uvm-from-zero/07-debug-and-tests.md)*

<details><summary><b>"Why did one seed find the bug and another not?"</b></summary>


The bug was only observable if a **read** of IRQEN came before any write to it. Random ordering makes that a probability per seed. That's why you run many seeds, and why coverage should include "first access after reset is a read" for every register. A built-in UVM sequence, `uvm_reg_hw_reset_seq`, checks all reset values directly. It's a good first test in any register bring-up.

</details>

<details><summary><b>"Which built-in UVM register sequences do you know?"</b></summary>


`uvm_reg_hw_reset_seq` (reset values), `uvm_reg_bit_bash_seq` (walks 1s and 0s through every RW bit), `uvm_reg_access_seq` (front door vs back door consistency, which needs HDL paths), `uvm_mem_walk_seq` and `uvm_mem_access_seq` for memories, and `uvm_reg_mem_built_in_seq` to run them all. Exclude registers with side effects using resource attributes like `NO_REG_BIT_BASH_TEST`.

</details>


### The random traffic test, and two traps it uncovered  
*Notes: [notes/uvm-from-zero/07-debug-and-tests.md](notes/uvm-from-zero/07-debug-and-tests.md)*

<details><summary><b>"randomize() + update() on a register does nothing. Why?"</b></summary>


Three usual causes. The randomized value equals the mirror, so `needs_update()` is 0. The field isn't randomizable: its access is RO or W1C-like and configure() turned rand\_mode off, or is\_rand was 0. Or randomization failed and the result was voided. Check `get()` vs `get_mirrored_value()` and `FIELD.value.rand_mode()`, and always check the randomize result.

</details>

<details><summary><b>"Why wait before reading the status registers?"</b></summary>


Right after traffic, RX\_LVL and TX\_LVL change every few cycles, and the model and RTL can legitimately differ by a cycle in when they update. Reading in a quiet period makes the read check deterministic. Reading *during* traffic is also valuable, but needs volatile-tolerant checking or tighter synchronization.

</details>

<details><summary><b>"Your random test passes 10 seeds. What would you add before calling it good?"</b></summary>


Reset in the middle of traffic. Reconfiguration with the pipeline drained. Back-pressure extremes (a slow TX slave, all-max RX). Interrupt clears and CLR. Error-response mixes. Then a regression of thousands of seeds with coverage, triaging every failure.

</details>


### Illegal RX traffic test: the MAX_DROP bug, confirmed  
*Notes: [notes/uvm-from-zero/07-debug-and-tests.md](notes/uvm-from-zero/07-debug-and-tests.md)*

<details><summary><b>"Create a test for a feature without touching the existing tests."</b></summary>


Here's the drop counter as an example. Extend the RX virtual sequence with a constraint for illegal transfers, extend the random test, raise its traffic knob above the counter's maximum, and factory-override the RX vseq with the new one. That's about 30 lines, all additive. It exercises the saturation, the MAX\_DROP flag and the IRQ path, and it found a real bug.

</details>

<details><summary><b>"How do you make sure a test actually exercised what it targets?"</b></summary>


Use coverage on the feature (e.g. CNT\_DROP reached 255 with IRQEN.MAX\_DROP = 0 and = 1, and CLR after saturation), not just a pass result. This bug escaped the plain random test because it never produced 255 drops. And it was only visible when MAX\_DROP was enabled, so the IRQEN value must be in the cross too.

</details>


## Lecture companion: Verification project stages


### The six stages of a verification project  
*Notes: [notes/uvm-from-zero/08-verification-project-stages.md](notes/uvm-from-zero/08-verification-project-stages.md)*

<details><summary><b>"Walk me through how you'd verify a new block from day one."</b></summary>


Spec study with an open-questions list to the architect. A testbench architecture document and a verification plan (features → checks, coverage, tests), reviewed with design and architecture. Reuse or build agents, then RAL, model, scoreboard and coverage, bringing them up with simple directed tests. Then random tests and regressions, triaging failures until everything passes. Close functional and code coverage, with waivers reviewed. Mutation qualification if required. Sign off with coverage reports, the test/seed list and the bug summary.

</details>

<details><summary><b>"When are you done verifying?"</b></summary>


When the agreed criteria in the plan are met: all regression tests passing over a statistically meaningful number of seeds, functional coverage closed (with holes explained or waived in review), code coverage closed by design (exclusions reviewed), the bug-discovery rate flattened, and qualification clean if required. "Done" is a reviewed decision against evidence, not a feeling.

</details>

<details><summary><b>"100% code coverage but a bug escaped to silicon. How?"</b></summary>


Code coverage only shows the lines executed. It doesn't show that the effect was **checked**, or that the right **combination** of conditions occurred. Typical causes: a missing or weak checker (exactly what mutation qualification exposes), functional coverage missing the corner (e.g. reconfiguring with data inside), or a spec gap where both RTL and model were wrong in the same way, like the SIZE + OFFSET bug in R8.

</details>

<details><summary><b>"Who reviews the verification plan, and why does that matter?"</b></summary>


Verification, design and concept/architecture. Design knows the implementation risks (arbiters, clock crossings, corner states), and architecture knows the intended system use. Their sign-off means everyone agrees on what will and won't be verified, so a missing feature is caught at review time, not after tape-out.

</details>
