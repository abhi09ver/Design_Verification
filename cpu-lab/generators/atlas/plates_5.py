PLATES = []

# ---------------------------------------------------------------- PL-25
PLATES.append(dict(id="p25", part="V", short="Bug catalog",
title="Bug catalog: symptom → cause → what caught it",
thesis="Interviewers ask for bug stories. These are real ones from three cores and one testbench, grouped by the mechanism that failed. Learn the pattern, not the instance.",
fig="""
<div class="scroll"><table class="grid" style="min-width:600px">
<tr><th>Pattern</th><th>Bug</th><th>Symptom</th><th>Caught by</th></tr>
<tr><td rowspan="3"><b>Signedness</b></td><td>Y1 SLT |a|&lt;|b|</td><td>wrong 0/1 on mixed signs</td><td>ISS + sign coverage</td></tr>
<tr><td>Y2 branch compares</td><td>wrong path</td><td>ISS PC compare</td></tr>
<tr><td>B02 zero-ext imm</td><td>addi −1 → 0xFFF</td><td>directed</td></tr>
<tr><td rowspan="2"><b>Missing gate</b></td><td>Y4 first-cycle write</td><td>first instr ×2</td><td>hostile imem</td></tr>
<tr><td>Y3 JALR data_req</td><td>phantom load</td><td>mem-access compare</td></tr>
<tr><td rowspan="3"><b>Lost / never woken</b></td><td>B04 ROB tag 0</td><td>deadlock</td><td>watchdog, liveness SVA</td></tr>
<tr><td>B08 3rd load to addr</td><td>deadlock</td><td>directed distillation</td></tr>
<tr><td>B05 2nd DIV overwrites</td><td>deadlock</td><td>directed</td></tr>
<tr><td rowspan="2"><b>Two sources of truth</b></td><td>B12 free-list vs busy</td><td>random deadlock</td><td>random (79/120 seeds)</td></tr>
<tr><td>B11 entry consumed twice</td><td>passes, but SVA</td><td>uniqueness SVA</td></tr>
<tr><td rowspan="2"><b>Ordering</b></td><td>B07 no disambiguation</td><td>stale load data</td><td>random aliasing</td></tr>
<tr><td>B13 store queue</td><td>orphan / bypassed store</td><td>random → b18, b19</td></tr>
<tr><td><b>Corner value</b></td><td>B14 Booth −2³¹</td><td>wrong product</td><td>random seed r13</td></tr>
<tr><td><b>Spec table</b></td><td>B06 x/0</td><td>+1 not −1</td><td>ISS (spec table)</td></tr>
<tr><td><b>Performance</b></td><td>B15 BTB PLRU</td><td>none functionally</td><td>unit test</td></tr>
<tr><td rowspan="4"><b>Testbench</b></td><td>D2 stale cb sample</td><td>stores lost</td><td>mem-heavy test</td></tr>
<tr><td>T1 opcode skew</td><td>everything "passes"</td><td>histogram</td></tr>
<tr><td>A1 early end of test</td><td>false fail / unchecked</td><td>log forensics</td></tr>
<tr><td>M1 misaligned $fatal</td><td>40% false fails</td><td>clean-RTL mutant 0</td></tr>
</table></div>""",
deep=[
 "<b>Telling a bug story</b>: symptom (what failed, where), first divergence (cycle, instruction), root cause (the line and why), fix, and the lesson (what checker or coverage now prevents the class). 60–90 seconds.",
 "<b>Most valuable stories show judgment</b>: a pass that was hiding a bug (T1 + D2), a fail that was the testbench (A1), a bug no result exposes (P2 → SVA), and a random failure distilled into a 10-instruction directed test (B13 → b19).",
 "<b>Deadlocks</b> (B04, B05, B08, B12) all share one shape: a resource or event is lost and something waits forever. That is why liveness watchdogs and conservation assertions find them by the dozen.",
 "<b>The cheapest bugs to find are at the interface</b> (Y3, D2): compare every transaction, not just the end state.",
],
rules=[
 "Every fixed bug gets a regression test, ideally the minimal distilled one.",
 "Every escape gets a post-mortem: which checker, coverage or stimulus would have caught it?",
],
bugs=[
 "IDs: Y = YARP RTL, B = Tomasulo core, T/D/M/A/S/W = YARP course testbench, P = injected mutants.",
],
ask=[
 ("Q: Tell me about the hardest bug you found.",
  "B14: random seed r13 failed on mulh of (−2³¹)×(−2³¹): RTL 0xC0000000, ISS 0x40000000. Radix-4 Booth digit −2 needs −2M = +2³², which needs 34 bits, but partial products were 33 bits wide, so it wrapped. Fixed the width, distilled the seed into b17_booth_min_neg. Lesson: extreme-value operand coverage (min, max, −1, 0) on every datapath input."),
]))

