PLATES = []

# ---------------------------------------------------------------- PL-17
PLATES.append(dict(id="p17", part="IV", short="DV strategy",
title="CPU verification strategy",
thesis="No single method closes a CPU. Each layer finds the bugs the others are blind to, and the plan says which layer owns which risk.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 270" role="img" aria-label="Verification layers">
 <polygon class="boxw" points="310,10 400,60 220,60"/><text class="t tb" x="270" y="50">Silicon</text>
 <polygon class="boxa" points="220,64 400,64 450,104 170,104"/><text class="t tb" x="214" y="90">Emulation / FPGA: OS boot, 10⁹+ instr</text>
 <polygon class="boxd" points="170,108 450,108 500,148 120,148"/><text class="t tb" x="160" y="134">SoC: coherence, interrupts, DMA, power</text>
 <polygon class="boxd" points="120,152 500,152 550,192 70,192"/><text class="t tb" x="100" y="178">Core: ISS lockstep · random streams · compliance · SVA</text>
 <polygon class="boxd" points="70,196 550,196 600,236 20,236"/><text class="t tb" x="40" y="222">Unit: ALU/decoder/LSQ/predictor · formal · exhaustive · mutation</text>
 <text class="tm" x="20" y="258">cheap, controllable, fast debug at the bottom · realistic, slow, hard to debug at the top</text>
</svg></div>
<table class="grid"><tr><th>Method</th><th>Owns the risk of</th><th>Blind to</th></tr>
<tr><td>ISS lockstep (commit compare)</td><td>wrong architectural result</td><td>timing, protocol, performance, no-data-effect bugs</td></tr>
<tr><td>Constrained-random streams (riscv-dv style)</td><td>hazard / interleaving corners</td><td>anything the constraints exclude</td></tr>
<tr><td>Directed + compliance (riscv-arch-test)</td><td>spec-listed behaviour, regressions</td><td>combinations nobody wrote</td></tr>
<tr><td>SVA / formal (riscv-formal, RVFI)</td><td>invariants for all inputs, protocol</td><td>long sequences (depth-bound)</td></tr>
<tr><td>Functional coverage</td><td>"did we try it?"</td><td>"was it checked?"</td></tr>
<tr><td>Mutation / TB qualification</td><td>"would we notice?"</td><td>bugs unlike the mutants</td></tr></table>""",
deep=[
 "<b>Start from risk, not from tests</b>: list features × failure modes (wrong value, hang, wrong order, lost update, performance) and assign a checker and a stimulus to each cell. That table is the verification plan.",
 "<b>Checker before stimulus</b>: a perfect stimulus with a weak checker finds nothing. The YARP course TB passed with a broken store path because nothing compared stores directly.",
 "<b>Open-source anchors worth naming</b>: riscv-dv (SV/UVM random instruction generator), riscv-arch-test (compliance), Spike / Sail (golden models; Sail is the formal spec), riscv-formal with RVFI (formal ISA checks via a standard retire port).",
 "<b>Sign-off is a set of trends</b>: coverage closed (and the holes waived with reasons), bug-find rate flattened, regressions stable over N nights, mutation score adequate, and every spec rule mapped to a check.",
],
rules=[
 "Every spec rule maps to at least one checker, and every checker to at least one test that exercises it (coverage).",
 "Every waiver of a coverage hole has a written reason and an owner.",
],
bugs=[
 "Method blind spot in the lab: <span class='tag t-bug'>P2</span> (fetch while pending) has no data effect, so the scoreboard was 0/6; SVA R10 caught it.",
 "Performance blind spot: pq5 \"no prediction\" passed every functional test.",
],
ask=[
 ("Q: You join a CPU team mid-project. What do you look at first?",
  "The verification plan's feature × check × coverage map and where it is thin; the bug database trend per unit (where bugs still arrive); whether the golden-model compare covers everything that retires (CSRs, traps, memory); and whether anything checks liveness and performance."),
]))

# ---------------------------------------------------------------- PL-18
PLATES.append(dict(id="p18", part="IV", short="Golden model",
title="Golden model and the commit scoreboard",
thesis="Step a reference ISS once per retired instruction and compare everything that instruction changed. Small, fast and exact: this is the backbone of every CPU testbench.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 250" role="img" aria-label="Lockstep scoreboard">
 <rect class="boxa" x="10" y="20" width="170" height="120" rx="4"/><text class="th" x="22" y="44">DUT</text><text class="tm" x="22" y="64">retire port (RVFI-like):</text>
 <text class="t tmono" x="22" y="84">pc, instr, rd, wdata</text><text class="t tmono" x="22" y="100">mem addr/size/wdata</text><text class="t tmono" x="22" y="116">trap, csr writes</text>
 <rect class="boxd" x="220" y="40" width="170" height="80" rx="4"/><text class="th" x="232" y="64">Scoreboard</text><text class="tm" x="232" y="84">per retire:</text><text class="tm" x="232" y="100">step(); compare()</text>
 <rect class="boxw" x="430" y="20" width="180" height="120" rx="4"/><text class="th" x="442" y="44">ISS (C/C++ via DPI)</text>
 <text class="t tmono" x="442" y="66">init()</text><text class="t tmono" x="442" y="82">step(instr)</text><text class="t tmono" x="442" y="98">compare_pc(addr)</text><text class="t tmono" x="442" y="114">compare_reg(i,v)</text><text class="t tmono" x="442" y="130">compare_mem(a,sz,wr,d)</text>
 <path class="wa" d="M180 80 H220"/><path class="wd" d="M390 80 H430"/><path class="wd" d="M430 100 H390"/>
 <rect class="boxr" x="10" y="160" width="600" height="80" rx="4"/>
 <text class="th" x="22" y="182">When to compare</text>
 <text class="t" x="22" y="202">ALU/branch/jump: at the instruction handshake (retires that edge)</text>
 <text class="t" x="22" y="220">load/store: at the data handshake (retire waits for it); compare address, size, wdata too</text>
 <text class="tm" x="22" y="236">sample RTL state AFTER the retire edge settles: negedge, or the write-port values themselves (PL-21)</text>
</svg></div>""",
deep=[
 "<b>Lockstep vs end-of-test</b>: comparing only final registers misses overwritten errors and gives no location. Comparing per retire pinpoints the first divergence. That is the instruction you debug.",
 "<b>Compare deltas, not the world</b>: comparing all 32 registers every retire (the course TB) is simple and slow. Comparing the one written register plus a periodic full check is how large cores do it.",
 "<b>Model the same policy as the RTL</b>: reset PC, alignment, illegal-instruction behaviour, unreset registers. In the lab a C++ model was written to the YARP policy and cross-checked against a Python ISS on 213/213 programs before it was trusted.",
 "<b>Non-determinism</b>: interrupts, mcycle/time, memory-mapped I/O and LR/SC success can't be predicted. The ISS follows the DUT for those (inject the interrupt, copy the read value), and separate checks judge whether the DUT's choice was legal.",
 "<b>Memory compare is a separate stream</b>: a correct register result with a phantom access (Y3) or a missing store (D2) passes the register compare.",
],
rules=[
 "One retire event ⇒ exactly one step(). Never step speculatively.",
 "Compare PC first. A PC mismatch makes every later compare noise.",
 "Fail on the first mismatch with expected vs actual and the instruction.",
],
bugs=[
 "<span class='tag t-bug'>S2</span> Course scoreboard read RTL regs from a thread woken by @cb: a race with the regfile NBA. Fixed by sampling at negedge.",
 "<span class='tag t-bug'>S3</span> No count check: a hung core or a dropped handshake passed.",
 "<span class='tag t-bug'>A1</span> End of test 32 cycles after the generator, not the driver: the last load was still pending, so a false mismatch (or the last instruction went unchecked).",
],
ask=[
 ("Q: Your ISS and RTL disagree. How do you decide who is wrong?",
  "Go to the spec text for that instruction and corner, then a second model (Sail or Spike vs your ISS), then the RTL. Model bugs are real: cross-check the model independently before trusting it, as the lab did on 213 programs."),
]))

