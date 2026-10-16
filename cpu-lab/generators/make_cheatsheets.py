# -*- coding: utf-8 -*-
"""Generate challenges 26-31 (Markdown) from the same data that built the three course pages."""
import html, importlib.util, os, re, sys, json
S = os.environ.get('CPU_LAB_SRC', '.')   # folder holding course/, beginner/, pq5/guide/ build scripts
OUT = sys.argv[1]

def load(name, path, argv_out):
    old = sys.argv; sys.argv = [path, argv_out]
    spec = importlib.util.spec_from_file_location(name, path); m = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.dirname(path)); spec.loader.exec_module(m); sys.argv = old
    return m

C = load('content', f'{S}/course/content.py', '/dev/null')
BP = load('bpage', f'{S}/beginner/build_page.py', f'{S}/_tmp1.html')
G = load('guide', f'{S}/pq5/guide/build_guide.py', f'{S}/_tmp2.html')

def md(s):
    s = re.sub(r'<code[^>]*>(.*?)</code>', lambda m: '`' + html.unescape(m[1]) + '`', s, flags=re.S)
    s = re.sub(r'</?(b|strong)>', '**', s); s = re.sub(r'</?(i|em)>', '*', s)
    s = re.sub(r'<a href="([^"]+)"[^>]*>(.*?)</a>', r'[\2](\1)', s)
    s = re.sub(r'<br\s*/?>', ' ', s); s = re.sub(r'</?(p|ol|ul|li|span|div)[^>]*>', ' ', s)
    s = re.sub(r'<[^>]+>', '', s)
    return re.sub(r'[ \t]+', ' ', html.unescape(s)).strip()

LAB = 'cpu-lab'
P = lambda f: f'[`{f}`]({LAB}/{f})'
SEV = {"deadlock": "Deadlock", "data": "Wrong data", "race": "Race / sim-only", "spec": "Spec violation", "perf": "Performance"}
HDR = lambda n, t, lvl, topics, rel: (f'# Challenge {n}: {t}\n\n> **Level:** {lvl}\n> **Topics:** {topics}\n> **Related:** {rel}\n> **Code:** [`cpu-lab/`]({LAB}/README.md) · **Interactive pages:** open the HTML files in [`cpu-lab/pages/`]({LAB}/pages/) in a browser\n\n---\n\n')
def qa(items):
    return '\n'.join(f'**Q: {md(q)}**\n\n{md(a)}\n' for q, a in items)

files = {}

# ------------------------------------------------------------------------------------------- 26
o = [HDR(26, "Out-of-Order CPU: The 3-Wide Tomasulo Core, Module by Module", "Senior DV / CPU design interviews",
         "rename, ROB, reservation stations, wakeup/select, CDB, completion buffer, commit, LSQ, memory disambiguation, branch recovery",
         "[27 – Bug hunt](27-ooo-core-bug-hunt.md), [28 – CPU verification](28-cpu-verification-iss-random-sva-mutation.md), [31 – Question bank](31-cpu-interview-question-bank.md)")]
o.append("""## 1. The Source

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
""")
for m in C.MODULES:
    o.append(f"\n### Module {m['n']} – {m['name']}  \n*Files:* `{md(m['files'])}`\n\n{md(m['what'])}\n\n**Hidden concepts**\n")
    for t, d in m['concepts']: o.append(f"- **{md(t)}** — {md(d)}")
    o.append("\n**Code walk (line numbers refer to the original upload)**\n")
    for r, d in m['code']: o.append(f"- `{r}` — {md(d)}")
    if m['bugs']: o.append("\n**Bugs found here:** " + ', '.join(f"[{b} {md(C.BUGS[b]['title'])}](27-ooo-core-bug-hunt.md#{b.lower()})" for b in m['bugs']))
    o.append("\n**Build it**\n"); o += [f"{i+1}. {md(b)}" for i, b in enumerate(m['build'])]
    o.append("")
o.append("\n## 5. Capstone: Build Branch Support\n\n" + md(C.CAPSTONE['intro']) + "\n")
o += [f"{i+1}. **{md(t)}** — {md(d)}" for i, (t, d) in enumerate(C.CAPSTONE['steps'])]
o.append("\n## 6. Likely Interviewer Follow-ups\n")
for m in C.MODULES: o.append(qa(m['qa']))
o.append("""
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

""" + md(C.INTERVIEW[0][1]) + """

## 9. Self-Check

- [ ] Draw the core from memory with every size (IQ 16, ROB 48, RS 12/4/16, CDB 3, LQ/SQ 8/8).
- [ ] Explain why the ROB index can act as the physical register name.
- [ ] Explain age = (tag − commit pointer) mod 48 and why raw `<` is wrong.
- [ ] Walk one `mul` through every stage with cycle numbers (open the stepper in `tomasulo_core_lab.html`).
- [ ] Explain why stores write memory only after retirement, and what a senior store is.
- [ ] Explain the 2-cycle wakeup→issue loop and how to make it 1 cycle.
""")
files['26-ooo-cpu-tomasulo-core.md'] = '\n'.join(o)

