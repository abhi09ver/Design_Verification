# Challenge 27: Bug Hunt: 15 Real Bugs in an Out-of-Order Core

> **Level:** Senior DV
> **Topics:** bug masking, deadlocks, lost wakeups, memory ordering, sentinel bugs, Booth corner case, frontend back-pressure, root-cause stories
> **Related:** [26 – The core](26-ooo-cpu-tomasulo-core.md), [28 – How they were found](28-cpu-verification-iss-random-sva-mutation.md), [25 – Debugging](25-debugging-intermittent-and-persistent-failures.md)
> **Code:** [`cpu-lab/`](cpu-lab/README.md) · **Interactive pages:** open the HTML files in [`cpu-lab/pages/`](cpu-lab/pages/) in a browser

---


## 1. The Source

The 3-wide Tomasulo core from [Challenge 26](26-ooo-cpu-tomasulo-core.md). Every bug below was reproduced in simulation (Verilator 5.048), fixed in [`cpu-lab/solutions/`](cpu-lab/solutions/) (each change tagged `FIX-n`), and re-verified. Diffs: [`cpu-lab/patches/`](cpu-lab/patches/).

## 2. Summary Table

| ID | Bug | Type | Where (original file:line) | Test that shows it |
|---|---|---|---|---|
| [B01](#b01) | Immediate bits leak into the opcode key | Deadlock | `tomasulo_pkg.sv:407, decoder.sv:137-145` | On the original RTL, 13 of the 20 directed tests trip SVA **A1** (valid instruction decoded as OTHER) before anything else, on the decode cycle. |
| [B02](#b02) | I-type immediates are zero-extended | Wrong data | `decoder.sv:150, 154, 156` | `b01_imm_sign_ext`: VALUE mismatch against the ISS. |
| [B03](#b03) | ALU silently drops OP-IMM instructions | Deadlock | `alu_unit.sv:25-43` | `b02_itype_alu` hangs |
| [B04](#b04) | ROB tag 0 can never be woken up | Deadlock | `alloc_reorder_retire.sv:933, 971, 1014, 1052` | `b03_rob_tag0`, `b12`, `b13`, `b10`: all hang |
| [B05](#b05) | Second DIV overwrites the first; unsigned M-ops never issue | Deadlock | `mul_div_top.sv:73-121` | `b04_two_divs`, `b09_unsupported_m_ops`, `b16_mul_variants`. |
| [B06](#b06) | Signed divide by zero returns +1 | Spec violation | `radix_8_dividor.sv:153-154` | `b10_div_by_zero` against the ISS (spec table: x/0 = -1, x%0 = x, -2^31/-1 = -2^31). |
| [B07](#b07) | Loads ignore older stores (no memory disambiguation) | Wrong data | `memory_management_unit.sv:371-419` | `b05`, `b06`, `b14`, and 1000s of random aliasing cases. |
| [B08](#b08) | Third load to one address is marked done but never broadcasts | Deadlock | `memory_management_unit.sv:277` | `b07_three_loads_same_addr`. |
| [B09](#b09) | Frontend ignores back-pressure and replays stale bundles | Wrong data | `fetch.sv:96, fetch_unit.sv:60, 104, 215, 257` | `b08_frontend_backpressure`: ORDER mismatch (the commit stream is not the program) |
| [B10](#b10) | lbu/lhu read as words and sign-extend | Wrong data | `alloc_reorder_retire.sv:808, memory_management_unit.sv:228` | `b14_byte_half`, `b15_unsigned_loads` |
| [B11](#b11) | MMU consumes the same LSB entry twice | Race / sim-only | `memory_management_unit.sv:129, 232, 259` | SVA **A7** (two LQ entries with the same ROB tag) fires on `t00_original`, the program that 'passed' |
| [B12](#b12) | Dispatch's private free-list disagrees with the real busy bits | Deadlock | `alloc_reorder_retire.sv:433-449, 663-671, 782, 798, 828` | Constrained-random (79 of 120 seeds failed before this fix) |
| [B13](#b13) | Store queue ordering: deadlock, orphaned and bypassed stores | Deadlock | `memory_management_unit.sv:216-267, 294-334, 21` | Constrained-random, then distilled into `b18_sq_order_deadlock` and `b19_senior_store`. |
| [B14](#b14) | Booth multiplier overflows on the most negative number | Wrong data | `radix_4_multiplier.sv:40, 72` | Random seed r13, then distilled into `b17_booth_min_neg`. |
| [B15](#b15) | BTB replacement evicts the most recent entry and never uses way 3 while it is free | Performance | `branch_predictor.sv:48-51, 124-133` | Unit test `unit/tb_btb_plru.sv` |

**Fix → bug map:** FIX-1 B01 · FIX-2 B02 · FIX-3 B03 · FIX-4 B04 · FIX-5 B05+B06 · FIX-6 B07 · FIX-7 B08 · FIX-8 B09 · FIX-9 B10 · FIX-10 B11 · FIX-11 B12 · FIX-12 B13 · FIX-13 B14 · FIX-14/15 B15

## 3. Each Bug: Symptom → Root Cause → Fix → Lesson

### B01

#### Immediate bits leak into the opcode key  
*Deadlock* · `tomasulo_pkg.sv:407, decoder.sv:137-145`

- **Symptom:** `addi x1, x0, 100` never retires. The ROB fills up behind it and the core hangs with 0 instructions committed. The original program passed only because every immediate in it was smaller than 32.
- **Hint (try before reading on):** Print `decode_reg.operation` for `addi x1,x0,100`. Which bits of the instruction ended up in the top 7 bits of the key?
- **Root cause:** The operation key is `{instr[31:25], funct3, opcode}`. Bits [31:25] are a real funct7 only for R-type instructions and the shift-immediates. For every other I-type, S-type and B-type instruction they are **immediate bits**. `addi` with imm=100 builds key `0x00c13`, matches nothing in `get_instr_type`, and is classified OTHER (type 11). OTHER instructions get no reservation station, so the ROB entry is never filled in.

Original:
```systemverilog
op = create_operation(fetch_instruction[i]);   // {instr[31:25], funct3, opcode}
decode_reg[i].instr_type <= get_instr_type(op);
```
Fix:
```systemverilog
op = create_operation(fetch_instruction[i]);
unique case (fetch_instruction[i][6:0])
  7'b0110011: ;                                          // R-type: keep funct7
  7'b0010011: if (fetch_instruction[i][13:12] != 2'b01)  // OP-IMM, not a shift
                op[16:10] = 7'b0;
  7'b1101111: op[16:7]  = 10'b0;                         // jal: no funct3 either
  default:    op[16:10] = 7'b0;                          // load/store/branch/jalr
endcase
```

- **Caught by:** On the original RTL, 13 of the 20 directed tests trip SVA **A1** (valid instruction decoded as OTHER) before anything else, on the decode cycle.
- **Lesson:** Know your ISA encoding cold. A field means something only for the formats that define it. One masking bug like this hid most of the others: 13 of 20 directed tests stopped within the first few instructions.

### B02

#### I-type immediates are zero-extended  
*Wrong data* · `decoder.sv:150, 154, 156`

- **Symptom:** `addi x1, x0, -1` writes `0x00000FFF`. `addi x3, x2, -40` writes `0x103C`.
- **Hint (try before reading on):** What happens when you assign a 12-bit slice to a 32-bit variable in SystemVerilog?
- **Root cause:** `temp_imm = fetch_instruction[i][31:20];` assigns a 12-bit unsigned slice to a 32-bit variable, so SystemVerilog zero-extends it. The S-type path does sign-extend, which is why stores with negative offsets looked fine.

Original:
```systemverilog
temp_imm = fetch_instruction[i][31:20];
```
Fix:
```systemverilog
temp_imm = {{20{fetch_instruction[i][31]}}, fetch_instruction[i][31:20]};
```

- **Caught by:** `b01_imm_sign_ext`: VALUE mismatch against the ISS.
- **Lesson:** Implicit width extension in SV is unsigned unless both sides are signed. Every immediate test needs a negative value.

### B03

#### ALU silently drops OP-IMM instructions  
*Deadlock* · `alu_unit.sv:25-43`

- **Symptom:** `andi / ori / xori / slli / srli / srai / slti / sltiu` are accepted by an ALU and then vanish. Their ROB entries never become ready.
- **Hint (try before reading on):** Look at what the ALU returns in the `default:` branch. Then look at what `alu_top` does with the RS entry in the same cycle.
- **Root cause:** The ALU case statement implements only the R-type ops plus `addi`. Anything else hits `default: result_ready = 0`. Meanwhile `alu_top` has already asserted `rs_clear` for that entry, so the instruction leaves the RS and never produces a result.

Original:
```systemverilog
default: begin
    alu_out.result = 32'hDEADBEEF;
    alu_out.result_ready = 1'b0;     // ...but the RS entry was already freed
end
```
Fix:
```systemverilog
andi:  alu_out.result = rs_in.src1_value & rs_in.immediate;
ori:   alu_out.result = rs_in.src1_value | rs_in.immediate;
xori:  alu_out.result = rs_in.src1_value ^ rs_in.immediate;
slti:  alu_out.result = ($signed(rs_in.src1_value) < $signed(rs_in.immediate));
sltiu: alu_out.result = (rs_in.src1_value < rs_in.immediate);
slli:  alu_out.result = rs_in.src1_value << rs_in.immediate[4:0];
srli:  alu_out.result = rs_in.src1_value >> rs_in.immediate[4:0];
srai:  alu_out.result = $signed(rs_in.src1_value) >>> rs_in.immediate[4:0];
```

- **Caught by:** `b02_itype_alu` hangs. SVA **A6** (ALU accepted an op but produced no result) fires on the exact cycle.
- **Lesson:** Any 'accept then do nothing' path is a lost instruction. A unit that frees its input must guarantee an output; that is a one-line assertion.

### B04

#### ROB tag 0 can never be woken up  
*Deadlock* · `alloc_reorder_retire.sv:933, 971, 1014, 1052`

- **Symptom:** `mul x1,x2,x3` followed by `add x4,x1,x1` hangs forever. The `add` waits on ROB tag 0, which is the first instruction ever dispatched.
- **Hint (try before reading on):** Which value of `src1_tag` is excluded from wakeup? Is that value ever a real tag?
- **Root cause:** The wakeup condition is `busy && !src1_valid && src1_tag != 0`. The author used 0 to mean 'no tag', but ROB index 0 is a real entry, and it is reused every 48 instructions. The LSB wakeup lacks the check, which is why `sw x1,4(x0)` in the original program worked and hid the bug.

Original:
```systemverilog
if (AS_RS[as_idx].busy && !AS_RS[as_idx].src1_valid && AS_RS[as_idx].src1_tag != 0) begin
```
Fix:
```systemverilog
if (AS_RS[as_idx].busy && !AS_RS[as_idx].src1_valid) begin   // valid bit is the ONLY qualifier
```

- **Caught by:** `b03_rob_tag0`, `b12`, `b13`, `b10`: all hang. SVA **A5** (head has not retired for 64 cycles).
- **Lesson:** Never use an in-band value as a sentinel. The same bug family appears again in the BTB (B15). Interviewers love this one.

### B05

#### Second DIV overwrites the first; unsigned M-ops never issue  
*Deadlock* · `mul_div_top.sv:73-121`

- **Symptom:** Two independent `div`s ready in the same cycle: the younger one completes and the older one disappears. `divu / remu / mulhu` sit in the RS forever.
- **Hint (try before reading on):** Indent the loop body properly. Which statements are inside `if (!slot_idx[0])`?
- **Root cause:** The 'odd slot: divide' search loop sits **outside** the even-slot `if`, so it runs for every slot. It writes `muldiv_in_div[slot_idx/2]`, and slots 0 and 1 both map to unit 0. The second DIV overwrites the first, whose `rs_clear` has already fired. Separately, the selector only matches `mul, mulh, div, rem`, and `mulhsu` was not decoded at all.

Original:
```systemverilog
if (!slot_idx[0]) begin
    ... pick a MUL ...
end
// Odd slot - dispatch divide operation      <-- runs for EVERY slot
for (muldiv_rs = 0; ...) if (... operation == div || operation == rem ...)
...
muldiv_in_div[slot_idx/2] = muldiv_rs_in[muldiv_min_idx];   // slot 0 and 1 -> unit 0
```
Fix:
```systemverilog
for (slot_idx = 0; slot_idx < 2*no_MulDiv_units; slot_idx++) begin
  // even slot = MUL port of unit slot/2, odd slot = DIV port
  pick oldest ready, not-yet-picked entry with
     slot_idx[0] ? is_div_class(op) : is_mul_class(op)   // all 4 + all 4 ops
  ...
end
```

- **Caught by:** `b04_two_divs`, `b09_unsupported_m_ops`, `b16_mul_variants`.
- **Lesson:** Issue logic must be 1:1: every entry cleared from an RS must reach exactly one functional unit input. Assert 'popcount(rs_clear) == number of valid FU inputs'.

### B06

#### Signed divide by zero returns +1  
*Spec violation* · `radix_8_dividor.sv:153-154`

- **Symptom:** `div x4, x2, x0` with x2 = -7 returns 1. RISC-V requires -1 (all ones) for any x/0, and x%0 = x.
- **Hint (try before reading on):** The magnitude algorithm already gives all-ones for /0. What does the sign-restore step do to it?
- **Root cause:** The divider divides magnitudes and then negates the quotient when the operand signs differ. For x/0 the magnitude quotient is all-ones, which is correct, but a negative dividend makes it negate that to +1. There was also no unsigned path, so divu/remu could not be supported.

Original:
```systemverilog
assign quotient = valid ? (sign_quotient ? -quotient : quotient) : '0;
```
Fix:
```systemverilog
// carried down the pipeline: div_by_zero, orig_dividend, is_signed
assign quotient  = !valid ? '0 : div_by_zero ? '1            : (sign_q ? -q : q);
assign remainder = !valid ? '0 : div_by_zero ? orig_dividend : (sign_r ? -r : r);
```

- **Caught by:** `b10_div_by_zero` against the ISS (spec table: x/0 = -1, x%0 = x, -2^31/-1 = -2^31).
- **Lesson:** Datapath corner cases come from the spec table, not from random values. Always test 0, -1, MIN_INT and MAX_INT on every operand.

### B07

#### Loads ignore older stores (no memory disambiguation)  
*Wrong data* · `memory_management_unit.sv:371-419`

- **Symptom:** `sw x1, 40(x0)` then `lw x2, 40(x0)` returns the old memory value (10) instead of 77. With slow store data (a MUL feeding the store) the load always wins the race.
- **Hint (try before reading on):** What does a load check before reading memory? List every place an older store can be at that moment.
- **Root cause:** Five separate mistakes in the load-issue loop. (a) It never checks stores still in the LSB, whose address or data is not ready yet. (b) It forwards only from `completed` stores, which are already in memory, so forwarding was pointless, and it ignores in-flight older stores. (c) Among matches it picks the lowest ROB tag, which is the **oldest** store, not the youngest. (d) It forwards the whole 32-bit data even for a byte load at a different offset. (e) It decides 'older' with a raw `<` on ROB tags, which is wrong once the ROB wraps.

Original:
```systemverilog
if (sq[j].valid && sq[j].rob_tag < lq[i].rob_tag) begin   // raw tag compare
  if (overlap)
    if (sq[j].completed)                                   // only stores ALREADY in memory
      if (youngest == -1 || sq[j].rob_tag < youngest_tag)  // picks the OLDEST
        forward sq[j].data                                 // whole word, no byte select
```
Fix:
```systemverilog
ld_age = rob_age(lq.rob_tag);                 // (tag - rob_head) mod 48
blocked = any older STORE still in the LSB;
best = youngest older overlapping SQ store not yet written to memory;
if (best found)
   if (best.addr == lq.addr && best.size >= lq.size) forward(extend(best.data))
   else blocked = 1;          // partial overlap: wait for it to drain
if (!blocked) issue (forward or read memory)
```

- **Caught by:** `b05`, `b06`, `b14`, and 1000s of random aliasing cases.
- **Lesson:** The memory RAW hazard is the one renaming cannot remove: addresses are only known at execute. You either wait (conservative, used here), or speculate and replay on a violation (real cores, with a store-set predictor).

### B08

#### Third load to one address is marked done but never broadcasts  
*Deadlock* · `memory_management_unit.sv:277`

- **Symptom:** Three `lw` from the same address, two load ports: the third never completes.
- **Hint (try before reading on):** When port 0 reads address A, which LQ entries get marked completed?
- **Root cause:** Completion was decided by matching `(addr, size)` against the port address, so **every** LQ entry with that address was marked completed. Only one result, with one ROB tag, goes on the CDB per port. The third load is 'completed' without ever broadcasting.

Original:
```systemverilog
if (lq[k].valid && !lq[k].completed && lq[k].addr == mem_read_addr[p] && lq[k].size == mem_read_size[p])
    lq_next[k].completed = 1;
```
Fix:
```systemverilog
if (mem_read_en[p] && issued_lq_idx[p] != -1)
    lq_next[issued_lq_idx[p]].completed = 1;   // the entry that was ACTUALLY issued
```

- **Caught by:** `b07_three_loads_same_addr`.
- **Lesson:** Track identity (an index or tag), never re-derive it from data. Data values are not unique.

### B09

#### Frontend ignores back-pressure and replays stale bundles  
*Wrong data* · `fetch.sv:96, fetch_unit.sv:60, 104, 215, 257`

- **Symptom:** With a long DIV chain stalling allocation, instructions 0x70–0x80 are never executed, and 0x64–0x6c are executed **twice**. The original test still finished because an instruction-count cap in the core stopped allocation after 33 instructions, duplicates included.
- **Hint (try before reading on):** Does the PC register know when the instruction queue refused a bundle? What does the fetch→decode latch hold when the IQ is empty?
- **Root cause:** Three cooperating problems. (1) `fetch_pc_mux_d` advances every cycle even while instruction memory is stalled on `iq_full`, so whole bundles are skipped. (2) The IQ accepts partial bundles (`enq_ready[j] = count+j < DEPTH`) while the PC moves by 3. (3) The fetch→decode latch only updates slots that have `deq_valid`, so a short bundle keeps stale valid instructions in the other slots. A fourth issue: at the end of the program the instruction memory freezes its last bundle as valid and re-enqueues it for 3 cycles.

Original:
```systemverilog
// fetch.sv: PC moves even when imem is stalled
end else if ((fetch_pc_mux_d < (NO_INSTR * 4)) && init) fetch_pc_mux_d <= fetch_pc_mux;
// fetch_unit.sv: latch keeps stale slots
if (deq_ready[i] && deq_valid[i]) fec_dec_latch[i] <= deq_data[i];
```
Fix:
```systemverilog
assign iq_room    = (iq.count + ISSUE_WIDTH) <= IQ_DEPTH;   // all-or-nothing
assign imem_stall = stall_in || !iq_room;
assign fetch_hold = imem_stall;                               // PC holds too
...
if (deq_ready[i]) fec_dec_latch[i] <= deq_valid[i] ? deq_data[i] : '0;   // bubbles
...
assign fetch_stall = stall_in;   // per-slot pc check makes bubbles past the end
```

- **Caught by:** `b08_frontend_backpressure`: ORDER mismatch (the commit stream is not the program). SVA **A2** watches the bundle shape.
- **Lesson:** Every valid/ready boundary needs the same rule: data moves only on `valid && ready`, and the producer holds otherwise. A hack in the testbench or RTL (the instr_ID cap) that 'makes the test end' is usually hiding a bug.

### B10

#### lbu/lhu read as words and sign-extend  
*Wrong data* · `alloc_reorder_retire.sv:808, memory_management_unit.sv:228`

- **Symptom:** `lbu x4, 65(x0)` returns `0xFFFFFFFF`. After fixing that, it returns `0xFFFFFF80` instead of `0x80`.
- **Hint (try before reading on):** funct3 for loads is {unsigned, size[1:0]}. Which bits does each line read?
- **Root cause:** Two bugs in two lines. The LSB size decode is `case (func3)` with `default: word`, so lbu (100) and lhu (101) become word loads, and a misaligned word read returns all-ones. Then the MMU computes `unsigned_load` from `op[2:0]`, but `op` is `{funct3, opcode}`, so those are opcode bits and the result is always 0.

Original:
```systemverilog
case (dispatch_reg[i].func3) 3'b000: byte; 3'b001: half; 3'b010: word; default: word;
unsigned_load = (op[2:0] == 3'b100 || op[2:0] == 3'b101);   // opcode bits!
```
Fix:
```systemverilog
case ({1'b0, dispatch_reg[i].func3[1:0]}) ...   // size = func3[1:0]
unsigned_load = op[9];                           // func3[2] of {func3, opcode}
```

- **Caught by:** `b14_byte_half`, `b15_unsigned_loads`. Found while debugging another test, which is typical.
- **Lesson:** Bit-slicing packed concatenations is where bugs hide. Name your fields with a struct instead of `op[9]`.

### B11

#### MMU consumes the same LSB entry twice  
*Race / sim-only* · `memory_management_unit.sv:129, 232, 259`

- **Symptom:** Even the original passing program enqueues load ROB 11 into the load queue **twice**. The duplicate happens to be harmless in that program, so the results are still correct, but SVA A7 fires.
- **Hint (try before reading on):** `lsb_entry_consumed` is assigned inside `always_ff`. When does the LSB's busy bit actually drop?
- **Root cause:** The MMU decides 'consume LSB[k]' inside its clocked block, so the pulse is visible after edge E and the LSB clears `busy` at edge E+1. During that cycle LSB[k] still looks busy and ready, so it is enqueued again.

Original:
```systemverilog
lsb_entry_consumed[k] = 1'b1;   // blocking assign inside always_ff -> seen one cycle late
```
Fix:
```systemverilog
lsb_consumed_prev = lsb_entry_consumed;           // what we took last cycle
...
if (lsb_consumed_prev[k]) ;                         // still clearing - skip
else if (lsb[k].busy && is_load && lsb[k].ready) enqueue...
```

- **Caught by:** SVA **A7** (two LQ entries with the same ROB tag) fires on `t00_original`, the program that 'passed'. The scoreboard cannot see it.
- **Lesson:** A passing test is not a clean test. Handshakes that cross a register boundary need explicit 'in flight' state.

### B12

#### Dispatch's private free-list disagrees with the real busy bits  
*Deadlock* · `alloc_reorder_retire.sv:433-449, 663-671, 782, 798, 828`

- **Symptom:** Random programs hang with a store stuck at `ready=0`. The store was dispatched to LSB[0] while LSB[0] still held another store, and the RS write was silently skipped.
- **Hint (try before reading on):** How many copies of 'is LSB[k] free?' exist, and are they updated by the same signal on the same cycle?
- **Root cause:** Dispatch keeps a shadow array (`*_busy_post_dispatch`) cleared by a one-cycle-**delayed** copy of the clear pulses. The RS's own `busy` bit is cleared by the undelayed pulse. Any pulse longer than one cycle (see B11) makes them disagree: dispatch hands out a busy slot, and the allocation guard `if (!busy)` skips the write without any error.

Original:
```systemverilog
if (lsb_entry_consumed_d1[k]) lsb_busy_post_dispatch[k] = 1'b0;   // shadow, 1 cycle late
...
if (!LS_buffer[dispatch_reg[d].rs_index].busy) begin ... end       // silent drop
```
Fix:
```systemverilog
always_comb begin   // ONE source of truth
  lsb_busy_view[k] = LS_buffer[k].busy;
  if (alloc_resources_available_d1)  // picked by the bundle about to be written
    foreach slot d in dispatch_reg: lsb_busy_view[dispatch_reg[d].rs_index] |= ...;
end
```

- **Caught by:** Constrained-random (79 of 120 seeds failed before this fix). SVA **A3** fires on the allocation cycle instead of 200 cycles later.
- **Lesson:** Two sources of truth will drift. A guard that silently skips work should be an assertion, not an `if`.

### B13

#### Store queue ordering: deadlock, orphaned and bypassed stores  
*Deadlock* · `memory_management_unit.sv:216-267, 294-334, 21`

- **Symptom:** (a) The oldest store waits on a DIV while 8 younger stores fill the SQ, and the core deadlocks. (b) A store that has retired but not drained looks *younger* than the loads after it, so they read stale memory.
- **Hint (try before reading on):** What order do stores enter the SQ in? After the ROB retires a store, what is its 'age'?
- **Root cause:** (a) Stores enter the SQ in LSB-index order, not program order. If younger stores fill the 8-entry SQ, the oldest store can never get in, never becomes ROB-ready, nothing retires, and nothing drains. (b) A store was marked 'go write memory' when its tag matched *any* of `rob_head[0..2]`, which is not proof that it retired, and it could be skipped by a safety check and orphaned forever. (c) After retirement, `(tag - rob_head) mod 48` wraps, so a senior store looks like the youngest instruction. (d) Coalescing squashed an older store that a load in between still needed.

Original:
```systemverilog
// enqueue: scans LSB[0..15] -> younger stores can enter first
// seniority: sq.rob_tag == rob_head[i] for ANY i, and only if 'safe'
```
Fix:
```systemverilog
// (a) a store may enter the SQ only if no OLDER store is still in the LSB
// (b) new ports: retire_valid / retire_rob_id from the ROB -> mark senior exactly then
// (c) senior store age = -1 (older than every in-flight load); SQ order = program order
// (d) ENABLE_COALESCING = 0
```

- **Caught by:** Constrained-random, then distilled into `b18_sq_order_deadlock` and `b19_senior_store`.
- **Lesson:** Resource deadlock: if a younger op can take the last slot an older op needs, you deadlock. Allocate in program order, or reserve a slot for the oldest.

### B14

#### Booth multiplier overflows on the most negative number  
*Wrong data* · `radix_4_multiplier.sv:40, 72`

- **Symptom:** `mulh` of (-2^31) × (-2^31) returns `0xC0000000`. The answer is `0x40000000`.
- **Hint (try before reading on):** Radix-4 Booth digit −2 needs −2M. How many bits does −2M need when M = −2^31?
- **Root cause:** Partial products are held in WIDTH+1 = 33 bits. −2M for M = −2^31 is +2^32, which needs 34 bits, so it wraps back to −2^32.

Original:
```systemverilog
logic signed [WIDTH:0] pp_values_temp [0:GROUPS-1];   // 33 bits
```
Fix:
```systemverilog
logic signed [WIDTH+1:0] pp_values_temp [0:GROUPS-1]; // 34 bits, sign-extend from [WIDTH+1]
```

- **Caught by:** Random seed r13, then distilled into `b17_booth_min_neg`.
- **Lesson:** Most-negative-number overflow (abs, negate, ×−2) is the classic datapath corner. The random generator found it because it seeds registers with extreme values.

### B15

#### BTB replacement evicts the most recent entry and never uses way 3 while it is free  
*Performance* · `branch_predictor.sv:48-51, 124-133`

- **Symptom:** Unit test: 4 new branches into a full 4-way set all replace way 0. Filling an empty set evicts a valid entry while way 3 is still free.
- **Hint (try before reading on):** Tree-PLRU bits must point *away* from the way just used. And what is 2'b11 used for in the free-way search?
- **Root cause:** `plru_update` never writes the root bit and points the pair bit **at** the way just used, so the 'victim' is the MRU entry. The free-way search uses `2'b11` as its 'not found' sentinel, but 3 is a real way.

Original:
```systemverilog
2'd0: plru_update = {old[2], old[1], 1'b0};   // root untouched, points AT way 0
free_way = 2'b11;  ...  if (free_way != 2'b11)   // 3 is a real way!
```
Fix:
```systemverilog
2'd0: plru_update = {1'b1, 1'b1, old[0]};     // victim -> right pair, way 1
...
free_found = 0; for (w...) if (!valid && !free_found) {free_way = w; free_found = 1;}
```

- **Caught by:** Unit test `unit/tb_btb_plru.sv`. Full-chip tests cannot see it, because the BTB is never trained.
- **Lesson:** Performance bugs never fail a functional test. Unit-level tests with a reference model (here: expected victim order) catch them.

## 4. Compile / Elaboration Errors Fixed First (FIX-0)

- `top_memory_subsystem.sv:20-29` — Parameter `ISSUE_WIDTH` overridden by design.sv but not declared (Verilator: PINNOTFOUND).
- `memory_management_unit.sv:239` — `logic rob_tag_exists = 0;` inside `always_ff`: a declaration initializer runs **once**, at time 0, which is an extra driver. This is the Xcelium MULAXX error in your log.
- `memory_management_unit.sv:129` — `always_ff @(posedge clk or negedge rst)` with an active-**high** reset: the block also runs on the falling edge of reset, outside any clock.
- `decoder.sv:145` — `get_instr_type` exists in both decoder_pkg (3 args) and tomasulo_pkg (1 arg). Xcelium and Verilator resolve the import differently, so call it with the package name.

## 5. Code-Review Findings Left Open (good exercises)

| Type | Finding | Where | Detail |
|---|---|---|---|
| Race / sim-only | ROB_next has two drivers | `alloc_reorder_retire.sv:772-778` | The RS-allocation `always @(posedge clk)` writes `ROB_next[...]`, which an `always_comb` also drives. The ROB allocation works only because of simulator event ordering. Synthesis would build something else. Fix: put the allocation into the always_comb that builds ROB_next. |
| Race / sim-only | Blocking state shared between clocked blocks | `alloc_reorder_retire.sv:395-678` | `temp_RAT_*` and the busy arrays are assigned with `=` in one clocked block and read by another clocked block at the same edge, so the result depends on scheduling order. Rule: state is written with `<=` in exactly one always_ff. |
| Race / sim-only | Retire-during-allocation writes three structures | `alloc_reorder_retire.sv:849-907` | For one dispatch slot it writes `AS_RS[idx]`, `MD_RS[idx]` and `LS_buffer[idx]` with the same index, whatever the instruction type. It looks unreachable (retired values are already in the ARF by then), so a code-coverage report would flag it as dead code. |
| Performance | 2-cycle wakeup→issue loop | `alloc_reorder_retire.sv:1186-1196` | `ready` is recomputed from the **registered** `src_valid` one cycle after wakeup, so dependent single-cycle ALU ops issue every 2 cycles (measured: b12 chain, ROB 1→2→3→4 at cycles 9, 11, 13, 15). See exercise E4. |
| Performance | Age by raw ROB index | `alu_top.sv:52, mul_div_top.sv` | Select picks the lowest ROB index as 'oldest'. After the ROB wraps that is not the oldest, which hurts fairness but not correctness here. |
| Spec violation | Misaligned access silently ignored | `data_mem.sv` | The original program contains `sw x25, 20(x19)` to address 0x19. RISC-V requires an address-misaligned exception (or hardware support). The core drops the store with no trap. |
| Spec violation | No branches at all | `alloc_reorder_retire.sv:598-638` | Type 11 (branch/jump) gets a ROB slot but no RS, so the ROB head waits forever. This is the capstone project. |
| Performance | Branch predictor integration | `fetch.sv, branch_predictor.sv` | Predictions come from the bundle fetched last cycle (one-cycle-late redirect). A not-taken prediction returns the current bundle's PC (refetch). Slots after a taken branch are not squashed. gshare updates with the current history instead of a checkpoint. |
| Spec violation | Decoder error check never matches | `decoder_pkg.sv:157` | `case({func7, func3})` (10 bits) is compared against 17-bit OP_* constants, so every R-type instruction is flagged as an error. The output is unused, which is why nobody noticed. |
| Race / sim-only | Asynchronous flush | `fetch_unit.sv, decoder.sv, completion_buffer.sv` | `posedge flush` appears in the sensitivity lists. Flush comes from logic, so treating it as an async reset invites glitches and reset-domain-crossing (RDC) problems. Keep flush synchronous. |


## 6. Likely Interviewer Follow-ups

**Q: Tell me about the hardest bug you found.**

The store-queue deadlock and bypass (B13). Random programs hung with a store stuck at not-ready. The trace showed the SQ full of *younger* stores while the oldest store waited in the LSB: a resource deadlock. While fixing it, a second problem appeared: after a store retired, its ROB tag no longer had a valid age, so it looked younger than later loads, which then read stale memory. Fix: stores enter the SQ in program order, the ROB tells the MMU exactly what retires, and senior stores count as older than every load. Lesson: shared resources must be allocated in age order or reserve room for the oldest.

**Q: What is bug masking?**

One bug stops execution before others can show. The decode op-key bug (B01) made 13 of 20 directed tests fail at the first instructions. Each fix exposed the next layer. Fix in small steps, keep tests narrow, and use assertions that report problems even when the end result is masked.

**Q: Your test passes. Why might you still not trust it?**

The original program passed 33/33, yet SVA A7 fires on it (duplicate load-queue entry, B11). Its checker was hand-written (one expected value relied on a wrong comment: instruction 16 is `xor`, not `add`), it had no liveness check, and an instruction-count cap ended the run. Ask: what is the oracle, what does it compare, and what can fail without it noticing?

## 7. Common Mistakes When Telling Bug Stories

- Describing the fix before the symptom and the reasoning. Use **symptom → hypothesis → experiment → root cause → fix → what I added so it can't come back**.
- Claiming numbers you did not measure. Every number in this file came from a simulation run.
- Forgetting the "regression" part: say which test and which assertion now guard the bug.

## 8. 60-Second Pitch

"I took a 3-wide RISC-V out-of-order core whose own test passed, put a golden ISS scoreboard, constrained-random stimulus and bound SVA around it, and found 15 functional bugs: decode op-key aliasing, a tag-0 sentinel that blocked wakeup, a divider and a Booth multiplier corner case, frontend back-pressure that skipped and duplicated instructions, and a family of load/store-queue ordering bugs including a resource deadlock. Directed tests found the first 11; random found the last 4. After fixing them the core passes 720 of 720 random programs with zero assertion firings."

## 9. Self-Check

- [ ] For each bug, say the symptom, root cause and fix in one breath each.
- [ ] Which 4 bugs were found only by random stimulus? (B11, B12, B13, B14)
- [ ] Which two bugs are the same family? (B04 and B15: in-band sentinels)
- [ ] Which bug did an assertion catch on a *passing* test? (B11, SVA A7 on `t00_original`)
