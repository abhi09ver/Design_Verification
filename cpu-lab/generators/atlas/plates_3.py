PLATES = []

# ---------------------------------------------------------------- PL-10
PLATES.append(dict(id="p10", part="III", short="Performance",
title="The performance equation",
thesis="Time = instructions × CPI × clock period. Every microarchitecture idea attacks one factor and usually hurts another. Performance verification checks that the cycle count matches the model, not just the answers.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 150" role="img" aria-label="Iron law of performance">
 <text class="th" x="10" y="30" style="font-size:22px">CPU time = IC × CPI × T<tspan class="tm" style="font-size:12px" dx="12">(the iron law)</tspan></text>
 <rect class="boxw" x="10" y="50" width="190" height="90" rx="4"/><text class="th" x="22" y="72">IC</text><text class="tm" x="22" y="92">ISA + compiler</text><text class="tm" x="22" y="108">C ext: same IC, smaller code</text><text class="tm" x="22" y="124">M ext: far lower IC for mul</text>
 <rect class="boxa" x="215" y="50" width="190" height="90" rx="4"/><text class="th" x="227" y="72">CPI</text><text class="tm" x="227" y="92">hazards, stalls, misses</text><text class="tm" x="227" y="108">pipeline → ~1, OOO/superscalar</text><text class="tm" x="227" y="124">→ &lt; 1 (IPC &gt; 1)</text>
 <rect class="boxw" x="420" y="50" width="190" height="90" rx="4"/><text class="th" x="432" y="72">T</text><text class="tm" x="432" y="92">critical path per stage</text><text class="tm" x="432" y="108">single-cycle: whole datapath</text><text class="tm" x="432" y="124">5-stage: ≈ slowest stage</text>
</svg></div>
<table class="grid"><tr><th>pq5 program</th><th class="n">N</th><th class="n">stalls</th><th class="n">flushes</th><th class="n">4+N+s+2f</th><th class="n">measured</th><th class="n">CPI</th></tr>
<tr><td>p01_alu</td><td class="n">23</td><td class="n">0</td><td class="n">0</td><td class="n">27</td><td class="n">27</td><td class="n">1.17</td></tr>
<tr><td>p02_forwarding</td><td class="n">14</td><td class="n">0</td><td class="n">0</td><td class="n">18</td><td class="n">18</td><td class="n">1.29</td></tr></table>
<div class="callout d">Formula checked against every pq5 run: <b>cycles = 4 + N + load-use stalls + 2 × flushes</b> (pipeline fill = 4, mispredict penalty = 2 because branches resolve in EX). Removing branch prediction failed <b>no</b> functional test but raised CPI to 1.66 on a loop. Only a cycle check catches that.</div>""",
deep=[
 "<b>Single-cycle</b>: CPI = 1, T = the whole datapath. <b>5-stage</b>: CPI ≈ 1 + stall rate, T ≈ ⅕. <b>OOO superscalar</b>: CPI &lt; 1, with T bounded by wakeup/select and bypass loops.",
 "<b>Amdahl</b>: speedup = 1 / ((1−f) + f/s). Halving the latency of an op used 10% of the time buys at most 5%.",
 "<b>Performance bugs are silent.</b> A predictor that never predicts, a BTB that evicts the wrong way (<b>B15</b>) or a stall that is one cycle too long all pass every functional test.",
 "<b>How to verify performance</b>: a cycle-approximate model or analytic formula per microbenchmark, assertions on bounded latencies (e.g. \"a load-use stall lasts exactly 1 cycle\"), and trend checks of CPI per test in regression.",
],
rules=[
 "The ISA says nothing about timing: performance is a design spec, so write it down (latencies, penalties, throughput).",
 "Measure CPI with the same retire event the scoreboard uses.",
],
bugs=[
 "<span class='tag t-bug'>B15</span> BTB replacement evicted the most recent entry and never used a free way. Found by unit test, invisible functionally.",
 "pq5 mutant \"no branch prediction\": 0/10 directed and 0/100 random fail, yet p04_loop_sum CPI rose to 1.66 (p09_multiply 1.48).",
],
ask=[
 ("Q: All tests pass. How would you find a performance bug?",
  "Compare cycle counts to an expected model per directed microbenchmark (loop, pointer chase, branchy code), assert latency bounds with SVA, and track CPI per test across regressions so a jump flags a change."),
]))

# ---------------------------------------------------------------- PL-11
PLATES.append(dict(id="p11", part="III", short="5-stage pipe",
title="The 5-stage pipeline",
thesis="Cut the single-cycle path into IF, ID, EX, MEM and WB with registers between them. Five instructions are in flight, and correctness now depends on the timing between them.",
fig="""
<div class="scroll"><table class="grid" style="font-family:var(--f-mono);font-size:12px;min-width:560px">
<tr><th>instr \\ cycle</th><th>1</th><th>2</th><th>3</th><th>4</th><th>5</th><th>6</th><th>7</th><th>8</th><th>9</th></tr>
<tr><td>i1 add x5,…</td><td>IF</td><td>ID</td><td>EX</td><td>MEM</td><td>WB</td><td></td><td></td><td></td><td></td></tr>
<tr><td>i2 sub …,x5</td><td></td><td>IF</td><td>ID</td><td class="good">EX ◀ fwd</td><td>MEM</td><td>WB</td><td></td><td></td><td></td></tr>
<tr><td>i3 lw x6,0(x5)</td><td></td><td></td><td>IF</td><td>ID</td><td>EX</td><td>MEM</td><td>WB</td><td></td><td></td></tr>
<tr><td>i4 add …,x6</td><td></td><td></td><td></td><td>IF</td><td>ID</td><td class="bad">stall</td><td class="good">EX ◀ fwd</td><td>MEM</td><td>WB</td></tr>
<tr><td>i5 beq taken</td><td></td><td></td><td></td><td></td><td>IF</td><td>IF</td><td>ID</td><td>EX ✱</td><td>MEM</td></tr>
</table></div>
<div class="scroll"><svg viewBox="0 0 620 120" style="margin-top:10px" role="img" aria-label="Pipeline registers with valid, stall and flush">
 <g><rect class="boxa" x="10" y="30" width="80" height="44" rx="3"/><text class="th" x="36" y="57">IF</text>
 <rect class="boxw" x="98" y="26" width="14" height="52"/>
 <rect class="boxa" x="120" y="30" width="80" height="44" rx="3"/><text class="th" x="146" y="57">ID</text>
 <rect class="boxw" x="208" y="26" width="14" height="52"/>
 <rect class="boxa" x="230" y="30" width="80" height="44" rx="3"/><text class="th" x="256" y="57">EX</text>
 <rect class="boxw" x="318" y="26" width="14" height="52"/>
 <rect class="boxa" x="340" y="30" width="80" height="44" rx="3"/><text class="th" x="358" y="57">MEM</text>
 <rect class="boxw" x="428" y="26" width="14" height="52"/>
 <rect class="boxa" x="450" y="30" width="80" height="44" rx="3"/><text class="th" x="474" y="57">WB</text></g>
 <path class="wb" d="M160 90 V100 H50 V78"/><text class="bugf" x="56" y="114" style="font-size:11px">stall (load-use): hold IF, ID; bubble into EX</text>
 <path class="wd" d="M270 20 V12 H50 V26"/><text class="dvf" x="300" y="16" style="font-size:11px">flush + redirect_pc from EX (wrong prediction)</text>
 <text class="tm" x="545" y="50">packet =</text><text class="tm" x="545" y="64">{valid, pc,</text><text class="tm" x="545" y="78">ctl, data}</text>
</svg></div>""",
deep=[
 "<b>Every stage register carries a valid bit.</b> valid=0 is a bubble. A flush clears valid; a stall holds the register and injects valid=0 downstream. Forgetting to clear valid in one register is the classic flush bug: pq5 failed 98/100 random tests when either IF/ID or ID was left unflushed.",
 "<b>Fill latency</b>: with no hazards N instructions take Δ + N − 1 = N + 4 cycles (Δ = 5 stages).",
 "<b>Structural hazards are removed by design</b>: separate instruction and data memory, a 2-read/1-write regfile, and the PC adder separate from the ALU.",
 "<b>WAR and WAW cannot happen</b> in an in-order pipeline where the write always happens in the last stage. RAW is the only data hazard (PL-12).",
 "<b>Stall vs flush in the same cycle</b>: flush must win (the stalled instruction is on the wrong path). pq5 also proves that it cannot happen, with assertion <code>a_noflushstall</code>.",
],
rules=[
 "Commit order = program order, one retire per cycle at most.",
 "A flushed instruction must have no architectural effect: no rf write, no store, no CSR change.",
],
bugs=[
 "pq5 mutant: flush forgets IF/ID → 6/10 directed, 98/100 random fail.",
 "pq5 mutant: x0 writable → 54/100 random fail (it shows up when a later instruction forwards x0).",
 "<span class='tag t-bug'>B09</span> Tomasulo frontend ignored back-pressure and replayed stale bundles: the commit stream was no longer the program.",
],
ask=[
 ("Q: What does the scoreboard compare for a pipelined core?",
  "The same thing as for a single-cycle one: the retire stream (pc, instr, rd, wdata, mem ops) in order against the ISS. Pipelining changes when instructions retire, not what they do, so the checker sits at retire and ignores timing."),
]))

# ---------------------------------------------------------------- PL-12
PLATES.append(dict(id="p12", part="III", short="Data hazards",
title="Data hazards: forwarding and the load-use stall",
thesis="A result exists before it is written back. Forwarding passes it backwards to the instruction that needs it; the one thing it cannot do is go backwards in time, which costs a load-use bubble.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 210" role="img" aria-label="Forwarding paths">
 <rect class="boxa" x="20" y="60" width="110" height="60" rx="3"/><text class="th" x="54" y="95">ID</text>
 <rect class="boxa" x="180" y="60" width="110" height="60" rx="3"/><text class="th" x="214" y="95">EX</text>
 <rect class="boxa" x="340" y="60" width="110" height="60" rx="3"/><text class="th" x="370" y="95">MEM</text>
 <rect class="boxa" x="500" y="60" width="110" height="60" rx="3"/><text class="th" x="534" y="95">WB</text>
 <path class="wd" d="M395 60 V36 H235 V60"/><text class="dvf" x="256" y="30" style="font-size:11px">dist 1: EX/MEM → EX (wins)</text>
 <path class="wd" d="M555 60 V14 H215 V60"/><text class="dvf" x="380" y="10" style="font-size:11px">dist 2: MEM/WB → EX</text>
 <path class="wd" d="M555 120 V150 H75 V120"/><text class="dvf" x="230" y="146" style="font-size:11px">dist 3: rf write-first (or WB → ID bypass)</text>
 <path class="wb" d="M395 120 V180 H235 V120"/><text class="bugf" x="250" y="196" style="font-size:11px">load in MEM → EX: value not ready → stall 1</text>
</svg></div>
<table class="grid"><tr><th>pq5: remove one mechanism</th><th class="n">directed fail</th><th class="n">random fail</th></tr>
<tr><td>no forward from MEM (dist 1)</td><td class="n">9/10</td><td class="n">100/100</td></tr>
<tr><td>no forward from WB (dist 2)</td><td class="n">9/10</td><td class="n">57/100</td></tr>
<tr><td>no write-through (dist 3)</td><td class="n">7/10</td><td class="n">54/100</td></tr>
<tr><td>no load-use stall</td><td class="n">2/10</td><td class="n">26/100</td></tr>
<tr><td class="bad">forwarding priority reversed</td><td class="n bad">2/10</td><td class="n bad">5/100</td></tr></table>""",
deep=[
 "<b>Forward condition</b> per operand: <code>valid &amp;&amp; wr_en &amp;&amp; rd != 0 &amp;&amp; rd == rs</code>. Every term is a bug if missing: invalid (flushed) producer, a store or branch (no write), x0, wrong register.",
 "<b>Priority</b>: if two older instructions write the same register, the nearer one is newer. Reversing the priority fails only 5/100 random programs, so it needs a directed \"write x5 three times then read\" test or a coverage cross on (distance × same-rd).",
 "<b>Load-use</b>: the loaded value exists at the end of MEM; the next instruction needs it at the start of EX. One bubble, detected in ID: <code>EX.is_load &amp;&amp; EX.rd != 0 &amp;&amp; EX.rd ∈ {ID.rs1, ID.rs2}</code>.",
 "<b>Redundant guards can be proven</b>: pq5's \"don't forward a load's address from MEM\" guard is unreachable because the interlock already stalls. The assertion <code>a_loaduse</code> proves it.",
 "<b>Store data is an operand too</b>: rs2 of a store needs forwarding exactly like an ALU operand, and so does the branch compare in EX.",
],
rules=[
 "Read-after-write must observe the latest older write in program order.",
 "The x0 source always reads 0, regardless of any in-flight write to x0.",
],
bugs=[
 "Forwarding priority reversed: passes 95% of random tests.",
 "Forwarding from a flushed (valid=0) instruction: a wrong-path value leaks into the right path.",
 "Store data (rs2) not forwarded: the store writes a stale value; only a later load sees it.",
],
ask=[
 ("Q: How do you make sure forwarding is fully covered?",
  "Cross producer type (ALU, load, jal link) × distance (1, 2, 3, 4+) × consumer operand (rs1, rs2, store data, branch) × same-rd collisions. Random programs with a small register pool (e.g. only x1–x6) hit it fast. Close the holes with directed sequences."),
]))