# ------------------------------------------------------------------------------------------- 27
o = [HDR(27, "Bug Hunt: 15 Real Bugs in an Out-of-Order Core", "Senior DV",
         "bug masking, deadlocks, lost wakeups, memory ordering, sentinel bugs, Booth corner case, frontend back-pressure, root-cause stories",
         "[26 – The core](26-ooo-cpu-tomasulo-core.md), [28 – How they were found](28-cpu-verification-iss-random-sva-mutation.md), [25 – Debugging](25-debugging-intermittent-and-persistent-failures.md)")]
o.append("""## 1. The Source

The 3-wide Tomasulo core from [Challenge 26](26-ooo-cpu-tomasulo-core.md). Every bug below was reproduced in simulation (Verilator 5.048), fixed in [`cpu-lab/solutions/`](cpu-lab/solutions/) (each change tagged `FIX-n`), and re-verified. Diffs: [`cpu-lab/patches/`](cpu-lab/patches/).

## 2. Summary Table

| ID | Bug | Type | Where (original file:line) | Test that shows it |
|---|---|---|---|---|
""")
for bid, b in C.BUGS.items():
    o.append(f"| [{bid}](#{bid.lower()}) | {md(b['title'])} | {SEV[b['sev']]} | `{b['loc']}` | {md(b['caught']).split('. ')[0]} |")
o.append("\n**Fix → bug map:** FIX-1 B01 · FIX-2 B02 · FIX-3 B03 · FIX-4 B04 · FIX-5 B05+B06 · FIX-6 B07 · FIX-7 B08 · FIX-8 B09 · FIX-9 B10 · FIX-10 B11 · FIX-11 B12 · FIX-12 B13 · FIX-13 B14 · FIX-14/15 B15\n")
o.append("## 3. Each Bug: Symptom → Root Cause → Fix → Lesson\n")
for bid, b in C.BUGS.items():
    o.append(f"### {bid}\n\n#### {md(b['title'])}  \n*{SEV[b['sev']]}* · `{b['loc']}`\n")
    o.append(f"- **Symptom:** {md(b['symptom'])}\n- **Hint (try before reading on):** {md(b['hint'])}\n- **Root cause:** {md(b['cause'])}\n")
    o.append(f"Original:\n```systemverilog\n{b['orig']}\n```\nFix:\n```systemverilog\n{b['fix']}\n```\n")
    o.append(f"- **Caught by:** {md(b['caught'])}\n- **Lesson:** {md(b['lesson'])}\n")
o.append("## 4. Compile / Elaboration Errors Fixed First (FIX-0)\n")
for loc, d in C.COMPILE: o.append(f"- `{loc}` — {md(d)}")
o.append("\n## 5. Code-Review Findings Left Open (good exercises)\n\n| Type | Finding | Where | Detail |\n|---|---|---|---|")
for sev, t, loc, d in C.NOTFIXED: o.append(f"| {SEV[sev]} | {t} | `{loc}` | {md(d)} |")
o.append("""

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
""")
files['27-ooo-core-bug-hunt.md'] = '\n'.join(o)

# ------------------------------------------------------------------------------------------- 28
V = C.VERIFY
o = [HDR(28, "Verifying a CPU: Golden ISS, Commit Scoreboard, Random, SVA, Mutation", "Senior DV",
         "ISA reference model, commit-trace comparison, liveness/watchdog, constrained random for CPUs, bind-based SVA, unit tests, mutation testing, bug masking, performance checks",
         "[08 – SVA](08-sva-assertions.md), [09 – Coverage closure](09-coverage-plateau-closure.md), [19 – TB from scratch](19-building-uvm-testbench-from-scratch.md), [27 – Bug hunt](27-ooo-core-bug-hunt.md)")]
