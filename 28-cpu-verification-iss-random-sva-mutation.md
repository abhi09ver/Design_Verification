# Challenge 28: Verifying a CPU: Golden ISS, Commit Scoreboard, Random, SVA, Mutation

> **Level:** Senior DV
> **Topics:** ISA reference model, commit-trace comparison, liveness/watchdog, constrained random for CPUs, bind-based SVA, unit tests, mutation testing, bug masking, performance checks
> **Related:** [08 – SVA](08-sva-assertions.md), [09 – Coverage closure](09-coverage-plateau-closure.md), [19 – TB from scratch](19-building-uvm-testbench-from-scratch.md), [27 – Bug hunt](27-ooo-core-bug-hunt.md)
> **Code:** [`cpu-lab/`](cpu-lab/README.md) · **Interactive pages:** open the HTML files in [`cpu-lab/pages/`](cpu-lab/pages/) in a browser

---


## 1. The Source

Your uploaded run used a hard-coded checker: 33 expected values keyed by ROB id. It passed. Then, with a proper flow on the same RTL, **19 of 20 directed tests and 720 of 720 random programs failed**. Here is the flow, the order it found things in, and why each layer exists.

## 2. What Was Wrong With the Original Checker

| Original approach | Problem | Replacement |
|---|---|---|
| 33 expected values hard-coded, keyed by ROB id | encodes what the author *thought* the RTL does; breaks when the ROB wraps; one expectation came from a wrong comment | independent ISS ([`tools/rv.py`](cpu-lab/tools/rv.py), [`pq5/tools/rv32i.py`](cpu-lab/pq5/tools/rv32i.py)) |
| Only checks register values | lost, duplicated or reordered instructions invisible | compare the **commit stream** (PC order) too |
| No liveness check; an instruction-count cap ended the run | deadlocks look like slow tests; duplicates were counted as progress | watchdog (HANG after 200 cycles with no retire) + list of stuck ROB entries |
| One program | every immediate < 32 and no aliasing → B01 hidden | directed bug hunts + constrained random |
| No white-box checks | B11 (duplicate LQ entry) invisible in results | 7 bound SVA properties |

## 3. The Six Layers and What Each Caught

| Layer | What | What it caught |
|---|---|---|
| Golden model (ISS) | `tools/rv.py`: about 200 lines of Python that execute RV32IM in program order with spec semantics. It is the definition of 'correct'. | Found the comment/hex mismatch in your program (instr 16 is `xor`, not `add`) and the misaligned store at 0x19. |
| Commit-trace scoreboard | `tb/tb_lab.sv` prints every retirement (PC, rd, value). `tools/run_test.py` checks order, values, final ARF, memory and liveness. | Finds lost, duplicated and reordered instructions (ORDER), wrong data (VALUE), and deadlocks (HANG with the stuck ROB entries). |
| Directed bug hunts | One 33-instruction program per hypothesis from code review: `tests/b01…b19`. | Confirmed 11 bugs. They also show **bug masking**: until B01 was fixed, most tests died in the first bundle and hid everything else. |
| Constrained random | `tools/gen_random.py`: 7 registers, 8 memory words, extreme seed values, all latencies mixed. | After the directed fixes, 79 of 120 seeds still failed. It found B11, B12, B13 and B14, which nobody would write a directed test for. |
| Assertions (SVA, bind) | `tb/core_sva.sv`: 7 properties attached with `bind`, no RTL edits. | Fire on the cycle a bug happens. A7 fires on **your original passing program**: the load queue holds a duplicate entry. |
| Unit tests | `unit/tb_btb_plru.sv`: the BTB in isolation with an expected victim order. | Found B15, which is invisible to every full-chip test because the BTB is never trained. |

**Random pass rate as fixes landed (120 seeds):** Original RTL: 0/120 → Fixed B01–B10: 41/120 → + B11, B12: 105/120 → + B13, B14: 120/120. The fixed core also passes 720/720.

## 4. Deep Dive

### 4.1 The commit-trace scoreboard (the core idea)

Everything inside an OOO core may reorder. The **committed stream** of `(pc, rd, value)` and the final memory may not. So:

```python
# tools/run_test.py (simplified)
exp = ISS().run(program)                         # program order, spec semantics
got = parse('COMMIT .* pc=(\w+) rd=(\d+) val=(\w+)', sim_log)
for k, (e, g) in enumerate(zip(exp, got)):
    if e.pc != g.pc:  fail(f'ORDER commit #{k}')           # lost / duplicated / reordered
    if e.rd and (e.rd, e.val) != (g.rd, g.val): fail('VALUE')
check(final_ARF == iss.x and final_MEM == iss.mem)
check(status == 'DONE')                                     # liveness
```

The testbench prints a `COMMIT` line from the ROB's "retiring this edge" signals, sampled at the negative clock edge ([`tb/tb_lab.sv`](cpu-lab/tb/tb_lab.sv)).

### 4.2 Constrained random for a CPU

[`tools/gen_random.py`](cpu-lab/tools/gen_random.py): **7 registers** (lots of RAW/WAW/WAR), **8 memory words** (lots of aliasing), extreme seed values (−2048, −1, 0, 2047), every latency class mixed. The pq5 generator ([`pq5/tools/gen_rand.py`](cpu-lab/pq5/tools/gen_rand.py)) adds loops, forward branches and `jalr` that always terminate, and x0 as a destination (see 4.5).

### 4.3 Assertions with `bind` ([`tb/core_sva.sv`](cpu-lab/tb/core_sva.sv))

