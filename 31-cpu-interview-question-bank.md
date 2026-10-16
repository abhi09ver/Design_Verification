# Challenge 31: CPU Interview Question Bank (OOO + Pipeline + Verification)

> **Level:** All levels
> **Topics:** every question from challenges 26–30 in one place, with model answers and 60-second pitches
> **Related:** [26](26-ooo-cpu-tomasulo-core.md), [27](27-ooo-core-bug-hunt.md), [28](28-cpu-verification-iss-random-sva-mutation.md), [29](29-pipelined-in-order-cpu-hazards.md), [30](30-cpu-from-zero-rtl-ladder.md)
> **Code:** [`cpu-lab/`](cpu-lab/README.md) · **Interactive pages:** open the HTML files in [`cpu-lab/pages/`](cpu-lab/pages/) in a browser

---


Use this the night before: read the question, answer out loud in under a minute, then compare.

## A. Pitches and stories

**Q: 2-minute pitch: describe this core.**

3-wide RISC-V RV32IM out-of-order core. Tomasulo with a 48-entry ROB holding the data. 12/4/16 reservation stations for ALU, MUL/DIV and load/store. 3 ALUs, 2 pipelined MUL/DIV units (radix-4 Booth, radix-8 divider). A 3-lane CDB fed by a completion buffer. In-order 3-wide commit. A load/store unit with an 8-entry LQ and SQ, store-to-load forwarding and conservative disambiguation. On the verification side, I built a commit-trace scoreboard against a Python ISS, directed and constrained-random stimulus, and bind-based SVA. That found 15 functional bugs across decode, issue, execute, memory and frontend, including two deadlocks that only random stimulus exposed.

**Q: What's the hardest bug you found and how did you debug it?**

The store-queue deadlock and bypass (B13). Random programs hung with a store stuck at not-ready. The trace showed the SQ full of younger stores while the oldest store waited in the LSB, which is a resource deadlock. While fixing it I found that the age function broke once a store retired: its ROB tag wrapped and it looked younger than later loads. The fix was in-order SQ entry and explicit retire signals from the ROB to the MMU. The general lesson: resources shared by instructions of different ages must be allocated in age order, or reserve capacity for the oldest.

**Q: How would you build a verification plan for an OOO core from scratch?**

Start with the contract: the committed stream equals the ISA reference. Then layer it. (1) An ISS-based commit scoreboard with lock-step comparison. (2) Directed tests per feature from the spec. (3) Constrained-random instruction streams with knobs for hazards, aliasing and latency mixes. (4) White-box SVA on microarchitectural invariants (ROB order, unique tags, RS free-list, LSQ order, credit counters). (5) Functional coverage: every structure full and empty, every bypass path, every corner-case matrix. (6) Unit-level tests and formal for datapath and arbiters. (7) Performance checks: IPC against a model, which catches the bugs that are correct but slow.

**Q: Correct but slow: how do you catch performance bugs?**

Keep a performance model or expected-cycle budget per directed test, and track IPC per regression run. Microbenchmarks isolate one mechanism: a dependent ALU chain should be 1 IPC per dependency, independent ALU ops should reach issue width. In this core, the chain test showed 2 cycles per dependent add, which pointed straight at the registered `ready` bit.

**Q: What is bug masking and how do you deal with it?**

One bug stops execution before others can show. Here, the decode key bug stopped 13 of 20 directed tests within the first few instructions. Each fix revealed the next layer. To deal with it: fix and re-run in small steps, keep tests narrow so each targets one mechanism, and use assertions, which report problems even when the end result is masked.

**Q: Why bind assertions instead of writing them in the RTL?**

Bind keeps verification code out of the design files: designers own the RTL, DV owns the checkers, and synthesis never sees them. A bind applies to every instance of a module and can reach internal signals by name. You can also turn checker sets on and off per run.

**Q: Blocking vs non-blocking assignments in this design: what went wrong?**

Several clocked blocks used blocking assignments for state that another clocked block reads at the same edge (temp_RAT, busy arrays, ROB_next), and one variable had two drivers. The result depends on which block the simulator schedules first, so behaviour can differ between Xcelium, VCS and Verilator, and synthesis builds something different again. The rule: one always_ff per state variable, written with non-blocking; next-state logic in always_comb.

**Q: GPU angle: what carries over from this CPU to a GPU SM?**

