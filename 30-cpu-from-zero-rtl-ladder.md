# Challenge 30: CPU From Zero: An 11-Level RTL Ladder From an Adder to an OOO Core

> **Level:** Fresher
> **Topics:** combinational vs sequential, `<=` vs `=`, ALU, register file, valid/ready FIFO, single-cycle CPU, scoreboard, renaming, RS + CDB, ROB, tiny OOO CPU, self-checking testbenches
> **Related:** [24 – Early-career portfolio](24-early-career-dv-expectations-and-portfolio.md), [29 – Pipelined CPU](29-pipelined-in-order-cpu-hazards.md), [26 – OOO core](26-ooo-cpu-tomasulo-core.md)
> **Code:** [`cpu-lab/`](cpu-lab/README.md) · **Interactive pages:** open the HTML files in [`cpu-lab/pages/`](cpu-lab/pages/) in a browser

---


## 1. The Source

Eleven small SystemVerilog designs, each with a self-checking testbench, in [`cpu-lab/beginner/`](cpu-lab/beginner/README.md). The interactive version with pictures and quizzes is `cpu-lab/pages/cpu_from_zero.html`. Run all with `./run_all.sh`, and the break-it tests with `python3 mutate.py`.

## 2. What Usually Goes Wrong for Beginners (all seen while building this)

| Mistake | Where |
|---|---|
| Sampling a handshake after the clock edge | first L05 testbench |
| Releasing reset on the same edge the DUT samples it | first L06–L11 testbenches |
| A checker that verifies order but not values | first L10 testbench (missed "retire before finished") |
| Indexing an array literal (`'{...}[k]`) — not legal SV | first L10 testbench |
| `>>>` on an unsigned value | L03 break-it |
| Zero-extending immediates | L06 break-it (= bug B02) |
| Tag 0 meaning "no tag" | L09 break-it (= bug B04) |

## 3. The Ladder


### Level 1 – Wires and gates (build an adder from nothing)  · [`L01_adder.sv`](cpu-lab/beginner/L01_adder.sv)

A computer only knows two things: **0** (off) and **1** (on), like a light switch. Gates are tiny rules: AND says 'both on?', OR says 'any on?', XOR says 'exactly one on?'. Glue enough rules together and you can add numbers. We build a 1-bit adder, then copy it 32 times.

**Key words:** `bit` = one 0-or-1; `combinational` = no memory: output follows input instantly; `assign` = a permanent wire connection; `generate` = copy hardware N times

**Read the code:** Read `full_adder`: sum is 1 when an odd number of inputs are 1. The carry goes to the next box, just like carrying in school maths.

**Run it:** `./run_all.sh 1` →
```
L01 adder32: PASS (0 errors in 1000 checks)
```
**Break it:** Change the carry to `assign cout = (a & b);` (forget the carry-in). →
```
L01 adder32: FAIL (990 errors in 1000 checks)
```
The adder is right only when no carry ever ripples. Random testing finds it immediately: 990 of 1000 checks fail.

**Check yourself:**
- *What is 1 + 1 in binary?* — 10: write 0, carry 1.
- *Why test 0xFFFFFFFF + 1 on purpose?* — It makes the carry ripple through all 32 boxes, the longest and riskiest path, and the result wraps to 0 with cout = 1.

*In the big core:* Your core's ALUs, address adders and the Booth multiplier are all built from this idea.


### Level 2 – The clock and memory (flip-flops remember)  · [`L02_counter.sv`](cpu-lab/beginner/L02_counter.sv)

The **clock** is a drumbeat: tick, tick, tick. A **flip-flop** is a notebook that may only write on the tick. Between ticks it keeps showing the old number. Everything in a CPU marches to this drum, which is why all parts stay in step.

**Key words:** `clock edge` = the instant the drum hits (0→1); `always_ff` = 'this block is flip-flops'; `<=` = non-blocking: all notebooks write together; `reset` = start from a known value

**Read the code:** `count <= count + 1` means: at the next tick, the new value is the old value plus 1. Use `<=` in `always_ff` and `=` in `always_comb`. Mixing them was a real source of races in the big core.