# ---------------------------------------------------------------- PL-26
PLATES.append(dict(id="p26", part="V", short="Debug playbook",
title="Debug playbook: from a red regression to a root cause",
thesis="Debug is a search. Shrink the space fast: first divergence, then the instruction, then the cycle, then the signal. Classify early: DUT, testbench, model or spec.",
fig="""
<div class="scroll"><svg viewBox="0 0 620 270" role="img" aria-label="Debug flow">
 <rect class="boxb" x="10" y="10" width="140" height="50" rx="4"/><text class="th" x="22" y="32">Failure</text><text class="tm" x="22" y="50">mismatch / hang / SVA</text>
 <path class="w" d="M150 35 H180"/>
 <rect class="box" x="180" y="10" width="140" height="50" rx="4"/><text class="th" x="192" y="32">First divergence</text><text class="tm" x="192" y="50">retire #, pc, instr</text>
 <path class="w" d="M320 35 H350"/>
 <rect class="box" x="350" y="10" width="120" height="50" rx="4"/><text class="th" x="362" y="32">Reproduce</text><text class="tm" x="362" y="50">seed, +MUT, short N</text>
 <path class="w" d="M470 35 H500"/>
 <rect class="box" x="500" y="10" width="110" height="50" rx="4"/><text class="th" x="512" y="32">Waves</text><text class="tm" x="512" y="50">window around it</text>
 <rect class="boxr" x="10" y="80" width="600" height="80" rx="4"/>
 <text class="th" x="22" y="102">Classify before fixing</text>
 <text class="t" x="22" y="122"><tspan class="tb">DUT</tspan> spec + model agree, RTL differs   ·   <tspan class="tb">Model</tspan> second ISS disagrees with yours</text>
 <text class="t" x="22" y="142"><tspan class="tb">TB</tspan> stimulus illegal, timing of sampling, end of test   ·   <tspan class="tb">Spec</tspan> ambiguous: ask, then document</text>
 <rect class="boxw" x="10" y="176" width="600" height="86" rx="4"/>
 <text class="th" x="22" y="198">Signals to pull for a CPU</text>
 <text class="t tmono" x="22" y="218">retire valid/pc/instr · rf wr_en/rd/data · fetch req/ready/addr · data req/ready/addr/wr</text>
 <text class="t tmono" x="22" y="236">stall/flush/redirect · forwarding selects · ROB head/tail, LSQ heads · FSM state</text>
 <text class="tm" x="22" y="254">For a hang: what is the oldest thing waiting, and what is it waiting for?</text>
</svg></div>""",
deep=[
 "<b>Read the log you have before rerunning</b>: the A1 \"lbu mismatch\" was diagnosed from timestamps alone. The load was accepted at 29.59 µs, and end of test ran at 29.64 µs with a 16-cycle data delay.",
 "<b>Impossible values point to the testbench</b>: an LBU result of 0x7b5babbc cannot come from a zero-extended byte, so the compare happened at the wrong time, not the ALU.",
 "<b>One-line experiments</b>: remove one suspected condition and rerun the same seeds (the D2 store fix took mem from 3/3 failing to 4/5 passing, exposing A1 as the remaining cause).",
 "<b>Hangs</b>: find the oldest unfinished item (ROB head, pending request) and what it waits for (tag, ready, credit). Watchdogs should print that state when they fire.",
 "<b>Make it smaller</b>: shrink N, shrink the seed's program, then hand-write the minimal directed test. The regression keeps the small test forever.",
],
rules=[
 "A fix is not done until the failing seed passes, the new directed test passes, and the full regression is still clean.",
 "Never change the checker to make a failure go away without a spec reference.",
],
bugs=[
 "Rerunning until green: the original TB failed 40% of clean seeds. A flaky TB hides real bugs in noise.",
],
ask=[
 ("Q: A random test fails once in 500 seeds. What do you do?",
  "Reproduce with the exact seed, find the first divergence, classify it (DUT, TB, model, spec), shrink it to a directed test, fix it, then ask why it was 1/500: add coverage for that corner and bias stimulus toward it so the class is hit every night."),
]))