# ---------------------------------------------------------------- PL-19
PLATES.append(dict(id="p19", part="IV", short="TB anatomy",
title="Class-based testbench anatomy",
thesis="Generator → driver → DUT → monitor → scoreboard, joined by mailboxes and one virtual interface. Every component has one job, so a test can change stimulus without touching any of them.",
fig="""
<div class="scroll"><svg viewBox="0 0 640 260" role="img" aria-label="Testbench components">
 <rect class="boxw" x="10" y="10" width="620" height="240" rx="6"/><text class="tm" x="20" y="28">environment: builds mailboxes, agent, scoreboard; runs them; end_of_test</text>
 <rect class="boxw" x="20" y="38" width="380" height="140" rx="5"/><text class="tm" x="30" y="56">agent</text>
 <rect class="boxd" x="30" y="66" width="100" height="56" rx="3"/><text class="th" x="40" y="88">generator</text><text class="tm" x="40" y="108">blueprint.copy()</text>
 <rect class="boxd" x="160" y="66" width="100" height="56" rx="3"/><text class="th" x="170" y="88">driver</text><text class="tm" x="170" y="108">plays memory</text>
 <rect class="boxd" x="290" y="66" width="100" height="56" rx="3"/><text class="th" x="300" y="88">monitor</text><text class="tm" x="300" y="108">samples /cycle</text>
 <path class="wd" d="M130 94 H160"/><text class="tm" x="132" y="86">mbx</text>
 <rect class="boxa" x="160" y="196" width="230" height="40" rx="3"/><text class="th" x="172" y="221">vif → DUT (YARP)</text>
 <path class="wa" d="M210 122 V196"/><path class="wa" d="M340 196 V122"/>
 <rect class="boxd" x="440" y="66" width="180" height="56" rx="3"/><text class="th" x="450" y="88">scoreboard</text><text class="tm" x="450" y="108">ISS via DPI</text>
 <path class="wd" d="M390 94 H440"/><text class="tm" x="396" y="86">mbx</text>
 <rect class="boxr" x="440" y="140" width="180" height="96" rx="3"/><text class="t tb" x="450" y="160">test</text><text class="tm" x="450" y="178">env.agent.gen.blueprint</text><text class="tm" x="450" y="194">  = new yarp_tr_cmp;</text><text class="tm" x="450" y="214">no base class edited</text>
</svg></div>""",
deep=[
 "<b>Blueprint pattern</b>: the generator constructs one transaction in new() and calls randomize() + copy() in run(). A test swaps the blueprint for a subclass with extra constraints. This is the pre-UVM version of a factory override.",
 "<b>copy() before put()</b>: putting the blueprint itself means every mailbox entry is the same object, and the driver sees the last randomization N times. The copy must copy every field (bug <b>T3</b>).",
 "<b>Reactive driver</b>: for a CPU, the TB is the memory. The driver waits for a request, waits the transaction's delay, then drives ready and data. Stimulus = instruction + delays.",
 "<b>Monitor samples every cycle</b>; the handshake is decoded in the scoreboard. The monitor must never block (unbounded mailbox) or it skips cycles.",
 "<b>End of test is a protocol</b>: the generator done → the driver done (count) → drain cycles → scoreboard completeness check (retired == num_tr, nothing pending) → a watchdog for hangs.",
],
rules=[
 "Components talk only through mailboxes and the interface, never by hierarchical references into each other.",
 "Construction in new(), activity in run(): that ordering is what makes overrides possible.",
],
bugs=[
 "<span class='tag t-bug'>C2</span> agent.sv included before monitor.sv: type used before declaration.",
 "<span class='tag t-bug'>C3</span> scoreboard run() was a function calling mailbox.get(), a blocking task.",
 "<span class='tag t-bug'>A1</span> drain counted from the generator, not the driver.",
 "<span class='tag t-bug'>W1</span> no watchdog: a hung core ran forever (10/10 seeds on mutant P1).",
],
ask=[
 ("Q: How does this map to UVM?",
  "Transaction = sequence_item; generator + blueprint = sequence + factory override; mailbox = TLM port/fifo; driver/monitor/agent the same; scoreboard = subscriber; end-of-test drain = objections + drain time; watchdog = global timeout."),
]))