**Run it:** `./run_all.sh 2` →
```
L02 counter: PASS (0 errors)
```
**Break it:** Delete `if (en)` so it always counts. →
```
L02 counter: FAIL (38 errors)
```
The testbench keeps its own model counter and compares every tick: 38 mismatches.

**Check yourself:**
- *A 4-bit counter is at 15 and counts once more. What does it show?* — 0. It wraps around, because 16 needs 5 bits.
- *Why does the testbench check just AFTER the clock edge?* — The flip-flop changes on the edge. Checking a moment later sees the new value; checking exactly on the edge is a race.

*In the big core:* Every register in your core (ROB entries, RS entries, the PC) is a bank of these notebooks.


### Level 3 – The ALU (the CPU's calculator)  · [`L03_alu.sv`](cpu-lab/beginner/L03_alu.sv)

The ALU (arithmetic logic unit) is a calculator with buttons: ADD, SUB, AND, SHIFT... In hardware all the answers are worked out at the same time, and the button (`op`) only chooses which answer leaves the box.

**Key words:** `case` = pick one of many; `$signed` = treat bits as a +/- number; `>>>` = shift that keeps the sign; `enum` = names instead of magic numbers

**Read the code:** SLT and SRA need `$signed`. Without it, -1 (0xFFFFFFFF) looks like a huge positive number.

**Run it:** `./run_all.sh 3` →
```
L03 alu: PASS (0 errors in 3000 checks)
```
**Break it:** Write `SRA: y = a >>> b[4:0];` without `$signed`. →
```
L03 alu: FAIL (148 errors in 3000 checks)
```
`>>>` on an unsigned value acts like a normal shift, so negative numbers lose their sign: 148 of 3000 random checks fail. Testing corner values (-1, MIN, MAX) on purpose helps.

**Check yourself:**
- *Why does the ALU have a `default` branch?* — So an unknown op can never silently 'do nothing'. In your big core, missing ops (andi, ori…) did exactly that and the instruction vanished (bug B03).
- *Is 0x80000000 bigger than 1?* — Unsigned: yes (2147483648). Signed: no (it is -2147483648). The same bits, two meanings.

*In the big core:* Your core has 3 of these ALUs working in parallel.


### Level 4 – The register file (32 lockers, one glued shut)  · [`L04_regfile.sv`](cpu-lab/beginner/L04_regfile.sv)

Registers are the CPU's pockets: tiny, very fast storage for numbers it is working on. RISC-V has 32 of them, x0 to x31. Each cycle you can peek into two lockers and put something into one. Locker **x0** is glued shut: it always reads 0, and anything you put in it disappears.

**Key words:** `read port` = a window to peek in; `write port` = a slot to put in; `x0` = always zero; `write enable` = 'actually write this cycle'

**Read the code:** Two guards protect x0: one on the write side (`wa != 0`) and one on the read side. Reads are combinational (instant); writes wait for the clock.

**Run it:** `./run_all.sh 4` →
```
L04 regfile: PASS (0 errors, x0 = 0)
```
**Break it:** Remove both x0 guards. →
```
L04 regfile: FAIL (6 errors, x0 = 0)
```
Now x0 can hold junk, and any instruction that reads x0 gets a wrong value: 6 read mismatches.

**Check yourself:**
- *Why have a zero register at all?* — It gives free constants and tricks: `addi x5, x0, 7` means 'x5 = 7', `add x5, x6, x0` means 'copy x6'.
- *You write x7 and read x7 in the same cycle. Which value do you get?* — In this design, the OLD one, because the write lands at the clock edge. Real pipelines add a bypass so you get the new one.

*In the big core:* Your core calls this the ARF (architectural register file). Renaming (Level 8) is about NOT waiting for it.


### Level 5 – Queues and handshakes (valid + ready)  · [`L05_fifo.sv`](cpu-lab/beginner/L05_fifo.sv)

