PLATES = []

# ---------------------------------------------------------------- PL-06
PLATES.append(dict(id="p06", part="II", short="Single-cycle",
title="Single-cycle datapath (YARP)",
thesis="Every instruction does fetch, decode, read, execute, memory and write-back in one clock. The datapath is a set of muxes, and the control unit's only job is to set them.",
fig="""
<div class="scroll"><svg viewBox="0 0 640 300" role="img" aria-label="YARP single-cycle datapath">
 <rect class="boxa" x="10" y="120" width="56" height="50" rx="3"/><text class="th" x="24" y="150">PC</text>
 <rect class="box" x="96" y="110" width="80" height="70" rx="3"/><text class="th" x="104" y="136">imem</text><text class="tm" x="104" y="156">req/addr</text><text class="tm" x="104" y="170">rd_data</text>
 <rect class="box" x="206" y="40" width="96" height="60" rx="3"/><text class="th" x="216" y="64">decode</text><text class="tm" x="216" y="84">rs1 rs2 rd imm</text>
 <rect class="boxw" x="206" y="200" width="96" height="60" rx="3"/><text class="th" x="216" y="224">control</text><text class="tm" x="216" y="244">mux selects</text>
 <rect class="box" x="332" y="110" width="80" height="70" rx="3"/><text class="th" x="340" y="136">regfile</text><text class="tm" x="340" y="156">2R 1W</text>
 <rect class="boxa" x="442" y="100" width="70" height="90" rx="3"/><text class="th" x="456" y="140">ALU</text><text class="tm" x="452" y="160">+ − &lt; ⊕ ≪</text>
 <rect class="box" x="542" y="110" width="88" height="70" rx="3"/><text class="th" x="552" y="136">dmem</text><text class="tm" x="552" y="156">addr size</text><text class="tm" x="552" y="170">wr rd</text>
 <rect class="boxw" x="442" y="220" width="70" height="40" rx="3"/><text class="t tb" x="452" y="244">branch</text>
 <path class="wa" d="M66 145 H96"/><path class="w" d="M176 130 H190 V70 H206"/>
 <path class="w" d="M302 70 H320 V130 H332"/><path class="w" d="M412 130 H442"/><path class="w" d="M412 160 H442"/>
 <path class="wa" d="M512 145 H542"/><text class="tm" x="514" y="138">addr</text>
 <path class="w" d="M254 100 V200"/>
 <path class="w" d="M412 170 H428 V240 H442"/>
 <path class="wd" d="M586 180 V285 H372 V180"/><text class="tm" x="430" y="280">wb mux: ALU | MEM | IMM | pc+4</text>
 <path class="wa" d="M477 260 V290 H38 V170"/><text class="tm" x="44" y="285">next pc: pc+4 | {alu[31:1],0} if branch_taken | pc_sel</text>
 <text class="tm" x="320" y="28">op1sel: rs1 | pc   op2sel: rs2 | imm</text>
</svg></div>
<table class="grid" style="margin-top:6px"><tr><th>Class</th><th>op1</th><th>op2</th><th>ALU</th><th>wb</th><th>pc</th><th>mem</th></tr>
<tr><td>R</td><td>rs1</td><td>rs2</td><td>funct</td><td>ALU</td><td>+4</td><td>–</td></tr>
<tr><td>I-alu</td><td>rs1</td><td>imm</td><td>funct</td><td>ALU</td><td>+4</td><td>–</td></tr>
<tr><td>Load</td><td>rs1</td><td>imm</td><td>add</td><td>MEM</td><td>+4</td><td>rd</td></tr>
<tr><td>Store</td><td>rs1</td><td>imm</td><td>add</td><td>–</td><td>+4</td><td>wr rs2</td></tr>
<tr><td>Branch</td><td>pc</td><td>imm</td><td>add</td><td>–</td><td>taken ? alu : +4</td><td>–</td></tr>
<tr><td>JAL / JALR</td><td>pc / rs1</td><td>imm</td><td>add</td><td>pc+4</td><td>alu &amp; ~1</td><td>–</td></tr>
<tr><td>LUI / AUIPC</td><td>– / pc</td><td>imm</td><td>– / add</td><td>IMM / ALU</td><td>+4</td><td>–</td></tr></table>""",
deep=[
 "<b>The branch unit compares rs1/rs2 while the ALU computes pc+imm.</b> Two units run in parallel. In YARP the compare is a separate module, and that is where Y2 lived.",
 "<b>The clock period is the longest path</b>: imem → decode → regfile read → ALU → dmem → wb mux → regfile setup. That is why single-cycle CPUs are slow. The pipeline (PL-11) cuts this path into stages.",
 "<b>Combinational memory read</b>: single-cycle assumes rd_data arrives in the same cycle as the address. Real memories are synchronous. That forces either a pipeline or a valid/ready stall FSM (PL-08).",
 "<b>White-box points for DV</b>: the regfile write port (wr_en, rd, data) gives one retire event per cycle. It is the natural compare point for a commit scoreboard.",
],
rules=[
 "Exactly one instruction retires per accepted fetch. No retire without a fetch handshake.",
 "Register writes and the PC update happen on the same edge: the retire edge.",
 "Loads write the register only once the data is valid.",
],
bugs=[
 "<span class='tag t-bug'>Y4</span> The first cycle after reset froze the PC but still wrote the regfile, so the first instruction executed twice.",
 "<span class='tag t-bug'>P4</span> Retiring a load before data_mem_ready advanced the PC early. It shows up as a PC mismatch.",
],
ask=[
 ("Q: What is the critical path of a single-cycle RISC-V?",
  "A load: PC → imem → decode/regfile read → address add → dmem read → extend → wb mux → regfile setup. Pipelining cuts it at the four boundaries between those blocks."),
]))