# ---------------------------------------------------------------- PL-20
PLATES.append(dict(id="p20", part="IV", short="Random stimulus",
title="Constrained-random instruction generation",
thesis="A solver picks uniformly among all solutions, not among the opcodes you had in mind. Instruction streams need the opcode chosen first, legal control flow, and a deliberate register and address strategy.",
fig="""
<table class="grid"><tr><th>Observed mix (course TB, 3 seeds × 50)</th><th class="n">share</th><th>Why</th></tr>
<tr><td>JAL (J-type)</td><td class="n bad">49%</td><td>funct3, funct7, rs1, rs2, imm12 all unconstrained → huge solution count</td></tr>
<tr><td>LUI / AUIPC (U-type)</td><td class="n bad">35%</td><td>same: unused fields still multiply the solutions</td></tr>
<tr><td>R-type</td><td class="n">1% (2 of 150)</td><td>funct7 pinned to 1–2 values</td></tr>
<tr><td>Load / store</td><td class="n">2 accesses total</td><td>funct3 and imm restricted</td></tr></table>
<div class="scroll"><svg viewBox="0 0 620 120" style="margin-top:10px" role="img" aria-label="Fix by choosing the opcode first">
 <rect class="boxb" x="10" y="10" width="290" height="100" rx="4"/><text class="th" x="22" y="32">Before</text>
 <text class="t tmono" x="22" y="54">rand opcode, rd, rs1, rs2,</text><text class="t tmono" x="22" y="70">     funct3, funct7, imm…</text><text class="t tmono" x="22" y="90">randomize();  // one solve</text>
 <rect class="boxd" x="320" y="10" width="290" height="100" rx="4"/><text class="th" x="332" y="32">After</text>
 <text class="t tmono" x="332" y="54">pre_randomize: randcase w_r: R…</text><text class="t tmono" x="332" y="70">opcode.rand_mode(0);</text><text class="t tmono" x="332" y="90">// or: solve opcode before …</text>
</svg></div>""",
deep=[
 "<b>Uniform over solutions</b> is the LRM rule. <code>solve opcode before funct3, …</code> makes the opcode uniform first; <code>dist</code> adds weights. Verilator ignored both here, so the portable fix was a weighted randcase in pre_randomize plus <code>rand_mode(0)</code>.",
 "<b>Legal control flow</b>: B/J immediates keep bit 1 clear, JALR jumps to an aligned absolute target (rs1 = x0). Otherwise the PC wanders into unaligned or unmapped space.",
 "<b>Alignment constraints on imm are useless</b> when the base register is random: rs1 + imm is what must be aligned. Either constrain the base (x0 window), or make the model and memory handle misalignment.",
 "<b>Register pool</b>: draw from a small pool (x1–x6) so dependences and forwarding happen; reserve registers for addresses and loop counters in streams.",
 "<b>Constraint override by name</b>: a subclass constraint with the same name replaces the base one (used for the b2b and stall delay profiles); different names AND together.",
 "<b>Instruction streams</b> (riscv-dv): build sequences with intent (loops, call/return, load/store patterns), not just independent instructions.",
],
rules=[
 "Never generate an encoding the plan has not decided how to check (illegal, reserved, misaligned): either constrain it out or model it.",
 "Measure the mix every run. A histogram is a one-line check.",
],
bugs=[
 "<span class='tag t-bug'>T1</span> opcode skew: R/branch/memory almost untested while every run passed.",
 "<span class='tag t-bug'>T2</span> 2-aligned branch targets: undefined territory for a core without C.",
 "<span class='tag t-bug'>T3</span> copy() skipped the instruction fields.",
],
ask=[
 ("Q: Your random test passes 1000 seeds. Are you done?",
  "Only if coverage says the seeds did something. Print the opcode histogram and the corner bins. Here 1000 passing seeds were 70% JAL/LUI, with almost no memory traffic and zero SUBs."),
]))