Think of a queue at a ticket counter. The person giving tickets raises a flag saying 'I have one' (**valid**). The counter raises a flag saying 'I have room' (**ready**). A ticket moves only when both flags are up on the same beat. If the counter is full, the giver must wait *and keep holding the same ticket*.

**Key words:** `FIFO` = first in, first out; `valid` = 'I have data'; `ready` = 'I can take it'; `back-pressure` = ready=0 makes the sender wait

**Read the code:** `count` has one extra bit so it can say 'completely full'. Push and pop in the same cycle leave the count unchanged.

**Run it:** `./run_all.sh 5` →
```
L05 fifo: PASS (0 errors, 177 items passed through)
```
**Break it:** Set `in_ready = 1` always (ignore 'full'). →
```
L05 fifo: FAIL (88 errors, 183 items passed through)
```
New tickets overwrite old ones that were never read: 88 scoreboard errors. My own first testbench also had a bug here: it checked the handshake *after* the clock edge, when everything had already moved. Always sample just *before* the edge.

**Check yourself:**
- *The giver has valid=1 but ready=0 for 3 beats. What must the giver do?* — Keep the same data and keep valid=1 until ready=1. Changing the data or dropping it loses a ticket.
- *What did your big core's frontend get wrong here?* — Its PC kept moving while the queue said 'not ready', so whole bundles of instructions were skipped (bug B09).

*In the big core:* Your core's 16-entry instruction queue and the fetch→decode path are exactly this.


### Level 6 – A whole tiny CPU (fetch → decode → execute → write back)  · [`L06_tiny_cpu.sv`](cpu-lab/beginner/L06_tiny_cpu.sv)

Now we have a calculator (ALU), pockets (registers) and memory, and we can build a CPU! A program is a list of instructions. The **PC** (program counter) is a bookmark pointing at the current line. Every cycle the CPU reads that line, works out what it means, does it, saves the answer, and moves the bookmark. A **branch** moves the bookmark somewhere else, which is how loops work.

**Key words:** `PC` = bookmark: address of the current instruction; `opcode` = which kind of instruction; `immediate` = a number written inside the instruction; `branch` = jump if a condition holds

**Read the code:** The test program adds 1+2+…+10 with a loop, stores 55 to memory, loads it back, and checks that `addi x5, x0, -1` gives 0xFFFFFFFF. Immediates are **always sign-extended** from bit 31. `funct7` means something only for R-type instructions. Your big core broke both rules (bugs B01 and B02).

**Run it:** `./run_all.sh 6` →
```
L06 tiny_cpu: PASS (x1 = sum 1..10 = 55, x4 loaded back = 55, x5 = ffffffff)
```
**Break it:** Zero-extend the immediate: `{20'b0, instr[31:20]}`. →
```
L06 tiny_cpu: FAIL x1=55 x4=55 x5=00000fff
```
The loop still works (all its numbers are small and positive), but `addi x5, x0, -1` gives 0x00000FFF. Tests with only small positive numbers would never notice. That is exactly how your big core's original test passed.

**Check yourself:**
- *How does the CPU make a loop?* — A branch at the bottom compares two registers and, if the condition holds, sets PC = PC + offset (negative offset = jump back).
- *Why is a single-cycle CPU slow?* — The clock must wait for the longest path (fetch + decode + register read + ALU + memory + write) every single cycle, even for simple instructions.

*In the big core:* Your core does these same four jobs, but split into many stages and for 3 instructions at a time.


### Level 7 – Why simple CPUs wait (dependencies and the scoreboard)  · [`L07_scoreboard.sv`](cpu-lab/beginner/L07_scoreboard.sv)

Faster CPUs work like an assembly line: a new instruction starts every cycle while older ones are still finishing. Problem: if `add x4, x3` needs x3 and `mul x3` hasn't finished, the add must wait. In a single-file line, **everyone behind it waits too**, even instructions that need nothing. A scoreboard keeps one 'busy' flag per register to know who must wait.

**Key words:** `RAW` = read-after-write: a true need; `WAW` = write-after-write: two writers; `stall` = wait a cycle; `busy bit` = 'this register is being computed'

**Read the code:** The flag is set when an instruction starts and cleared when its result comes back. `stall` checks both sources and the destination.