o.append("## 1. The Source\n\n" + md(V['intro']) + "\n")
o.append("""## 2. What Was Wrong With the Original Checker

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
""")
for t, d, f in V['layers']: o.append(f"| {md(t)} | {md(d)} | {md(f)} |")
o.append("\n**Random pass rate as fixes landed (120 seeds):** " + ' → '.join(f"{l}: {v}/120" for l, v in V['stages']) + ". The fixed core also passes 720/720.\n")
o.append("""## 4. Deep Dive

### 4.1 The commit-trace scoreboard (the core idea)

Everything inside an OOO core may reorder. The **committed stream** of `(pc, rd, value)` and the final memory may not. So:

```python
# tools/run_test.py (simplified)
exp = ISS().run(program)                         # program order, spec semantics
got = parse('COMMIT .* pc=(\\w+) rd=(\\d+) val=(\\w+)', sim_log)
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
""" + '\n'.join(G.MUT) + """
```

- **A surviving mutant is a question.** "Forward a load's address" survives because the load-use interlock makes that path unreachable. It was proven with an assertion (`a_loaduse`) rather than assumed.
- **Random had a blind spot.** The first generator never wrote x0, so "x0 can be written" escaped 100/100 random programs. After adding x0 destinations: caught in 54/100.
- On the beginner ladder, 11 of 11 mutants are caught. The first L10 (ROB) testbench missed "retire before finished" because it checked order but not values.

### 4.6 Performance is a check too

The fixed OOO core is correct but issues dependent ALU ops every **2** cycles (b12 chain: CDB at cycles 9, 11, 13, 15) because `ready` is re-registered after wakeup. Without branch prediction, pq5 stays correct but CPI rises from 1.02 to 1.66 on a loop. Track CPI per test.

## 5. Likely Interviewer Follow-ups

""" + qa([
 ("Scoreboard at commit vs at writeback?", "Commit-level matches the ISS exactly and is architecturally clean, but reports late and misses transient corruption. Unit or writeback-level scoreboards localise failures but need a microarchitectural model. Real projects do both."),
 ("How do you know you're done?", "Coverage closure against a plan (features × corners), assertion coverage (properties exercised, not just never failed), a flattened bug-rate curve across seeds, a code-coverage hole review, and sign-off reviews. Never 'all tests pass'."),
 ("How would you verify forwarding completely?", "Producer kind (ALU, load, link, lui) × distance (1, 2, 3, 4+) × consumer operand (rs1, rs2, store data, branch compare, jalr base) × same register written twice (priority). Directed tests per cell, coverage of that cross in random, golden compare at commit."),
 ("Why bind assertions instead of putting them in RTL?", "Keeps verification code out of design files, applies to every instance, reaches internal signals by name, never reaches synthesis, and checker sets can be switched per run."),
]) + """
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
""")
files['28-cpu-verification-iss-random-sva-mutation.md'] = '\n'.join(o)

# ------------------------------------------------------------------------------------------- 29
o = [HDR(29, "Pipelined In-Order CPU (Pequeno-Style 5-Stage RV32I): Hazards, Forwarding, Prediction", "Fresher → senior",
         "RV32I formats, 5-stage pipeline, valid/stall/flush, structural/data/control hazards, forwarding, load-use interlock, static prediction, CPI accounting",
         "[11 – coverage plan for a pipeline](11-functional-vs-code-coverage.md), [26 – OOO core](26-ooo-cpu-tomasulo-core.md), [30 – RTL ladder](30-cpu-from-zero-rtl-ladder.md)")]
o.append("""## 1. The Source

Chipmunk Logic's series *Designing Pequeno RISC-V CPU from scratch* (Mitu Raj), Parts 1–6:
""" + '\n'.join(f"- Part {n}: [{G.PARTS[n-1]['title']}]({u})" for n, u in G.POSTS.items()) + """

This challenge summarises each part in my own words and continues to a complete CPU, **pq5** ([`cpu-lab/pq5/`](cpu-lab/pq5/README.md)): original code following the same architecture, one module per stage, verified against an ISS. It is not the series' RTL.

## 2. What to Watch Out For

The posts are an architecture walk-through, not a verification guide, and stop before the execute unit. The parts that are easy to get wrong when you build it yourself, and how pq5 handles them:

| Question the posts leave to you | pq5's answer | Evidence |
|---|---|---|
| WB writes the register decode reads in the same cycle? | register-file write-through | removing it breaks 7/10 directed programs |
| What may forwarding pass from a load in MEM? | nothing (data exists only after MEM) | the guard is unreachable thanks to the interlock; proven by `a_loaduse` |
| Flush and stall in the same cycle? | flush wins; proven impossible anyway | `a_noflushstall` |
| Penalty of a wrong guess? | 2 bubbles (resolve in EX) | measured |

## 3. Background, Part by Part
""")
for p in G.PARTS:
    o.append(f"\n### Part {p['n']} – {p['title']}  ([original post]({G.POSTS[p['n']]}))\n\n*What it covers:* {md(p['summary'])}\n\n*Like you're 10:* {md(p['kid'])}\n")
    if p.get('ours'): o.append(f"*In pq5:* {md(p['ours'])}\n")
    for t, d in p['hidden']: o.append(f"- **{md(t)}** — {md(d)}")
    o.append("")
