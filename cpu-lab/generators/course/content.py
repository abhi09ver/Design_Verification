# -*- coding: utf-8 -*-
# Course content for the Tomasulo Core Lab page. Rendered by build_course.py.
# Line references point at the ORIGINAL files from result_3.zip.

STATS = [
    ("0 → 720", "of 720 random programs pass", "original → fixed core"),
    ("15", "functional bugs proven in sim", "+ 4 compile/elab errors"),
    ("20", "directed tests", "19 pass, 1 capstone left for you"),
    ("7", "SVA properties", "fire on the cycle a bug happens"),
]

# ----------------------------------------------------------------------------------
# Bugs. sev: deadlock | data | race | spec | perf
# ----------------------------------------------------------------------------------
BUGS = {
 "B01": dict(title="Immediate bits leak into the opcode key", sev="deadlock", mod="decode",
   loc="tomasulo_pkg.sv:407, decoder.sv:137-145",
   symptom="<code>addi x1, x0, 100</code> never retires. The ROB fills up behind it and the core hangs with 0 instructions committed. The original program passed only because every immediate in it was smaller than 32.",
   hint="Print <code>decode_reg.operation</code> for <code>addi x1,x0,100</code>. Which bits of the instruction ended up in the top 7 bits of the key?",
   cause="The operation key is <code>{instr[31:25], funct3, opcode}</code>. Bits [31:25] are a real funct7 only for R-type instructions and the shift-immediates. For every other I-type, S-type and B-type instruction they are <b>immediate bits</b>. <code>addi</code> with imm=100 builds key <code>0x00c13</code>, matches nothing in <code>get_instr_type</code>, and is classified OTHER (type 11). OTHER instructions get no reservation station, so the ROB entry is never filled in.",
   orig="""op = create_operation(fetch_instruction[i]);   // {instr[31:25], funct3, opcode}
decode_reg[i].instr_type <= get_instr_type(op);""",
   fix="""op = create_operation(fetch_instruction[i]);
unique case (fetch_instruction[i][6:0])
  7'b0110011: ;                                          // R-type: keep funct7
  7'b0010011: if (fetch_instruction[i][13:12] != 2'b01)  // OP-IMM, not a shift
                op[16:10] = 7'b0;
  7'b1101111: op[16:7]  = 10'b0;                         // jal: no funct3 either
  default:    op[16:10] = 7'b0;                          // load/store/branch/jalr
endcase""",
   caught="On the original RTL, 13 of the 20 directed tests trip SVA <b>A1</b> (valid instruction decoded as OTHER) before anything else, on the decode cycle.",
   lesson="Know your ISA encoding cold. A field means something only for the formats that define it. One masking bug like this hid most of the others: 13 of 20 directed tests stopped within the first few instructions."),
 "B02": dict(title="I-type immediates are zero-extended", sev="data", mod="decode",
   loc="decoder.sv:150, 154, 156",
   symptom="<code>addi x1, x0, -1</code> writes <code>0x00000FFF</code>. <code>addi x3, x2, -40</code> writes <code>0x103C</code>.",
   hint="What happens when you assign a 12-bit slice to a 32-bit variable in SystemVerilog?",
   cause="<code>temp_imm = fetch_instruction[i][31:20];</code> assigns a 12-bit unsigned slice to a 32-bit variable, so SystemVerilog zero-extends it. The S-type path does sign-extend, which is why stores with negative offsets looked fine.",
   orig="temp_imm = fetch_instruction[i][31:20];",
   fix="temp_imm = {{20{fetch_instruction[i][31]}}, fetch_instruction[i][31:20]};",
   caught="<code>b01_imm_sign_ext</code>: VALUE mismatch against the ISS.",
   lesson="Implicit width extension in SV is unsigned unless both sides are signed. Every immediate test needs a negative value."),
 "B03": dict(title="ALU silently drops OP-IMM instructions", sev="deadlock", mod="execute",
   loc="alu_unit.sv:25-43",
   symptom="<code>andi / ori / xori / slli / srli / srai / slti / sltiu</code> are accepted by an ALU and then vanish. Their ROB entries never become ready.",
   hint="Look at what the ALU returns in the <code>default:</code> branch. Then look at what <code>alu_top</code> does with the RS entry in the same cycle.",
   cause="The ALU case statement implements only the R-type ops plus <code>addi</code>. Anything else hits <code>default: result_ready = 0</code>. Meanwhile <code>alu_top</code> has already asserted <code>rs_clear</code> for that entry, so the instruction leaves the RS and never produces a result.",
   orig="""default: begin
    alu_out.result = 32'hDEADBEEF;
    alu_out.result_ready = 1'b0;     // ...but the RS entry was already freed
end""",
   fix="""andi:  alu_out.result = rs_in.src1_value & rs_in.immediate;
ori:   alu_out.result = rs_in.src1_value | rs_in.immediate;
xori:  alu_out.result = rs_in.src1_value ^ rs_in.immediate;
slti:  alu_out.result = ($signed(rs_in.src1_value) < $signed(rs_in.immediate));
sltiu: alu_out.result = (rs_in.src1_value < rs_in.immediate);
slli:  alu_out.result = rs_in.src1_value << rs_in.immediate[4:0];
srli:  alu_out.result = rs_in.src1_value >> rs_in.immediate[4:0];
srai:  alu_out.result = $signed(rs_in.src1_value) >>> rs_in.immediate[4:0];""",
   caught="<code>b02_itype_alu</code> hangs. SVA <b>A6</b> (ALU accepted an op but produced no result) fires on the exact cycle.",
   lesson="Any 'accept then do nothing' path is a lost instruction. A unit that frees its input must guarantee an output; that is a one-line assertion."),
 "B04": dict(title="ROB tag 0 can never be woken up", sev="deadlock", mod="issue",
   loc="alloc_reorder_retire.sv:933, 971, 1014, 1052",
   symptom="<code>mul x1,x2,x3</code> followed by <code>add x4,x1,x1</code> hangs forever. The <code>add</code> waits on ROB tag 0, which is the first instruction ever dispatched.",
   hint="Which value of <code>src1_tag</code> is excluded from wakeup? Is that value ever a real tag?",
   cause="The wakeup condition is <code>busy && !src1_valid && src1_tag != 0</code>. The author used 0 to mean 'no tag', but ROB index 0 is a real entry, and it is reused every 48 instructions. The LSB wakeup lacks the check, which is why <code>sw x1,4(x0)</code> in the original program worked and hid the bug.",
   orig="if (AS_RS[as_idx].busy && !AS_RS[as_idx].src1_valid && AS_RS[as_idx].src1_tag != 0) begin",
   fix="if (AS_RS[as_idx].busy && !AS_RS[as_idx].src1_valid) begin   // valid bit is the ONLY qualifier",
   caught="<code>b03_rob_tag0</code>, <code>b12</code>, <code>b13</code>, <code>b10</code>: all hang. SVA <b>A5</b> (head has not retired for 64 cycles).",
   lesson="Never use an in-band value as a sentinel. The same bug family appears again in the BTB (B15). Interviewers love this one."),
 "B05": dict(title="Second DIV overwrites the first; unsigned M-ops never issue", sev="deadlock", mod="issue",
   loc="mul_div_top.sv:73-121",
   symptom="Two independent <code>div</code>s ready in the same cycle: the younger one completes and the older one disappears. <code>divu / remu / mulhu</code> sit in the RS forever.",
   hint="Indent the loop body properly. Which statements are inside <code>if (!slot_idx[0])</code>?",
   cause="The 'odd slot: divide' search loop sits <b>outside</b> the even-slot <code>if</code>, so it runs for every slot. It writes <code>muldiv_in_div[slot_idx/2]</code>, and slots 0 and 1 both map to unit 0. The second DIV overwrites the first, whose <code>rs_clear</code> has already fired. Separately, the selector only matches <code>mul, mulh, div, rem</code>, and <code>mulhsu</code> was not decoded at all.",
   orig="""if (!slot_idx[0]) begin
    ... pick a MUL ...
end
// Odd slot - dispatch divide operation      <-- runs for EVERY slot
for (muldiv_rs = 0; ...) if (... operation == div || operation == rem ...)
...
muldiv_in_div[slot_idx/2] = muldiv_rs_in[muldiv_min_idx];   // slot 0 and 1 -> unit 0""",
   fix="""for (slot_idx = 0; slot_idx < 2*no_MulDiv_units; slot_idx++) begin
  // even slot = MUL port of unit slot/2, odd slot = DIV port
  pick oldest ready, not-yet-picked entry with
     slot_idx[0] ? is_div_class(op) : is_mul_class(op)   // all 4 + all 4 ops
  ...
end""",
   caught="<code>b04_two_divs</code>, <code>b09_unsupported_m_ops</code>, <code>b16_mul_variants</code>.",
   lesson="Issue logic must be 1:1: every entry cleared from an RS must reach exactly one functional unit input. Assert 'popcount(rs_clear) == number of valid FU inputs'."),
 "B06": dict(title="Signed divide by zero returns +1", sev="spec", mod="execute",
   loc="radix_8_dividor.sv:153-154",
   symptom="<code>div x4, x2, x0</code> with x2 = -7 returns 1. RISC-V requires -1 (all ones) for any x/0, and x%0 = x.",
   hint="The magnitude algorithm already gives all-ones for /0. What does the sign-restore step do to it?",
   cause="The divider divides magnitudes and then negates the quotient when the operand signs differ. For x/0 the magnitude quotient is all-ones, which is correct, but a negative dividend makes it negate that to +1. There was also no unsigned path, so divu/remu could not be supported.",
   orig="assign quotient = valid ? (sign_quotient ? -quotient : quotient) : '0;",
   fix="""// carried down the pipeline: div_by_zero, orig_dividend, is_signed
assign quotient  = !valid ? '0 : div_by_zero ? '1            : (sign_q ? -q : q);
assign remainder = !valid ? '0 : div_by_zero ? orig_dividend : (sign_r ? -r : r);""",
   caught="<code>b10_div_by_zero</code> against the ISS (spec table: x/0 = -1, x%0 = x, -2^31/-1 = -2^31).",
   lesson="Datapath corner cases come from the spec table, not from random values. Always test 0, -1, MIN_INT and MAX_INT on every operand."),
 "B07": dict(title="Loads ignore older stores (no memory disambiguation)", sev="data", mod="memory",
   loc="memory_management_unit.sv:371-419",
   symptom="<code>sw x1, 40(x0)</code> then <code>lw x2, 40(x0)</code> returns the old memory value (10) instead of 77. With slow store data (a MUL feeding the store) the load always wins the race.",
   hint="What does a load check before reading memory? List every place an older store can be at that moment.",
   cause="Five separate mistakes in the load-issue loop. (a) It never checks stores still in the LSB, whose address or data is not ready yet. (b) It forwards only from <code>completed</code> stores, which are already in memory, so forwarding was pointless, and it ignores in-flight older stores. (c) Among matches it picks the lowest ROB tag, which is the <b>oldest</b> store, not the youngest. (d) It forwards the whole 32-bit data even for a byte load at a different offset. (e) It decides 'older' with a raw <code>&lt;</code> on ROB tags, which is wrong once the ROB wraps.",
   orig="""if (sq[j].valid && sq[j].rob_tag < lq[i].rob_tag) begin   // raw tag compare
  if (overlap)
    if (sq[j].completed)                                   // only stores ALREADY in memory
      if (youngest == -1 || sq[j].rob_tag < youngest_tag)  // picks the OLDEST
        forward sq[j].data                                 // whole word, no byte select""",
   fix="""ld_age = rob_age(lq.rob_tag);                 // (tag - rob_head) mod 48
blocked = any older STORE still in the LSB;
best = youngest older overlapping SQ store not yet written to memory;
if (best found)
   if (best.addr == lq.addr && best.size >= lq.size) forward(extend(best.data))
   else blocked = 1;          // partial overlap: wait for it to drain
if (!blocked) issue (forward or read memory)""",
   caught="<code>b05</code>, <code>b06</code>, <code>b14</code>, and 1000s of random aliasing cases.",
   lesson="The memory RAW hazard is the one renaming cannot remove: addresses are only known at execute. You either wait (conservative, used here), or speculate and replay on a violation (real cores, with a store-set predictor)."),
 "B08": dict(title="Third load to one address is marked done but never broadcasts", sev="deadlock", mod="memory",
   loc="memory_management_unit.sv:277",
   symptom="Three <code>lw</code> from the same address, two load ports: the third never completes.",
   hint="When port 0 reads address A, which LQ entries get marked completed?",
   cause="Completion was decided by matching <code>(addr, size)</code> against the port address, so <b>every</b> LQ entry with that address was marked completed. Only one result, with one ROB tag, goes on the CDB per port. The third load is 'completed' without ever broadcasting.",
   orig="if (lq[k].valid && !lq[k].completed && lq[k].addr == mem_read_addr[p] && lq[k].size == mem_read_size[p])\n    lq_next[k].completed = 1;",
   fix="if (mem_read_en[p] && issued_lq_idx[p] != -1)\n    lq_next[issued_lq_idx[p]].completed = 1;   // the entry that was ACTUALLY issued",
   caught="<code>b07_three_loads_same_addr</code>.",
   lesson="Track identity (an index or tag), never re-derive it from data. Data values are not unique."),
 "B09": dict(title="Frontend ignores back-pressure and replays stale bundles", sev="data", mod="frontend",
   loc="fetch.sv:96, fetch_unit.sv:60, 104, 215, 257",
   symptom="With a long DIV chain stalling allocation, instructions 0x70–0x80 are never executed, and 0x64–0x6c are executed <b>twice</b>. The original test still finished because an instruction-count cap in the core stopped allocation after 33 instructions, duplicates included.",
   hint="Does the PC register know when the instruction queue refused a bundle? What does the fetch→decode latch hold when the IQ is empty?",
   cause="Three cooperating problems. (1) <code>fetch_pc_mux_d</code> advances every cycle even while instruction memory is stalled on <code>iq_full</code>, so whole bundles are skipped. (2) The IQ accepts partial bundles (<code>enq_ready[j] = count+j &lt; DEPTH</code>) while the PC moves by 3. (3) The fetch→decode latch only updates slots that have <code>deq_valid</code>, so a short bundle keeps stale valid instructions in the other slots. A fourth issue: at the end of the program the instruction memory freezes its last bundle as valid and re-enqueues it for 3 cycles.",
   orig="""// fetch.sv: PC moves even when imem is stalled
end else if ((fetch_pc_mux_d < (NO_INSTR * 4)) && init) fetch_pc_mux_d <= fetch_pc_mux;
// fetch_unit.sv: latch keeps stale slots
if (deq_ready[i] && deq_valid[i]) fec_dec_latch[i] <= deq_data[i];""",
   fix="""assign iq_room    = (iq.count + ISSUE_WIDTH) <= IQ_DEPTH;   // all-or-nothing
assign imem_stall = stall_in || !iq_room;
assign fetch_hold = imem_stall;                               // PC holds too
...
if (deq_ready[i]) fec_dec_latch[i] <= deq_valid[i] ? deq_data[i] : '0;   // bubbles
...
assign fetch_stall = stall_in;   // per-slot pc check makes bubbles past the end""",
   caught="<code>b08_frontend_backpressure</code>: ORDER mismatch (the commit stream is not the program). SVA <b>A2</b> watches the bundle shape.",
   lesson="Every valid/ready boundary needs the same rule: data moves only on <code>valid &amp;&amp; ready</code>, and the producer holds otherwise. A hack in the testbench or RTL (the instr_ID cap) that 'makes the test end' is usually hiding a bug."),
 "B10": dict(title="lbu/lhu read as words and sign-extend", sev="data", mod="memory",
   loc="alloc_reorder_retire.sv:808, memory_management_unit.sv:228",
   symptom="<code>lbu x4, 65(x0)</code> returns <code>0xFFFFFFFF</code>. After fixing that, it returns <code>0xFFFFFF80</code> instead of <code>0x80</code>.",
   hint="funct3 for loads is {unsigned, size[1:0]}. Which bits does each line read?",
   cause="Two bugs in two lines. The LSB size decode is <code>case (func3)</code> with <code>default: word</code>, so lbu (100) and lhu (101) become word loads, and a misaligned word read returns all-ones. Then the MMU computes <code>unsigned_load</code> from <code>op[2:0]</code>, but <code>op</code> is <code>{funct3, opcode}</code>, so those are opcode bits and the result is always 0.",
   orig="""case (dispatch_reg[i].func3) 3'b000: byte; 3'b001: half; 3'b010: word; default: word;
unsigned_load = (op[2:0] == 3'b100 || op[2:0] == 3'b101);   // opcode bits!""",
   fix="""case ({1'b0, dispatch_reg[i].func3[1:0]}) ...   // size = func3[1:0]
unsigned_load = op[9];                           // func3[2] of {func3, opcode}""",
   caught="<code>b14_byte_half</code>, <code>b15_unsigned_loads</code>. Found while debugging another test, which is typical.",
   lesson="Bit-slicing packed concatenations is where bugs hide. Name your fields with a struct instead of <code>op[9]</code>."),
 "B11": dict(title="MMU consumes the same LSB entry twice", sev="race", mod="memory",
   loc="memory_management_unit.sv:129, 232, 259",
   symptom="Even the original passing program enqueues load ROB 11 into the load queue <b>twice</b>. The duplicate happens to be harmless in that program, so the results are still correct, but SVA A7 fires.",
   hint="<code>lsb_entry_consumed</code> is assigned inside <code>always_ff</code>. When does the LSB's busy bit actually drop?",
   cause="The MMU decides 'consume LSB[k]' inside its clocked block, so the pulse is visible after edge E and the LSB clears <code>busy</code> at edge E+1. During that cycle LSB[k] still looks busy and ready, so it is enqueued again.",
   orig="lsb_entry_consumed[k] = 1'b1;   // blocking assign inside always_ff -> seen one cycle late",
   fix="""lsb_consumed_prev = lsb_entry_consumed;           // what we took last cycle
...
if (lsb_consumed_prev[k]) ;                         // still clearing - skip
else if (lsb[k].busy && is_load && lsb[k].ready) enqueue...""",
   caught="SVA <b>A7</b> (two LQ entries with the same ROB tag) fires on <code>t00_original</code>, the program that 'passed'. The scoreboard cannot see it.",
   lesson="A passing test is not a clean test. Handshakes that cross a register boundary need explicit 'in flight' state."),
 "B12": dict(title="Dispatch's private free-list disagrees with the real busy bits", sev="deadlock", mod="rename",
   loc="alloc_reorder_retire.sv:433-449, 663-671, 782, 798, 828",
   symptom="Random programs hang with a store stuck at <code>ready=0</code>. The store was dispatched to LSB[0] while LSB[0] still held another store, and the RS write was silently skipped.",
   hint="How many copies of 'is LSB[k] free?' exist, and are they updated by the same signal on the same cycle?",
   cause="Dispatch keeps a shadow array (<code>*_busy_post_dispatch</code>) cleared by a one-cycle-<b>delayed</b> copy of the clear pulses. The RS's own <code>busy</code> bit is cleared by the undelayed pulse. Any pulse longer than one cycle (see B11) makes them disagree: dispatch hands out a busy slot, and the allocation guard <code>if (!busy)</code> skips the write without any error.",
   orig="""if (lsb_entry_consumed_d1[k]) lsb_busy_post_dispatch[k] = 1'b0;   // shadow, 1 cycle late
...
if (!LS_buffer[dispatch_reg[d].rs_index].busy) begin ... end       // silent drop""",
   fix="""always_comb begin   // ONE source of truth
  lsb_busy_view[k] = LS_buffer[k].busy;
  if (alloc_resources_available_d1)  // picked by the bundle about to be written
    foreach slot d in dispatch_reg: lsb_busy_view[dispatch_reg[d].rs_index] |= ...;
end""",
   caught="Constrained-random (79 of 120 seeds failed before this fix). SVA <b>A3</b> fires on the allocation cycle instead of 200 cycles later.",
   lesson="Two sources of truth will drift. A guard that silently skips work should be an assertion, not an <code>if</code>."),
 "B13": dict(title="Store queue ordering: deadlock, orphaned and bypassed stores", sev="deadlock", mod="memory",
   loc="memory_management_unit.sv:216-267, 294-334, 21",
   symptom="(a) The oldest store waits on a DIV while 8 younger stores fill the SQ, and the core deadlocks. (b) A store that has retired but not drained looks <i>younger</i> than the loads after it, so they read stale memory.",
   hint="What order do stores enter the SQ in? After the ROB retires a store, what is its 'age'?",
   cause="(a) Stores enter the SQ in LSB-index order, not program order. If younger stores fill the 8-entry SQ, the oldest store can never get in, never becomes ROB-ready, nothing retires, and nothing drains. (b) A store was marked 'go write memory' when its tag matched <i>any</i> of <code>rob_head[0..2]</code>, which is not proof that it retired, and it could be skipped by a safety check and orphaned forever. (c) After retirement, <code>(tag - rob_head) mod 48</code> wraps, so a senior store looks like the youngest instruction. (d) Coalescing squashed an older store that a load in between still needed.",
   orig="""// enqueue: scans LSB[0..15] -> younger stores can enter first
// seniority: sq.rob_tag == rob_head[i] for ANY i, and only if 'safe'""",
   fix="""// (a) a store may enter the SQ only if no OLDER store is still in the LSB
// (b) new ports: retire_valid / retire_rob_id from the ROB -> mark senior exactly then
// (c) senior store age = -1 (older than every in-flight load); SQ order = program order
// (d) ENABLE_COALESCING = 0""",
   caught="Constrained-random, then distilled into <code>b18_sq_order_deadlock</code> and <code>b19_senior_store</code>.",
   lesson="Resource deadlock: if a younger op can take the last slot an older op needs, you deadlock. Allocate in program order, or reserve a slot for the oldest."),
 "B14": dict(title="Booth multiplier overflows on the most negative number", sev="data", mod="execute",
   loc="radix_4_multiplier.sv:40, 72",
   symptom="<code>mulh</code> of (-2^31) × (-2^31) returns <code>0xC0000000</code>. The answer is <code>0x40000000</code>.",
   hint="Radix-4 Booth digit −2 needs −2M. How many bits does −2M need when M = −2^31?",
   cause="Partial products are held in WIDTH+1 = 33 bits. −2M for M = −2^31 is +2^32, which needs 34 bits, so it wraps back to −2^32.",
   orig="logic signed [WIDTH:0] pp_values_temp [0:GROUPS-1];   // 33 bits",
   fix="logic signed [WIDTH+1:0] pp_values_temp [0:GROUPS-1]; // 34 bits, sign-extend from [WIDTH+1]",
   caught="Random seed r13, then distilled into <code>b17_booth_min_neg</code>.",
   lesson="Most-negative-number overflow (abs, negate, ×−2) is the classic datapath corner. The random generator found it because it seeds registers with extreme values."),
 "B15": dict(title="BTB replacement evicts the most recent entry and never uses way 3 while it is free", sev="perf", mod="frontend",
   loc="branch_predictor.sv:48-51, 124-133",
   symptom="Unit test: 4 new branches into a full 4-way set all replace way 0. Filling an empty set evicts a valid entry while way 3 is still free.",
   hint="Tree-PLRU bits must point <i>away</i> from the way just used. And what is 2'b11 used for in the free-way search?",
   cause="<code>plru_update</code> never writes the root bit and points the pair bit <b>at</b> the way just used, so the 'victim' is the MRU entry. The free-way search uses <code>2'b11</code> as its 'not found' sentinel, but 3 is a real way.",
   orig="""2'd0: plru_update = {old[2], old[1], 1'b0};   // root untouched, points AT way 0
free_way = 2'b11;  ...  if (free_way != 2'b11)   // 3 is a real way!""",
   fix="""2'd0: plru_update = {1'b1, 1'b1, old[0]};     // victim -> right pair, way 1
...
free_found = 0; for (w...) if (!valid && !free_found) {free_way = w; free_found = 1;}""",
   caught="Unit test <code>unit/tb_btb_plru.sv</code>. Full-chip tests cannot see it, because the BTB is never trained.",
   lesson="Performance bugs never fail a functional test. Unit-level tests with a reference model (here: expected victim order) catch them."),
}