**Run it:** `./run_all.sh 7` →
```
L07 scoreboard: PASS (0 errors: dependent add must wait, independent op must not)
```
**Break it:** Only check the destination (remove the RAW check). →
```
L07 scoreboard: FAIL (1 errors: dependent add must wait, independent op must not
```
The add starts before the mul finishes and would use a stale x3: the testbench catches it.

**Check yourself:**
- *`addi x5, x0, 7` sits behind a stalled instruction. Does it need to wait?* — Logically no, it depends on nothing. An in-order CPU makes it wait anyway. Out-of-order CPUs let it go ahead (Levels 8–11).
- *Which hazards are 'fake'?* — WAR and WAW. They only exist because there are few register names. Renaming (Level 8) removes them; only RAW is real.

*In the big core:* This is the problem your whole out-of-order core exists to solve.


### Level 8 – Renaming (ticket numbers instead of names)  · [`L08_rename.sv`](cpu-lab/beginner/L08_rename.sv)

In a restaurant two customers might both order 'pizza'. The kitchen doesn't track 'pizza'; it tracks **ticket numbers**. The CPU does the same: every result gets a fresh ticket (a tag). The rename table (RAT) remembers, for each register, which ticket will produce its newest value. If there is no ticket, the value is already sitting in the register file.

**Key words:** `tag / ticket` = the name of a future value; `RAT` = register → newest ticket; `valid bit` = 'a ticket exists'; `commit` = ticket finished, value saved

**Read the code:** Two rules. (1) A **separate valid bit**: ticket 0 is a real ticket, never 'no ticket'. (2) When a ticket finishes, clear the entry **only if it still points to that ticket**; a newer ticket may have replaced it.

**Run it:** `./run_all.sh 8` →
```
L08 rename: PASS (0 errors)
```
**Break it:** Clear the RAT entry on any finish, without checking the ticket number. →
```
L08 rename: FAIL (1 errors)
```
When old ticket 0 finishes, it wipes the mapping that belongs to newer ticket 1. Later readers would read a stale register.

**Check yourself:**
- *`mul x3…` gets ticket 0, then `sub x3…` gets ticket 2. Who reads which?* — Instructions between them read ticket 0. Instructions after the sub read ticket 2. Both writers can run at the same time without clashing.
- *Why is 'tag 0 means none' dangerous?* — Ticket 0 is handed out like any other number. Your big core made this mistake and every instruction waiting on ticket 0 waited forever (bug B04).

*In the big core:* Your core's RAT has 32 entries, and its tickets are the 48 ROB slots.


### Level 9 – Waiting room and the bell (reservation station + CDB)  · [`L09_rs_cdb.sv`](cpu-lab/beginner/L09_rs_cdb.sv)

Order tickets wait on a rail (the **reservation station**) until all their ingredients are ready. When a cook finishes, they ring the bell and shout 'ticket 2 is ready, it's 30!'. That bell is the **common data bus (CDB)**. Every waiting ticket listens: anyone who needs ticket 2 grabs the 30. As soon as a ticket has everything, it raises its hand, and the oldest raised hand goes to a cook. A younger, ready instruction can go before an older, waiting one. **That is out-of-order execution.**

**Key words:** `RS` = where instructions wait for operands; `wakeup` = matching your tag on the bell; `select` = pick one ready instruction; `CDB` = the shared result bell

**Read the code:** Two subtle cases are handled: tag 0 is a real tag (only the ready bit matters), and an instruction inserted on the **same cycle** the bell rings must catch it too, or it waits forever.

**Run it:** `./run_all.sh 9` →
```
L09 reservation station: PASS (0 errors: younger ready op first, tag-0 wakeup)
```
**Break it:** Add `&& e[i].a_tag != 0` to the wakeup. →
```
L09 reservation station: FAIL (1 errors: younger ready op first, tag-0 wakeup)
```
The test makes instruction A wait for ticket 0. It never wakes up and the testbench fails. This is your core's bug B04, rebuilt small.