Scoreboarding and dependency tracking per warp, operand collectors (like data-capture RS), result buses with limited writeback ports, credit-based flow control, LSQ-like coalescing and ordering in the LD/ST unit, and the same verification pattern: a reference model of the ISA (PTX/SASS semantics), commit- or retire-level comparison, and stress on shared-resource arbitration. GPUs mostly issue in order per warp; the out-of-order aspect is across warps.


## B. Out-of-order core, by module


### Frontend

**Q: Why does an OOO core need an instruction queue between fetch and decode?**

It decouples two pipelines with different stall sources. Fetch stalls on I-cache misses and redirects; decode/rename stalls on back-end resources (ROB, RS, LSQ full). The queue absorbs bursts so neither side waits for the other cycle by cycle, and it is the natural point to apply back-pressure.

**Q: A fetch register is stalled but the PC keeps moving. How would you detect that in verification?**

Compare the committed PC stream with the ISS. Any skipped instruction is an ORDER mismatch at the first commit after the gap. White-box: an assertion that the PC register is stable whenever the fetch register is held (`imem_stall |=> $stable(pc)`), plus a scoreboard of fetched vs. enqueued PCs.

**Q: Tree-PLRU vs true LRU for a 4-way BTB?**

True LRU for 4 ways needs 5 bits per set (one of 24 orderings) and an update that touches all of them. Tree-PLRU needs 3 bits, and an access only flips the bits on its path. It approximates LRU: it never evicts the MRU way, but it does not always pick the true LRU way.

**Q: How do you verify a branch predictor if a misprediction is never a functional failure?**

With performance checks and unit tests: a reference model of the predictor fed the same branch stream must predict the same direction and target; then assert prediction accuracy on known patterns (always-taken loop, alternating, correlated). Full-chip: check that every mispredict is recovered (commit stream correct) and track MPKI as a regression metric.


### Decode

**Q: Why sign-extend immediates in decode and not in the ALU?**

Decode is the only stage that knows the format. After decode, the immediate is just a 32-bit operand, so the ALU, the AGU and the branch unit all share one representation. It also takes the sign-extension mux out of the execute critical path.

**Q: Your directed test suite passes, but one decode field is wrong for 90% of encodings. How?**

The tests only used small immediates (here every immediate was below 32), so the aliased bits were always 0. Field-level coverage on the encoding (each bit of imm toggled, each format × each opcode) would show the hole at once. Constrained-random over the full encoding space finds it in seconds.

**Q: What decode-time information does rename need?**

Source and destination architectural registers, whether each source is used, whether dst is real (not x0, not store/branch), the functional-unit class, and the immediate. Getting 'source used' wrong creates false dependencies, which are slow but correct. Getting 'dst real' wrong corrupts state.


### Rename & Dispatch

**Q: Explain register renaming in one minute.**

Architectural registers are few, so independent instructions reuse the same names, creating false WAR/WAW dependencies. Rename maps each destination to a fresh physical name (here a ROB entry) and records the newest mapping in the RAT. Sources read the RAT to find their producer. Only true RAW dependencies remain, so independent work can run out of order. At commit, the value moves to the architectural state, and the mapping is cleared if it still points at that entry.

**Q: ROB-as-storage (this core) vs physical register file?**

ROB-as-storage copies values twice (FU → ROB → ARF at commit), and operands may come from the ROB, the ARF or the CDB, which means more read ports and muxes. A PRF writes once; commit only frees the previous mapping. The PRF scales better, which is why modern cores (and RISC-V BOOM) use it. ROB-as-storage is simpler to build and verify, which is why teaching cores use it.

**Q: When is it safe to clear a RAT entry at commit?**

Only if it still points to the committing entry. If a younger instruction already renamed the same register, the mapping belongs to the younger one and must stay. This core checks `RAT_tag == retiring rob` before clearing, which is correct.

**Q: How do you stall a 3-wide dispatch fairly?**

All-or-nothing on the bundle is simplest and keeps decode slots a prefix. Partial dispatch is faster but then the remaining slots must shift down (or decode must handle holes), and ROB indexing can no longer be `head + slot`.


### Issue: wakeup & select

**Q: Walk me through wakeup and select for a 3-wide CDB.**