COMPILE = [
  ("top_memory_subsystem.sv:20-29", "Parameter <code>ISSUE_WIDTH</code> overridden by design.sv but not declared (Verilator: PINNOTFOUND)."),
  ("memory_management_unit.sv:239", "<code>logic rob_tag_exists = 0;</code> inside <code>always_ff</code>: a declaration initializer runs <b>once</b>, at time 0, which is an extra driver. This is the Xcelium MULAXX error in your log."),
  ("memory_management_unit.sv:129", "<code>always_ff @(posedge clk or negedge rst)</code> with an active-<b>high</b> reset: the block also runs on the falling edge of reset, outside any clock."),
  ("decoder.sv:145", "<code>get_instr_type</code> exists in both decoder_pkg (3 args) and tomasulo_pkg (1 arg). Xcelium and Verilator resolve the import differently, so call it with the package name."),
]

NOTFIXED = [
  ("race", "ROB_next has two drivers", "alloc_reorder_retire.sv:772-778", "The RS-allocation <code>always @(posedge clk)</code> writes <code>ROB_next[...]</code>, which an <code>always_comb</code> also drives. The ROB allocation works only because of simulator event ordering. Synthesis would build something else. Fix: put the allocation into the always_comb that builds ROB_next."),
  ("race", "Blocking state shared between clocked blocks", "alloc_reorder_retire.sv:395-678", "<code>temp_RAT_*</code> and the busy arrays are assigned with <code>=</code> in one clocked block and read by another clocked block at the same edge, so the result depends on scheduling order. Rule: state is written with <code>&lt;=</code> in exactly one always_ff."),
  ("race", "Retire-during-allocation writes three structures", "alloc_reorder_retire.sv:849-907", "For one dispatch slot it writes <code>AS_RS[idx]</code>, <code>MD_RS[idx]</code> and <code>LS_buffer[idx]</code> with the same index, whatever the instruction type. It looks unreachable (retired values are already in the ARF by then), so a code-coverage report would flag it as dead code."),
  ("perf", "2-cycle wakeup→issue loop", "alloc_reorder_retire.sv:1186-1196", "<code>ready</code> is recomputed from the <b>registered</b> <code>src_valid</code> one cycle after wakeup, so dependent single-cycle ALU ops issue every 2 cycles (measured: b12 chain, ROB 1→2→3→4 at cycles 9, 11, 13, 15). See exercise E4."),
  ("perf", "Age by raw ROB index", "alu_top.sv:52, mul_div_top.sv", "Select picks the lowest ROB index as 'oldest'. After the ROB wraps that is not the oldest, which hurts fairness but not correctness here."),
  ("spec", "Misaligned access silently ignored", "data_mem.sv", "The original program contains <code>sw x25, 20(x19)</code> to address 0x19. RISC-V requires an address-misaligned exception (or hardware support). The core drops the store with no trap."),
  ("spec", "No branches at all", "alloc_reorder_retire.sv:598-638", "Type 11 (branch/jump) gets a ROB slot but no RS, so the ROB head waits forever. This is the capstone project."),
  ("perf", "Branch predictor integration", "fetch.sv, branch_predictor.sv", "Predictions come from the bundle fetched last cycle (one-cycle-late redirect). A not-taken prediction returns the current bundle's PC (refetch). Slots after a taken branch are not squashed. gshare updates with the current history instead of a checkpoint."),
  ("spec", "Decoder error check never matches", "decoder_pkg.sv:157", "<code>case({func7, func3})</code> (10 bits) is compared against 17-bit OP_* constants, so every R-type instruction is flagged as an error. The output is unused, which is why nobody noticed."),
  ("race", "Asynchronous flush", "fetch_unit.sv, decoder.sv, completion_buffer.sv", "<code>posedge flush</code> appears in the sensitivity lists. Flush comes from logic, so treating it as an async reset invites glitches and reset-domain-crossing (RDC) problems. Keep flush synchronous."),
]