**Check yourself:**
- *Instruction B is younger than A but ready first. Who goes?* — B. Waiting A doesn't block it, which is the whole point.
- *Why one bell for everyone instead of private messages?* — The producer doesn't know who needs its result. Broadcasting the ticket number lets any number of waiters match it in the same cycle.

*In the big core:* Your core has 12 ALU + 4 MUL/DIV + 16 load/store RS entries and a 3-lane CDB.


### Level 10 – Serve in order (the reorder buffer)  · [`L10_rob.sv`](cpu-lab/beginner/L10_rob.sv)

Dishes get cooked in any order, but customers must be served in the order they ordered. The **reorder buffer (ROB)** is a line of slots: new instructions join at the tail, finished ones are marked done, and only the one at the head (the oldest) may leave and update the real registers. This keeps the CPU's official state tidy at every moment.

**Key words:** `ROB` = the in-order line; `head` = oldest: commits; `tail` = next free slot; `commit / retire` = make a result official

**Read the code:** It's a circular FIFO (Level 5 again!) plus a 'done' flag per slot. `commit_valid = valid[head] && done[head]`.

**Run it:** `./run_all.sh 10` →
```
L10 rob: PASS (finished in order 2,4,0,3,1 -> retired in order '{'h0, 'h1, 'h2, 'h3, 'h4})
```
**Break it:** Retire without waiting for `done`. →
```
L10 rob: FAIL (finished in order 2,4,0,3,1 -> retired in order '{'h0, 'h1, 'h2, 
```
My first testbench MISSED this: it only checked the *order* of retirement, not the values. A weak checker passes a broken design. After adding a value check, the testbench catches it. Always ask: what could be wrong that my checker can't see?

**Check yourself:**
- *Finish order is 2, 4, 0, 3, 1. What is the retire order?* — 0, 1, 2, 3, 4, always program order.
- *Why bother? Just write results when they finish.* — If something goes wrong (a wrong-guess branch, an exception) we must undo everything after a point. With in-order retirement nothing after that point has touched the real registers yet.

*In the big core:* Your core's ROB has 48 slots and retires up to 3 per cycle.


### Level 11 – The whole restaurant (a tiny out-of-order CPU)  · [`L11_tiny_ooo.sv`](cpu-lab/beginner/L11_tiny_ooo.sv)

Now glue Levels 8, 9 and 10 together. Orders come in one per cycle (dispatch). Each gets a ticket and a ROB slot, waits on the rail for ingredients, gets cooked when ready (ALU: 1 beat, MUL: 3 beats), rings the bell, and is served in order. Below is the **real timeline** from simulating it: instructions finish out of order and retire perfectly in order.

**Key words:** `dispatch` = rename + ROB slot + RS slot; `issue` = start cooking; `structural hazard` = two results want the single bell; `WAW` = two writers to x3: newest wins at commit

**Read the code:** Look at T4 (`addi x5`): it is ordered after the slow `mul` (T2) and the `add` that waits for it (T3), yet it finishes in cycle 7, before both. Then it waits, done, until cycle 12 to be served. x3 is written by two muls; the ARF ends with the second one's value (4), because commit is in order.

**Run it:** `./run_all.sh 11` →
```
L11 tiny_ooo: PASS (x3=4 x4=35 x7=39)
```
**Break it:** In `lookup()`, ignore finished-but-not-committed ROB values (`if (1'b0)`). →
```
L11 tiny_ooo: FAIL (x3=30 x4=0 x7=0)
```
An instruction whose producer already rang the bell waits for a bell that will never ring again: a missed wakeup, so the CPU stalls forever and the final registers are wrong (x4 = 0, x7 = 0).

**Check yourself:**
- *Why can't an ALU op start in the cycle a MUL is 2 stages along?* — Both results would reach the single bell (CDB) in the same cycle. That is a structural hazard: not enough of a resource. Your big core uses 3 CDB lanes plus a completion buffer instead.
- *Name the three places a source value can come from at dispatch.* — The register file (no ticket), the ROB (ticket finished but not yet served), or the CDB right now. Otherwise, wait for the bell.

