# Challenge 26: Out-of-Order CPU: The 3-Wide Tomasulo Core, Module by Module

> **Level:** Senior DV / CPU design interviews
> **Topics:** rename, ROB, reservation stations, wakeup/select, CDB, completion buffer, commit, LSQ, memory disambiguation, branch recovery
> **Related:** [27 – Bug hunt](27-ooo-core-bug-hunt.md), [28 – CPU verification](28-cpu-verification-iss-random-sva-mutation.md), [31 – Question bank](31-cpu-interview-question-bank.md)
> **Code:** [`cpu-lab/`](cpu-lab/README.md) · **Interactive pages:** open the HTML files in [`cpu-lab/pages/`](cpu-lab/pages/) in a browser

---


## 1. The Source

A 6,700-line SystemVerilog **3-wide RISC-V (RV32IM) out-of-order core** in the Tomasulo style, with the ROB holding results (uploaded as `result_3.zip`; kept verbatim in [`cpu-lab/original_upload/`](cpu-lab/original_upload/)).
Its own test (33 instructions, hard-coded expected values) passed 33/33 at IPC 1.32. The original Xcelium run actually stopped at elaboration (`MULAXX` in the MMU).

## 2. What's Wrong With It (short version)

Under a proper flow (golden ISS, commit-by-commit compare, constrained random, SVA), the original RTL fails **19 of 20 directed tests and 720 of 720 random programs**. 15 functional bugs were reproduced, fixed and re-verified (fixed core: 19/20 directed, the remaining one is the branch capstone; 720/720 random; 0 assertion firings). Full list: [Challenge 27](27-ooo-core-bug-hunt.md).

## 3. The Machine at a Glance (real parameters)

| Block | Size | Notes |
|---|---|---|
| Fetch | 3 instr/cycle, 64-word IMEM | fetch register → **16-entry instruction queue** → fetch→decode latch |
| Branch predictor | BTB 64×4 (tree-PLRU), gshare 1K, RAS 16, BPQ 16 | backend never resolves branches (capstone) |
| Decode | 3-wide | 17-bit op key `{funct7, funct3, opcode}`, 2-bit type: 00 ALU, 01 MEM, 10 MUL/DIV, 11 other |
| Rename | RAT 32 → ROB tag | ROB is the physical register name (data-in-ROB Tomasulo) |
| ROB | 48 entries | `ROB_head` = allocation pointer, `ROB_tail` = commit pointer (the reverse of textbooks) |
| Reservation stations | ALU 12, MUL/DIV 4, Load/store buffer 16 | data-capture RS |
| Execute | 3 ALU (1 cycle), 2× (MUL radix-4 Booth 3 stages + DIV radix-8 11 stages) | per-tag op table for MUL/DIV |
| Memory | LQ 8, SQ 8, 2 load ports + 1 store port, DMEM 1024 words | stores write after retire (senior stores) |
| Writeback | completion buffer 48 entries, 9 inputs → **CDB 3 lanes** | `almost_full` at 48 − 9 − 5 = 34 |
| Commit | 3/cycle, in order | ARF update, RAT clear if still pointing at the entry |

**Three orders:** instructions *enter* in program order, *execute* in dataflow order, *leave* in program order.
**Three hazards, three answers:** WAR/WAW → renaming. RAW through registers → tags + CDB wakeup. RAW through memory → LSQ (addresses known late).

## 4. Deep Dive, Module by Module


### Module 1 – Frontend  
*Files:* `fetch.sv · fetch_unit.sv · branch_predictor.sv`

Every cycle the frontend reads **3 consecutive instructions** (12 bytes) from a byte-addressed instruction memory into a fetch register. That register feeds a **16-entry instruction queue** (IQ), and the IQ feeds a fetch→decode latch. A predecoder classifies each slot as call, return or branch for the branch predictor: a 64-set × 4-way BTB with tree-PLRU, a 1K-entry gshare, a 16-deep return address stack, and a branch-prediction queue. 
 The PC register (`fetch_pc_mux_d`) normally advances by 12. The IQ decouples fetch from decode: fetch can run ahead while decode is stalled, until the queue fills.

**Hidden concepts**

- **Valid/ready is a contract** — Data crosses a boundary only on `valid && ready`. The producer must **hold** both the data and its own state (here: the PC) when `ready` is low. Bug B09 breaks this contract in three places.
- **All-or-nothing bundles** — If a 3-wide bundle can be partly accepted, the PC must move by the accepted amount. Accepting all or nothing (`count + 3 <= depth`) is simpler and keeps one invariant: decode slots are a contiguous prefix, which ROB indexing depends on (`rob = ROB_head + slot`).
- **Prediction timing** — This predictor looks at the bundle *already fetched*, so a taken branch redirects one cycle late and the next sequential bundle is wrong-path. Real cores either predict from the PC (next-line/BTB lookup in the same cycle as the I-cache) or squash the wrong-path bundle.
- **Why gshare needs checkpoints** — The global history register must be updated **speculatively** at prediction and restored on a mispredict. Updating it at resolution, as here, indexes the table with a different history than prediction used.