# ----------------------------------------------------------------------------------
# Modules
# ----------------------------------------------------------------------------------
MODULES = [
 dict(id="frontend", n="1", name="Frontend", files="fetch.sv · fetch_unit.sv · branch_predictor.sv",
  what="""<p>Every cycle the frontend reads <b>3 consecutive instructions</b> (12 bytes) from a byte-addressed instruction memory into a fetch register. That register feeds a <b>16-entry instruction queue</b> (IQ), and the IQ feeds a fetch→decode latch. A predecoder classifies each slot as call, return or branch for the branch predictor: a 64-set × 4-way BTB with tree-PLRU, a 1K-entry gshare, a 16-deep return address stack, and a branch-prediction queue.</p>
<p>The PC register (<code>fetch_pc_mux_d</code>) normally advances by 12. The IQ decouples fetch from decode: fetch can run ahead while decode is stalled, until the queue fills.</p>""",
  diagram="fetch",
  concepts=[
   ("Valid/ready is a contract", "Data crosses a boundary only on <code>valid &amp;&amp; ready</code>. The producer must <b>hold</b> both the data and its own state (here: the PC) when <code>ready</code> is low. Bug B09 breaks this contract in three places."),
   ("All-or-nothing bundles", "If a 3-wide bundle can be partly accepted, the PC must move by the accepted amount. Accepting all or nothing (<code>count + 3 &lt;= depth</code>) is simpler and keeps one invariant: decode slots are a contiguous prefix, which ROB indexing depends on (<code>rob = ROB_head + slot</code>)."),
   ("Prediction timing", "This predictor looks at the bundle <i>already fetched</i>, so a taken branch redirects one cycle late and the next sequential bundle is wrong-path. Real cores either predict from the PC (next-line/BTB lookup in the same cycle as the I-cache) or squash the wrong-path bundle."),
   ("Why gshare needs checkpoints", "The global history register must be updated <b>speculatively</b> at prediction and restored on a mispredict. Updating it at resolution, as here, indexes the table with a different history than prediction used."),
  ],
  code=[("fetch.sv:85-102", "PC update: advances whenever <code>init</code> and inside the program. No back-pressure input."),
        ("fetch_unit.sv:52-65", "Fetch→decode latch: slots without new data keep their old content."),
        ("fetch_unit.sv:214-215", "IQ <code>enq_ready[j] = count + j &lt; DEPTH</code>: partial bundles possible."),
        ("branch_predictor.sv:45-67", "Tree-PLRU update and victim functions.")],
  bugs=["B09", "B15"],
  build=[
   "Draw the timing of PC → fetch_reg → IQ → latch → decode_reg for a 4-cycle allocation stall. Mark every cycle where a bundle exists in two places.",
   "Write the SVA: <code>$fell(imem_stall) |-> ...</code> no bundle is lost or duplicated. Hint: keep a counter of PCs fetched vs. PCs enqueued.",
   "Run <code>make test T=tests/b08_frontend_backpressure.s RTL=rtl</code>, then fix fetch.sv/fetch_unit.sv yourself. Compare with <code>solutions/</code>.",
   "Extend <code>unit/tb_btb_plru.sv</code> into a reference-model check: a Python or SV model of tree-PLRU predicts each victim.",
  ],
  qa=[
   ("Why does an OOO core need an instruction queue between fetch and decode?", "It decouples two pipelines with different stall sources. Fetch stalls on I-cache misses and redirects; decode/rename stalls on back-end resources (ROB, RS, LSQ full). The queue absorbs bursts so neither side waits for the other cycle by cycle, and it is the natural point to apply back-pressure."),
   ("A fetch register is stalled but the PC keeps moving. How would you detect that in verification?", "Compare the committed PC stream with the ISS. Any skipped instruction is an ORDER mismatch at the first commit after the gap. White-box: an assertion that the PC register is stable whenever the fetch register is held (<code>imem_stall |=> $stable(pc)</code>), plus a scoreboard of fetched vs. enqueued PCs."),
   ("Tree-PLRU vs true LRU for a 4-way BTB?", "True LRU for 4 ways needs 5 bits per set (one of 24 orderings) and an update that touches all of them. Tree-PLRU needs 3 bits, and an access only flips the bits on its path. It approximates LRU: it never evicts the MRU way, but it does not always pick the true LRU way."),
   ("How do you verify a branch predictor if a misprediction is never a functional failure?", "With performance checks and unit tests: a reference model of the predictor fed the same branch stream must predict the same direction and target; then assert prediction accuracy on known patterns (always-taken loop, alternating, correlated). Full-chip: check that every mispredict is recovered (commit stream correct) and track MPKI as a regression metric."),
  ]),
 dict(id="decode", n="2", name="Decode", files="decoder.sv · decoder_pkg.sv · tomasulo_pkg.sv",
  what="""<p>Three parallel decoders turn each instruction word into a <code>decode_entry_t</code>: register fields, the immediate, a 17-bit <b>operation key</b> <code>{funct7, funct3, opcode}</code>, and a 2-bit type that picks the reservation station: 00 ALU, 01 memory, 10 MUL/DIV, 11 other (branch/jump). <code>dst</code> is forced to 0 for stores and branches so they never claim a register.</p>""",
  diagram="formats",
  concepts=[
   ("Format decides what bits mean", "RISC-V has six formats (R, I, S, B, U, J). The same bit positions mean different things in each. [31:25] is funct7 only in R-type (and as imm[11:5] that happens to carry the srai flag in shifts). Everything downstream of the decoder trusts the key, so a decode bug looks like a back-end bug."),
   ("The immediate is always sign-extended", "In RV32I, imm bit 31 is always the sign, in every format. That design choice lets hardware start sign-extension before it knows the format."),
   ("x0 is not a register", "Writes to x0 are discarded and reads give 0. Here that is done by never renaming x0 (dst = 0 means 'no destination') and reading 0 at dispatch. Any path that forgets it creates a fake dependency on 'x0'."),
  ],
  code=[("tomasulo_pkg.sv:404-409", "<code>create_operation</code>: the 17-bit key."),
        ("tomasulo_pkg.sv:352-365", "<code>get_instr_type</code>: unknown key → OTHER."),
        ("decoder.sv:122-171", "Key, type, dst and immediate decode."),
        ("decoder_pkg.sv:142-167", "<code>is_valid_instruction</code> (widths mismatch, never matches R-type).")],
  bugs=["B01", "B02"],
  build=[
   "Write a decoder unit test that loops over every RV32IM instruction with random fields, including imm ≥ 32 and negative, and checks <code>instr_type</code> and <code>immediate</code> against <code>tools/rv.py</code>.",
   "Add SVA A1 to your own copy, then break the decoder on purpose and watch it fire.",
   "Make illegal instructions raise <code>decoder_error</code> correctly (fix the 10-bit vs 17-bit compare) and block allocation.",
  ],
  qa=[
   ("Why sign-extend immediates in decode and not in the ALU?", "Decode is the only stage that knows the format. After decode, the immediate is just a 32-bit operand, so the ALU, the AGU and the branch unit all share one representation. It also takes the sign-extension mux out of the execute critical path."),
   ("Your directed test suite passes, but one decode field is wrong for 90% of encodings. How?", "The tests only used small immediates (here every immediate was below 32), so the aliased bits were always 0. Field-level coverage on the encoding (each bit of imm toggled, each format × each opcode) would show the hole at once. Constrained-random over the full encoding space finds it in seconds."),
   ("What decode-time information does rename need?", "Source and destination architectural registers, whether each source is used, whether dst is real (not x0, not store/branch), the functional-unit class, and the immediate. Getting 'source used' wrong creates false dependencies, which are slow but correct. Getting 'dst real' wrong corrupts state."),
  ]),
 dict(id="rename", n="3", name="Rename & Dispatch", files="alloc_reorder_retire.sv:342-678",
  what="""<p>Dispatch takes up to 3 decoded instructions per cycle. For each one it:</p>
<ol><li>Allocates a ROB entry: <code>rob = (ROB_head + slot) % 48</code>. In this code <b>ROB_head is the allocation pointer and ROB_tail the commit pointer</b>, the reverse of most textbooks.</li>
<li>Resolves each source in priority order: a producer earlier in the same bundle → the RAT (in flight, so take its ROB tag, then try to grab the value from the CDB or retire bus this cycle) → x0 → the ARF.</li>
<li>Picks a free RS slot of the right class.</li>
<li>Updates the RAT: <code>RAT[dst] = rob</code>.</li></ol>
<p>The bundle goes to all-or-nothing allocation: if any resource is short (ROB, ALU RS, MD RS, LSB), the whole bundle stalls (<code>alloc_stall</code>).</p>""",
  diagram="rob",
  concepts=[
   ("The ROB index is the physical register", "This is Tomasulo with a ROB, where data lives in the ROB. A ROB tag names the value, the RAT maps x3 → ROB5, and consumers wait on tag 5. This removes WAR and WAW hazards: in the stepper, x3 is written by the MUL (ROB 2) and the SUB (ROB 5), and the RAT simply points to the youngest. A PRF-based design (MIPS R10K, most modern cores) keeps values in a physical register file instead, so the ROB holds only pointers."),
   ("Intra-bundle dependencies", "Instruction 2 in a bundle may read what instruction 0 writes in the same cycle. The RAT cannot know yet, so dispatch compares each source against earlier slots' destinations (a priority mux, youngest earlier slot wins). Cost grows as O(width²), one reason rename width is hard to scale."),
   ("Age = distance from the commit pointer", "In a circular ROB, tag 3 can be younger than tag 40. True age is <code>(tag − commit_ptr) mod N</code>. Any raw <code>&lt;</code> on tags is a bug waiting for the wrap."),
   ("One source of truth", "Bug B12 had two copies of 'which RS slots are free', updated by signals one cycle apart. Derive availability from the real state plus what is in flight, and nothing else."),
  ],
  code=[("alloc_reorder_retire.sv:342-387", "Resource counting and <code>alloc_stall</code> (note the <code>instr_ID</code> cap applied after the stall)."),
        ("alloc_reorder_retire.sv:504-549", "Source resolution: bundle → RAT (+CDB/retire bypass) → x0 → ARF."),
        ("alloc_reorder_retire.sv:433-449", "The shadow free-list (bug B12)."),
        ("alloc_reorder_retire.sv:767-778", "ROB allocation written into <code>ROB_next</code> from a clocked block (race).")],
  bugs=["B12"],
  build=[
   "Draw the ROB at cycle 9 of the stepper: which entries are valid, which tags the RAT points to, and why x1/x2 no longer have mappings.",
   "Replace the shadow free-list yourself (single source of truth). Run 50 random seeds before and after: <code>python3 tools/gen_random.py N f.s; make test T=f.s</code>.",
   "Move the ROB allocation out of the clocked block into the <code>always_comb</code> that builds <code>ROB_next</code>, so it has a single driver. Re-run the regression.",
   "Remove the <code>instr_ID</code> cap. Which test now fails on the original frontend, and why does it pass on the fixed one?",
  ],
  qa=[
   ("Explain register renaming in one minute.", "Architectural registers are few, so independent instructions reuse the same names, creating false WAR/WAW dependencies. Rename maps each destination to a fresh physical name (here a ROB entry) and records the newest mapping in the RAT. Sources read the RAT to find their producer. Only true RAW dependencies remain, so independent work can run out of order. At commit, the value moves to the architectural state, and the mapping is cleared if it still points at that entry."),
   ("ROB-as-storage (this core) vs physical register file?", "ROB-as-storage copies values twice (FU → ROB → ARF at commit), and operands may come from the ROB, the ARF or the CDB, which means more read ports and muxes. A PRF writes once; commit only frees the previous mapping. The PRF scales better, which is why modern cores (and RISC-V BOOM) use it. ROB-as-storage is simpler to build and verify, which is why teaching cores use it."),
   ("When is it safe to clear a RAT entry at commit?", "Only if it still points to the committing entry. If a younger instruction already renamed the same register, the mapping belongs to the younger one and must stay. This core checks <code>RAT_tag == retiring rob</code> before clearing, which is correct."),
   ("How do you stall a 3-wide dispatch fairly?", "All-or-nothing on the bundle is simplest and keeps decode slots a prefix. Partial dispatch is faster but then the remaining slots must shift down (or decode must handle holes), and ROB indexing can no longer be <code>head + slot</code>."),
  ]),
 dict(id="issue", n="4", name="Issue: wakeup & select", files="alloc_reorder_retire.sv:913-1197 · alu_top.sv · mul_div_top.sv",
  what="""<p>Reservation stations: <b>12 ALU</b>, <b>4 MUL/DIV</b>, <b>16 load/store</b> (LSB). Each entry holds the operation, two operands, each with either a value or the ROB tag it waits for, and a <code>ready</code> bit.</p>
<p><b>Wakeup:</b> every cycle each waiting operand compares its tag with all 3 CDB lanes. It also checks a 1-cycle-delayed copy of the CDB and the retire bus, as belt-and-braces. <b>Select:</b> <code>alu_top</code> picks up to 3 ready entries (one per ALU), oldest-ROB-index first. <code>mul_div_top</code> picks one MUL and one DIV per unit. A selected entry is cleared from the RS that same cycle (<code>rs_clear</code>).</p>""",
  diagram="wakeup",
  concepts=[
   ("The wakeup–select loop sets your IPC", "For back-to-back dependent single-cycle ops, an instruction selected in cycle N must wake its consumer in time for the consumer to be selected in N+1. That is the critical loop of every OOO core. Here <code>ready</code> is re-registered from <code>src_valid</code>, which adds a cycle: dependent adds run at 1 per 2 cycles (see the chain in exercise E4)."),
   ("Capture vs. no-capture RS", "This design is <b>data-capture</b>: operand values are copied into the RS, from the ARF at dispatch or from the CDB at wakeup. The alternative is <b>non-capture</b>: the RS holds only tags and operands are read from the PRF after select. Capture needs wide RS entries and CDB-to-RS data wires. Non-capture needs PRF read ports after select."),
   ("Select must be 1:1", "Every entry cleared from an RS must arrive at exactly one functional-unit input in the same cycle. Bug B03 (ALU drops op) and bug B05 (DIV overwritten) both broke this, and both lost an instruction silently."),
   ("Sentinels", "Tag 0 used as 'no tag' (B04). The valid bit is the only correct qualifier."),
  ],
  code=[("alloc_reorder_retire.sv:929-1006", "ALU RS wakeup (4 sources, short-circuit)."),
        ("alloc_reorder_retire.sv:1186-1196", "<code>ready</code> recomputed from registered <code>src_valid</code>: the 2-cycle loop."),
        ("alu_top.sv:29-69", "Oldest-first select, up to 3 per cycle."),
        ("mul_div_top.sv:50-129", "MUL/DIV select (bug B05).")],
  bugs=["B04", "B05"],
  build=[
   "<b>E4 (performance):</b> make dependent ALU ops issue back to back. Compute ready as <code>(src_valid | cdb_match)</code> combinationally for select. Measure <code>b12_raw_chain</code> cycles before and after (39 now).",
   "Write the 1:1 select assertion: <code>$countones(rs_clear) == $countones(ex_valid)</code> for the ALU and MUL/DIV tops.",
   "Replace raw-index age in <code>alu_top</code> with true age <code>(rob − ROB_tail) mod 48</code>. Write a test that makes the ROB wrap (more than 48 instructions; raise NO_INSTR and the IMEM size).",
  ],
  qa=[
   ("Walk me through wakeup and select for a 3-wide CDB.", "Each RS operand has a comparator per CDB lane (12 ALU × 2 operands × 3 lanes = 72 tag comparators just for the ALU RS). On a match, the value is captured and the operand marked valid. Select is a priority arbiter over ready entries (oldest first, or position-based), one grant per functional unit. In high-frequency designs wakeup and select are in the same cycle for 1-cycle ops, often with speculative wakeup for loads (assume an L1 hit, replay on a miss)."),
   ("Why might a real design not pick the oldest ready instruction?", "A true age matrix costs N² bits and a wide reduction. Many designs use position-based priority (lowest RS index) or a compacting queue, where position equals age. Oldest-first matters mostly for long-latency chains and for forward-progress guarantees, so a cheap approximation plus an anti-starvation timer is common."),
   ("Name three ways an instruction can be lost between RS and ROB, and the assertion for each.", "(1) Selected but the FU drops it: <code>ex_valid |-> ##[lat] result_ready</code>. (2) Two entries selected into one FU port: one-hot check on FU inputs, popcount(clear) = popcount(issue). (3) Wakeup missed because the broadcast came while the entry was being written: compare the tag against the CDB in the allocation cycle too (this design does). Plus a global liveness check that the ROB head retires within N cycles."),
  ]),
 dict(id="execute", n="5", name="Execute", files="alu_unit.sv · mul_div.sv · radix_4_multiplier.sv · radix_8_dividor.sv",
  what="""<p><b>3 single-cycle ALUs.</b> <b>2 MUL/DIV units</b>, each with a 3-stage radix-4 Booth multiplier (Booth encode → CSA tree → carry-propagate add) and an 11-stage radix-8 divider that does 3 quotient bits per stage, fully pipelined with the ROB tag carried along. MUL/DIV entries leave the RS at issue. Results come back tagged, and the unit keeps a per-tag table of which operation (mul vs. mulh) to finish.</p>""",
  diagram=None,
  concepts=[
   ("Radix-4 Booth", "Booth recoding looks at 3 multiplier bits at a time (overlapping by one) and turns them into a digit in {−2, −1, 0, +1, +2}. That halves the partial products (16 instead of 32 for 32 bits). The −2 digit needs −2M, so partial products need 2 extra bits, not 1 (bug B14)."),
   ("Signed vs. unsigned high product", "One signed 32×32 multiplier can produce all four RISC-V multiplies: <code>mulhu = mulh + (a&lt;0 ? b : 0) + (b&lt;0 ? a : 0)</code> and <code>mulhsu = mulh + (b&lt;0 ? a : 0)</code>, all mod 2³². This is how the fix adds mulhu/mulhsu without a second multiplier."),
   ("RISC-V does not trap on divide by zero", "x/0 = all ones, x%0 = x. Overflow −2³¹/−1 = −2³¹ with remainder 0. These come straight from the spec table and are the first things to test."),
   ("Variable latency means out-of-order completion", "ALU 1 cycle, MUL 3, DIV 11+. Results arrive out of order and in bursts, which is why the completion buffer exists (module 6)."),
  ],
  code=[("alu_unit.sv:18-51", "ALU case: OP-IMM ops missing (bug B03)."),
        ("radix_4_multiplier.sv:38-80", "Booth encode and partial products (bug B14)."),
        ("radix_8_dividor.sv:58-155", "Radix-8 restoring divider, sign handling (bug B06)."),
        ("mul_div.sv:48-149", "Per-tag op table and result mux.")],
  bugs=["B03", "B06", "B14"],
  build=[
   "Write an exhaustive-corner unit test for the multiplier: all pairs from {0, 1, −1, 2³¹−1, −2³¹, random} × 4 ops vs. Python big-int.",
   "Make the divider early-out when the dividend is small. Then make the verification catch the bug you will almost certainly introduce: two results with different latencies reaching the output in the same cycle.",
   "Add the missing <code>stall</code> handling: today the MUL/DIV pipelines keep producing results while the completion buffer is almost full. Prove with an assertion that the buffer never drops a result.",
  ],
  qa=[
   ("Why radix-4 Booth instead of a plain array multiplier?", "It halves the partial-product count, so the reduction tree is shallower (fewer CSA levels) and smaller, for a modest recoding cost. Radix-8 halves again but needs a hard 3M multiple precomputed with an adder, which is the classic area/delay trade-off."),
   ("How would you verify a 32-bit divider? You cannot simulate 2⁶⁴ cases.", "Corner cases from the spec (0, ±1, MIN/MAX, x/0, overflow), random with a reference model, structured patterns (powers of two, all-ones, divisor > dividend), and formal equivalence against a simple behavioural divider (<code>a == q*b + r</code> and <code>|r| &lt; |b|</code>, with sign rules) using an SVA property on the output. Formal is the real answer for datapath at Nvidia/Google scale."),
   ("A pipelined unit returns results by tag. What can go wrong?", "Tag reuse (a tag freed and reallocated while an old op is still in the pipe), a flush that does not kill in-flight ops, two ops with the same tag (rename bug), and a result arriving after its ROB entry is gone. Assert that every returned tag is a live, not-yet-completed ROB entry (SVA A4)."),
  ]),
 dict(id="writeback", n="6", name="Writeback & CDB", files="completion_buffer.sv",
  what="""<p>Nine producers (3 ALU + 2×MUL + 2×DIV + 2 load ports) can finish in the same cycle, but the common data bus has only <b>3 lanes</b>. The completion buffer is a 48-entry FIFO. When it is empty and at most 3 results arrive, they bypass straight to the CDB. Otherwise they are queued and drained 3 per cycle. When the count reaches <code>48 − 9 − 5 = 34</code>, <code>almost_full</code> stalls the ALU and MUL/DIV select and the load issue.</p>""",
  diagram=None,
  concepts=[
   ("Why a buffer at all", "Without it you need either 9 CDB lanes (9 tag comparators per operand per RS entry) or arbitration that stalls functional units mid-pipeline. Pipelined MUL/DIV cannot stall cheaply. Buffering moves the cost to a FIFO."),
   ("Safety margin = credits", "<code>almost_full</code> must fire early enough to absorb everything already in flight that cannot be stopped: up to 9 results per cycle, plus the multi-cycle pipelines. The margin is credit-based flow control done by hand. A formal proof or an assertion that the FIFO never overflows is the real check, because the enqueue silently drops results when full (completion_buffer.sv:126)."),
   ("FIFO order is not age order", "Results are broadcast in arrival order, not program order. That is fine because the ROB restores order at commit."),
  ],
  code=[("completion_buffer.sv:89-141", "Dequeue then enqueue in one cycle; silent drop at full."),
        ("completion_buffer.sv:143-187", "Bypass vs. buffered output mux."),
        ("completion_buffer.sv:192-197", "<code>almost_full</code> threshold.")],
  bugs=[],
  build=[
   "Add an assertion: <code>func_results[i].result_ready |-> next_count &lt; BUFFER_DEPTH</code> (no silent drop). Then shrink <code>SAFETY_MARGIN</code> to 0 and write a test that overflows the buffer.",
   "Prioritise the CDB by age (oldest first) instead of FIFO order. Does IPC change on the random suite? (Measure; don't guess.)",
  ],
  qa=[
   ("How many CDB lanes would you choose, and how do you decide?", "Simulate: measure results per cycle on the target workloads. Most of the time it is at most the issue width. Each lane adds a tag comparator per operand per RS entry plus a write port into the ROB/PRF, so the cost grows with RS size × lanes. Choose the lane count where the queueing delay costs less IPC than the extra wakeup-loop delay and area."),
   ("What is credit-based flow control and where else does it show up in a GPU?", "The sender keeps a count of free slots at the receiver, decrements it on send, and the receiver returns a credit when it frees a slot, so the sender never overruns. In GPUs: NoC/crossbar links, memory request queues, the texture and L1 return paths, and NVLink. Verification checks credit conservation (credits + in-flight + occupied = depth) as an invariant."),
  ]),
 dict(id="commit", n="7", name="Commit", files="alloc_reorder_retire.sv:1219-1406",
  what="""<p>Up to 3 instructions retire per cycle, in order, from <code>ROB_tail</code> (the commit pointer). An entry retires if it is <code>valid &amp;&amp; ready</code>. The first entry that is not ready stops the group. On retire, the value is written to the ARF (unless dst = x0), the RAT mapping is cleared if it still points at this entry, and the retire info is broadcast as a late wakeup source. Stores become 'ready' when they enter the store queue, and they write memory only after they retire (module 8).</p>""",
  diagram=None,
  concepts=[
   ("Precise state", "Because commit is in order, the ARF always equals the state of a simple in-order machine at some instruction boundary. That makes precise exceptions and interrupts possible: flush everything younger than the faulting instruction, and the ARF is exactly right. This core has no exceptions yet. Implementing them uses the same mechanism as branch recovery (module 10)."),
   ("The commit stream is your verification contract", "Everything inside the core may reorder. The committed stream of (PC, rd, value) and the memory writes may not. That is why the lab's scoreboard compares exactly those against the ISS, commit by commit."),
   ("Retire width vs. dispatch width", "If retire is narrower than dispatch, the ROB fills on long-latency stalls and never catches up. Here both are 3."),
  ],
  code=[("alloc_reorder_retire.sv:1234-1286", "<code>always_comb</code>: CDB writeback into ROB_next, then retire up to 3."),
        ("alloc_reorder_retire.sv:1291-1363", "ROB/ARF update, perf counters, and the store-ready hook.")],
  bugs=[],
  build=[
   "Add an assertion that retire is in order: <code>commit_valid_next[i] |-> commit_valid_next[i-1]</code>, and that <code>commit_rob_id_next[i] == (ROB_tail + i) % 48</code>.",
   "Add a precise <b>illegal-instruction exception</b>: mark the ROB entry 'exception' at decode, and at commit flush everything and redirect fetch to a handler PC. Extend <code>tools/rv.py</code> to model it.",
  ],
  qa=[
   ("Why can't stores write memory when they execute?", "Memory is architectural state. A store that executes and is later squashed (a mispredicted branch or an older exception) would have changed memory irreversibly. So stores wait in the store queue and write only after commit. Loads can still get the value early through store-to-load forwarding."),
   ("What would you put in a commit-stage scoreboard for a CPU?", "Per retired instruction: PC, instruction word, rd and value, CSR changes, memory address/data/size for stores, and exceptions/interrupts with their cause. Compare in order against an ISS (Spike, Sail, or an in-house model) in lock-step or from a trace. Handle legal divergence such as interrupts and timers by injecting them into the ISS at the same retire point."),
  ]),
 dict(id="memory", n="8", name="Memory: LSB, LQ, SQ", files="memory_management_unit.sv · data_mem.sv · top_memory_subsystem.sv",
  what="""<p>Memory instructions wait in the 16-entry LSB until their base register (and, for stores, the data) is ready. The MMU then moves loads into an <b>8-entry load queue</b> and stores into an <b>8-entry store queue</b>. Loads issue on <b>2 read ports</b>, either forwarded from an older store or read from data memory (1024 words, initialised so word i = i). Stores mark their ROB entry ready on entering the SQ, become <b>senior</b> when they retire, and drain through <b>1 write port</b> in program order.</p>""",
  diagram="lsq",
  concepts=[
   ("The memory RAW hazard", "Registers are renamed at decode, but memory addresses are only known at execute, so a load may not know whether an older store writes its address. The options are: wait until all older store addresses are known (conservative, used by the fix), or speculate, issue anyway, check when the older store's address resolves, and replay on a violation. Real cores speculate, with a store-set or memory-dependence predictor to avoid repeat violations."),
   ("Forwarding rules", "Forward from the <b>youngest older</b> store that overlaps. Forward only if it fully covers the load's bytes, then byte-select and extend. On a partial overlap, wait until the store has drained to memory."),
   ("Senior stores", "Between 'retired' and 'written to memory' a store is architecturally done but still invisible in memory. Every load is younger than a senior store, and the ROB tag can no longer give its age (bug B13c)."),
   ("Resource deadlock", "If a younger instruction can take the last slot in a shared queue that an older one needs, and the younger one cannot leave before the older one, you have a deadlock (bug B13a). The fixes are in-order allocation or a reserved slot for the oldest."),
  ],
  code=[("memory_management_unit.sv:127-345", "Clocked block: LQ/SQ dequeue, enqueue from LSB, completion, seniority."),
        ("memory_management_unit.sv:347-446", "Load issue: forwarding search and memory read."),
        ("memory_management_unit.sv:228", "<code>unsigned_load</code> from the wrong bits (bug B10)."),
        ("data_mem.sv", "Byte/half/word read and write with alignment checks (misaligned access silently ignored).")],
  bugs=["B07", "B08", "B10", "B11", "B13"],
  build=[
   "Read <code>solutions/memory_management_unit.sv</code> and draw the decision tree for a load: LSB check → youngest older overlapping SQ store → forward / wait / read.",
   "Implement <b>speculative</b> load issue with violation detection: let loads bypass unknown-address stores, and when a store's address resolves, check younger completed loads; on a match, raise <code>violation_detected</code> (the port already exists in design.sv) and flush from the load. You need module 10's flush first.",
   "Write the LSQ checker as a TB component: keep a shadow memory updated only at store <b>retire</b>, and check every load value against 'shadow memory at the load's position in program order'.",
  ],
  qa=[
   ("A load and an older store to the same address are both in flight. Walk through every possible outcome.", "Store address unknown: the load waits (conservative) or speculates. Address known and it overlaps: if the store data is known and fully covers the load, forward with byte select and sign/zero extend. If the data is unknown, or it is a partial overlap, wait. If the store is senior or already written, the load can read memory once the write completes. Plus the case that older stores to the same address exist further back: the youngest one wins."),
   ("How do you verify memory ordering in an OOO core?", "End-to-end: an ISS comparison of load values and final memory, with constrained-random programs that use few addresses and mixed sizes to force aliasing (here 8 words). White-box: assertions on LSQ invariants (unique tags, SQ in program order, a store writes memory only when senior, forward-source selection), and functional coverage of the matrix {forward, partial-overlap wait, unknown-address wait, violation} × {byte, half, word}. Litmus tests if the design is multi-core."),
   ("Why does this core put stores in program order in the SQ even though it slows things down?", "It removes a deadlock (younger stores filling the SQ) and makes the SQ's position order equal to program order, which the in-order drain and the forwarding search depend on. A faster design allocates SQ entries at dispatch, in program order and early, so ordering comes for free and the LSB→SQ move disappears."),
  ]),
]