Each RS operand has a comparator per CDB lane (12 ALU × 2 operands × 3 lanes = 72 tag comparators just for the ALU RS). On a match, the value is captured and the operand marked valid. Select is a priority arbiter over ready entries (oldest first, or position-based), one grant per functional unit. In high-frequency designs wakeup and select are in the same cycle for 1-cycle ops, often with speculative wakeup for loads (assume an L1 hit, replay on a miss).

**Q: Why might a real design not pick the oldest ready instruction?**

A true age matrix costs N² bits and a wide reduction. Many designs use position-based priority (lowest RS index) or a compacting queue, where position equals age. Oldest-first matters mostly for long-latency chains and for forward-progress guarantees, so a cheap approximation plus an anti-starvation timer is common.

**Q: Name three ways an instruction can be lost between RS and ROB, and the assertion for each.**

(1) Selected but the FU drops it: `ex_valid |-> ##[lat] result_ready`. (2) Two entries selected into one FU port: one-hot check on FU inputs, popcount(clear) = popcount(issue). (3) Wakeup missed because the broadcast came while the entry was being written: compare the tag against the CDB in the allocation cycle too (this design does). Plus a global liveness check that the ROB head retires within N cycles.


### Execute

**Q: Why radix-4 Booth instead of a plain array multiplier?**

It halves the partial-product count, so the reduction tree is shallower (fewer CSA levels) and smaller, for a modest recoding cost. Radix-8 halves again but needs a hard 3M multiple precomputed with an adder, which is the classic area/delay trade-off.

**Q: How would you verify a 32-bit divider? You cannot simulate 2⁶⁴ cases.**

Corner cases from the spec (0, ±1, MIN/MAX, x/0, overflow), random with a reference model, structured patterns (powers of two, all-ones, divisor > dividend), and formal equivalence against a simple behavioural divider (`a == q*b + r` and `|r| < |b|`, with sign rules) using an SVA property on the output. Formal is the real answer for datapath at Nvidia/Google scale.

**Q: A pipelined unit returns results by tag. What can go wrong?**

Tag reuse (a tag freed and reallocated while an old op is still in the pipe), a flush that does not kill in-flight ops, two ops with the same tag (rename bug), and a result arriving after its ROB entry is gone. Assert that every returned tag is a live, not-yet-completed ROB entry (SVA A4).


### Writeback & CDB

**Q: How many CDB lanes would you choose, and how do you decide?**

Simulate: measure results per cycle on the target workloads. Most of the time it is at most the issue width. Each lane adds a tag comparator per operand per RS entry plus a write port into the ROB/PRF, so the cost grows with RS size × lanes. Choose the lane count where the queueing delay costs less IPC than the extra wakeup-loop delay and area.

**Q: What is credit-based flow control and where else does it show up in a GPU?**

The sender keeps a count of free slots at the receiver, decrements it on send, and the receiver returns a credit when it frees a slot, so the sender never overruns. In GPUs: NoC/crossbar links, memory request queues, the texture and L1 return paths, and NVLink. Verification checks credit conservation (credits + in-flight + occupied = depth) as an invariant.


### Commit

**Q: Why can't stores write memory when they execute?**

Memory is architectural state. A store that executes and is later squashed (a mispredicted branch or an older exception) would have changed memory irreversibly. So stores wait in the store queue and write only after commit. Loads can still get the value early through store-to-load forwarding.

**Q: What would you put in a commit-stage scoreboard for a CPU?**

Per retired instruction: PC, instruction word, rd and value, CSR changes, memory address/data/size for stores, and exceptions/interrupts with their cause. Compare in order against an ISS (Spike, Sail, or an in-house model) in lock-step or from a trace. Handle legal divergence such as interrupts and timers by injecting them into the ISS at the same retire point.


### Memory: LSB, LQ, SQ

**Q: A load and an older store to the same address are both in flight. Walk through every possible outcome.**

Store address unknown: the load waits (conservative) or speculates. Address known and it overlaps: if the store data is known and fully covers the load, forward with byte select and sign/zero extend. If the data is unknown, or it is a partial overlap, wait. If the store is senior or already written, the load can read memory once the write completes. Plus the case that older stores to the same address exist further back: the youngest one wins.

**Q: How do you verify memory ordering in an OOO core?**