*In the big core:* This is your 3-wide core in miniature. Next step: the advanced course.


## 4. Deep Dive: the tiny OOO CPU (Level 11) timeline

```
L10 rob: PASS (finished in order 2,4,0,3,1 -> retired in order '{'h0, 'h1, 'h2, 'h3, 'h4})
cycle  1:  dispatch addi x1, x0, 5   -> ticket T0
cycle  2:  dispatch addi x2, x0, 6   -> ticket T1  start T0
cycle  3:  dispatch mul  x3, x1, x2  -> ticket T2  start T1  BELL T0=5
cycle  4:  dispatch add  x4, x3, x1  -> ticket T3  BELL T1=6  COMMIT addi x1, x0, 5
cycle  5:  dispatch addi x5, x0, 7   -> ticket T4  start T2  COMMIT addi x2, x0, 6
cycle  6:  dispatch sub  x6, x5, x1  -> ticket T5  start T4
cycle  7:  dispatch mul  x3, x6, x6  -> ticket T6  BELL T4=7
cycle  8:  dispatch add  x7, x3, x4  -> ticket T7  start T5  BELL T2=30
cycle  9:  start T3  BELL T5=2  COMMIT mul  x3, x1, x2
cycle 10:  start T6  BELL T3=35
cycle 11:  COMMIT add  x4, x3, x1
cycle 12:  COMMIT addi x5, x0, 7
cycle 13:  BELL T6=4  COMMIT sub  x6, x5, x1
cycle 14:  start T7  COMMIT mul  x3, x6, x6
cycle 15:  BELL T7=39
cycle 16:  COMMIT add  x7, x3, x4
finished (bell) in order : '{'h0, 'h1, 'h4, 'h2, 'h5, 'h3, 'h6, 'h7}
retired (commit) in order: '{'h0, 'h1, 'h2, 'h3, 'h4, 'h5, 'h6, 'h7}
```

T4 (`addi x5`) finishes in cycle 7, before the older `mul` (T2) and `add` (T3), then waits, done, until cycle 12 to commit. x3 is written twice; the ARF ends with the second `mul`'s value (4) because commit is in order.


## 5. RTL Rules of Thumb (collected from every bug in this lab)

1. One `always_ff` per state variable, written with `<=`; next-state math in `always_comb` with `=`.
2. A separate valid bit, never an in-band sentinel (tag 0, way 3).
3. Data moves only on `valid && ready`; the producer holds data **and** its own state (PC) otherwise.
4. Track identity (index or tag), never re-derive it from data values.
5. Circular-buffer age = `(tag − head) mod N`, never raw `<`.
6. A unit that frees its input must produce an output; make that an assertion, not an `if`.
7. Sign-extend from bit 31; know which bits are a field in which format.
8. Change testbench inputs away from the active clock edge; sample just before it.

## 6. Likely Interviewer Follow-ups

**Q: Blocking vs non-blocking?** `<=` updates all flip-flops together at the end of the time step; `=` updates immediately. Use `<=` for state in `always_ff`, `=` in `always_comb`. Mixing them on state read by another clocked block creates simulation races (seen in the OOO core).

**Q: Why does a FIFO count need one extra bit?** To represent both 0 and DEPTH (full) distinctly.

**Q: What makes a testbench self-checking?** It contains a reference (model, queue, golden file) and compares automatically, printing PASS/FAIL. Prove it can fail by breaking the design on purpose.

## 7. 60-Second Pitch

"I built a CPU from the ground up in eleven steps, from an adder to a tiny out-of-order core with renaming, a reservation station, a common data bus and a reorder buffer. Every level has a self-checking testbench, and I proved each testbench works by injecting a classic mistake and making sure it fails. One of my own testbenches missed a broken ROB until I added a value check, which taught me to always ask what my checker cannot see."

## 8. Self-Check

- [ ] Type L05 (FIFO) and L10 (ROB) from memory and pass the tests.
- [ ] Explain each break-it mutant and why the test catches it.
- [ ] Explain the L11 timeline: which instructions finished out of order and why commit is still in order.