**Code walk (line numbers refer to the original upload)**

- `fetch.sv:85-102` — PC update: advances whenever `init` and inside the program. No back-pressure input.
- `fetch_unit.sv:52-65` — Fetch→decode latch: slots without new data keep their old content.
- `fetch_unit.sv:214-215` — IQ `enq_ready[j] = count + j < DEPTH`: partial bundles possible.
- `branch_predictor.sv:45-67` — Tree-PLRU update and victim functions.

**Bugs found here:** [B09 Frontend ignores back-pressure and replays stale bundles](27-ooo-core-bug-hunt.md#b09), [B15 BTB replacement evicts the most recent entry and never uses way 3 while it is free](27-ooo-core-bug-hunt.md#b15)

**Build it**

1. Draw the timing of PC → fetch_reg → IQ → latch → decode_reg for a 4-cycle allocation stall. Mark every cycle where a bundle exists in two places.
2. Write the SVA: `$fell(imem_stall) |-> ...` no bundle is lost or duplicated. Hint: keep a counter of PCs fetched vs. PCs enqueued.
3. Run `make test T=tests/b08_frontend_backpressure.s RTL=rtl`, then fix fetch.sv/fetch_unit.sv yourself. Compare with `solutions/`.
4. Extend `unit/tb_btb_plru.sv` into a reference-model check: a Python or SV model of tree-PLRU predicts each victim.


### Module 2 – Decode  
*Files:* `decoder.sv · decoder_pkg.sv · tomasulo_pkg.sv`

Three parallel decoders turn each instruction word into a `decode_entry_t`: register fields, the immediate, a 17-bit **operation key** `{funct7, funct3, opcode}`, and a 2-bit type that picks the reservation station: 00 ALU, 01 memory, 10 MUL/DIV, 11 other (branch/jump). `dst` is forced to 0 for stores and branches so they never claim a register.

**Hidden concepts**

- **Format decides what bits mean** — RISC-V has six formats (R, I, S, B, U, J). The same bit positions mean different things in each. [31:25] is funct7 only in R-type (and as imm[11:5] that happens to carry the srai flag in shifts). Everything downstream of the decoder trusts the key, so a decode bug looks like a back-end bug.
- **The immediate is always sign-extended** — In RV32I, imm bit 31 is always the sign, in every format. That design choice lets hardware start sign-extension before it knows the format.
- **x0 is not a register** — Writes to x0 are discarded and reads give 0. Here that is done by never renaming x0 (dst = 0 means 'no destination') and reading 0 at dispatch. Any path that forgets it creates a fake dependency on 'x0'.

**Code walk (line numbers refer to the original upload)**

- `tomasulo_pkg.sv:404-409` — `create_operation`: the 17-bit key.
- `tomasulo_pkg.sv:352-365` — `get_instr_type`: unknown key → OTHER.
- `decoder.sv:122-171` — Key, type, dst and immediate decode.
- `decoder_pkg.sv:142-167` — `is_valid_instruction` (widths mismatch, never matches R-type).

**Bugs found here:** [B01 Immediate bits leak into the opcode key](27-ooo-core-bug-hunt.md#b01), [B02 I-type immediates are zero-extended](27-ooo-core-bug-hunt.md#b02)

**Build it**

1. Write a decoder unit test that loops over every RV32IM instruction with random fields, including imm ≥ 32 and negative, and checks `instr_type` and `immediate` against `tools/rv.py`.
2. Add SVA A1 to your own copy, then break the decoder on purpose and watch it fire.
3. Make illegal instructions raise `decoder_error` correctly (fix the 10-bit vs 17-bit compare) and block allocation.


### Module 3 – Rename & Dispatch  
*Files:* `alloc_reorder_retire.sv:342-678`

Dispatch takes up to 3 decoded instructions per cycle. For each one it: 
 Allocates a ROB entry: `rob = (ROB_head + slot) % 48`. In this code **ROB_head is the allocation pointer and ROB_tail the commit pointer**, the reverse of most textbooks. 
 Resolves each source in priority order: a producer earlier in the same bundle → the RAT (in flight, so take its ROB tag, then try to grab the value from the CDB or retire bus this cycle) → x0 → the ARF. 
 Picks a free RS slot of the right class. 
 Updates the RAT: `RAT[dst] = rob`. 
 The bundle goes to all-or-nothing allocation: if any resource is short (ROB, ALU RS, MD RS, LSB), the whole bundle stalls (`alloc_stall`).

**Hidden concepts**

- **The ROB index is the physical register** — This is Tomasulo with a ROB, where data lives in the ROB. A ROB tag names the value, the RAT maps x3 → ROB5, and consumers wait on tag 5. This removes WAR and WAW hazards: in the stepper, x3 is written by the MUL (ROB 2) and the SUB (ROB 5), and the RAT simply points to the youngest. A PRF-based design (MIPS R10K, most modern cores) keeps values in a physical register file instead, so the ROB holds only pointers.
- **Intra-bundle dependencies** — Instruction 2 in a bundle may read what instruction 0 writes in the same cycle. The RAT cannot know yet, so dispatch compares each source against earlier slots' destinations (a priority mux, youngest earlier slot wins). Cost grows as O(width²), one reason rename width is hard to scale.
- **Age = distance from the commit pointer** — In a circular ROB, tag 3 can be younger than tag 40. True age is `(tag − commit_ptr) mod N`. Any raw `<` on tags is a bug waiting for the wrap.
- **One source of truth** — Bug B12 had two copies of 'which RS slots are free', updated by signals one cycle apart. Derive availability from the real state plus what is in flight, and nothing else.

**Code walk (line numbers refer to the original upload)**

- `alloc_reorder_retire.sv:342-387` — Resource counting and `alloc_stall` (note the `instr_ID` cap applied after the stall).
- `alloc_reorder_retire.sv:504-549` — Source resolution: bundle → RAT (+CDB/retire bypass) → x0 → ARF.
- `alloc_reorder_retire.sv:433-449` — The shadow free-list (bug B12).
- `alloc_reorder_retire.sv:767-778` — ROB allocation written into `ROB_next` from a clocked block (race).

**Bugs found here:** [B12 Dispatch's private free-list disagrees with the real busy bits](27-ooo-core-bug-hunt.md#b12)

**Build it**

1. Draw the ROB at cycle 9 of the stepper: which entries are valid, which tags the RAT points to, and why x1/x2 no longer have mappings.
2. Replace the shadow free-list yourself (single source of truth). Run 50 random seeds before and after: `python3 tools/gen_random.py N f.s; make test T=f.s`.
3. Move the ROB allocation out of the clocked block into the `always_comb` that builds `ROB_next`, so it has a single driver. Re-run the regression.
4. Remove the `instr_ID` cap. Which test now fails on the original frontend, and why does it pass on the fixed one?


### Module 4 – Issue: wakeup & select  
*Files:* `alloc_reorder_retire.sv:913-1197 · alu_top.sv · mul_div_top.sv`

Reservation stations: **12 ALU**, **4 MUL/DIV**, **16 load/store** (LSB). Each entry holds the operation, two operands, each with either a value or the ROB tag it waits for, and a `ready` bit. 
 **Wakeup:** every cycle each waiting operand compares its tag with all 3 CDB lanes. It also checks a 1-cycle-delayed copy of the CDB and the retire bus, as belt-and-braces. **Select:** `alu_top` picks up to 3 ready entries (one per ALU), oldest-ROB-index first. `mul_div_top` picks one MUL and one DIV per unit. A selected entry is cleared from the RS that same cycle (`rs_clear`).

**Hidden concepts**

- **The wakeup–select loop sets your IPC** — For back-to-back dependent single-cycle ops, an instruction selected in cycle N must wake its consumer in time for the consumer to be selected in N+1. That is the critical loop of every OOO core. Here `ready` is re-registered from `src_valid`, which adds a cycle: dependent adds run at 1 per 2 cycles (see the chain in exercise E4).
- **Capture vs. no-capture RS** — This design is **data-capture**: operand values are copied into the RS, from the ARF at dispatch or from the CDB at wakeup. The alternative is **non-capture**: the RS holds only tags and operands are read from the PRF after select. Capture needs wide RS entries and CDB-to-RS data wires. Non-capture needs PRF read ports after select.
- **Select must be 1:1** — Every entry cleared from an RS must arrive at exactly one functional-unit input in the same cycle. Bug B03 (ALU drops op) and bug B05 (DIV overwritten) both broke this, and both lost an instruction silently.
- **Sentinels** — Tag 0 used as 'no tag' (B04). The valid bit is the only correct qualifier.

**Code walk (line numbers refer to the original upload)**

- `alloc_reorder_retire.sv:929-1006` — ALU RS wakeup (4 sources, short-circuit).
- `alloc_reorder_retire.sv:1186-1196` — `ready` recomputed from registered `src_valid`: the 2-cycle loop.
- `alu_top.sv:29-69` — Oldest-first select, up to 3 per cycle.
- `mul_div_top.sv:50-129` — MUL/DIV select (bug B05).

**Bugs found here:** [B04 ROB tag 0 can never be woken up](27-ooo-core-bug-hunt.md#b04), [B05 Second DIV overwrites the first; unsigned M-ops never issue](27-ooo-core-bug-hunt.md#b05)

**Build it**

1. **E4 (performance):** make dependent ALU ops issue back to back. Compute ready as `(src_valid | cdb_match)` combinationally for select. Measure `b12_raw_chain` cycles before and after (39 now).
2. Write the 1:1 select assertion: `$countones(rs_clear) == $countones(ex_valid)` for the ALU and MUL/DIV tops.
3. Replace raw-index age in `alu_top` with true age `(rob − ROB_tail) mod 48`. Write a test that makes the ROB wrap (more than 48 instructions; raise NO_INSTR and the IMEM size).


### Module 5 – Execute  
*Files:* `alu_unit.sv · mul_div.sv · radix_4_multiplier.sv · radix_8_dividor.sv`

**3 single-cycle ALUs.** **2 MUL/DIV units**, each with a 3-stage radix-4 Booth multiplier (Booth encode → CSA tree → carry-propagate add) and an 11-stage radix-8 divider that does 3 quotient bits per stage, fully pipelined with the ROB tag carried along. MUL/DIV entries leave the RS at issue. Results come back tagged, and the unit keeps a per-tag table of which operation (mul vs. mulh) to finish.

**Hidden concepts**

- **Radix-4 Booth** — Booth recoding looks at 3 multiplier bits at a time (overlapping by one) and turns them into a digit in {−2, −1, 0, +1, +2}. That halves the partial products (16 instead of 32 for 32 bits). The −2 digit needs −2M, so partial products need 2 extra bits, not 1 (bug B14).
- **Signed vs. unsigned high product** — One signed 32×32 multiplier can produce all four RISC-V multiplies: `mulhu = mulh + (a<0 ? b : 0) + (b<0 ? a : 0)` and `mulhsu = mulh + (b<0 ? a : 0)`, all mod 2³². This is how the fix adds mulhu/mulhsu without a second multiplier.
- **RISC-V does not trap on divide by zero** — x/0 = all ones, x%0 = x. Overflow −2³¹/−1 = −2³¹ with remainder 0. These come straight from the spec table and are the first things to test.
- **Variable latency means out-of-order completion** — ALU 1 cycle, MUL 3, DIV 11+. Results arrive out of order and in bursts, which is why the completion buffer exists (module 6).

**Code walk (line numbers refer to the original upload)**

- `alu_unit.sv:18-51` — ALU case: OP-IMM ops missing (bug B03).
- `radix_4_multiplier.sv:38-80` — Booth encode and partial products (bug B14).
- `radix_8_dividor.sv:58-155` — Radix-8 restoring divider, sign handling (bug B06).
- `mul_div.sv:48-149` — Per-tag op table and result mux.

**Bugs found here:** [B03 ALU silently drops OP-IMM instructions](27-ooo-core-bug-hunt.md#b03), [B06 Signed divide by zero returns +1](27-ooo-core-bug-hunt.md#b06), [B14 Booth multiplier overflows on the most negative number](27-ooo-core-bug-hunt.md#b14)

**Build it**

1. Write an exhaustive-corner unit test for the multiplier: all pairs from {0, 1, −1, 2³¹−1, −2³¹, random} × 4 ops vs. Python big-int.
2. Make the divider early-out when the dividend is small. Then make the verification catch the bug you will almost certainly introduce: two results with different latencies reaching the output in the same cycle.
3. Add the missing `stall` handling: today the MUL/DIV pipelines keep producing results while the completion buffer is almost full. Prove with an assertion that the buffer never drops a result.


### Module 6 – Writeback & CDB  
*Files:* `completion_buffer.sv`

Nine producers (3 ALU + 2×MUL + 2×DIV + 2 load ports) can finish in the same cycle, but the common data bus has only **3 lanes**. The completion buffer is a 48-entry FIFO. When it is empty and at most 3 results arrive, they bypass straight to the CDB. Otherwise they are queued and drained 3 per cycle. When the count reaches `48 − 9 − 5 = 34`, `almost_full` stalls the ALU and MUL/DIV select and the load issue.

**Hidden concepts**

- **Why a buffer at all** — Without it you need either 9 CDB lanes (9 tag comparators per operand per RS entry) or arbitration that stalls functional units mid-pipeline. Pipelined MUL/DIV cannot stall cheaply. Buffering moves the cost to a FIFO.
- **Safety margin = credits** — `almost_full` must fire early enough to absorb everything already in flight that cannot be stopped: up to 9 results per cycle, plus the multi-cycle pipelines. The margin is credit-based flow control done by hand. A formal proof or an assertion that the FIFO never overflows is the real check, because the enqueue silently drops results when full (completion_buffer.sv:126).
- **FIFO order is not age order** — Results are broadcast in arrival order, not program order. That is fine because the ROB restores order at commit.

**Code walk (line numbers refer to the original upload)**

- `completion_buffer.sv:89-141` — Dequeue then enqueue in one cycle; silent drop at full.
- `completion_buffer.sv:143-187` — Bypass vs. buffered output mux.
- `completion_buffer.sv:192-197` — `almost_full` threshold.

**Build it**

1. Add an assertion: `func_results[i].result_ready |-> next_count < BUFFER_DEPTH` (no silent drop). Then shrink `SAFETY_MARGIN` to 0 and write a test that overflows the buffer.
2. Prioritise the CDB by age (oldest first) instead of FIFO order. Does IPC change on the random suite? (Measure; don't guess.)


### Module 7 – Commit  
*Files:* `alloc_reorder_retire.sv:1219-1406`

Up to 3 instructions retire per cycle, in order, from `ROB_tail` (the commit pointer). An entry retires if it is `valid && ready`. The first entry that is not ready stops the group. On retire, the value is written to the ARF (unless dst = x0), the RAT mapping is cleared if it still points at this entry, and the retire info is broadcast as a late wakeup source. Stores become 'ready' when they enter the store queue, and they write memory only after they retire (module 8).

**Hidden concepts**

- **Precise state** — Because commit is in order, the ARF always equals the state of a simple in-order machine at some instruction boundary. That makes precise exceptions and interrupts possible: flush everything younger than the faulting instruction, and the ARF is exactly right. This core has no exceptions yet. Implementing them uses the same mechanism as branch recovery (module 10).
- **The commit stream is your verification contract** — Everything inside the core may reorder. The committed stream of (PC, rd, value) and the memory writes may not. That is why the lab's scoreboard compares exactly those against the ISS, commit by commit.
- **Retire width vs. dispatch width** — If retire is narrower than dispatch, the ROB fills on long-latency stalls and never catches up. Here both are 3.

**Code walk (line numbers refer to the original upload)**

- `alloc_reorder_retire.sv:1234-1286` — `always_comb`: CDB writeback into ROB_next, then retire up to 3.
- `alloc_reorder_retire.sv:1291-1363` — ROB/ARF update, perf counters, and the store-ready hook.

**Build it**

1. Add an assertion that retire is in order: `commit_valid_next[i] |-> commit_valid_next[i-1]`, and that `commit_rob_id_next[i] == (ROB_tail + i) % 48`.
2. Add a precise **illegal-instruction exception**: mark the ROB entry 'exception' at decode, and at commit flush everything and redirect fetch to a handler PC. Extend `tools/rv.py` to model it.


### Module 8 – Memory: LSB, LQ, SQ  
*Files:* `memory_management_unit.sv · data_mem.sv · top_memory_subsystem.sv`

Memory instructions wait in the 16-entry LSB until their base register (and, for stores, the data) is ready. The MMU then moves loads into an **8-entry load queue** and stores into an **8-entry store queue**. Loads issue on **2 read ports**, either forwarded from an older store or read from data memory (1024 words, initialised so word i = i). Stores mark their ROB entry ready on entering the SQ, become **senior** when they retire, and drain through **1 write port** in program order.

**Hidden concepts**

- **The memory RAW hazard** — Registers are renamed at decode, but memory addresses are only known at execute, so a load may not know whether an older store writes its address. The options are: wait until all older store addresses are known (conservative, used by the fix), or speculate, issue anyway, check when the older store's address resolves, and replay on a violation. Real cores speculate, with a store-set or memory-dependence predictor to avoid repeat violations.
- **Forwarding rules** — Forward from the **youngest older** store that overlaps. Forward only if it fully covers the load's bytes, then byte-select and extend. On a partial overlap, wait until the store has drained to memory.
- **Senior stores** — Between 'retired' and 'written to memory' a store is architecturally done but still invisible in memory. Every load is younger than a senior store, and the ROB tag can no longer give its age (bug B13c).
- **Resource deadlock** — If a younger instruction can take the last slot in a shared queue that an older one needs, and the younger one cannot leave before the older one, you have a deadlock (bug B13a). The fixes are in-order allocation or a reserved slot for the oldest.

**Code walk (line numbers refer to the original upload)**

- `memory_management_unit.sv:127-345` — Clocked block: LQ/SQ dequeue, enqueue from LSB, completion, seniority.
- `memory_management_unit.sv:347-446` — Load issue: forwarding search and memory read.
- `memory_management_unit.sv:228` — `unsigned_load` from the wrong bits (bug B10).
- `data_mem.sv` — Byte/half/word read and write with alignment checks (misaligned access silently ignored).

**Bugs found here:** [B07 Loads ignore older stores (no memory disambiguation)](27-ooo-core-bug-hunt.md#b07), [B08 Third load to one address is marked done but never broadcasts](27-ooo-core-bug-hunt.md#b08), [B10 lbu/lhu read as words and sign-extend](27-ooo-core-bug-hunt.md#b10), [B11 MMU consumes the same LSB entry twice](27-ooo-core-bug-hunt.md#b11), [B13 Store queue ordering: deadlock, orphaned and bypassed stores](27-ooo-core-bug-hunt.md#b13)

**Build it**

1. Read `solutions/memory_management_unit.sv` and draw the decision tree for a load: LSB check → youngest older overlapping SQ store → forward / wait / read.
2. Implement **speculative** load issue with violation detection: let loads bypass unknown-address stores, and when a store's address resolves, check younger completed loads; on a match, raise `violation_detected` (the port already exists in design.sv) and flush from the load. You need module 10's flush first.
3. Write the LSQ checker as a TB component: keep a shadow memory updated only at store **retire**, and check every load value against 'shadow memory at the load's position in program order'.


## 5. Capstone: Build Branch Support

The backend has no branch unit. A branch gets type 11: it receives a ROB slot but no reservation station, so the ROB head waits forever (`b11_branch` hangs). Building branch support is the best single project for an OOO interview: it touches every module and forces you to design recovery.

1. **Branch unit** — Add type 11 to dispatch. Give branches ALU RS entries (or a separate BR RS). Compute taken and target in a branch unit: `beq bne blt bge bltu bgeu`, `jal`, `jalr`. `jal/jalr` also write rd = PC+4.
2. **Resolve and compare** — Carry the predicted next-PC with each instruction from fetch (the BPQ is a start). At execute, mispredict = (actual next-PC ≠ predicted).
3. **Recovery** — Simplest correct version: when a mispredicted branch **commits**, assert `flush`, clear everything younger (the ROB, all RS, LQ, SQ non-senior entries, the completion buffer, the MUL/DIV pipelines), restore the RAT to 'all registers in ARF', and redirect fetch to the correct PC. Faster: recover at execute with RAT checkpoints per branch.
4. **Train the predictor** — Drive `update_en/pc/taken/target` from commit. Checkpoint gshare history at prediction.
5. **Verify** — Extend `tools/rv.py` (branches are already modelled). Write loops, calls/returns and data-dependent branches. Assertions: nothing younger than a flushing branch commits; after a flush the RAT is clean; senior stores survive the flush. Coverage: mispredicts in each bundle slot, a mispredict while the ROB wraps, a mispredict with a DIV in flight.

## 6. Likely Interviewer Follow-ups

**Q: Why does an OOO core need an instruction queue between fetch and decode?**

It decouples two pipelines with different stall sources. Fetch stalls on I-cache misses and redirects; decode/rename stalls on back-end resources (ROB, RS, LSQ full). The queue absorbs bursts so neither side waits for the other cycle by cycle, and it is the natural point to apply back-pressure.

**Q: A fetch register is stalled but the PC keeps moving. How would you detect that in verification?**

Compare the committed PC stream with the ISS. Any skipped instruction is an ORDER mismatch at the first commit after the gap. White-box: an assertion that the PC register is stable whenever the fetch register is held (`imem_stall |=> $stable(pc)`), plus a scoreboard of fetched vs. enqueued PCs.

**Q: Tree-PLRU vs true LRU for a 4-way BTB?**

True LRU for 4 ways needs 5 bits per set (one of 24 orderings) and an update that touches all of them. Tree-PLRU needs 3 bits, and an access only flips the bits on its path. It approximates LRU: it never evicts the MRU way, but it does not always pick the true LRU way.

**Q: How do you verify a branch predictor if a misprediction is never a functional failure?**

With performance checks and unit tests: a reference model of the predictor fed the same branch stream must predict the same direction and target; then assert prediction accuracy on known patterns (always-taken loop, alternating, correlated). Full-chip: check that every mispredict is recovered (commit stream correct) and track MPKI as a regression metric.

**Q: Why sign-extend immediates in decode and not in the ALU?**

Decode is the only stage that knows the format. After decode, the immediate is just a 32-bit operand, so the ALU, the AGU and the branch unit all share one representation. It also takes the sign-extension mux out of the execute critical path.

**Q: Your directed test suite passes, but one decode field is wrong for 90% of encodings. How?**

The tests only used small immediates (here every immediate was below 32), so the aliased bits were always 0. Field-level coverage on the encoding (each bit of imm toggled, each format × each opcode) would show the hole at once. Constrained-random over the full encoding space finds it in seconds.

**Q: What decode-time information does rename need?**

Source and destination architectural registers, whether each source is used, whether dst is real (not x0, not store/branch), the functional-unit class, and the immediate. Getting 'source used' wrong creates false dependencies, which are slow but correct. Getting 'dst real' wrong corrupts state.

**Q: Explain register renaming in one minute.**

Architectural registers are few, so independent instructions reuse the same names, creating false WAR/WAW dependencies. Rename maps each destination to a fresh physical name (here a ROB entry) and records the newest mapping in the RAT. Sources read the RAT to find their producer. Only true RAW dependencies remain, so independent work can run out of order. At commit, the value moves to the architectural state, and the mapping is cleared if it still points at that entry.

**Q: ROB-as-storage (this core) vs physical register file?**

ROB-as-storage copies values twice (FU → ROB → ARF at commit), and operands may come from the ROB, the ARF or the CDB, which means more read ports and muxes. A PRF writes once; commit only frees the previous mapping. The PRF scales better, which is why modern cores (and RISC-V BOOM) use it. ROB-as-storage is simpler to build and verify, which is why teaching cores use it.

**Q: When is it safe to clear a RAT entry at commit?**

Only if it still points to the committing entry. If a younger instruction already renamed the same register, the mapping belongs to the younger one and must stay. This core checks `RAT_tag == retiring rob` before clearing, which is correct.

**Q: How do you stall a 3-wide dispatch fairly?**

All-or-nothing on the bundle is simplest and keeps decode slots a prefix. Partial dispatch is faster but then the remaining slots must shift down (or decode must handle holes), and ROB indexing can no longer be `head + slot`.

**Q: Walk me through wakeup and select for a 3-wide CDB.**

Each RS operand has a comparator per CDB lane (12 ALU × 2 operands × 3 lanes = 72 tag comparators just for the ALU RS). On a match, the value is captured and the operand marked valid. Select is a priority arbiter over ready entries (oldest first, or position-based), one grant per functional unit. In high-frequency designs wakeup and select are in the same cycle for 1-cycle ops, often with speculative wakeup for loads (assume an L1 hit, replay on a miss).

**Q: Why might a real design not pick the oldest ready instruction?**

A true age matrix costs N² bits and a wide reduction. Many designs use position-based priority (lowest RS index) or a compacting queue, where position equals age. Oldest-first matters mostly for long-latency chains and for forward-progress guarantees, so a cheap approximation plus an anti-starvation timer is common.

**Q: Name three ways an instruction can be lost between RS and ROB, and the assertion for each.**

(1) Selected but the FU drops it: `ex_valid |-> ##[lat] result_ready`. (2) Two entries selected into one FU port: one-hot check on FU inputs, popcount(clear) = popcount(issue). (3) Wakeup missed because the broadcast came while the entry was being written: compare the tag against the CDB in the allocation cycle too (this design does). Plus a global liveness check that the ROB head retires within N cycles.

**Q: Why radix-4 Booth instead of a plain array multiplier?**

It halves the partial-product count, so the reduction tree is shallower (fewer CSA levels) and smaller, for a modest recoding cost. Radix-8 halves again but needs a hard 3M multiple precomputed with an adder, which is the classic area/delay trade-off.

**Q: How would you verify a 32-bit divider? You cannot simulate 2⁶⁴ cases.**

Corner cases from the spec (0, ±1, MIN/MAX, x/0, overflow), random with a reference model, structured patterns (powers of two, all-ones, divisor > dividend), and formal equivalence against a simple behavioural divider (`a == q*b + r` and `|r| < |b|`, with sign rules) using an SVA property on the output. Formal is the real answer for datapath at Nvidia/Google scale.

**Q: A pipelined unit returns results by tag. What can go wrong?**

Tag reuse (a tag freed and reallocated while an old op is still in the pipe), a flush that does not kill in-flight ops, two ops with the same tag (rename bug), and a result arriving after its ROB entry is gone. Assert that every returned tag is a live, not-yet-completed ROB entry (SVA A4).

**Q: How many CDB lanes would you choose, and how do you decide?**

Simulate: measure results per cycle on the target workloads. Most of the time it is at most the issue width. Each lane adds a tag comparator per operand per RS entry plus a write port into the ROB/PRF, so the cost grows with RS size × lanes. Choose the lane count where the queueing delay costs less IPC than the extra wakeup-loop delay and area.

**Q: What is credit-based flow control and where else does it show up in a GPU?**

The sender keeps a count of free slots at the receiver, decrements it on send, and the receiver returns a credit when it frees a slot, so the sender never overruns. In GPUs: NoC/crossbar links, memory request queues, the texture and L1 return paths, and NVLink. Verification checks credit conservation (credits + in-flight + occupied = depth) as an invariant.

**Q: Why can't stores write memory when they execute?**

Memory is architectural state. A store that executes and is later squashed (a mispredicted branch or an older exception) would have changed memory irreversibly. So stores wait in the store queue and write only after commit. Loads can still get the value early through store-to-load forwarding.

**Q: What would you put in a commit-stage scoreboard for a CPU?**

Per retired instruction: PC, instruction word, rd and value, CSR changes, memory address/data/size for stores, and exceptions/interrupts with their cause. Compare in order against an ISS (Spike, Sail, or an in-house model) in lock-step or from a trace. Handle legal divergence such as interrupts and timers by injecting them into the ISS at the same retire point.

**Q: A load and an older store to the same address are both in flight. Walk through every possible outcome.**

Store address unknown: the load waits (conservative) or speculates. Address known and it overlaps: if the store data is known and fully covers the load, forward with byte select and sign/zero extend. If the data is unknown, or it is a partial overlap, wait. If the store is senior or already written, the load can read memory once the write completes. Plus the case that older stores to the same address exist further back: the youngest one wins.

**Q: How do you verify memory ordering in an OOO core?**

End-to-end: an ISS comparison of load values and final memory, with constrained-random programs that use few addresses and mixed sizes to force aliasing (here 8 words). White-box: assertions on LSQ invariants (unique tags, SQ in program order, a store writes memory only when senior, forward-source selection), and functional coverage of the matrix {forward, partial-overlap wait, unknown-address wait, violation} × {byte, half, word}. Litmus tests if the design is multi-core.

**Q: Why does this core put stores in program order in the SQ even though it slows things down?**

It removes a deadlock (younger stores filling the SQ) and makes the SQ's position order equal to program order, which the in-order drain and the forwarding search depend on. A faster design allocates SQ entries at dispatch, in program order and early, so ordering comes for free and the LSB→SQ move disappears.


## 7. Common Mistakes (all found in this core)

| Mistake | Where it bit |
|---|---|
| Using an in-band value as a sentinel ("tag 0 = no tag", "way 3 = not found") | B04, B15 |
| Slicing bits by position without knowing the format (funct7 in I-type) | B01, B10 |
| Two copies of the same state updated on different cycles | B12 |
| Comparing circular-buffer tags with raw `<` | B07, B13 |
| "Accept then drop" paths: an RS entry freed with no result produced | B03, B05, B08 |
| A testbench/RTL hack that makes the test end (instruction-count cap) hiding real bugs | B09 |
| Blocking assignments to state read by another clocked block; one variable with two drivers | review findings in [27](27-ooo-core-bug-hunt.md) |

## 8. 60-Second Interview Pitch

3-wide RISC-V RV32IM out-of-order core. Tomasulo with a 48-entry ROB holding the data. 12/4/16 reservation stations for ALU, MUL/DIV and load/store. 3 ALUs, 2 pipelined MUL/DIV units (radix-4 Booth, radix-8 divider). A 3-lane CDB fed by a completion buffer. In-order 3-wide commit. A load/store unit with an 8-entry LQ and SQ, store-to-load forwarding and conservative disambiguation. On the verification side, I built a commit-trace scoreboard against a Python ISS, directed and constrained-random stimulus, and bind-based SVA. That found 15 functional bugs across decode, issue, execute, memory and frontend, including two deadlocks that only random stimulus exposed.

## 9. Self-Check

- [ ] Draw the core from memory with every size (IQ 16, ROB 48, RS 12/4/16, CDB 3, LQ/SQ 8/8).
- [ ] Explain why the ROB index can act as the physical register name.
- [ ] Explain age = (tag − commit pointer) mod 48 and why raw `<` is wrong.
- [ ] Walk one `mul` through every stage with cycle numbers (open the stepper in `tomasulo_core_lab.html`).
- [ ] Explain why stores write memory only after retirement, and what a senior store is.
- [ ] Explain the 2-cycle wakeup→issue loop and how to make it 1 cycle.