# ---------------------------------------------------------------- PL-13
PLATES.append(dict(id="p13", part="III", short="Control hazards",
title="Control hazards and branch prediction",
thesis="Fetch has to guess the next PC before the branch is decoded. Correctness requires only that a wrong guess be squashed completely; performance is how rarely you guess wrong.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 200" role="img" aria-label="Prediction structures">
 <rect class="boxa" x="10" y="20" width="140" height="60" rx="3"/><text class="th" x="22" y="44">Static</text><text class="tm" x="22" y="64">BTFN: backward taken,</text><text class="tm" x="22" y="76">forward not taken</text>
 <rect class="boxa" x="165" y="20" width="140" height="60" rx="3"/><text class="th" x="177" y="44">BHT</text><text class="tm" x="177" y="64">2-bit counters,</text><text class="tm" x="177" y="76">gshare (pc ⊕ history)</text>
 <rect class="boxa" x="320" y="20" width="140" height="60" rx="3"/><text class="th" x="332" y="44">BTB</text><text class="tm" x="332" y="64">pc → target,</text><text class="tm" x="332" y="76">tagged, set-assoc</text>
 <rect class="boxa" x="475" y="20" width="135" height="60" rx="3"/><text class="th" x="487" y="44">RAS</text><text class="tm" x="487" y="64">return stack for</text><text class="tm" x="487" y="76">jalr ra (ret)</text>
 <rect class="boxr" x="10" y="100" width="600" height="90" rx="4"/>
 <text class="th" x="22" y="122">One check catches every kind of wrong guess</text>
 <text class="t tmono" x="22" y="144">carry pred_npc with the instruction; in EX:</text>
 <text class="t tmono" x="22" y="162">if (real_npc != pred_npc) flush younger, redirect pc ← real_npc</text>
 <text class="tm" x="22" y="182">covers wrong direction, wrong target, unpredicted jalr and an aliased BTB hit on a non-branch</text>
</svg></div>""",
deep=[
 "<b>Penalty = depth of resolution.</b> Resolving in EX costs 2 (pq5); resolving in ID costs 1 but needs a comparator plus forwarding into ID. Deep OOO cores pay 10–20 cycles, which is why predictors are large.",
 "<b>Recovery must undo speculative state</b>: in-order cores clear valid bits; OOO cores also restore the rename map (checkpoint or ROB walk), free physical registers, kill younger LSQ entries and repair the global history.",
 "<b>Predictor bugs are mostly performance bugs</b>, unless the predictor can produce a target that is never checked (e.g. a non-branch predicted taken, with no check in EX).",
 "<b>DV for prediction</b>: functional (every mispredict flushes completely), then performance (accuracy on known patterns: loops, alternating, correlated), then unit tests of replacement, aliasing and counter saturation.",
],
rules=[
 "Prediction is invisible to the ISA: wrong-path instructions must never retire or change memory.",
 "A taken branch/jump to a misaligned target traps on the branch itself (no C).",
],
bugs=[
 "<span class='tag t-bug'>B15</span> BTB PLRU evicted the newest entry and ignored a free way.",
 "Mispredict in the same cycle as an older load-use stall: the stall holds the wrong-path instruction.",
 "RAS not repaired after a mispredicted call: every later return mispredicts (performance only).",
],
ask=[
 ("Q: How do you verify that a mispredict leaves no trace?",
  "Directed: branch to code that would store or write registers on the wrong path, then check memory and the regfile. Random: lockstep ISS at retire, plus an SVA that nothing retires with a flushed ID, plus coverage of mispredict × wrong-path instruction type (store, load, CSR, branch)."),
]))

# ---------------------------------------------------------------- PL-14
PLATES.append(dict(id="p14", part="III", short="Out-of-order",
title="Out-of-order core: rename, issue, commit",
thesis="Issue instructions when their operands are ready, not in program order, then retire in program order so software never notices. The ROB is the bridge between the two orders.",
fig="""
<div class="scroll"><svg viewBox="0 0 640 270" role="img" aria-label="Tomasulo with reorder buffer">
 <rect class="boxa" x="10" y="20" width="90" height="56" rx="3"/><text class="th" x="22" y="44">Fetch</text><text class="tm" x="22" y="62">+ predict</text>
 <rect class="boxa" x="120" y="20" width="120" height="56" rx="3"/><text class="th" x="132" y="44">Rename</text><text class="tm" x="132" y="62">RAT: reg → tag</text>
 <rect class="box" x="260" y="10" width="150" height="76" rx="3"/><text class="th" x="272" y="32">Reservation stns</text><text class="tm" x="272" y="50">wait for tags</text><text class="tm" x="272" y="66">select oldest-ready</text>
 <rect class="box" x="430" y="10" width="90" height="34" rx="3"/><text class="t tb" x="442" y="32">ALU ×n</text>
 <rect class="box" x="430" y="52" width="90" height="34" rx="3"/><text class="t tb" x="442" y="74">MUL/DIV</text>
 <rect class="box" x="540" y="10" width="90" height="76" rx="3"/><text class="t tb" x="552" y="32">LSQ</text><text class="tm" x="552" y="52">PL-15</text>
 <path class="w" d="M100 48 H120"/><path class="w" d="M240 48 H260"/><path class="w" d="M410 27 H430"/><path class="w" d="M410 69 H430"/>
 <path class="wd" d="M475 86 V118"/><path class="wd" d="M585 86 V118"/>
 <rect class="boxd" x="10" y="118" width="620" height="30" rx="3"/><text class="dvf tb" x="22" y="138">CDB: broadcast {tag, value} → RS wakeup + ROB fill</text>
 <path class="wd" d="M335 118 V86"/>
 <rect class="boxa" x="120" y="170" width="510" height="56" rx="3"/>
 <text class="th" x="132" y="192">ROB (program order)</text>
 <g class="tmono"><rect class="boxw" x="310" y="180" width="60" height="36"/><text class="t" x="320" y="202">head</text>
 <rect class="boxw" x="370" y="180" width="60" height="36"/><rect class="boxw" x="430" y="180" width="60" height="36"/><rect class="boxw" x="490" y="180" width="60" height="36"/>
 <rect class="boxw" x="550" y="180" width="60" height="36"/><text class="t" x="560" y="202">tail</text></g>
 <path class="wa" d="M180 76 V170"/><text class="tm" x="186" y="160">allocate</text>
 <path class="wa" d="M340 226 V250 H40"/><text class="t" x="44" y="264">commit in order → ARF, stores drain, exceptions taken here</text>
</svg></div>""",
deep=[
 "<b>Renaming removes WAR and WAW</b>: each destination gets a fresh tag (ROB entry or physical register). Only true RAW dependences remain.",
 "<b>Wakeup/select is the critical loop</b>: the CDB tag compares against every RS source, and back-to-back dependent issue needs wakeup and select in one cycle. Tag width and CDB count bound IPC.",
 "<b>Tag 0 is a real tag.</b> Using 0 as \"no tag\" while also allocating ROB entry 0 means one entry can never be woken. Tomasulo lab bug <b>B04</b>: a deadlock that only shows when entry 0 is used for a long-latency op.",
 "<b>Free-list consistency</b>: two structures tracking the same resource (a dispatch free-list vs busy bits) will drift. Lab bug <b>B12</b> failed 79 of 120 random seeds before the fix.",
 "<b>Commit is where correctness is defined</b>: the scoreboard compares the commit stream, exceptions and interrupts are taken at the head, and stores leave the core only after commit.",
 "<b>Mispredict recovery</b>: squash everything younger than the branch in ROB, RS and LSQ; restore the RAT (checkpoint at the branch, or walk the ROB); free the tags.",
],
rules=[
 "Retire order = program order; retired state is always a precise architectural state.",
 "No younger instruction may make a visible change before an older one retires (stores, CSRs, I/O loads).",
],
bugs=[
 "<span class='tag t-bug'>B04</span> ROB tag 0 could never be woken: deadlock.",
 "<span class='tag t-bug'>B05</span> A second DIV overwrote the first in the divider: deadlock and lost result.",
 "<span class='tag t-bug'>B11</span> MMU consumed one load-buffer entry twice. Caught by SVA A7 on the program that \"passed\".",
 "<span class='tag t-bug'>B12</span> Dispatch free-list disagreed with busy bits: 79/120 random seeds failed.",
],
ask=[
 ("Q: What do you check in an OOO core beyond the commit stream?",
  "Liveness (every allocated ROB entry eventually retires: watchdog plus SVA), resource conservation (free + used = total for ROB, RS, physical registers, LSQ, every cycle), uniqueness (no tag in two places), and no wakeup for a tag that is not in flight. Those are what found B04, B05, B11 and B12."),
]))

# ---------------------------------------------------------------- PL-15
PLATES.append(dict(id="p15", part="III", short="LSQ & memory order",
title="Load/store queue and memory disambiguation",
thesis="Registers are renamed but memory is not. A load that runs ahead of an older store to the same address reads stale data, unless the LSQ catches it.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 230" role="img" aria-label="Store to load forwarding">
 <text class="th" x="10" y="20">Store queue (oldest → youngest)</text>
 <g class="tmono">
  <rect class="boxw" x="10" y="30" width="140" height="44"/><text class="t" x="18" y="50">sw 0x100 ← A</text><text class="tm" x="18" y="66">committed (senior)</text>
  <rect class="boxw" x="150" y="30" width="140" height="44"/><text class="t" x="158" y="50">sw 0x104 ← B</text><text class="tm" x="158" y="66">addr known</text>
  <rect class="boxb" x="290" y="30" width="140" height="44"/><text class="t" x="298" y="50">sw ??? ← C</text><text class="bugf" x="298" y="66" style="font-size:11px">addr unknown</text>
 </g>
 <rect class="boxa" x="460" y="30" width="150" height="44" rx="3"/><text class="t tmono" x="468" y="50">lw 0x104</text><text class="tm" x="468" y="66">younger load</text>
 <path class="wd" d="M535 74 V88 H220 V74"/><text class="dvf" x="300" y="102" style="font-size:11px">search older stores, youngest first</text>
 <rect class="boxr" x="10" y="110" width="600" height="112" rx="4"/>
 <text class="t" x="22" y="132"><tspan class="tb">Match, full overlap</tspan>  → forward store data (B)</text>
 <text class="t" x="22" y="152"><tspan class="tb">Partial overlap</tspan> (sb into a lw) → wait for the store to drain, or merge bytes</text>
 <text class="t" x="22" y="172"><tspan class="tb">Older address unknown</tspan> (C) → wait (conservative) or speculate</text>
 <text class="t" x="22" y="192"><tspan class="tb">Speculate</tspan> → when C resolves to 0x104, detect the violation and replay the load + younger</text>
 <text class="tm" x="22" y="212">No match → read the cache. Stores write memory only after commit.</text>
</svg></div>""",
deep=[
 "<b>Senior stores</b>: a committed store still in the queue is architecturally done but not yet in memory. Loads must still see it, flushes must not kill it, and a reset or flush that drops it loses data (lab <b>B13</b>, distilled into <code>b19_senior_store</code>).",
 "<b>Byte-level overlap</b>: compare address <i>and</i> size. sb 0x101 then lw 0x100 overlaps one byte. Comparing word addresses only forwards the whole word: wrong.",
 "<b>Ordering inside the LSQ</b>: the youngest older store wins. Multiple loads to one address must each complete (lab <b>B08</b>: the third load was marked done and never broadcast).",
 "<b>Memory consistency</b>: single-core needs program-order semantics for one hart. Multi-core RVWMO allows more reordering, but FENCE must restore order, and atomics (A ext) need LR/SC reservation rules.",
 "<b>DV stimulus</b>: small address pools (8–16 lines), mixed sizes and offsets, stores with late addresses (dependent on a slow divide), and many loads in flight. That is how B07 and B13 were found by random before directed tests existed.",
],
rules=[
 "A load returns the value of the youngest older store to each byte, else memory.",
 "Stores are not visible outside the core until commit.",
 "FENCE orders memory operations as specified (predecessor/successor sets).",
],
bugs=[
 "<span class='tag t-bug'>B07</span> Loads ignored older stores (no disambiguation): wrong data on aliasing.",
 "<span class='tag t-bug'>B08</span> The third load to one address never broadcast: deadlock.",
 "<span class='tag t-bug'>B13</span> Store-queue ordering: deadlocks, orphaned and bypassed stores.",
],
ask=[
 ("Q: How would you stress an LSQ?",
  "Constrain addresses to a few lines so aliasing is common, mix byte/half/word at all offsets, make store addresses depend on long-latency ops so loads run ahead, and fill the queues (back-pressure). Check with the ISS at commit, plus SVA that the store queue drains in order and nothing is lost on a flush."),
]))