# ---------------------------------------------------------------- PL-27
PLATES.append(dict(id="p27", part="V", short="Rapid fire",
title="Rapid-fire interview drills",
thesis="Short answers a senior CPU verification engineer gives without thinking. Each one points back to the plate with the depth.",
fig="""
<dl class="kv">
<dt>01</dt><dd><b>Why in-order commit in an OOO core?</b> Precise exceptions, simple recovery, and the ISA's sequential model. (PL-14)</dd>
<dt>02</dt><dd><b>What does renaming remove?</b> WAR and WAW. Only true RAW dependences remain. (PL-14)</dd>
<dt>03</dt><dd><b>Load-use penalty in 5-stage?</b> 1 bubble: data exists after MEM, needed at start of EX. (PL-12)</dd>
<dt>04</dt><dd><b>Mispredict penalty in pq5?</b> 2 cycles: resolved in EX. (PL-13)</dd>
<dt>05</dt><dd><b>Why does x0 need care in forwarding?</b> A write to x0 in flight must not forward; reads of x0 are 0. (PL-12)</dd>
<dt>06</dt><dd><b>sltiu x1,x2,−1?</b> imm sign-extends to 0xFFFFFFFF, compared unsigned → 1 unless x2 = 0xFFFFFFFF. (PL-03)</dd>
<dt>07</dt><dd><b>jalr target?</b> (rs1 + imm) &amp; ~1, using the old rs1 even if rd = rs1. (PL-03)</dd>
<dt>08</dt><dd><b>Signed divide by zero?</b> Quotient −1, remainder = dividend, no trap. (PL-01)</dd>
<dt>09</dt><dd><b>Where do you compare against the ISS?</b> At retire: pc, rd/wdata, memory ops, traps, CSR writes. (PL-18)</dd>
<dt>10</dt><dd><b>How do you handle interrupts in lockstep?</b> The DUT decides; inject the same interrupt into the ISS at that retire boundary; check legality separately. (PL-05)</dd>
<dt>11</dt><dd><b>Why is randomize() skewed?</b> Uniform over all solutions; opcodes with more free fields win. solve-before or pick the opcode first. (PL-20)</dd>
<dt>12</dt><dd><b>What does #1step sample?</b> The value just before the clock edge (Preponed). (PL-21)</dd>
<dt>13</dt><dd><b>A bug only SVA can find?</b> One with no data effect, e.g. a protocol violation the responder tolerates. (PL-22)</dd>
<dt>14</dt><dd><b>Code coverage 100%: done?</b> No: executed ≠ checked ≠ right combinations. (PL-23)</dd>
<dt>15</dt><dd><b>How do you qualify a testbench?</b> Mutation: inject realistic bugs, require 100% caught and 0 false fails. (PL-24)</dd>
<dt>16</dt><dd><b>Store-to-load forwarding corner?</b> Partial overlap (sb then lw): wait or merge bytes. (PL-15)</dd>
<dt>17</dt><dd><b>What's RVFI?</b> RISC-V Formal Interface: a standard retire trace port used by riscv-formal and handy for scoreboards. (PL-17)</dd>
<dt>18</dt><dd><b>How do you find deadlocks?</b> Watchdog + per-resource liveness and conservation assertions + full-queue stimulus. (PL-14)</dd>
</dl>""",
deep=[
 "<b>\"How would you verify X?\" template</b>: (1) spec and risks, (2) reference model, (3) checkers: scoreboard + SVA + liveness, (4) stimulus: directed corners + constrained random, (5) coverage model, (6) closure: holes, mutation, regression trend.",
 "<b>Say numbers</b>: \"4 of 9 to 9 of 9 bugs caught\", \"79 of 120 seeds\", \"CPI 1.17 vs 1.66\". Measured results are what separate a senior answer.",
 "<b>Name trade-offs</b>: lockstep compare (precise, slower) vs end-of-test (fast, blind), formal (complete, depth-bound) vs simulation (deep, incomplete).",
 "<b>Close with the lesson</b>: every bug story ends with which checker or coverage point you added so the bug class cannot return.",
],
rules=[
 "Answer the question asked first, in one sentence, then add depth.",
 "When unsure about a spec detail, say what you would check and where (the spec chapter, Sail, Spike).",
],
bugs=[
 "Common interview mistake: describing a test that would pass on the buggy design, e.g. a slt test with only positive operands.",
],
ask=[
 ("60-second pitch",
  "\"I verified RV32I cores from single-cycle to Tomasulo. On YARP I found four RTL bugs against a C++ ISS over DPI, then fixed the class-based testbench itself: a store path that never wrote, 70% skewed stimulus and an early end of test. I added coverage closure and protocol SVA and proved it with mutation testing: 9 of 9 bugs caught, zero false alarms.\""),
]))