VERIFY = dict(
  intro="""<p>Your uploaded run used a hard-coded checker: 33 expected values keyed by ROB id. It passed. Then, with a proper flow on the same RTL, <b>19 of 20 directed tests and 720 of 720 random programs failed</b>. Here is the flow, the order it found things in, and why each layer exists.</p>""",
  layers=[
   ("Golden model (ISS)", "<code>tools/rv.py</code>: about 200 lines of Python that execute RV32IM in program order with spec semantics. It is the definition of 'correct'.", "Found the comment/hex mismatch in your program (instr 16 is <code>xor</code>, not <code>add</code>) and the misaligned store at 0x19."),
   ("Commit-trace scoreboard", "<code>tb/tb_lab.sv</code> prints every retirement (PC, rd, value). <code>tools/run_test.py</code> checks order, values, final ARF, memory and liveness.", "Finds lost, duplicated and reordered instructions (ORDER), wrong data (VALUE), and deadlocks (HANG with the stuck ROB entries)."),
   ("Directed bug hunts", "One 33-instruction program per hypothesis from code review: <code>tests/b01…b19</code>.", "Confirmed 11 bugs. They also show <b>bug masking</b>: until B01 was fixed, most tests died in the first bundle and hid everything else."),
   ("Constrained random", "<code>tools/gen_random.py</code>: 7 registers, 8 memory words, extreme seed values, all latencies mixed.", "After the directed fixes, 79 of 120 seeds still failed. It found B11, B12, B13 and B14, which nobody would write a directed test for."),
   ("Assertions (SVA, bind)", "<code>tb/core_sva.sv</code>: 7 properties attached with <code>bind</code>, no RTL edits.", "Fire on the cycle a bug happens. A7 fires on <b>your original passing program</b>: the load queue holds a duplicate entry."),
   ("Unit tests", "<code>unit/tb_btb_plru.sv</code>: the BTB in isolation with an expected victim order.", "Found B15, which is invisible to every full-chip test because the BTB is never trained."),
  ],
  stages=[("Original RTL", 0), ("Fixed B01–B10", 41), ("+ B11, B12", 105), ("+ B13, B14", 120)],
)