for p in G.EXTRA:
    o.append(f"\n### Part {p['n']} – {p['title']} (beyond the six posts)\n\n*Like you're 10:* {md(p['kid'])}\n\n{md(p['text'])}\n")
    for t, d in p['hidden']: o.append(f"- **{md(t)}** — {md(d)}")
o.append("""
## 4. Deep Dive: Measured Behaviour

### 4.1 The cost formula, checked on every program

`cycles = 4 + N + load_use_stalls + 2 × flushes` (no hazards: Δ + N − 1 with Δ = 5)

| program | N | stalls | flushes | predicted | measured | CPI |
|---|---|---|---|---|---|---|
""")
for l in G.REG:
    m = re.match(r'\[PASS\] (\S+)\s+(\d+) instr\s+(\d+) cycles\s+CPI\s+([\d.]+)\s+\(load-use stalls (\d+), flushes (\d+)\)', l)
    n, i, c, cpi, s, f = m.groups(); i, c, s, f = int(i), int(c), int(s), int(f)
    o.append(f"| `{n}` | {i} | {s} | {f} | 4+{i}+{s}+2×{f} = **{4+i+s+2*f}** | {c} | {cpi} |")
o.append("\n### 4.2 Pipeline pictures straight from simulation (`make pipe T=...`)\n\nLoad-use stall (`p03_load_use`, cycle 5: `lw x2` in EX, `addi x3,x2,1` waits in ID):\n```\n" +
         ''.join(open(f'{S}/pq5/build/pipe_loaduse.txt').read().splitlines(True)[:8]) + "```\nWrong guess (`p05_if_else`, cycle 5: forward branch was taken → 2 bubbles):\n```\n" +
         ''.join(open(f'{S}/pq5/build/pipe_ifelse.txt').read().splitlines(True)[:8]) + "```\n")
o.append("### 4.3 Remove one mechanism, see what breaks\n\n```\n" + '\n'.join(G.MUT) + "\n```\n")
o.append("### 4.4 The code\n\nAll stages: [`cpu-lab/pq5/rtl/pq5.sv`](cpu-lab/pq5/rtl/pq5.sv) (333 lines). The execute stage, which holds the forwarding and the branch check:\n\n```systemverilog\n" + G.module('pq5_execute') + "\n```\n")
o.append("## 5. Likely Interviewer Follow-ups\n\n" + qa([x for p in G.PARTS for x in p['quiz'] + p['iq']]) + qa([
 ("Design a hazard unit for a 5-stage pipeline. What inputs does it need?", "Sources and 'uses' flags of the instruction in ID; destination, write-enable and 'is load' of EX and MEM; the branch outcome from EX. Outputs: stall IF+ID with a bubble into EX on load-use; flush IF/ID+ID/EX on mispredict; forwarding selects per ALU operand."),
 ("Why is the load-use penalty 1 cycle and not 2?", "Load data exists at the end of MEM; the dependent instruction needs it at the start of its EX. One bubble lines them up, then forward from MEM/WB."),
]))
o.append("""
## 6. Common Mistakes

- Letting the PC move while IF/ID is stalled (instruction skipped). Same bug family as B09 in the OOO core.
- Stalling on "rs2" of an I-type (those bits are the immediate): false dependency, slower.
- Forwarding priority reversed (WB before MEM): fails only 2/10 directed and 5/100 random, easy to miss.
- Forgetting distance 3 (same-cycle register write/read).
- `$finish` in a testbench does not stop the current block: my first pq5 testbench printed one extra commit.

## 7. 60-Second Pitch

"A classic 5-stage in-order RV32I pipeline: structural hazards removed by split memories and a 2-read/1-write register file; RAW handled by forwarding from MEM and WB into EX plus register-file write-through, with a one-bubble interlock for load-use; control handled by a static predictor (backward taken, jal taken) and a 2-cycle flush from EX. I verified it against an ISS on ten real programs and 500 random ones, and every run obeys cycles = 4 + N + stalls + 2 × flushes exactly. Removing any correctness mechanism makes tests fail; removing prediction only raises CPI from 1.02 to 1.66 on a loop."

## 8. Self-Check

- [ ] Draw the five stages, four pipeline registers, the forwarding paths, stall and flush from memory.
- [ ] Compute cycles for a 10-instruction program with one load-use and one mispredict (4+10+1+2 = 17).
- [ ] Explain why WAR and WAW can't occur here but can in an OOO core.
- [ ] Explain why a backward branch is predicted taken.
""")
files['29-pipelined-in-order-cpu-hazards.md'] = '\n'.join(o)