End-to-end: an ISS comparison of load values and final memory, with constrained-random programs that use few addresses and mixed sizes to force aliasing (here 8 words). White-box: assertions on LSQ invariants (unique tags, SQ in program order, a store writes memory only when senior, forward-source selection), and functional coverage of the matrix {forward, partial-overlap wait, unknown-address wait, violation} × {byte, half, word}. Litmus tests if the design is multi-core.

**Q: Why does this core put stores in program order in the SQ even though it slows things down?**

It removes a deadlock (younger stores filling the SQ) and makes the SQ's position order equal to program order, which the in-order drain and the forwarding search depend on. A faster design allocates SQ entries at dispatch, in program order and early, so ordering comes for free and the LSB→SQ move disappears.


## C. Pipelined in-order CPU

**Q: Where is rs1 in an S-type instruction?**

Bits 19:15, the same as in every other format that has rs1.

**Q: What does `addi x5, x0, -1` put in x5?**

0xFFFFFFFF. The 12-bit -1 is sign-extended to 32 bits.

**Q: Which instruction is a 'free' NOP?**

`addi x0, x0, 0`. The write to x0 is thrown away.

**Q: Why is RISC-V popular for teaching and for industry?**

Open and royalty-free, small clean base ISA with optional extensions, fixed 32-bit encoding with register fields in fixed positions (simple decoders), and a big open tool and RTL ecosystem.

**Q: A program has 100 instructions and no hazards. How many cycles on a 5-stage pipeline?**

5 + 100 − 1 = 104.

**Q: What is a bubble?**

A pipeline slot carrying nothing (valid = 0). It moves through the stages like an instruction but changes no state.

**Q: Throughput vs latency for a pipeline?**

Latency per instruction stays about the same (or grows slightly because of pipeline registers). Throughput approaches 1 instruction per cycle at a higher clock frequency. The cost is area, power and hazards.

**Q: Why can't WAW happen in an in-order 5-stage pipeline?**

All writes happen in the same stage (WB) in program order, so the later write always lands last.

**Q: `lw x2,0(x0)` then `add x3,x2,x2`. How many bubbles?**

One. With one independent instruction in between: zero.

**Q: A loop runs 100 times. The backward branch is predicted taken. How many flushes?**

One, on the final exit, when the branch falls through. `p04_loop_sum` shows exactly 1.

**Q: Explain forwarding, and where the muxes go.**

Muxes at the ALU inputs in EX choose between the register value read in decode, the result in EX/MEM (distance 1), or the value in MEM/WB (distance 2). The nearest producer wins. Distance 3 is covered by the register file writing before (or through to) the read. Loads in EX/MEM are not forwardable, so an interlock inserts a bubble.

**Q: What happens to CPI with 20% branches, 30% mispredicted, 2-cycle penalty?**

1 + 0.2 × 0.3 × 2 = 1.12, ignoring other stalls.

**Q: Why is a backward branch predicted taken?**

Backward branches usually close loops, and loops usually go round again.

**Q: Which instruction can't a static predictor guess the target of, and why?**

`jalr`. Its target is in a register, which fetch doesn't have yet.

**Q: Static vs dynamic branch prediction?**

Static: a fixed rule from the instruction itself (backward taken), no state, ~60-70% accurate. Dynamic: learns from history (2-bit counters, gshare, TAGE), 90%+, needs tables, update logic and recovery of speculative history.

**Q: Which formats have no rs1?**

U (lui, auipc) and J (jal).

**Q: Why does a store need rs2?**

rs2 holds the data being stored; rs1 holds the base address.

**Q: Where would you put the load-use detection and why?**

In decode, because the dependent instruction is there when the load is in EX, the last moment you can hold it back cheaply, and holding decode + fetch is simple.

**Q: How many read ports does a 2-wide superscalar CPU need?**

Four (two sources each). Port count is a big area cost of wide CPUs.

**Q: Name two ways to make x0 read as zero.**

Guard the read (`ra == 0 ? 0 : r[ra]`), or guard the write so r[0] is never written (and reset it to 0). pq5 does both.

**Q: Write-first vs read-first register file?**

Write-first returns the value being written in the same cycle (no extra forwarding path needed for distance 3). Read-first returns the old value, so the pipeline must forward from WB. FPGA block RAMs can be configured either way.


## D. Fundamentals (CPU From Zero)

**Q: What is 1 + 1 in binary?**

10: write 0, carry 1.