CAPSTONE = dict(
  intro="""<p>The backend has no branch unit. A branch gets type 11: it receives a ROB slot but no reservation station, so the ROB head waits forever (<code>b11_branch</code> hangs). Building branch support is the best single project for an OOO interview: it touches every module and forces you to design recovery.</p>""",
  steps=[
   ("Branch unit", "Add type 11 to dispatch. Give branches ALU RS entries (or a separate BR RS). Compute taken and target in a branch unit: <code>beq bne blt bge bltu bgeu</code>, <code>jal</code>, <code>jalr</code>. <code>jal/jalr</code> also write rd = PC+4."),
   ("Resolve and compare", "Carry the predicted next-PC with each instruction from fetch (the BPQ is a start). At execute, mispredict = (actual next-PC ≠ predicted)."),
   ("Recovery", "Simplest correct version: when a mispredicted branch <b>commits</b>, assert <code>flush</code>, clear everything younger (the ROB, all RS, LQ, SQ non-senior entries, the completion buffer, the MUL/DIV pipelines), restore the RAT to 'all registers in ARF', and redirect fetch to the correct PC. Faster: recover at execute with RAT checkpoints per branch."),
   ("Train the predictor", "Drive <code>update_en/pc/taken/target</code> from commit. Checkpoint gshare history at prediction."),
   ("Verify", "Extend <code>tools/rv.py</code> (branches are already modelled). Write loops, calls/returns and data-dependent branches. Assertions: nothing younger than a flushing branch commits; after a flush the RAT is clean; senior stores survive the flush. Coverage: mispredicts in each bundle slot, a mispredict while the ROB wraps, a mispredict with a DIV in flight."),
  ])