# ---------------------------------------------------------------- PL-07
PLATES.append(dict(id="p07", part="II", short="Decode/control",
title="Control decode and encoding collisions",
thesis="The control unit maps opcode/funct to a bundle of mux selects. Bugs come from default values, overrides that clear too little, and keys built from too few bits.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 250" role="img" aria-label="JALR and LB key collision">
 <text class="th" x="10" y="20">YARP I-type key = {opcode[4], funct3}</text>
 <rect class="boxw" x="10" y="34" width="290" height="70" rx="4"/>
 <text class="t tmono" x="22" y="56">LB    0000011  f3=000</text>
 <text class="t tmono" x="22" y="76">key = {0, 000}  → data_req=1</text>
 <text class="tm" x="22" y="96">opcode[4] = 0</text>
 <rect class="boxb" x="320" y="34" width="290" height="70" rx="4"/>
 <text class="t tmono" x="332" y="56">JALR  1100111  f3=000</text>
 <text class="t tmono" x="332" y="76">key = {0, 000}  → data_req=1 ✗</text>
 <text class="tm" x="332" y="96">opcode[4] = 0 as well</text>
 <rect class="boxr" x="10" y="120" width="600" height="58" rx="4"/>
 <text class="t" x="22" y="142">JALR override set pc_sel, wb=PC, alu=ADD … but did not clear data_req / data_byte</text>
 <text class="t tb" x="22" y="164">→ every JALR issued a phantom data-memory read (bug Y3)</text>
 <text class="th" x="10" y="204">Safer pattern</text>
 <text class="t tmono" x="10" y="224">ctl = '0;  case (opcode) … full 7-bit key, then funct3/funct7 …</text>
 <text class="t tmono" x="10" y="242">default: illegal = 1;   // never "behave like ADD"</text>
</svg></div>""",
deep=[
 "<b>Start from all-zero (no side effects)</b> and turn on only what each instruction needs. A side-effect signal (data_req, rf_wr_en, pc_sel) that defaults on is a phantom write waiting to happen.",
 "<b>An override must restate every side-effect field.</b> A partial override inherits whatever the earlier case left. That is how Y3 happened.",
 "<b>A <code>default:</code> that executes ADD</b> hides illegal encodings. The core silently runs garbage, and only a model with the same quirk agrees.",
 "<b>Phantom requests are invisible to register checks.</b> The register result was correct, so only an interface check (scoreboard comparing every data access, or SVA \"data_req only for load/store\") catches them.",
 "<b>Decode is ideal for formal</b>: write the spec table as SVA (<code>opcode==JALR |-> !data_req</code>) and prove it for all encodings.",
],
rules=[
 "data_req is asserted iff the opcode is LOAD or STORE.",
 "rf_wr_en is never asserted for STORE or BRANCH.",
 "Reserved funct3/funct7 values decode to illegal.",
],
bugs=[
 "<span class='tag t-bug'>Y3</span> JALR phantom load. Caught 9/9 by the data-access compare in the fixed TB.",
 "<span class='tag t-bug'>B01</span> Opcode key polluted by immediate bits, so instructions decoded as OTHER and the core deadlocked.",
 "<span class='tag t-bug'>B03</span> ALU silently dropped OP-IMM: the instruction never completed.",
],
ask=[
 ("Q: The register results all match the ISS. What can still be wrong in decode?",
  "Side effects that do not reach registers: phantom memory reads, writes to x0 that forward, illegal encodings that execute instead of trapping, and CSR or fence side effects. Check the interfaces as well as the architectural state."),
]))

# ---------------------------------------------------------------- PL-08
PLATES.append(dict(id="p08", part="II", short="Valid/ready",
title="Valid/ready memory handshake",
thesis="Real memories answer late. The core raises req, holds the payload stable, and the transfer happens only on the edge where req and ready are both high. YARP's spec turns this into ten rules, and each rule is one assertion.",
fig="""
<div class="scroll"><svg viewBox="0 0 640 250" role="img" aria-label="Valid ready waveform with data pending">
 <g class="tm"><text x="4" y="34">clk</text><text x="4" y="64">i_req</text><text x="4" y="94">i_addr</text><text x="4" y="124">i_ready</text><text x="4" y="154">d_req</text><text x="4" y="184">d_ready</text><text x="4" y="214">state</text></g>
 <path class="w" d="M60 40 h20 v-14 h20 v14 h20 v-14 h20 v14 h20 v-14 h20 v14 h20 v-14 h20 v14 h20 v-14 h20 v14 h20 v-14 h20 v14 h20 v-14 h20 v14 h20 v-14 h20 v14 h20 v-14 h20 v14 h20 v-14 h20 v14 h20 v-14 h20 v14 h20"/>
 <path class="wa" d="M60 70 v-14 h160 v14 h120 v-14 h220"/>
 <rect class="boxw" x="60" y="82" width="160" height="16"/><text class="t tmono" x="100" y="94">PC (stable)</text>
 <rect class="boxw" x="340" y="82" width="120" height="16"/><text class="t tmono" x="356" y="94">PC+4</text>
 <path class="wd" d="M60 130 h120 v-14 h40 v14 h160 v-14 h40 v14 h180"/>
 <path class="wa" d="M60 160 h120 v-14 h160 v14 h260"/>
 <path class="wd" d="M60 190 h260 v-14 h40 v14 h240"/>
 <line class="wm" x1="220" y1="20" x2="220" y2="230"/><text class="dvf" x="160" y="245" style="font-size:11px">instr handshake + d_req (R3)</text>
 <line class="wm" x1="340" y1="20" x2="340" y2="230"/><text class="dvf" x="300" y="16" style="font-size:11px">data handshake</text>
 <text class="t tmono" x="64" y="214">FETCH</text><text class="t tmono" x="232" y="214">PENDING</text><text class="tm" x="232" y="228">i_req=0 (R10)</text><text class="t tmono" x="350" y="214">FETCH</text>
</svg></div>
<table class="grid"><tr><th>Rule</th><th>Spec text, compressed</th><th>SVA</th></tr>
<tr><td>R1 R2</td><td>i_req held, i_addr stable until i_ready</td><td class="mono">i_req&amp;&amp;!i_rdy |=&gt; i_req &amp;&amp; $stable(addr)</td></tr>
<tr><td>R3</td><td>d_req starts in the instr-accept cycle</td><td class="mono">d_req &amp;&amp; !$past(d_wait) |-&gt; i_hs</td></tr>
<tr><td>R4–R7</td><td>d_req and payload stable until d_ready</td><td class="mono">d_wait |=&gt; d_req &amp;&amp; $stable({a,be,wr,wd})</td></tr>
<tr><td>R8 R9</td><td>back-to-back legal; ready may toggle alone</td><td>cover, never assert</td></tr>
<tr><td>R10</td><td>no fetch while data pending</td><td class="mono">d_wait |=&gt; !i_req</td></tr></table>""",
deep=[
 "<b>Pending FSM</b>: on an instruction handshake for a load/store, if d_ready is not already high, latch the instruction (the memory stops driving it next cycle), drop i_req, and hold the data payload from the latch. Retire on the data handshake.",
 "<b>Ready without a request is legal</b> (R9). A responder that holds ready high gets 1-cycle transfers. A responder that waits to see req first costs a cycle every time.",
 "<b>The instruction bits disappear after the handshake.</b> Forgetting to latch them (mutant <b>P1</b>) makes the data payload change mid-transfer. SVA R4/R5 catch it immediately; without SVA it shows up as a hang.",
 "<b>A rule with no data effect needs an assertion</b>: fetching during a pending load (mutant <b>P2</b>) corrupts nothing visible in this TB. The scoreboard passed 6/6, and only SVA R10 caught it.",
 "<b>Cover the legal corners too</b>: stall→handshake, back-to-back handshakes, ready held with no request. Otherwise the assertions may be vacuously true.",
],
rules=[
 "The payload is only meaningful while req is high.",
 "No combinational path from ready to req (protocol deadlock rule of thumb).",
 "The reserved size code 2'b10 is never driven.",
],
bugs=[
 "<span class='tag t-bug'>RTL</span> The uploaded YARP had no ready ports at all. Random ready tripped R2 on the first stall.",
 "<span class='tag t-bug'>P1</span> No instruction latch: caught by SVA R4. The original TB hung on 10/10 seeds.",
 "<span class='tag t-bug'>P2</span> Fetch while pending: caught only by SVA R10.",
 "<span class='tag t-bug'>P3</span> PC ignores ready: SVA R2 at the first stall.",
],
ask=[
 ("Q: Why put protocol assertions in the interface, not the scoreboard?",
  "Every test and every environment that instantiates the interface gets them, they fire at the exact cycle (not at the next compare point), and they check rules that have no data effect. The scoreboard checks results; assertions check behaviour."),
]))

# ---------------------------------------------------------------- PL-09
PLATES.append(dict(id="p09", part="II", short="Reset & X",
title="Reset, first cycle and X-propagation",
thesis="Reset bugs live in the cycles nobody tests: the edge reset releases, the first fetch, and state that was never reset. Make the testbench hostile in those cycles.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 190" role="img" aria-label="First cycle after reset double execution">
 <g class="tm"><text x="4" y="34">clk</text><text x="4" y="64">reset_n</text><text x="4" y="94">reset_seen_q</text><text x="4" y="124">pc_q</text><text x="4" y="154">rf write</text></g>
 <path class="w" d="M90 40 h25 v-14 h25 v14 h25 v-14 h25 v14 h25 v-14 h25 v14 h25 v-14 h25 v14 h25 v-14 h25 v14 h25 v-14 h25 v14 h25"/>
 <path class="wa" d="M90 70 h75 v-14 h345"/>
 <path class="wa" d="M90 100 h125 v-14 h295"/>
 <rect class="boxw" x="90" y="112" width="175" height="16"/><text class="t tmono" x="140" y="124">0x0 (frozen)</text>
 <rect class="boxw" x="265" y="112" width="50" height="16"/><text class="t tmono" x="270" y="124">0x4</text>
 <rect class="boxb" x="165" y="140" width="50" height="16"/><text class="bugf tmono" x="170" y="152">x1+=1</text>
 <rect class="boxw" x="215" y="140" width="50" height="16"/><text class="t tmono" x="220" y="152">x1+=1</text>
 <text class="bugf" x="290" y="152" style="font-size:12px">addi x1,x1,1 ran twice → x1 = 2 (or more)</text>
 <text class="tm" x="90" y="180">Hidden when TB memory returns 0 for req=0 (YARP decodes 0x00000000 as a no-op); exposed with +IMEM_ALWAYS.</text>
</svg></div>""",
deep=[
 "<b>Gate every architectural side effect with the same condition that gates the PC.</b> YARP froze the PC with <code>reset_seen_q</code> but let the regfile and data request run (<b>Y4</b>).",
 "<b>Polite testbench models hide bugs.</b> Memory that returns 0 when not requested makes the extra cycle harmless. Hostile models return real data whenever the spec allows, including with no request and with random ready.",
 "<b>Unreset state</b>: the YARP regfile has no reset (legal: x1–x31 are UNSPECIFIED at reset). The model must start from the same values, or the TB must initialise registers by program before comparing.",
 "<b>X-propagation</b>: an X on ready or rd_data right after reset (driver bug <b>D1</b>) can be optimistic in RTL sim (if/case treat X as false) and pessimistic in gate sim. Drive every responder output in the reset sequence.",
 "<b>Reset in the middle</b>: assert reset during a pending load. Every FSM must return to idle, and no write may happen on the reset edge.",
],
rules=[
 "PC = reset vector at the first fetch. The vector is implementation-defined (YARP: parameter RESET_PC, 0x1000 by default).",
 "Only pc and mstatus-type CSRs have mandated reset values. GPRs are unspecified.",
 "No architectural write may occur before the first instruction is accepted.",
],
bugs=[
 "<span class='tag t-bug'>Y4</span> First instruction executed twice. Found with an always-answering imem.",
 "<span class='tag t-bug'>D1</span> TB drove only reset_n, leaving ready/rd_data at X after reset.",
],
ask=[
 ("Q: How do you verify reset?",
  "Reset at time 0 and mid-traffic (pending load, stall, branch in flight); check that every state element returns to its spec value; check that no side effect happens on the reset edge or in the first cycle; check that the first fetch is the reset vector. Run both X-pessimistic and hostile-memory variants."),
]))