**Q: Why test 0xFFFFFFFF + 1 on purpose?**

It makes the carry ripple through all 32 boxes, the longest and riskiest path, and the result wraps to 0 with cout = 1.

**Q: A 4-bit counter is at 15 and counts once more. What does it show?**

0. It wraps around, because 16 needs 5 bits.

**Q: Why does the testbench check just AFTER the clock edge?**

The flip-flop changes on the edge. Checking a moment later sees the new value; checking exactly on the edge is a race.

**Q: Why does the ALU have a `default` branch?**

So an unknown op can never silently 'do nothing'. In your big core, missing ops (andi, ori…) did exactly that and the instruction vanished (bug B03).

**Q: Is 0x80000000 bigger than 1?**

Unsigned: yes (2147483648). Signed: no (it is -2147483648). The same bits, two meanings.

**Q: Why have a zero register at all?**

It gives free constants and tricks: `addi x5, x0, 7` means 'x5 = 7', `add x5, x6, x0` means 'copy x6'.

**Q: You write x7 and read x7 in the same cycle. Which value do you get?**

In this design, the OLD one, because the write lands at the clock edge. Real pipelines add a bypass so you get the new one.

**Q: The giver has valid=1 but ready=0 for 3 beats. What must the giver do?**

Keep the same data and keep valid=1 until ready=1. Changing the data or dropping it loses a ticket.

**Q: What did your big core's frontend get wrong here?**

Its PC kept moving while the queue said 'not ready', so whole bundles of instructions were skipped (bug B09).

**Q: How does the CPU make a loop?**

A branch at the bottom compares two registers and, if the condition holds, sets PC = PC + offset (negative offset = jump back).

**Q: Why is a single-cycle CPU slow?**

The clock must wait for the longest path (fetch + decode + register read + ALU + memory + write) every single cycle, even for simple instructions.

**Q: `addi x5, x0, 7` sits behind a stalled instruction. Does it need to wait?**

Logically no, it depends on nothing. An in-order CPU makes it wait anyway. Out-of-order CPUs let it go ahead (Levels 8–11).

**Q: Which hazards are 'fake'?**

WAR and WAW. They only exist because there are few register names. Renaming (Level 8) removes them; only RAW is real.

**Q: `mul x3…` gets ticket 0, then `sub x3…` gets ticket 2. Who reads which?**

Instructions between them read ticket 0. Instructions after the sub read ticket 2. Both writers can run at the same time without clashing.

**Q: Why is 'tag 0 means none' dangerous?**

Ticket 0 is handed out like any other number. Your big core made this mistake and every instruction waiting on ticket 0 waited forever (bug B04).

**Q: Instruction B is younger than A but ready first. Who goes?**

B. Waiting A doesn't block it, which is the whole point.

**Q: Why one bell for everyone instead of private messages?**

The producer doesn't know who needs its result. Broadcasting the ticket number lets any number of waiters match it in the same cycle.

**Q: Finish order is 2, 4, 0, 3, 1. What is the retire order?**

0, 1, 2, 3, 4, always program order.

**Q: Why bother? Just write results when they finish.**

If something goes wrong (a wrong-guess branch, an exception) we must undo everything after a point. With in-order retirement nothing after that point has touched the real registers yet.

**Q: Why can't an ALU op start in the cycle a MUL is 2 stages along?**

Both results would reach the single bell (CDB) in the same cycle. That is a structural hazard: not enough of a resource. Your big core uses 3 CDB lanes plus a completion buffer instead.

**Q: Name the three places a source value can come from at dispatch.**

The register file (no ticket), the ROB (ticket finished but not yet served), or the CDB right now. Otherwise, wait for the bell.


## E. Numbers worth remembering (all measured in this lab)

| Fact | Value |
|---|---|
| Original OOO core: directed / random pass | 1/20 (scoreboard only), 0/720 |
| Fixed OOO core | 19/20 (branch capstone open), 720/720, 0 SVA firings |
| Bugs found by directed vs random | 11 vs 4 (B11–B14) |
| Dependent ALU chain in the OOO core | 1 result per 2 cycles (registered `ready`) |
| pq5 cycle formula | 4 + N + stalls + 2 × flushes |
| pq5 mispredict / load-use penalty | 2 cycles / 1 cycle |
| pq5 loop CPI with / without prediction | 1.02 / 1.66 |