INTERVIEW = [
 ("2-minute pitch: describe this core.", "3-wide RISC-V RV32IM out-of-order core. Tomasulo with a 48-entry ROB holding the data. 12/4/16 reservation stations for ALU, MUL/DIV and load/store. 3 ALUs, 2 pipelined MUL/DIV units (radix-4 Booth, radix-8 divider). A 3-lane CDB fed by a completion buffer. In-order 3-wide commit. A load/store unit with an 8-entry LQ and SQ, store-to-load forwarding and conservative disambiguation. On the verification side, I built a commit-trace scoreboard against a Python ISS, directed and constrained-random stimulus, and bind-based SVA. That found 15 functional bugs across decode, issue, execute, memory and frontend, including two deadlocks that only random stimulus exposed."),
 ("What's the hardest bug you found and how did you debug it?", "The store-queue deadlock and bypass (B13). Random programs hung with a store stuck at not-ready. The trace showed the SQ full of younger stores while the oldest store waited in the LSB, which is a resource deadlock. While fixing it I found that the age function broke once a store retired: its ROB tag wrapped and it looked younger than later loads. The fix was in-order SQ entry and explicit retire signals from the ROB to the MMU. The general lesson: resources shared by instructions of different ages must be allocated in age order, or reserve capacity for the oldest."),
 ("How would you build a verification plan for an OOO core from scratch?", "Start with the contract: the committed stream equals the ISA reference. Then layer it. (1) An ISS-based commit scoreboard with lock-step comparison. (2) Directed tests per feature from the spec. (3) Constrained-random instruction streams with knobs for hazards, aliasing and latency mixes. (4) White-box SVA on microarchitectural invariants (ROB order, unique tags, RS free-list, LSQ order, credit counters). (5) Functional coverage: every structure full and empty, every bypass path, every corner-case matrix. (6) Unit-level tests and formal for datapath and arbiters. (7) Performance checks: IPC against a model, which catches the bugs that are correct but slow."),
 ("Correct but slow: how do you catch performance bugs?", "Keep a performance model or expected-cycle budget per directed test, and track IPC per regression run. Microbenchmarks isolate one mechanism: a dependent ALU chain should be 1 IPC per dependency, independent ALU ops should reach issue width. In this core, the chain test showed 2 cycles per dependent add, which pointed straight at the registered <code>ready</code> bit."),
 ("What is bug masking and how do you deal with it?", "One bug stops execution before others can show. Here, the decode key bug stopped 13 of 20 directed tests within the first few instructions. Each fix revealed the next layer. To deal with it: fix and re-run in small steps, keep tests narrow so each targets one mechanism, and use assertions, which report problems even when the end result is masked."),
 ("Why bind assertions instead of writing them in the RTL?", "Bind keeps verification code out of the design files: designers own the RTL, DV owns the checkers, and synthesis never sees them. A bind applies to every instance of a module and can reach internal signals by name. You can also turn checker sets on and off per run."),
 ("Blocking vs non-blocking assignments in this design: what went wrong?", "Several clocked blocks used blocking assignments for state that another clocked block reads at the same edge (temp_RAT, busy arrays, ROB_next), and one variable had two drivers. The result depends on which block the simulator schedules first, so behaviour can differ between Xcelium, VCS and Verilator, and synthesis builds something different again. The rule: one always_ff per state variable, written with non-blocking; next-state logic in always_comb."),
 ("GPU angle: what carries over from this CPU to a GPU SM?", "Scoreboarding and dependency tracking per warp, operand collectors (like data-capture RS), result buses with limited writeback ports, credit-based flow control, LSQ-like coalescing and ordering in the LD/ST unit, and the same verification pattern: a reference model of the ISA (PTX/SASS semantics), commit- or retire-level comparison, and stress on shared-resource arbitration. GPUs mostly issue in order per warp; the out-of-order aspect is across warps."),
]