| SVA | Property | Caught |
|---|---|---|
| A1 | a valid decoded instruction is never type OTHER unless it is a branch | B01, on the decode cycle |
| A2 | decode valid slots form a prefix | frontend bundle shape |
| A3 | the RS/LSB slot written at allocation is free | B12, on the allocation cycle |
| A4 | a CDB broadcast targets a live, not-yet-ready ROB entry | duplicate/stale broadcasts |
| A5 | the ROB head retires within 64 cycles | deadlocks (blind spot: an invalid head = a "hole") |
| A6 | an ALU that accepted an op produces a result | B03 |
| A7 | no two LQ entries share a ROB tag | B11, even on the original *passing* program |

```systemverilog
bind alloc_reorder_retire core_sva #(.IW(ISSUE_WIDTH), .NROB(no_ROB)) u_core_sva (.clk(clk), .rst(rst), ...);
a3_rs_free: assert property ((alloc_d1 && dispatch_reg[d].valid && dispatch_reg[d].rs_allocated) |->
                             !alu_rs[dispatch_reg[d].rs_index].busy) else $error("[SVA A3] ...");
```

### 4.4 Unit-level tests catch what full-chip cannot

The BTB is never trained in full-chip runs, so its replacement bugs (B15) are invisible there. [`unit/tb_btb_plru.sv`](cpu-lab/unit/tb_btb_plru.sv) fills a set and checks the victim order: the original always evicted way 0.

### 4.5 Mutation testing: testing the tests

Inject one known mistake, check the testbench fails. On the 5-stage pq5 CPU ([`pq5/tools/mutate_pq5.py`](cpu-lab/pq5/tools/mutate_pq5.py)):

```
no forwarding from MEM (distance 1)           directed fails:  9/10 p01,p02,p03,p04,p06,p07,p08,p09,p10 random fails: 100/100
no forwarding from WB (distance 2)            directed fails:  9/10 p01,p02,p03,p04,p06,p07,p08,p09,p10 random fails:  57/100
forwarding priority reversed                  directed fails:  2/10 p02,p08                        random fails:   5/100
forward a load's ADDRESS from MEM             directed fails:  0/10                                random fails:   0/100
no register-file write-through (distance 3)   directed fails:  7/10 p01,p02,p04,p06,p07,p09,p10    random fails:  54/100
no load-use stall                             directed fails:  2/10 p03,p07                        random fails:  26/100
flush forgets the instruction in IF/ID        directed fails:  6/10 p04,p05,p06,p07,p09,p10        random fails:  98/100
flush forgets the instruction in decode       directed fails:  6/10 p04,p05,p06,p07,p09,p10        random fails:  98/100
x0 can be written                             directed fails:  5/10 p02,p03,p05,p06,p09            random fails:  54/100
PERF: no branch prediction (always pc+4)      directed fails:  0/10                                random fails:   0/100  CPI p04_loop_sum=1.66 p09_multiply=1.48
```

- **A surviving mutant is a question.** "Forward a load's address" survives because the load-use interlock makes that path unreachable. It was proven with an assertion (`a_loaduse`) rather than assumed.
- **Random had a blind spot.** The first generator never wrote x0, so "x0 can be written" escaped 100/100 random programs. After adding x0 destinations: caught in 54/100.
- On the beginner ladder, 11 of 11 mutants are caught. The first L10 (ROB) testbench missed "retire before finished" because it checked order but not values.

### 4.6 Performance is a check too

The fixed OOO core is correct but issues dependent ALU ops every **2** cycles (b12 chain: CDB at cycles 9, 11, 13, 15) because `ready` is re-registered after wakeup. Without branch prediction, pq5 stays correct but CPI rises from 1.02 to 1.66 on a loop. Track CPI per test.

## 5. Likely Interviewer Follow-ups

**Q: Scoreboard at commit vs at writeback?**

Commit-level matches the ISS exactly and is architecturally clean, but reports late and misses transient corruption. Unit or writeback-level scoreboards localise failures but need a microarchitectural model. Real projects do both.

**Q: How do you know you're done?**

Coverage closure against a plan (features × corners), assertion coverage (properties exercised, not just never failed), a flattened bug-rate curve across seeds, a code-coverage hole review, and sign-off reviews. Never 'all tests pass'.

**Q: How would you verify forwarding completely?**

Producer kind (ALU, load, link, lui) × distance (1, 2, 3, 4+) × consumer operand (rs1, rs2, store data, branch compare, jalr base) × same register written twice (priority). Directed tests per cell, coverage of that cross in random, golden compare at commit.

**Q: Why bind assertions instead of putting them in RTL?**

Keeps verification code out of design files, applies to every instance, reaches internal signals by name, never reaches synthesis, and checker sets can be switched per run.

## 6. Common Mistakes

- Writing the checker from the RTL instead of the spec (the original 33 expected values).
- No liveness check: half of these bugs were deadlocks.
- Random stimulus with no constraints toward hazards (1024 memory words would rarely alias; 8 words alias constantly).
- Sampling a handshake *after* the clock edge in the testbench (my own first FIFO testbench did this).
- Releasing reset on the same clock edge the DUT samples it (a race: the first instruction went missing from the log).

## 7. 60-Second Pitch

"My oracle is an instruction-set simulator, and I compare the committed stream instruction by instruction, plus final registers and memory, plus a liveness watchdog. On top of that: directed tests per hypothesis, constrained random tuned for hazards, and bound SVA for microarchitectural invariants. Then I test the tests with mutation: every mechanism I remove must make something fail. On the OOO core this found 15 bugs; random found the last four and an assertion caught one on the original passing test."

## 8. Self-Check

- [ ] Write the 10-line commit comparison from memory.
- [ ] Name 3 things a register-value-only checker cannot see.
- [ ] Explain what a surviving mutant can mean (test hole vs redundant logic) and how you decide.
- [ ] Give one example where random had a blind spot and how you fixed the generator.