# ------------------------------------------------------------------------------------------- 30
R = json.load(open(f'{S}/beginner/results.json'))
o = [HDR(30, "CPU From Zero: An 11-Level RTL Ladder From an Adder to an OOO Core", "Fresher",
         "combinational vs sequential, `<=` vs `=`, ALU, register file, valid/ready FIFO, single-cycle CPU, scoreboard, renaming, RS + CDB, ROB, tiny OOO CPU, self-checking testbenches",
         "[24 – Early-career portfolio](24-early-career-dv-expectations-and-portfolio.md), [29 – Pipelined CPU](29-pipelined-in-order-cpu-hazards.md), [26 – OOO core](26-ooo-cpu-tomasulo-core.md)")]
o.append("""## 1. The Source

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
""")
for d in BP.L:
    k = f"L{d['n']:02d}"
    o.append(f"\n### Level {d['n']} – {d['title']} ({d['sub']})  · [`{d['file']}`]({LAB}/beginner/{d['file']})\n\n{md(d['story'])}\n")
    o.append("**Key words:** " + '; '.join(f"`{a}` = {b}" for a, b in d['words']) + "\n")
    o.append(f"**Read the code:** {md(d['look'])}\n")
    o.append(f"**Run it:** `./run_all.sh {d['n']}` →\n```\n{R[k]['pass']}\n```")
    o.append(f"**Break it:** {md(d['breakit'][0])} →\n```\n{R[k]['mut'].split('CAUGHT: ')[-1]}\n```\n{md(d['breakit'][1])}\n")
    o.append("**Check yourself:**\n" + '\n'.join(f"- *{md(q)}* — {md(a)}" for q, a in d['quiz']))
    o.append(f"\n*In the big core:* {md(d['big'])}\n")
o.append("\n## 4. Deep Dive: the tiny OOO CPU (Level 11) timeline\n\n```\n" + '\n'.join(R['L11']['log']) + "\n```\n\nT4 (`addi x5`) finishes in cycle 7, before the older `mul` (T2) and `add` (T3), then waits, done, until cycle 12 to commit. x3 is written twice; the ARF ends with the second `mul`'s value (4) because commit is in order.\n")
o.append("""
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
""")
files['30-cpu-from-zero-rtl-ladder.md'] = '\n'.join(o)

# ------------------------------------------------------------------------------------------- 31
o = [HDR(31, "CPU Interview Question Bank (OOO + Pipeline + Verification)", "All levels",
         "every question from challenges 26–30 in one place, with model answers and 60-second pitches",
         "[26](26-ooo-cpu-tomasulo-core.md), [27](27-ooo-core-bug-hunt.md), [28](28-cpu-verification-iss-random-sva-mutation.md), [29](29-pipelined-in-order-cpu-hazards.md), [30](30-cpu-from-zero-rtl-ladder.md)")]
o.append("Use this the night before: read the question, answer out loud in under a minute, then compare.\n\n## A. Pitches and stories\n\n" + qa(C.INTERVIEW))
o.append("\n## B. Out-of-order core, by module\n")
for m in C.MODULES: o.append(f"\n### {m['name']}\n\n" + qa(m['qa']))
o.append("\n## C. Pipelined in-order CPU\n\n" + qa([x for p in G.PARTS for x in p['quiz'] + p['iq']]))
o.append("\n## D. Fundamentals (CPU From Zero)\n\n" + qa([x for d in BP.L for x in d['quiz']]))
o.append("""
## E. Numbers worth remembering (all measured in this lab)

| Fact | Value |
|---|---|
| Original OOO core: directed / random pass | 1/20 (scoreboard only), 0/720 |
| Fixed OOO core | 19/20 (branch capstone open), 720/720, 0 SVA firings |
| Bugs found by directed vs random | 11 vs 4 (B11–B14) |
| Dependent ALU chain in the OOO core | 1 result per 2 cycles (registered `ready`) |
| pq5 cycle formula | 4 + N + stalls + 2 × flushes |
| pq5 mispredict / load-use penalty | 2 cycles / 1 cycle |
| pq5 loop CPI with / without prediction | 1.02 / 1.66 |
""")
files['31-cpu-interview-question-bank.md'] = '\n'.join(o)

for name, text in files.items():
    text = re.sub(r'\|\n\n\|', '|\n|', text)          # no blank line inside tables
    open(os.path.join(OUT, name), 'w').write(text.rstrip() + '\n')
    print(name, len(text))