# ---------------------------------------------------------------- PL-16
PLATES.append(dict(id="p16", part="III", short="Caches & VM",
title="Memory hierarchy: caches, coherence, translation",
thesis="Caches and TLBs must be invisible to the ISA except for timing. Verifying them is mostly about proving that invisibility under replacement, races and multiple masters.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 220" role="img" aria-label="Cache address breakdown and MESI">
 <text class="th" x="10" y="20">Address split (32 KiB, 4-way, 64 B lines)</text>
 <g class="tmono"><rect class="boxa" x="10" y="30" width="300" height="34"/><text class="acc" x="120" y="52">tag [31:13]</text>
 <rect class="boxw" x="310" y="30" width="140" height="34"/><text class="t" x="340" y="52">index [12:6]</text>
 <rect class="boxr" x="450" y="30" width="160" height="34"/><text class="t" x="480" y="52">offset [5:0]</text></g>
 <text class="tm" x="10" y="82">sets = 32K / (64 × 4) = 128 → 7 index bits; tag = 32 − 7 − 6 = 19 bits</text>
 <text class="th" x="10" y="112">MESI (per line, per core)</text>
 <g><rect class="boxd" x="10" y="124" width="110" height="40" rx="3"/><text class="t tb" x="18" y="149">M modified</text>
 <rect class="boxd" x="140" y="124" width="110" height="40" rx="3"/><text class="t tb" x="148" y="149">E exclusive</text>
 <rect class="boxd" x="270" y="124" width="110" height="40" rx="3"/><text class="t tb" x="278" y="149">S shared</text>
 <rect class="boxw" x="400" y="124" width="110" height="40" rx="3"/><text class="t tb" x="408" y="149">I invalid</text></g>
 <text class="tm" x="10" y="186">invariant: one M or E holder per line, or any number of S; a write needs M (invalidate the others first)</text>
 <text class="tm" x="10" y="206">AMAT = hit time + miss rate × miss penalty   ·   misses: compulsory, capacity, conflict (+ coherence)</text>
</svg></div>""",
deep=[
 "<b>Write-back + write-allocate</b> is the usual L1D. A dirty line must be written back before eviction, and an eviction racing a read of the same line is a classic corner.",
 "<b>Replacement</b>: LRU, PLRU or random never change results, only timing. A broken replacement policy is a performance bug, unless it evicts a line with a pending fill.",
 "<b>Coherence verification</b> = invariants plus a golden memory: single-writer/multiple-reader per line, data value = last write in a global order, no lost writebacks. Use formal on the protocol tables and random with heavy line sharing.",
 "<b>Virtual memory (Sv32)</b>: 2-level page walk, PTE V/R/W/X/U/A/D bits, page faults (cause 12/13/15). TLB bugs: stale entries after <code>sfence.vma</code>, a missed A/D update, wrong permission on superpages.",
 "<b>Self-modifying code</b>: instruction fetch may be stale after a store until <code>fence.i</code> (Zifencei). The ISS and the DUT must agree on when the new code becomes visible.",
],
rules=[
 "Without fences, a single hart still sees its own stores in program order.",
 "Caches are architecturally invisible: a timing difference only.",
 "<code>fence.i</code> synchronises the instruction and data streams of one hart.",
],
bugs=[
 "Eviction of a dirty line racing a new miss to the same set: the writeback uses the new tag.",
 "A snoop hit on a line in transit (fill pending): a stale S state.",
 "<code>sfence.vma</code> doesn't flush the global entries the spec requires: stale translation.",
],
ask=[
 ("Q: How do you verify a cache you can't see from the ISA?",
  "Reference memory model at the cache boundary (every load returns the latest write), invariants as SVA (one owner, dirty implies valid, no hit on two ways), stimulus that forces conflict misses (addresses mapping to one set) and back-to-back evict/refill, and coverage of every state-transition × request type."),
]))