# ---------------------------------------------------------------- PL-21
PLATES.append(dict(id="p21", part="IV", short="SV timing",
title="Clocking blocks, sampling and races",
thesis="Three of the worst testbench bugs in the lab came from when a value is read, not what is read. Know the scheduler well enough to say which value you get.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 240" role="img" aria-label="Clocking block sampling and drive">
 <path class="w" d="M20 50 H120 V20 H300 V50 H480 V20 H600"/><text class="tm" x="20" y="14">clk</text>
 <line class="wm" x1="120" y1="10" x2="120" y2="230"/><line class="wm" x1="480" y1="10" x2="480" y2="230"/>
 <rect class="boxd" x="96" y="62" width="24" height="18"/><text class="dvf" x="20" y="76" style="font-size:11px">#1step</text>
 <text class="t" x="130" y="76">cb.x reads the value from just BEFORE the edge</text>
 <rect class="boxa" x="120" y="92" width="18" height="18"/><text class="t" x="146" y="106">cb.y &lt;= v is applied after the edge (output skew)</text>
 <rect class="boxb" x="10" y="124" width="600" height="104" rx="4"/>
 <text class="t" x="22" y="146"><tspan class="tb bugf">D2</tspan>  drive cb.ready &lt;= 1, then test cb.ready → still 0 (old sample) → store never written</text>
 <text class="t" x="22" y="168"><tspan class="tb bugf">D3</tspan>  forked "ready &lt;= 0" and next txn "ready &lt;= 1" wake on the same edge → tool-dependent winner</text>
 <text class="t" x="22" y="190"><tspan class="tb bugf">S2</tspan>  class thread woken by @cb reads RTL regfile → may run before the NBA update</text>
 <text class="tm" x="22" y="214">Fix pattern: decide from your own state, drive once per edge inline, sample RTL state half a cycle later</text>
</svg></div>""",
deep=[
 "<b>Inputs are sampled in the Preponed region</b> (<code>#1step</code>): the value the design had just before the edge. That is race-free and correct for monitors, and a trap if you expect to see what you just drove.",
 "<b>Outputs are applied in Re-NBA</b> (with output skew): after the design's NBAs for that edge. Two drives in the same step: the last one wins, and \"last\" depends on thread order.",
 "<b>Class threads woken by @cb run in the Reactive/Active part of the step</b>. Hierarchical peeks at design flops can see old or new values depending on the simulator. Sample at negedge, or tap the write port (wr_en, rd, data) so the value is the event.",
 "<b>A responder sees req one edge late.</b> A clocked driver that waits to see req before raising ready costs a cycle per transfer; holding ready high in advance is legal and gives back-to-back transfers.",
 "<b>Direction discipline</b>: one clocking block per role (drv_cb with outputs, mon_cb all inputs) plus modports. An all-<code>inout</code> block (the original interface) lets a monitor drive the bus with no complaint.",
],
rules=[
 "Drive each signal from exactly one place per clock edge.",
 "Monitors use clocking-block inputs only; never sample with a bare @(posedge clk) in a class.",
],
bugs=[
 "<span class='tag t-bug'>D2</span> stale sampled ready: stores never reached the TB memory model.",
 "<span class='tag t-bug'>D3</span> fork/join_none deassert raced the next assert.",
 "<span class='tag t-bug'>S2</span> regfile read from @cb thread: scheduler-dependent.",
 "<span class='tag t-bug'>D1</span> ready/rd_data left X after reset.",
],
ask=[
 ("Q: What does #1step mean in a clocking block?",
  "Sample in the Preponed region of the clock's time step, i.e. the last value before any update caused by that edge. It removes the race between the design changing a signal on the edge and the testbench reading it."),
]))

# ---------------------------------------------------------------- PL-22
PLATES.append(dict(id="p22", part="IV", short="Assertions",
title="Assertions: protocol rules and microarchitecture invariants",
thesis="An assertion checks behaviour at the cycle it happens, for every test that binds it. It is the only checker for bugs that never produce a wrong value.",
fig="""
<table class="grid"><tr><th>Kind</th><th>Example</th><th>Caught in the labs</th></tr>
<tr><td>Protocol hold/stable</td><td class="mono">req &amp;&amp; !ready |=&gt; req &amp;&amp; $stable(addr)</td><td>P3 (R2), P1 (R4)</td></tr>
<tr><td>Protocol exclusion</td><td class="mono">d_wait |=&gt; !i_req</td><td><b>P2: only this</b></td></tr>
<tr><td>Decode legality</td><td class="mono">opcode==JALR |-&gt; !data_req</td><td>Y3 (at source)</td></tr>
<tr><td>Uniqueness</td><td class="mono">$onehot0(lq_tag_match)</td><td>B11 (A7)</td></tr>
<tr><td>Conservation</td><td class="mono">free + used == DEPTH</td><td>B12 class</td></tr>
<tr><td>Liveness (bounded)</td><td class="mono">alloc |-&gt; ##[1:MAX] retire</td><td>B04, B05, B08</td></tr>
<tr><td>Proved-redundant guard</td><td class="mono">a_loaduse</td><td>pq5 dead code</td></tr></table>
<div class="callout">Pair each important assertion with a <b>cover</b> of its trigger. An assertion whose antecedent never fires is vacuously true: green and useless.</div>""",
deep=[
 "<b>Where to put them</b>: protocol SVA in the interface (every env gets them), microarchitecture invariants bound to the RTL with <code>bind</code> (designers can own them), and ISA-level properties in formal (riscv-formal style).",
 "<b>|-&gt; vs |=&gt;</b>: overlapping (same cycle) vs next cycle. Payload stability is <code>|=&gt; $stable</code>; a same-cycle relation (R3: data req starts with the instruction handshake) is <code>|-&gt;</code>.",
 "<b>disable iff (!reset_n)</b> on everything, or every reset becomes a failure.",
 "<b>Assertions find bugs earlier in time</b>: P1 (no instruction latch) was a 10/10 hang in the original TB. With SVA it failed on the exact cycle with \"R4 data_mem_req dropped before ready\".",
 "<b>Formal on small blocks</b>: decoder, ALU, arbiters, FIFOs and protocol FSMs can be proven completely. Prove the unit, simulate the core.",
],
rules=[
 "Every spec protocol rule has one named assertion and one cover.",
 "Assertions must never fire on correct RTL: run them on the known-good design first (0/9 false fires in the lab).",
],
bugs=[
 "Original course interface had no assertions: P2 was invisible to every test.",
 "Vacuous pass: an assertion on a signal renamed in RTL compiles against a stale wire and never triggers. Covers expose it.",
],
ask=[
 ("Q: Give an example of a bug only an assertion can catch.",
  "In the lab: the core kept fetching while a load was pending, which the spec forbids. The memory model happened not to answer, so no result was ever wrong, and the scoreboard passed 6/6. The protocol assertion d_wait |=> !i_req failed at once."),
]))

# ---------------------------------------------------------------- PL-23
PLATES.append(dict(id="p23", part="IV", short="Coverage",
title="Functional coverage that finds bugs",
thesis="Coverage answers \"did we exercise it?\". Model the corners where bugs hide (operand classes, hazard distances, protocol timing), not just opcodes, and close the holes with targeted stimulus.",
fig="""
<table class="grid"><tr><th>Bin (scoreboard, clean RTL)</th><th class="n">default s2</th><th class="n">mem s1</th><th class="n">cmp s1</th><th class="n">merged 9 runs</th></tr>
<tr><td>SLT  a&lt;0≤b</td><td class="n bad">0</td><td class="n bad">0</td><td class="n">16</td><td class="n">41</td></tr>
<tr><td>SLT  a≥0&gt;b</td><td class="n bad">0</td><td class="n bad">0</td><td class="n">18</td><td class="n">45</td></tr>
<tr><td>SLT  both neg</td><td class="n bad">0</td><td class="n bad">0</td><td class="n">5</td><td class="n">17</td></tr>
<tr><td>BLT/BGE both neg</td><td class="n bad">0</td><td class="n bad">0</td><td class="n">3</td><td class="n">9</td></tr>
<tr><td>SLTU msb set</td><td class="n bad">0</td><td class="n bad">0</td><td class="n">18</td><td class="n">42</td></tr>
<tr><td>LBU loaded bit 7 set</td><td class="n bad">0</td><td class="n">4</td><td class="n">0 (no loads)</td><td class="n">18</td></tr>
<tr><td>Holes in this run</td><td class="n bad">yes</td><td class="n bad">yes</td><td class="n bad">yes (loads)</td><td class="n good">none</td></tr></table>
<div class="callout d">Closure loop that fixed the SLT escape: <b>Y1 caught 5/6</b> → coverage showed SLT sign corners at 0 in the escaped run → added the <code>cmp</code> test → merged holes 0 → <b>Y1 caught 9/9</b>.</div>""",
deep=[
 "<b>Instruction × operand class</b> (zero, ±1, max, min, sign mix) for every compare, shift and add. That is where Y1, Y2 and B14 live.",
 "<b>Hazard crosses</b>: producer type × distance × consumer operand × same-rd chains (PL-12). Control: branch type × taken × predicted × resolved-wrong.",
 "<b>Protocol timing</b>: delay 0 / 1 / long on each interface × instruction class (load stalled while... ), back-to-back handshakes, ready without request.",
 "<b>Microarchitecture state</b>: queue full / empty / wrap for ROB, RS, LSQ; every FSM state × input; flush arriving in every state.",
 "<b>Coverage ≠ checking</b>: a hit bin only says the situation occurred. Pair it with a checker that would fail there (mutation testing proves that, PL-24).",
 "<b>Per-test holes are fine</b>: the cmp test has no loads, and mem has few compares. Sign-off uses merged regression coverage.",
],
rules=[
 "Each coverage point maps to a plan item, and each hole is closed or waived with a reason.",
 "Sample coverage at the same event the checker uses (retire), with pre-instruction operand values.",
],
bugs=[
 "Escape: Y1 missed in the mem run because SLT never saw mixed signs.",
 "Hidden hole: SLTU with bit 31 set was 0 in every default and mem run; nobody had looked.",
],
ask=[
 ("Q: 100% code coverage. Is the design verified?",
  "No. Code coverage says each line toggled, not that it was checked, or that the right combinations happened. Y1's buggy line executed in every run; only the sign-mixed operands exposed it. Use functional coverage of the corners plus checkers, plus mutation to prove the checkers fire."),
]))

# ---------------------------------------------------------------- PL-24
PLATES.append(dict(id="p24", part="IV", short="Mutation testing",
title="Qualifying the testbench: mutation testing",
thesis="Put known bugs into the RTL and see if the testbench notices. It is the only direct measure of checker strength, and it found five testbench weaknesses that passing tests had hidden.",
fig="""
<table class="grid"><tr><th>#</th><th>Injected bug</th><th>Original TB<br>real / false / hung</th><th class="n">Fixed TB</th><th>By</th></tr>
<tr><td>0</td><td>none</td><td>0 / <b class="bad">4</b> / 0</td><td class="n good">0/9</td><td>–</td></tr>
<tr><td>1</td><td>SLT magnitude</td><td>3 / 3 / 0</td><td class="n good">9/9</td><td>reg</td></tr>
<tr><td>2</td><td>branch signedness</td><td class="bad">0 / 4 / 0</td><td class="n good">9/9</td><td>PC</td></tr>
<tr><td>3</td><td>JALR phantom load</td><td>9 / 1 / 0</td><td class="n good">9/9</td><td>mem</td></tr>
<tr><td>4</td><td>no instr latch</td><td class="bad">0 / 0 / 10</td><td class="n">6/9</td><td>SVA R4</td></tr>
<tr><td>5</td><td>fetch while pending</td><td class="bad">0 / 4 / 0</td><td class="n">6/9</td><td>SVA R10</td></tr>
<tr><td>6</td><td>PC ignores ready</td><td>10 / 0 / 0</td><td class="n good">9/9</td><td>SVA R2</td></tr>
<tr><td>7</td><td>load retires early</td><td>9 / 1 / 0</td><td class="n">6/9</td><td>PC</td></tr>
<tr><td>8</td><td>SUB as ADD</td><td class="bad">0 / 4 / 0</td><td class="n">6/9</td><td>reg</td></tr>
<tr><td>9</td><td>LBU sign-extends</td><td class="bad">0 / 4 / 0</td><td class="n">3/9</td><td>reg (mem test)</td></tr></table>
<p class="tm" style="margin:6px 0 0;font-size:12px">Original: 50 instr × 10 seeds. Fixed: 500 instr × {default, mem, cmp} × 3 seeds. Every mutant is caught by the fixed regression; misses are tests that by design have no loads (cmp) or no SUB.</p>""",
deep=[
 "<b>Run the clean design first</b>: the original TB failed 4/10 seeds on correct RTL (misalignment $fatal). A testbench with false failures trains people to rerun until green.",
 "<b>Classify each failure</b>: real mismatch vs TB crash vs hang. Counting all three as \"detected\" inflates the score; the original TB's hangs and $fatals were not detection.",
 "<b>One build, runtime select</b>: <code>+MUT=n</code> picks the bug, so 10 mutants cost 2 builds instead of 20 (the first attempt hung for an hour rebuilding per mutant, without a watchdog).",
 "<b>Pick mutants like real bugs</b>: signedness, missing gating, wrong default, dropped latch, protocol shortcut. Random operator flips mostly produce instantly obvious failures.",
 "<b>A surviving mutant is a plan item</b>: either a missing checker (P2 → SVA), missing stimulus (Y1 → cmp test, P6 → mem test), or an equivalent mutant (then document it).",
],
rules=[
 "Mutation score is per regression, not per test.",
 "Every surviving mutant gets a reason: fixed, equivalent, or waived.",
],
bugs=[
 "TB weaknesses found this way: weak stimulus (T1), broken store path (D2), early end (A1), no SVA (P2), no watchdog (W1).",
],
ask=[
 ("Q: How do you know your testbench is good enough?",
  "Coverage says what was exercised; mutation says what would be noticed. I inject realistic bugs, require the regression to catch every one with zero false failures on clean RTL, and treat each survivor as a missing checker or stimulus. On YARP that took detection from 4 of 9 bugs to 9 of 9."),
]))
