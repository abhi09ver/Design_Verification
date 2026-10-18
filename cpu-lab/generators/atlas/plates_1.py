PLATES = []

# ---------------------------------------------------------------- PL-01
PLATES.append(dict(id="p01", part="I", short="ISA contract",
title="The RV32I contract",
thesis="The ISA is a contract between software and every implementation. Verification checks the implementation against this contract and nothing else, so you need to know exactly what it does and does not promise.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 300" role="img" aria-label="Architectural state of RV32I">
 <rect class="boxa" x="10" y="10" width="190" height="280" rx="4"/>
 <text class="th" x="22" y="34">Architectural state</text>
 <text class="t tmono" x="22" y="60">x0  = 0 (always)</text>
 <text class="t tmono" x="22" y="80">x1 … x31  32-bit</text>
 <text class="t tmono" x="22" y="100">pc        32-bit</text>
 <text class="t tmono" x="22" y="120">memory    byte-addr,</text>
 <text class="t tmono" x="22" y="136">          little-endian</text>
 <text class="tm" x="22" y="166">no flags register</text>
 <text class="tm" x="22" y="184">no overflow trap</text>
 <text class="tm" x="22" y="202">no delay slots</text>
 <text class="tm" x="22" y="220">CSRs live in Zicsr</text>
 <text class="tm" x="22" y="238">(privileged spec)</text>
 <rect class="box" x="220" y="10" width="390" height="280" rx="4"/>
 <text class="th" x="232" y="34">40 instructions in 6 formats</text>
 <g class="tmono">
  <rect class="boxw" x="232" y="48" width="180" height="44"/><text class="t tb" x="240" y="66">OP (R) · 10</text><text class="tm" x="240" y="83">add sub sll slt sltu xor srl sra or and</text>
  <rect class="boxw" x="418" y="48" width="180" height="44"/><text class="t tb" x="426" y="66">OP-IMM (I) · 9</text><text class="tm" x="426" y="83">addi slti sltiu xori ori andi slli srli srai</text>
  <rect class="boxw" x="232" y="100" width="180" height="44"/><text class="t tb" x="240" y="118">LOAD (I) · 5</text><text class="tm" x="240" y="135">lb lh lw lbu lhu</text>
  <rect class="boxw" x="418" y="100" width="180" height="44"/><text class="t tb" x="426" y="118">STORE (S) · 3</text><text class="tm" x="426" y="135">sb sh sw</text>
  <rect class="boxw" x="232" y="152" width="180" height="44"/><text class="t tb" x="240" y="170">BRANCH (B) · 6</text><text class="tm" x="240" y="187">beq bne blt bge bltu bgeu</text>
  <rect class="boxw" x="418" y="152" width="180" height="44"/><text class="t tb" x="426" y="170">JUMP · 2</text><text class="tm" x="426" y="187">jal (J)   jalr (I)</text>
  <rect class="boxw" x="232" y="204" width="180" height="44"/><text class="t tb" x="240" y="222">UPPER (U) · 2</text><text class="tm" x="240" y="239">lui auipc</text>
  <rect class="boxw" x="418" y="204" width="180" height="44"/><text class="t tb" x="426" y="222">SYSTEM / MEM · 3</text><text class="tm" x="426" y="239">fence ecall ebreak</text>
 </g>
 <text class="tm" x="232" y="275">37 compute / memory / control + 3 system = 40</text>
</svg></div>
<div class="callout">Extensions are separate contracts: <b>M</b> mul/div, <b>A</b> atomics, <b>C</b> 16-bit, <b>F/D</b> float, <b>Zicsr</b>, <b>Zifencei</b>. "RV32IMC" means base plus those. A verification plan starts by naming the exact ISA string.</div>""",
deep=[
 "<b>Load/store architecture</b>: only loads and stores touch memory, and every ALU op is register–register or register–immediate. That is what makes a single-cycle or 5-stage datapath simple.",
 "<b>x0 is not a register you can write.</b> Writes are discarded and reads return 0. <code>addi x0,x0,0</code> is the canonical NOP. A hardware bug that stores into x0 is invisible until something forwards from it.",
 "<b>No condition codes</b>: branches compare two registers directly. There are no flags to rename in an OOO core, which removes a whole bug class.",
 "<b>No integer overflow trap</b>: <code>add</code> wraps silently. Software detects overflow with <code>slt</code>/<code>sltu</code>.",
 "<b>Divide by zero does not trap</b> (M extension): x/0 = −1, x%0 = x, and −2³¹/−1 = −2³¹. Tomasulo lab bug <b>B06</b> returned +1.",
 "<b>Implementation-defined ≠ undefined</b>: misaligned data access may be handled in hardware or trap. The DV plan must pick the policy the design implements, and the reference model must match it.",
],
rules=[
 "Instructions are 32-bit and 4-byte aligned (without C). A jump or taken branch to a non-aligned target raises <i>instruction-address-misaligned</i>.",
 "Register read happens before write in one instruction: <code>jalr x1,0(x1)</code> uses the old x1.",
 "HINT space: writes to x0 with other encodings are legal NOP-like hints. They must not trap.",
],
bugs=[
 "<span class='tag t-bug'>B06</span> signed divide by zero returned +1 instead of −1.",
 "<span class='tag t-bug'>B14</span> Booth multiplier overflowed on −2³¹ (the one value with no positive twin).",
 "Classic: the regfile write port lets x0 be written, and forwarding then sends that value onward.",
],
ask=[
 ("Q: Where do you start verifying a RISC-V core?",
  "Pin the contract: ISA string, privilege modes, the misaligned and illegal-instruction policy, and the reset state. Then pick a golden model configured to that exact contract. Every later check derives from it."),
]))

# ---------------------------------------------------------------- PL-02
PLATES.append(dict(id="p02", part="I", short="Encodings",
title="Formats and immediates",
thesis="Six formats keep rs1, rs2 and rd in the same bit positions so decode can read registers before it knows the format. Immediates pay the price: their bits are scrambled to keep the sign bit at inst[31].",
fig="""
<div class="scroll"><table class="bits">
<tr><th></th><th>31</th><th colspan="6">30 … 25</th><th colspan="4">24 … 21</th><th>20</th><th colspan="5">19 … 15</th><th colspan="3">14 … 12</th><th colspan="4">11 … 8</th><th>7</th><th colspan="7">6 … 0</th></tr>
<tr><td class="lbl">R</td><td class="f" colspan="7">funct7</td><td class="f" colspan="5">rs2</td><td class="f" colspan="5">rs1</td><td class="f" colspan="3">funct3</td><td class="f" colspan="5">rd</td><td class="op" colspan="7">opcode</td></tr>
<tr><td class="lbl">I</td><td class="imm" colspan="12">imm[11:0]</td><td class="f" colspan="5">rs1</td><td class="f" colspan="3">funct3</td><td class="f" colspan="5">rd</td><td class="op" colspan="7">opcode</td></tr>
<tr><td class="lbl">S</td><td class="imm" colspan="7">imm[11:5]</td><td class="f" colspan="5">rs2</td><td class="f" colspan="5">rs1</td><td class="f" colspan="3">funct3</td><td class="imm" colspan="5">imm[4:0]</td><td class="op" colspan="7">opcode</td></tr>
<tr><td class="lbl">B</td><td class="imm">12</td><td class="imm" colspan="6">imm[10:5]</td><td class="f" colspan="5">rs2</td><td class="f" colspan="5">rs1</td><td class="f" colspan="3">funct3</td><td class="imm" colspan="4">imm[4:1]</td><td class="imm">11</td><td class="op" colspan="7">opcode</td></tr>
<tr><td class="lbl">U</td><td class="imm" colspan="20">imm[31:12]</td><td class="f" colspan="5">rd</td><td class="op" colspan="7">opcode</td></tr>
<tr><td class="lbl">J</td><td class="imm">20</td><td class="imm" colspan="10">imm[10:1]</td><td class="imm">11</td><td class="imm" colspan="8">imm[19:12]</td><td class="f" colspan="5">rd</td><td class="op" colspan="7">opcode</td></tr>
</table></div>
<table class="grid" style="margin-top:12px">
<tr><th>opcode</th><th>class</th><th>imm value (sign = inst[31])</th></tr>
<tr><td class="mono">0110011</td><td>OP (R)</td><td>none</td></tr>
<tr><td class="mono">0010011</td><td>OP-IMM (I)</td><td class="mono">sx(inst[31:20])</td></tr>
<tr><td class="mono">0000011 / 0100011</td><td>LOAD / STORE</td><td class="mono">I / sx({inst[31:25],inst[11:7]})</td></tr>
<tr><td class="mono">1100011</td><td>BRANCH</td><td class="mono">sx({i[31],i[7],i[30:25],i[11:8],0})</td></tr>
<tr><td class="mono">0110111 / 0010111</td><td>LUI / AUIPC</td><td class="mono">{inst[31:12], 12'b0}</td></tr>
<tr><td class="mono">1101111 / 1100111</td><td>JAL / JALR</td><td class="mono">sx({i[31],i[19:12],i[20],i[30:21],0}) / I</td></tr>
</table>""",
deep=[
 "<b>B and J offsets are in units of 2 bytes</b>: bit 0 is implicit 0. That gives ±4 KiB for branches and ±1 MiB for JAL. With C absent, bit 1 must also be 0 at the target, or the jump traps.",
 "<b>Why scramble?</b> Each immediate bit sits in as few positions as possible across formats, so the mux tree in decode stays small. Sign extension always comes from inst[31], so it can start before the format is known.",
 "<b>funct7 matters only for 3 cases</b>: ADD/SUB and SRL/SRA (bit 30), and SRLI/SRAI (imm[10], also inst[30]). Every other funct7 in OP is reserved, so it should decode as illegal, not as an alias.",
 "<b>A decoder keyed on partial fields aliases.</b> YARP keyed I-type control on {opcode[4], funct3}. JALR (1100111, f3=000) collided with LB (0000011, f3=000). That is bug <b>Y3</b>.",
 "<b>Stimulus encodes the same layout.</b> A generator that packs B-type bits wrong produces legal-looking but different branches. Cross-check your encoder against an assembler or ISS once.",
],
rules=[
 "Illegal: opcode not in the table, a reserved funct3/funct7 combination, or the all-zero instruction <code>0x00000000</code> (defined illegal so zeroed memory traps).",
 "SLLI/SRLI/SRAI on RV32: imm[5] = 1 is reserved.",
 "JALR requires funct3 = 000. Other values are reserved.",
],
bugs=[
 "<span class='tag t-bug'>Y3</span> JALR aliased LB in a {opcode[4],funct3} key, so every JALR issued a phantom data read.",
 "<span class='tag t-bug'>B01</span> Tomasulo decode let immediate bits leak into the opcode key: valid instructions decoded as OTHER, then deadlock.",
 "<span class='tag t-bug'>B02</span> I-type immediates were zero-extended: <code>addi x1,x0,-1</code> gave 0x00000FFF.",
],
ask=[
 ("Q: How do you verify a decoder?",
  "Exhaustively. 2³² is too many, but opcode×funct3×funct7 plus immediate boundary values is small. Compare every control field against a table derived from the spec, and make sure reserved encodings decode to illegal. Formal equivalence against a spec-written decoder closes it."),
]))

# ---------------------------------------------------------------- PL-03
PLATES.append(dict(id="p03", part="I", short="Semantics",
title="Semantics corners: signed, unsigned, shifts, jumps",
thesis="Most ALU bugs are not wrong operators. They are wrong interpretations of the same 32 bits. SystemVerilog makes this worse: <code>logic</code> is unsigned unless you say otherwise.",
fig="""
<table class="grid">
<tr><th>Instruction</th><th>Compare as</th><th>Corner that exposes a bug</th></tr>
<tr><td class="mono">slt / slti / blt / bge</td><td>signed</td><td class="mono">a=−1 (0xFFFFFFFF), b=1 → 1 &nbsp; (unsigned says 0)</td></tr>
<tr><td class="mono">sltu / bltu / bgeu</td><td>unsigned</td><td class="mono">a=0x80000000, b=1 → 0 &nbsp; (signed says 1)</td></tr>
<tr><td class="mono">sltiu</td><td>imm is <b>sign</b>-extended, then compared unsigned</td><td class="mono">sltiu rd,rs,−1 → 1 unless rs=0xFFFFFFFF</td></tr>
<tr><td class="mono">sltiu rd,rs,1</td><td>idiom</td><td class="mono">= seqz (rd = rs==0)</td></tr>
<tr><td class="mono">sll / srl / sra</td><td>shamt = rs2[4:0]</td><td class="mono">rs2=33 shifts by 1; sra keeps the sign</td></tr>
<tr><td class="mono">lui / auipc</td><td>imm&lt;&lt;12, auipc adds pc</td><td class="mono">auipc uses <b>its own</b> pc, not pc+4</td></tr>
<tr><td class="mono">jal / jalr</td><td>rd = pc+4</td><td class="mono">jalr target = (rs1+imm) &amp; ~1</td></tr>
</table>
<div class="scroll"><svg viewBox="0 0 600 120" style="margin-top:12px" role="img" aria-label="Number line showing signed versus magnitude order">
 <line class="w" x1="20" y1="60" x2="580" y2="60"/>
 <text class="tm" x="20" y="90">−2³¹</text><text class="tm" x="290" y="90">0</text><text class="tm" x="540" y="90">2³¹−1</text>
 <circle class="bugf" cx="140" cy="60" r="6"/><text class="t tmono" x="112" y="44">a = −5</text>
 <circle class="dvf" cx="345" cy="60" r="6"/><text class="t tmono" x="325" y="44">b = 3</text>
 <text class="t" x="20" y="18">signed:  a &lt; b   → slt = 1  ✓</text>
 <text class="bugf" x="320" y="18" style="font-size:12px">|a| &lt; |b| ?  5 &lt; 3 → 0  ✗  (bug Y1)</text>
 <text class="tm" x="20" y="112">A magnitude compare agrees with signed compare whenever both operands are non-negative. That is why easy stimulus never sees it.</text>
</svg></div>""",
deep=[
 "<b>Three compare semantics, four bug shapes</b>: signed-as-unsigned, unsigned-as-signed, magnitude (abs), and wrong operand order. Each one agrees with the correct answer on half the input space or more.",
 "<b>In SystemVerilog</b>: <code>a &lt; b</code> on <code>logic [31:0]</code> is unsigned. Signed needs <code>$signed(a) &lt; $signed(b)</code>, and one unsigned operand makes the whole expression unsigned. Bug <b>Y2</b> is exactly this.",
 "<b>Shifts</b>: only the low 5 bits of the amount count. SRA must replicate bit 31 (<code>$signed(a) &gt;&gt;&gt; sh</code>). <code>&gt;&gt;&gt;</code> on an unsigned operand is a logical shift.",
 "<b>JALR clears bit 0 only.</b> Bit 1 left at 1 makes a misaligned target, which must trap when C is absent. A design without traps (YARP) must document what it does instead, and the model must follow.",
 "<b>rd = rs1 on JALR</b>: the target uses the old rs1, and the link value goes to rd. An implementation that writes rd first jumps to pc+4+imm.",
],
rules=[
 "Writes to x0 by any of these instructions are discarded, including the jal/jalr link.",
 "No instruction sets flags. Overflow is silent wrap.",
 "SUB is funct7 = 0100000. Any other non-zero funct7 on OP is reserved.",
],
bugs=[
 "<span class='tag t-bug'>Y1</span> SLT compared |a| &lt; |b|. Caught 9/9 only after compare-corner coverage plus a targeted test.",
 "<span class='tag t-bug'>Y2</span> BLT/BGE used unsigned compares, and BLTU/BGEU used magnitudes. The original testbench never caught it (0/10).",
 "<span class='tag t-bug'>P5</span> SUB decoded as ADD. Missed entirely by a stimulus that was 70% JAL/LUI.",
],
ask=[
 ("Q: Name a test that exposes a signed/unsigned bug.",
  "Operands with different signs, and both negative, on every compare form: slt, slti, sltu, sltiu, and all six branches. Make it a coverage cross (instruction × operand-sign class), not a hand test, so you can prove it was hit."),
]))

# ---------------------------------------------------------------- PL-04
PLATES.append(dict(id="p04", part="I", short="Memory access",
title="Loads, stores, sizes and alignment",
thesis="A load is address, size, sign rule and byte placement. Each of the four is a separate place to be wrong, and the memory interface contract decides which side of the boundary each one lives on.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 230" role="img" aria-label="Little-endian word and load extension">
 <text class="th" x="10" y="20">Little-endian word at 0x100 = 0x8899AABB</text>
 <g>
  <rect class="boxw" x="10" y="32" width="70" height="34"/><text class="t tmono" x="22" y="54">0x100</text>
  <rect class="boxw" x="80" y="32" width="70" height="34"/><text class="t tmono" x="92" y="54">0x101</text>
  <rect class="boxw" x="150" y="32" width="70" height="34"/><text class="t tmono" x="162" y="54">0x102</text>
  <rect class="boxw" x="220" y="32" width="70" height="34"/><text class="t tmono" x="232" y="54">0x103</text>
  <rect class="boxa" x="10" y="66" width="70" height="30"/><text class="acc tmono" x="34" y="86">BB</text>
  <rect class="boxa" x="80" y="66" width="70" height="30"/><text class="acc tmono" x="104" y="86">AA</text>
  <rect class="boxa" x="150" y="66" width="70" height="30"/><text class="acc tmono" x="174" y="86">99</text>
  <rect class="boxa" x="220" y="66" width="70" height="30"/><text class="acc tmono" x="244" y="86">88</text>
 </g>
 <text class="tm" x="10" y="114">lowest address = least significant byte</text>
 <g class="tmono">
  <text class="t" x="320" y="44">lb  x1, 0x100  → 0xFFFFFFBB</text>
  <text class="t" x="320" y="64">lbu x1, 0x100  → 0x000000BB</text>
  <text class="t" x="320" y="84">lh  x1, 0x102  → 0xFFFF8899</text>
  <text class="t" x="320" y="104">lhu x1, 0x102  → 0x00008899</text>
  <text class="t" x="320" y="124">lw  x1, 0x100  → 0x8899AABB</text>
 </g>
 <rect class="boxr" x="10" y="140" width="600" height="80" rx="4"/>
 <text class="th" x="22" y="162">Interface contract (write it down)</text>
 <text class="t" x="22" y="182">Lane-aligned: memory returns the whole word; the core shifts by addr[1:0], then extends.</text>
 <text class="t" x="22" y="200">Right-aligned (YARP): memory shifts; the core only extends. The TB model must match.</text>
 <text class="tm" x="22" y="215">YARP byte_en is a SIZE code (00 B, 01 H, 11 W, 10 reserved), not four byte enables.</text>
</svg></div>""",
deep=[
 "<b>Sign rule depends on the instruction, not the data</b>: LB/LH extend bit 7/15, while LBU/LHU zero-extend. A bug only shows when the loaded byte has its top bit set. Random memory full of zeros never shows it (mutant <b>P6</b>).",
 "<b>Misaligned</b> (lw at 0x101, lh at 0x103): allowed to work, trap, or be emulated by the execution environment. Pick one. The YARP lab uses byte-wise access in RTL, TB memory and the C model. The original testbench <code>$fatal</code>-ed on it, which gave 40% false failures.",
 "<b>Store data</b>: SB/SH write only the low byte/half of rs2. Memory must not touch the other lanes (read-modify-write or byte strobes).",
 "<b>Load-after-store is the real check</b>: a store that never lands is invisible until a later load reads the same bytes. Constrain addresses into a small window so that happens often.",
 "<b>A load to x0</b> still performs the access (it matters for I/O side effects), but the result is discarded.",
],
rules=[
 "Little-endian byte order is mandated for the base ISA.",
 "Alignment policy is implementation-defined. The reference model must be configured to the same policy as the RTL.",
 "The load address is rs1 + sign-extended imm, computed modulo 2³².",
],
bugs=[
 "<span class='tag t-bug'>B10</span> Tomasulo lbu/lhu read whole words and sign-extended.",
 "<span class='tag t-bug'>D2</span> YARP TB driver gated store writes on a stale clocking-block sample, so stores never reached memory. Loads read 0 and the C model disagreed.",
 "<span class='tag t-bug'>M1</span> TB memory model <code>$fatal</code> on misaligned addresses, although the spec says handle them.",
],
ask=[
 ("Q: Your loads pass. Why might stores still be broken?",
  "Loads only prove stores if they read back what was stored. Random addresses make that rare. Check the store stream directly (address/size/data vs the model at the interface) and bias load addresses onto recently stored bytes."),
]))

# ---------------------------------------------------------------- PL-05
PLATES.append(dict(id="p05", part="I", short="Traps & CSRs",
title="Traps, CSRs and precise exceptions",
thesis="The base ISA leaves exceptions to the privileged spec, and that is where senior interviews go. A trap has to look as if every older instruction finished and no younger one started.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 250" role="img" aria-label="Machine-mode trap flow">
 <rect class="box" x="10" y="20" width="150" height="54" rx="4"/><text class="th" x="22" y="42">Instruction i</text><text class="tm" x="22" y="62">faults (or interrupt)</text>
 <path class="wa" d="M160 47 H215"/><polygon class="acc" points="215,42 225,47 215,52"/>
 <rect class="boxa" x="225" y="10" width="200" height="140" rx="4"/>
 <text class="th" x="237" y="32">Hardware, atomically</text>
 <g class="tmono"><text class="t" x="237" y="54">mepc   ← pc of i</text>
 <text class="t" x="237" y="72">mcause ← {intr, code}</text>
 <text class="t" x="237" y="90">mtval  ← bad addr / instr</text>
 <text class="t" x="237" y="108">MPIE ← MIE ; MIE ← 0</text>
 <text class="t" x="237" y="126">MPP ← priv ; priv ← M</text>
 <text class="t" x="237" y="144">pc ← mtvec</text></g>
 <path class="wa" d="M425 80 H470"/><polygon class="acc" points="470,75 480,80 470,85"/>
 <rect class="box" x="480" y="40" width="130" height="80" rx="4"/><text class="th" x="492" y="62">Handler</text><text class="tm" x="492" y="82">… mret</text><text class="tm" x="492" y="100">pc ← mepc</text>
 <rect class="boxr" x="10" y="166" width="600" height="76" rx="4"/>
 <text class="th" x="22" y="188">Precise</text>
 <text class="t" x="22" y="208">all instructions older than i retired · i and younger have no architectural effect</text>
 <text class="tm" x="22" y="228">In an OOO core this is the ROB's job: the exception is recorded at execute and taken only when i reaches the ROB head.</text>
</svg></div>
<table class="grid" style="margin-top:8px"><tr><th>mcause</th><th>Exception (intr=0)</th><th>mcause</th><th>Interrupt (intr=1)</th></tr>
<tr><td class="n">0</td><td>instr addr misaligned</td><td class="n">3</td><td>machine software</td></tr>
<tr><td class="n">2</td><td>illegal instruction</td><td class="n">7</td><td>machine timer</td></tr>
<tr><td class="n">3</td><td>breakpoint (ebreak)</td><td class="n">11</td><td>machine external</td></tr>
<tr><td class="n">4 / 6</td><td>load / store misaligned</td><td></td><td></td></tr>
<tr><td class="n">5 / 7</td><td>load / store access fault</td><td></td><td></td></tr>
<tr><td class="n">11</td><td>ecall from M</td><td></td><td></td></tr></table>""",
deep=[
 "<b>Synchronous vs asynchronous</b>: an exception belongs to one instruction and is deterministic, so an ISS can predict it. An interrupt arrives between instructions at a time the design chooses. The ISS cannot predict it and must be told: \"DUT took interrupt X before instruction N\".",
 "<b>mepc points at the faulting instruction</b> for exceptions (ecall included: software adds 4) and at the next unexecuted instruction for interrupts.",
 "<b>Priority when several apply</b>: the spec orders exceptions (e.g. instruction-address faults before illegal instruction) and interrupts (MEI &gt; MSI &gt; MTI). These are corners worth a cross.",
 "<b>CSR side effects</b>: reading <code>mcycle</code>/<code>minstret</code> is non-deterministic against a model. Mask, or let the model take the DUT value. CSR writes with WARL fields need the model to apply the same legalization.",
 "<b>Common OOO trap bugs</b>: a younger store already sitting in the store queue gets drained after the trap; a younger load updated the RAT; mepc taken from the fetch PC instead of the faulting PC.",
],
rules=[
 "Traps are precise in the base privileged spec.",
 "MIE clears on trap entry and is restored from MPIE on mret.",
 "Writes to read-only CSRs are illegal-instruction exceptions. WARL fields legalize silently.",
],
bugs=[
 "YARP has no trap support. An illegal opcode silently acts as a NOP, so the model must mirror that policy or every illegal instruction mismatches.",
 "Interrupt taken in the same cycle as a branch mispredict: mepc points into the wrong path.",
 "Store committed to memory after an older load faulted (imprecise).",
],
ask=[
 ("Q: How do you check interrupts against an ISS?",
  "The DUT decides when. The TB observes the retirement point where the trap was taken and injects the same interrupt into the ISS at that instruction boundary, then compares everything else as usual. Separately, check the decision is legal: enabled, pending, priority, latency bound, with SVA plus coverage."),
]))
