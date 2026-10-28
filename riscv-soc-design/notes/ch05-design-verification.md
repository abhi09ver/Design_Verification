# Chapter 5 · Design Verification

Oct 28, 2026 · @Abhishek

## At a glance

> "If you didn't test it, it doesn't work." (Bob Colwell, chief architect of Pentium Pro through Pentium 4)

**Logic verification** checks that the RTL matches its specification. It costs more than design: verification engineers are about half of an SoC team, and the book's summary says verification now takes nearly twice the effort of all other chip-design work combined. Hardware bugs are also unforgiving. A new mask set costs millions, plus the lost time to market.

Every simulation-based method has the same three parts: a **testbench** applies **test vectors** to the **DUT** (device under test) and compares the results against a **reference model**. The hard problems:

- deciding which features need testing
- choosing test vectors that reach them
- building a reference model you can trust
- locating and fixing a bug once it shows up
- coping with the very long run times of big simulations

&#91;embedded content: Coverage-driven verification, the method this chapter builds up section by section\]

SystemVerilog is used in five different subsets, and a verification engineer uses all of them (book Table 5.1):

| Subset | Purpose | Section |
| --- | --- | --- |
| Synthesizable | RTL design | 4.2 |
| Testbench | Read vectors and files, drive clocks, check results, log mismatches | 5.4 |
| Assertions (SVA) | Properties the design must satisfy | 5.7 |
| Functional coverage | Covergroups and coverpoints that measure how thoroughly the design was exercised | 5.9 |
| Object-oriented | Reusable testbenches, especially with UVM (drivers, monitors, sequencers, scoreboards); the book points to *Getting Started with UVM* \[Cooper13\] | outside the book |

For a RISC-V core, the pieces map like this:

- the **DUT** is the SystemVerilog core
- the **test vectors** are RISC-V programs: riscv-arch-test, directed tests, constrained-random tests
- the **reference model** is Sail, Spike or ImperasDV
- the two sides talk through **RVVI**, the RISC-V Verification Interface

## 5.1 Verification strategies

### 5.1.1 Where test vectors come from: five strategies, from naive to industrial

&#91;embedded content: Why exhaustive testing stops at small blocks\]

| Strategy | What it is | Good for | Weakness |
| --- | --- | --- | --- |
| **Exhaustive** | Every input combination | Tiny blocks: a full adder needs 2^3 = 8 vectors | A 64-bit adder needs 2^128 |
| **Ad hoc** | A handful of hand-written cases (the Chapter 2 test program; booting Linux) | Quick early confidence | No assurance of full input coverage. Linux exercises interactions but is "no substitute for rigorously testing each feature" |
| **Directed** | Systematic corner cases, often crossed | For a 64-bit adder, 12 corners per input {0, 1, 2, 3, 2^32, 2^63−1, 2^63, 2^63+1, 2^64−2, 2^64−1, two mid-range randoms}, crossed = 144 vectors | Misses bugs not tied to a corner (a typo in one column of a hand-built adder; a defect that ignores one input) |
| **Coverage-driven** | Define **coverpoints** (every rd, rs1, rs2, every opcode, extreme values) and generate tests until each is hit | Proving the plan was exercised; riscv-arch-test is built this way | Covers only what someone thought to write down |
| **Constrained random** | A generator emits millions of legal random instruction sequences | Hard-to-reach combinations, such as an interrupt arriving while the IFU is stalled waiting for the LSU to service a TLB miss; it also finds bugs in areas the DV plan never anticipated | Needs a reference model and a way to know when you have run enough (coverage) |

**When do you stop?** When code and functional coverage reach 100%, or when it becomes easier to write a directed test for the few coverpoints the random generator keeps missing.

In practice teams use all five. Wally started with ad hoc programs, then riscv-arch-test (coverage-driven, with randomized operands), plus directed tests for the privileged specification, which riscv-arch-test barely covers.

**The story to know: the 1994 Pentium FDIV bug.** A tool optimized away 5 of the 1,066 minterms in the PLA that selects quotient digits during division. The result was wrong around the 9th or 10th decimal digit in about 1 of every 9 billion random divisions. Intel first said a typical spreadsheet user would hit it once in 27,000 years; IBM estimated once every 24 days for heavy financial spreadsheets. Intel recalled the chips at a cost of **$475 million**. Two lessons interviewers look for:

1. **Rare-but-real** bugs need volume (random testing at scale) or proof (formal), not just directed corners.
2. **Verify what you ship.** Intel tested the quotient-selection equations, which were correct, not the PLA the tool actually generated. Today's version of that lesson is gate-level simulation and equivalence checking after synthesis.

### 5.1.2 Reference models

A reference model needn't be cycle-accurate, but it must implement every architectural feature faithfully, including behavior the specification leaves open. For example, RISC-V strongly recommends but does not require an illegal-instruction trap on an undefined opcode; the model and the DUT must make the same choice. **Write the reference model and the RTL with different teams**, so they don't share the same misunderstanding.

| Model | Role | Limits |
| --- | --- | --- |
| Sail | Official executable specification; outranks the English spec where they disagree | Weak interrupt and peripheral support (as of the book) |
| Spike | Mature, has interrupts; the reference for some OpenHW cores | Not the formal spec |
| ImperasDV | Commercial, widely used in industry; lock-step capable (Synopsys acquired Imperas in 2024) | Licensed |
| Others | QEMU, Whisper, IDL |  |

### 5.1.3 Unit versus system testing

|  | Unit-level | System-level |
| --- | --- | --- |
| Speed | Faster: less RTL, only relevant tests | Slower |
| Ideal role | Each unit (IEU, FPU, IFU, LSU) proven alone, so system tests catch only integration bugs | Integration and interactions |
| Cost | A testbench per unit; driving every control, data and stall signal into an LSU is hard | One testbench: load a program and run it |

So teams favor **large blocks with simple interfaces**: a whole core, an accelerator, the SoC. The exception is when a unit's interface is clean and its input space is huge. Wally tests its FPU at unit level with TestFloat (5.11.8).

### 5.1.4 Emulation

A large SoC simulates at a few kHz, or even a few Hz. Mapped onto FPGAs it runs at MHz, so a test that takes days in simulation finishes in seconds. The costs: minutes to hours to synthesize, place, route and download; some infrastructure to drive and check it; and debug through a clunky on-chip logic analyzer. One large FPGA (thousands to tens of thousands of dollars) holds a moderate design. Commercial SoCs use **Cadence Palladium** or **Synopsys ZeBu**: racks of FPGAs that handle hundreds of billions of gates, with automatic partitioning and better debug, at millions of dollars each.

### 5.1.5 Technology Readiness Levels

&#91;embedded content: Technology Readiness Levels and where Wally stands\]

NASA created the TRL scale in the 1970s for space programs; the US Defense Department and the European Space Agency adopted it. OpenHW applies it to cores. Wally (officially CORE-V Wally, cvw) targets TRL3 for all configurations and TRL5 for rv64gc. The TRL5 checklist is effectively the definition of "verification complete" for a processor IP.

### 5.1.6 How design and verification work together

- **The bad old days (1990s):** designers threw RTL "over the wall" to a separate verification team, often in another country. It was slow, and designers made choices without seeing what they cost in verification. Now projects start "with the goal of verification in mind."
- **Regression:** tests are written before or alongside the RTL. A short regression runs on every change and a long one nightly.
- **Pitfall:** tweaking RTL until the tests pass, instead of designing from the specification. The tests are never complete, so bugs remain.
- **Always-broken versus always-working** \[Keating07\]:

|  | Always-broken | Always-working |
| --- | --- | --- |
| Flow | Units built and unit-tested separately, then integrated in big painful steps | Integrate a minimal system once, then add features one at a time, each passing system regression before check-in |
| System state | Broken except briefly after each integration | Working after the first prototype |
| When regression breaks | Hard to say which of many changes caused it | The last change did it: easy to find |

- **Test-driven development** \[Beck03\] is a disciplined always-working loop:
  1. Add a test for the new capability.
  2. Watch it fail.
  3. Implement the change.
  4. Watch it pass along with every other test.
  5. Refactor.

Wally works this way: small changes, each tested immediately, on a dev branch of a fork and merged by pull request. A notable piece of advice from the book: if a change breaks something, it may be faster to **throw the change away and redo it in smaller steps** than to debug it in a waveform viewer.

## 5.2–5.4 The DV plan, lint, and testbenches

### 5.2 The design verification plan

The DV plan, or test plan, has two readers. A **reviewer** must be able to see that every feature of the system is covered (the forest). A **verification engineer** must be able to turn each line into a test and a coverage measure (the trees). The usual shape: a top-level list of areas (base ISA, unprivileged extensions, privileged instructions, privileged extensions), each pointing to a spreadsheet with one row per feature and subfeature. For the M extension, a feature per instruction, with subfeatures such as:

- every register as each source and as the destination
- every combination where source and destination are the same register
- corner-case inputs: 0, 1, 2, a random value, max positive, max negative, −1
- for division, also divide by zero and overflow

Each row carries **six columns**:

| Column | Example for `div` |
| --- | --- |
| Spec reference | Unprivileged spec, M chapter, division |
| Feature description | Signed divide, including −2^(XLEN−1) ÷ −1 overflow |
| Required stimulus | Directed operands at each corner, in all registers |
| Checking method | Lock-step against the reference model |
| Coverage specification | Coverpoint on the operand corners, crossed with rd = rs1 |
| Link to the coverage item | covergroup `div_cg`, coverpoint `cp_rs1_corners` |

In an interview, "how would you verify X?" is really "show me your DV plan for X". Answer in these columns: features, stimulus, checker, coverage.

### 5.3 Lint

Static analysis that is much faster than finding the same problem later in waveforms. Typical findings:

- unsynthesizable code
- unintended latches and combinational loops
- undeclared, unused or undriven signals
- mismatched port and vector widths
- missing `default` and other always/case pitfalls
- deprecated constructs and poor style

The commercial leaders are Real Intent Ascent Lint and Synopsys SpyGlass, usually run with a company rule set. Wally uses free Verilator lint. Chapter 4's runs show it catching CASEINCOMPLETE, BLKSEQ, WIDTHTRUNC and IMPLICIT.

False positives are waived **locally and narrowly**:

```systemverilog
// verilator lint_off CASEINCOMPLETE
... the one case statement that is fine ...
// verilator lint_on CASEINCOMPLETE
```

The rule is to keep the tree **lint-clean on every check-in**, so a new warning is always news.

### 5.4 Testbenches

&#91;embedded content: The book's self-checking testbench (Fig. 5.1, Code Example 5.1)\]

The essential testbench language:

- `initial` runs once; `always` with no sensitivity list repeats forever (the clock).
- `#5` delays are allowed here, unlike in RTL.
- `$readmemb` / `$readmemh` load vector files; `$display` prints; `$dumpfile` / `$dumpvars` write a VCD for Verilator and GTKWave.
- `===` and `!==` are used because outputs might be x. Comparing x with `!=` gives x, which an `if` treats as false, so a mismatch would pass silently: Chapter 4's x-optimism, inside your checker.
- `$stop` pauses (Questa keeps waves and coverage); `$finish(code)` ends (Verilator prefers it). Codes: 0 = nothing printed, 1 = time and location (the default), 2 = plus memory statistics.

**I ran it.** The cvw example `fulladder.sv` with its 8-vector file, in both Verilator 5.020 and Icarus: `10 tests completed with 0 errors`. Then two experiments:

| DUT | Vectors | Result |
| --- | --- | --- |
| Correct full adder | all 8 | 0 errors |
| Bug: `cout = (a & b) \| (b & c)` (the `a & c` term deleted) | all 8 | **caught**: `Error: inputs = 101, outputs cout s = 00 (10 expected)` |
| Same bug | 6 vectors (101 and 110 removed, as in the book's coverage example) | **0 errors: the bug escapes** |

Statement coverage is still 100% in the escaped case. Section 5.8 shows which coverage metric does flag the gap.

**A testbench bug hiding in plain sight.** The book's testbench stops when the next vector is all x. The version in today's cvw repo stops at `vectornum === 10` instead, while the file has only 8 vectors. So it reports "10 tests": the last two "tests" apply x inputs and compare x against x with `!==`, which matches. With my 6-vector file it still said "10 tests completed" while really running 6. The lesson: **check the checker**. Test counts and pass messages must come from real comparisons, and a good testbench fails if it ran fewer checks than expected.

## 5.5 Logic simulators

**Event-driven simulation**, from first principles: the simulator keeps a queue of *events* (signal changes at a given time). When a signal changes, every `assign` or `always_comb` that reads it is re-evaluated. If the result changes, that is a new event, either after the stated `#delay` or after a zero-width **delta cycle** that keeps cause and effect in order at the same simulation time. Old simulators interpreted the code; modern ones compile it.

| Simulator | Vendor | How it runs | Wally invocation |
| --- | --- | --- | --- |
| Questa (formerly ModelSim) | Siemens | Compiled, 4-state, full SystemVerilog including UVM and coverage | `vsim -do fulladder.do`, batch `vsim -c -do …`, or one-shot `qrun fulladder.sv` |
| VCS | Synopsys | Compiles to an executable `simv` | `vcs -sverilog -full64 fulladder.sv; ./simv` |
| Xcelium | Cadence | Compiled, full-featured | (not used in the book) |
| Verilator | Open source (conceived at DEC in 1994, open since 1998, led by Wilson Snyder since 2001) | Translates SystemVerilog to C++, compiles, runs; **2-state**; often as fast as or faster than commercial tools; no UVM yet (as of the book) | `verilator --binary --top-module testbench --trace fulladder.sv; obj_dir/Vtestbench`, waves in GTKWave |

Questa workflow details worth knowing:

- `vlog` compiles, `vopt +acc` optimizes while keeping signals visible for debug, `vsim` simulates.
- A `.do` file (Tcl) scripts the whole sequence; `restart -f` reruns while keeping the waveform setup.
- Use "full visibility" during debug, or the optimizer removes the internal signals you want to see.
- Batch mode (`-c`) for regressions, GUI only for debugging.

**Why it matters which one you use:** Wally runs its regression on Verilator (free, fast, and runs the whole suite) and checks the nightly run on Questa and VCS as well. Chapter 4 showed why more than one matters: a 4-state simulator shows x where Verilator shows 0 or a random value, and simulators differ in SystemVerilog support and scheduling. Running regressions on two simulators catches tool-dependent behavior, such as races and x-handling, before silicon does.

## 5.6 Lock-step-compare and RVVI

### Why signatures are not enough

A signature test writes a few result words at the end. Two problems:

- **It only sees what reaches the signature.** Early riscv-arch-test floating-point tests saved each instruction's result but not the FP exception flags, so bugs in the flag logic passed. (The Chapter 3 companion shows the same effect: a load bug that a signature check misses and lock-step catches.)
- **Long system tests have no useful signature.** A Linux boot or a benchmark signals success only after millions of instructions, if at all, and tells you nothing about where it went wrong.

### Lock-step-compare

After **every** retired instruction, the testbench reports every architectural state change (PC, integer and FP registers, CSRs, memory) and the reference model, running the same program, checks it. A deviation is reported at the instruction where it happens, not millions of cycles later.

&#91;embedded content: Lock-step-compare with a reference model over RVVI (book Fig. 5.4, simplified)\]

What makes it work:

1. **The same nondeterministic inputs.** Interrupts must be injected into the reference at the same instruction boundary as in the DUT, and values read from memory and peripherals (a timer, a UART) are passed to the model, so both follow the same PC sequence.
2. **Configure the model to match the implementation's choices.** RISC-V allows many legal behaviors: XLEN, extensions, and subtle ones such as whether `mstatus.UXL` is writable (so user-mode XLEN can change at run time). If the model makes a different legal choice, you get false mismatches.
3. **A tracer** that turns the pipeline into one retirement record per instruction.

### RVVI-TRACE (5.6.1)

The RISC-V Verification Interface is a standard SystemVerilog interface. Wally uses it for lock-step with ImperasDV and as the input to riscvISACOV functional coverage.

| Signal | Width | Meaning |
| --- | --- | --- |
| `clk` | 1 | When state updates |
| `insn` | 32 | The instruction |
| `trap` | 1 | Trapped instead of retiring |
| `pc_rdata` | XLEN | Its PC |
| `x_wdata` / `x_wb` | XLEN × 32 / 32 | New integer register values / which ones were written |
| `f_wdata` / `f_wb` | FLEN × 32 / 32 | Same for FP registers |
| `csr` / `csr_wb` | XLEN × 4096 / 4096 | CSR values / which were written |

In Wally, `testbench/common/wallyTracer.sv` takes register-file and CSR updates from the **Writeback** stage. It carries earlier-stage signals (PCF, InstrF, TrapM) down to Writeback, accounting for stalls and flushes, so each record describes one instruction. Reading today's tracer, I noticed that `csr_wb` is computed by comparing each CSR with its previous value, so it flags *changes*. A CSR write of the value already there produces no write record.

**Lock-step in action (from the labs).** I injected the book's own debugging bug (Section 5.11.7: the ALU's OR became `+`) into the cpu-from-scratch pipeline and reran the bug hunt. The book's test, the directed test and 10 of 10 random lock-step seeds all caught it. Lock-step named the exact instruction:

```text
MISMATCH at retired instruction #55: differs in rd
   ref  pc=800000dc insn=01a360b3 x1=f9270f4e      <- or x1, x6, x26
   dut  pc=800000dc insn=01a360b3 x1=79270f4e
```

The two values differ only in bit 31. **OR and ADD agree whenever the operands share no 1 bits**, so this bug only shows when the operands overlap. That is why the book's failing case is `2 OR 2` (the expected 2 versus the buggy 4), and why riscvISACOV has coverpoints such as `cmp_rs1_rs2_eqval`, which require rs1 equal to rs2 at least once. Random operands found it here; carefully chosen operands that happen not to overlap would not.

## 5.7 Assertions

SystemVerilog Assertions (SVA) state properties the RTL must always satisfy. Their value is **locality**: they fire where and when the rule breaks, long before the damage reaches architectural state, so the root cause is found in minutes rather than by tracing waves back from a bad signature. Typical homes: FIFOs (no push when full), bus interfaces, state machines. The same properties also drive functional coverage (`cover property`) and formal verification (5.10).

### Immediate assertions (5.7.1): checked when executed

```systemverilog
assert (expression) <pass_statement> else <fail_statement>;
// fail_statement defaults to $error; severities: $fatal(code, msg), $error, $warning, $info
```

Wally's `riscvassertions` module is all immediate assertions in an `initial` block. They are checked once, at time 0, to reject illegal configurations:

```systemverilog
assert (P.PMP_ENTRIES == 0 || P.PMP_ENTRIES==16 || P.PMP_ENTRIES==64)
  else $fatal(1, "Illegal number of PMP entries: PMP_ENTRIES must be 0, 16, or 64");
assert (P.S_SUPPORTED || P.VIRTMEM_SUPPORTED == 0)
  else $fatal(1, "Virtual memory requires S mode support");
assert (P.DCACHE_SUPPORTED || ~P.F_SUPPORTED || P.FLEN <= P.XLEN)
  else $fatal(1, "Data cache required to support FLEN > XLEN because AHB/DTIM bus width is XLEN");
```

The point the book makes: the rules live **in the code base**, not in a document someone might not read. Note that the condition passes only when it is exactly 1. If it evaluates to 0, x or z, the else branch runs, so an assertion is not fooled by x-optimism the way an `if` is.

**Deferred immediate assertions** (`assert final (...)`) wait until the expression has settled in that time step, so a combinational glitch during evaluation doesn't produce a false failure.

### Concurrent assertions (5.7.2): properties across clock cycles

Sequence and property syntax, with the implication operators:

- `a |-> b`: if a holds at this edge, b must hold at the **same** edge.
- `a |=> b`: if a holds at this edge, b must hold at the **next** edge.
- When the antecedent is false, the property passes *vacuously*. Coverage of the antecedent tells you whether the check ever really ran.

The book's example, an AHB rule: while `HREADY` is low (the slave inserted a wait state), the manager must not change `HTRANS`, except IDLE → NONSEQ, or BUSY → SEQ during a burst:

```systemverilog
transaction_type_stability: assert property (
  @(posedge HCLK) disable iff (!HRESETn)
    !HREADY |=> $stable(HTRANS) |
                ($past(HTRANS) == AHB_IDLE) |
                (($past(HTRANS) == AHB_BUSY) & (HBURST != 3'b000)));
```

- `$stable(x)`: x equals its value at the previous clock.
- `$past(x)`: x's value one clock earlier.
- `disable iff`: switches the check off during reset.

**I ran it in Verilator 5.020** with `--assert`. In a small testbench the manager starts a NONSEQ transfer, the slave holds HREADY low, and then the manager illegally changes HTRANS to SEQ. Verilator reported:

```text
[55] %Error: ahb.sv:10: Assertion failed in TOP.ahb_tb.transaction_type_stability
```

&#91;image: Concurrent assertion evaluated edge by edge: one pass, then a failure at 55\]

Reading the waveform: at edge 35, HREADY is low, so the check is scheduled for edge 45, where HTRANS is still NONSEQ: pass. At edge 45 HREADY is still low, so edge 55 is checked; HTRANS has become SEQ, and its past value was neither IDLE nor BUSY: **fail at 55**, the exact cycle of the bug. The companion page lets you edit these waveforms and watch the property re-evaluate.

**Wally today (5.11.10):** its only assertions are the configuration checks in `riscvassertions`. Concurrent protocol and microarchitecture assertions (one-hot selects, FIFO bounds, no stall and flush conflicts, AHB rules on the bus) are an obvious area where a verification engineer could add value.

## 5.8 Code coverage

Code coverage measures how much of the **RTL text** the tests exercised. Simulators collect it automatically.

| Metric | Question it answers |
| --- | --- |
| Line / statement | Did each line, or each statement (finer), execute? |
| Branch | Did each `if` / `case` condition evaluate both true and false? |
| Condition | Did each input of an `if` condition take 0 and 1 *while it alone decided the outcome*? |
| Expression | The same, for the right-hand side of assignments |
| FSM | Was every state reached and every transition taken? |
| Toggle | Did every bit go 0→1 and 1→0? (common in industry; not in the book's Questa example) |

**The idea behind condition and expression coverage** (Questa's "focused expression coverage"; the MC/DC idea from avionics): an input only counts as tested when the other inputs are set so that **it alone decides the output**, its *non-masking condition*. In `y = a & b | c`, a controls y only when b = 1 and c = 0, so full coverage needs six cases: a = 0/1 with b = 1, c = 0; b = 0/1 with a = 1, c = 0; and c = 0/1 while a & b = 0.

### The full adder, worked through (Code Examples 5.7–5.11)

Questa flow: `vopt +cover=sbecf` (statement, branch, expression, condition, FSM), `vsim -coverage`, `coverage save … fulladder.ucdb`, then `vcover report -details`. Merge runs with `vcover merge -out combined.ucdb test1.ucdb test2.ucdb`.

There are six coverage bins: one per input term (a, b, c) in each of the two expressions, and a term counts only when it was seen both 0 and 1 under its non-masking condition. For `cout = a&b | a&c | b&c`, input a decides the output only when b ≠ c.

| Vector set | Statement | Expression | Total | Missing bin |
| --- | --- | --- | --- | --- |
| All 8 | 2 / 2 = 100% | 6 / 6 = 100% | 100% | none |
| 101 and 110 removed | 2 / 2 = **100%** | 5 / 6 = **83.33%** | **91.66%** | cout's term a: `a_1` never seen with b ≠ c |

I recomputed the bins in Python and got exactly the book's 83.33% and 91.66%. Now link it to the Section 5.4 experiment: **the bug that escaped (the deleted a & c term) lives exactly in the bin coverage reported missing.** Statement coverage said 100% and was useless; expression coverage pointed straight at the hole. That is the best one-line answer to "why isn't line coverage enough?"

### Closing coverage, and exclusions

TRL5 needs 100% code coverage. The usual route is directed tests for the obvious cases, random tests for the non-obvious ones, then more directed tests for the strange ones (illegal instructions). Some code is **unreachable** in a configuration: an RV32 build can't execute RV64-only paths, and the shared cache code can never invalidate the *data* cache. Such code gets a reviewed **exclusion**. Exclusions are dangerous: a stale or careless exclusion hides real holes, so each one needs a written reason and a reviewer.

**Code coverage is necessary but not sufficient.** It cannot report a feature that was never coded: 100% of nothing is still 100%. That gap is what functional coverage covers.

## 5.9 Functional coverage

Code coverage asks *was all the code exercised?* Functional coverage asks *were all the features exercised?* Its two flavors:

- **Architectural** coverage applies to any core that implements an extension: every instruction, register and operand corner.
- **Microarchitectural** coverage is specific to one implementation: pipeline hazards, interrupts landing in particular pipeline states, cache and bus corners, branch-predictor behavior.

The book's hard-won line: **"coverage that is easy to describe doesn't catch many bugs, and coverage that catches hard bugs takes a lot of thought to describe."**

The SystemVerilog vocabulary:

- A **covergroup** is a set of related coverpoints sampled at the same moment (for example, when an add retires).
- A **coverpoint** is one thing to measure, divided into **bins**: `cp_rd` has 32, one per register.
- A **cross** is the product of coverpoints, such as rs1 sign × rs2 sign = 4 bins.
- `iff` guards when a sample counts.

Run the tests, the simulator counts bin hits, and run them **in lock-step** at the same time, so a hit bin also proves the result was right.

&#91;embedded content: Anatomy of a riscvISACOV covergroup\]

### riscvISACOV (5.9.1)

Imperas (now Synopsys) wrote these SystemVerilog covergroups: one file per extension (RV32I, RV64I, RV64M…), one covergroup per instruction. The RV32I set is public; more are licensed. They read state through RVVI, so the same covergroups work on any core with a tracer. Instructions use only the coverpoints that make sense for them: R-type has no immediate, I-type has no rs2, shifts have no negative amounts, and only branches have an offset.

The full RV{32/64}I list (book Table 5.5): `cp_asm_count`, `cp_rd` / `cp_rs1` / `cp_rs2` (32 each), the sign coverpoints, `cp_offset`, `cp_imm_sign` (0, positive, negative), the crosses `cr_rs1_rs2` and `cr_rs1_imm`, register-equality coverpoints (`cmp_rd_rs1_eq`, `cmp_rd_rs2_eq`, `cmp_rd_rs1_rs2`) and value-equality ones (`…_eqval`), toggles of rd, rs1 and rs2 (2×XLEN bins each), `…_maxvals` (6 bins each), `cp_gpr_hazard` (none, RAW, WAR, WAW), `cp_mem_hazard`, and `cp_mem_unaligned`.

### Directed tests from coverage (5.9.2)

In `addins/cvw-arch-verif`, `covergroupgen.py` reads CSV test plans (which coverpoints apply to which instruction, for RV32 and RV64) and generates the covergroups. `testgen.py` reads the covergroups and writes assembly tests that hit each bin. The test plan, the coverage model and the tests all come from one source, so they can't drift apart.

### Constrained random (5.9.3)

**riscv-dv** (started at Google, now maintained by CHIPS Alliance) uses Python scripts that drive SystemVerilog UVM classes to emit random assembly programs. It is a submodule of Wally, but the book says Wally isn't using it regularly and its scripts have broken. Random tests find the corners that nobody thought to write a coverpoint for; coverage tells you when you have run enough of them.

## 5.10 Formal verification

The "holy grail": a mathematical proof that the RTL implements the specification for **all** inputs, not just the ones simulated.

How it works:

1. Annotate the DUT with SVA. `assume` constrains inputs and some internal nodes to legal values; `assert` states what must always hold.
2. The tool searches the logic between them, the **cone of influence**, for a counterexample that satisfies every assumption but breaks an assertion.
3. If none exists, the assertion is **proven**. If one exists, you get a short waveform trace that shows the bug, which is often the fastest debug artifact there is.

The limit: the number of cases grows exponentially with the size of the cone, so whole-core proofs are usually out of reach. Algorithmic advances keep shrinking the cones, and methodology now says which blocks suit formal and how to write the properties.

| Where formal works well today | Why |
| --- | --- |
| Arbiters, FIFOs, protocol checkers, one-hot or mutual-exclusion properties | Small cones, control-dominated logic |
| Forwarding and hazard units | A finite state space with tricky corners (the labs' x0-forwarding bug is a one-line assertion) |
| Equivalence checking (RTL vs RTL, RTL vs netlist) | A routine sign-off step after synthesis (Chapter 6) |
| Deep datapaths (multipliers, FP dividers) | Hard: wide cones; simulation plus specialized techniques |

**A real case:** OpenHW ran formal on the CV32E40P v2.0.0 core (4-stage RV32IMC) against the Sail specification, translated into assertions by a proprietary tool. It found many interesting bugs, but fully proving that the core matches Sail would have taken an impractical amount of compute. Formal finds bugs that simulation misses, but it doesn't replace simulation for a whole core.

## 5.11 Wally verification, end to end

Wally targets **TRL3 for every configuration** and **TRL5 for rv64gc**.

### DV plan (5.11.1, book Table 5.6)

| Test | Section | TRL3 scope | TRL5 scope |
| --- | --- | --- | --- |
| Verilator lint | 5.3, 5.11.4 | all configs | rv64gc |
| riscv-arch-test | 3.7 | all configs | rv64gc |
| wally-riscv-arch-test | 3.7 | all configs | rv64gc |
| TestFloat | 5.11.8, 16.5.2 | rv{32/64}gc + derived | rv64gc |
| CoreMark | 21.1 | many configs | rv64gc |
| Embench | 21.2 | rv32\* | n/a |
| Cache performance validation (PV) | 21.3.1 | rv{32/64}gc | rv64gc |
| Branch predictor PV | 21.3.2 | rv{32/64}gc | rv64gc |
| Linux boot | 22.3.2 | rv64gc | rv64gc |
| ImperasDV lock-step | 5.6, 5.11.9 |  | rv64gc |
| FPGA Linux boot | 23.2 |  | rv64gc |
| Code coverage | 5.11.11 |  | rv64gc |
| Functional coverage | 5.11.12 |  | rv64gc |

Notice **performance validation**: a cache or branch predictor that is functionally correct but slow is still a bug, and only a performance test catches it. The live plan is in `docs/testplans`. Build the tests with `make --jobs`, then run everything except the FPGA boot with `regression-wally --nightly`.

### Reference models (5.11.2)

- **RISCOF + Sail** generate the reference signatures. Tests that use CSRs, interrupts or peripherals Sail can't model set `NO_SAIL=True` and use hand-written signatures. The whole GCC → RISCOF → Sail → Verilator flow is open source.
- **ImperasDV** (commercial) does rv64gc lock-step. It confirms the hand-written signatures, catches discrepancies that never reach a signature, and has even found a bug **in Sail** (the Zfa `fcvtmod.w.d` instruction). Reference models have bugs too, which is why every mismatch is investigated on both sides.

### The testbench (5.11.3)

`testbench/testbench.sv` takes `+TEST=<suite>` and then:

- picks the suite from `tests.vh`
- instantiates `wallypipelinedsoc`
- generates clock and reset
- runs `riscvassertions`
- decodes instruction names and labels for the waveforms

For each program in the suite it:

1. Loads `test.elf.memfile` at 0x80000000.
2. Runs until the self-loop or `write_tohost`.
3. Flushes the D-cache back to memory, since results may still sit in the cache.
4. Compares the signature range with `test.signature.output` and reports.

**Design choice:** each test file runs in under a second, but starting the simulator and compiling Wally takes many seconds, so **one simulation runs a whole suite back to back**. Interrupt tests program the CLINT, PLIC and GPIO from software (8.3.2). The `buildroot` case runs the first 1.6 million instructions of a Linux boot and checks only that it doesn't hang; the full lock-step boot takes several days.

### Lint, simulate, regress (5.11.4–5.11.6)

- `lint-wally` lints rv32e, rv64gc, rv32gc, rv32imc, rv32i, rv64i and fdqh\_rv64gc through `testbench/wallywrapper.sv`, because some problems only appear in one configuration.
- `wsim <config> <suite>` is one front end for all three simulators. Key options:
  - `--sim {questa,verilator,vcs}`, `--gui`, `--vcd`
  - `--tb testbench_fp`
  - `--ccov` (code coverage), `--fcov` (functional coverage)
  - `--lockstep` / `--lockstepverbose`
  - `--args` (plusargs), `--params` (parameter overrides), `--define`

  For example, `wsim rv64gc arch64i` prints `rv64i_m/I/src/add-01.S succeeded. Brilliant!!!` for each file and ends with `SUCCESS! All tests ran without failures.`
- `regression-wally` runs lint plus every suite in parallel on Verilator. Logs go to `logs/<config>_<suite>.log`. **Run it before every commit**; that is what keeps the tree always working.
- `regression-wally --nightly` adds everything below. `nightly_build.py` clones fresh, builds, runs it, emails the results, and keeps 30 days of logs; it is scheduled with cron at 9 PM.
  - all derived configurations, linted and run
  - Questa and VCS as well as Verilator
  - ImperasDV lock-step on wally-riscv-arch-test, the coverage tests and the Linux boot
  - TestFloat on every FP configuration
  - functional coverage
  - cache performance validation
  - CoreMark and Embench

### Debugging (5.11.7)

The book plants three bugs and finds them in order. The method generalizes to any failure.

&#91;embedded content: The book's three-bug debugging exercise (Section 5.11.7) as a procedure\]

Principles behind it:

- The pattern of failures tells you the kind of bug. Everything failing means a build or elaboration problem; one family failing means a logic bug in shared hardware.
- Start from the test you understand best.
- Shrink the reproduction until it runs in seconds.
- Go from the observed effect (a store address) back through *contributing signals* to the first wrong value.
- Fix the cause, not the symptom, then rerun the full regression.

I reproduced bug 3 in the labs core: lock-step stopped at the first wrong `or` (see 5.6).

### FPU unit testing (5.11.8)

TestFloat (16.5.2) finds FPU bugs that riscv-arch-test missed and also covers quad precision. It is **unit-level** on purpose: `testbench-fp.sv` applies vectors from `tests/fp/vectors` straight to the FP execution units, with no programs, register setup or signatures, so it is much faster. For example, `wsim f_rv64gc add --tb testbench_fp` runs `f32_add_rne.tv` and the other rounding modes. The nightly run covers half, single, double and quad precision on every FP configuration. This is 5.1.3's rule in practice: unit-level testing is worth it when the interface is clean and the input space is huge.

### Lock-step with ImperasDV (5.11.9)

`wsim rv64gc <path>/add-01.S/ref/ref.elf --lockstep` ends with an ImperasDV report: `Total compares : 24,371 / Mismatches : 0`. `--lockstepverbose` logs each instruction, for example `0x80000000(rvtest_init): Machine 7d5c0837 lui x16,0x7d5c0` and `x16 0000000000000000 -> 000000007d5c0000`. The model takes memory and peripheral read values and interrupt timing from the RTL. This technique has found **at least 20 bugs in Wally** \[Thompson23\]. The nightly run lock-steps all of wally-riscv-arch-test, the coverage tests and the Linux boot.

### Code coverage on rv64gc (5.11.11)

Build `tests/coverage` (hand-written directed tests for illegal instructions, every TLB and PMP entry, and so on), then run `regression-wally --ccov`. Reports land in `sim/questa/cov` and `sim/covhtmlreport/index.html`; the `*_uncovered_*.rpt` files are the useful ones.

**Example 1: a missing test.**

- Branches are opcode 1100011 with any funct3 except 010 and 011; `if (BFunctD)` in `controller.sv` checks that.
- riscv-arch-test never sends a malformed branch, so the false side of that `if` is never taken.
- The coverage report shows it at line 211: `***0*** All False Count`.
- The fix is a single line in `tests/coverage/ieu.S`: `.word 0x00002063`. That is opcode 0x63 with funct3 = 010 and everything else zero, written with `.word` because no assembler mnemonic produces an illegal branch.

**Example 2: a justified exclusion.**

- The I-cache and D-cache share `cachefsm.sv`, but `InvalidateCache` only ever happens on the I-cache, so one branch is unreachable in the D-cache (`112  2  ***0***`).
- The source line gets a marker comment: `// exclusion-tag: dcache InvalidateCheck`.
- The exclusion file finds that line by its text instead of by line number: `coverage exclude -scope /dut/core/lsu/bus/dcache/dcache/cachefsm -linerange [GetLineNum ../src/cache/cachefsm.sv "exclusion-tag: dcache InvalidateCheck"] -item b 2`.
- **Why the tag:** exclusions written as raw line numbers break silently whenever the file is edited. Scoping it to the D-cache keeps the same code in the I-cache measured.

### Functional coverage (5.11.12)

The flow, run from `addins/cvw-arch-verif`: `make --jobs` runs `covergroupgen.py` (CSV test plans to covergroups in `fcov`) and `testgen.py` (covergroups to directed assembly tests), then `regression-wally --fcov` runs those tests in lock-step under Questa, merges the `.ucdb` files and writes reports. At the time of the book, rv32gc stood at 79 covergroups, 69.70% of covergroups and 65.97% of bins covered. `beq` was at 96.42%, its only gap being `cp_offset` bin `neg` = 0. **No test had taken a backward branch yet**, which is exactly the kind of hole functional coverage exists to expose. The next targets are privileged features: virtual memory, PMP and CSRs.

## Chapter 5 recap and interview drill

### The chapter in six sentences

1. Verification costs more than design: a testbench applies vectors to the DUT and compares the results against an independent reference model, and the hard parts are choosing features, vectors, the reference, debugging and run time.
2. Vectors go from exhaustive (tiny blocks) and ad hoc, through directed corners and coverage-driven tests, to constrained random; teams use all of them, and coverage says when to stop.
3. A DV plan lists every feature with its specification reference, stimulus, checker and coverage item; lint keeps the RTL clean; testbenches drive inputs on one edge and check outputs on the other with x-safe `!==`.
4. Lock-step-compare over RVVI checks every retired instruction against a reference fed the same interrupts and read values. Signatures check only an end state.
5. Assertions catch rule violations where and when they happen, code coverage proves the RTL was exercised (expression coverage, not just lines), functional coverage proves the features were exercised, and formal proves properties on small cones.
6. Wally applies all of this, from TRL3 on every configuration to TRL5 on rv64gc: lint, Sail signatures, ImperasDV lock-step, TestFloat, coverage with reviewed exclusions, regressions before every commit and nightly.

### Interview questions with model answers

**Q1. You are given a new RISC-V core. Describe your verification strategy.** Start with a DV plan by area (base ISA, each extension, privileged, microarchitecture), each feature with its spec reference, stimulus, checker and coverage item. Set up lint and a smoke regression first, so the tree stays always-working. Bring up compliance (riscv-arch-test through RISCOF). Then build the main engine: a tracer feeding RVVI to a reference model (Sail, Spike or ImperasDV) for lock-step on every test, plus functional coverage on the same RVVI stream. Add directed tests from the coverpoints, constrained random (riscv-dv or a home-grown generator) for interactions, and assertions on interfaces and hazard logic. Close with code and functional coverage to 100% using reviewed exclusions, plus performance tests and a Linux boot. Run unit-level tests where the interface is clean, such as TestFloat on the FPU.

**Q2. Signature checking versus lock-step: compare them.** A signature stores a few results at the end and compares them with a reference file. It is simple and portable, but blind to anything that never reaches the signature: early FP tests missed the exception flags, overwritten intermediate values are lost, and a long Linux boot has no useful signature. Lock-step compares PC, registers, CSRs and memory after every retired instruction and stops at the first divergence. It needs a tracer, a configurable reference, and identical interrupts and peripheral read values. In my labs core it pinpointed the injected OR→+ bug at retired instruction #55.

**Q3. Code coverage is 100%. Are you done?** No. Code coverage proves the code that exists was exercised, not that it is correct, and not that every feature exists at all. Line and statement coverage are especially weak. I showed a full adder with a deleted a&c term passing its tests at 100% statement coverage, and expression coverage was 83% with the hole exactly where the bug was. You also need functional coverage against the DV plan, lock-step or self-checking to prove the results were right, and review of every exclusion.

**Q4. What is expression or condition coverage and why does it matter?** Each input of a boolean expression must be seen at 0 and at 1 while the other inputs are set so that it alone decides the output, its non-masking condition (MC/DC-style). For `a&b | a&c | b&c`, input a only counts when b ≠ c. It catches tests that exercise a line without ever showing that each term matters. In the full adder, 4 well-chosen vectors (001, 010, 011, 101) already give 100% expression coverage and catch the dropped-term bug.

**Q5. Write an assertion for "HTRANS must not change while HREADY is low", and explain `|=>`.** `assert property (@(posedge HCLK) disable iff (!HRESETn) !HREADY |=> $stable(HTRANS) | ($past(HTRANS)==IDLE) | ($past(HTRANS)==BUSY & HBURST!=SINGLE));`. The `|=>` operator checks the consequent one cycle after the antecedent; `|->` checks it in the same cycle. When HREADY is high the property passes vacuously, so I would add `cover property (!HREADY)` to prove the check really ran. In Verilator it fired at the exact edge where HTRANS changed (t = 55).

**Q6. A regression run shows 72 configurations failing. Where do you start?** Widespread failure means a build or elaboration problem, not logic. Read the first error in any log, for example "ForwardedSrcAE is driven by more than one continuous assignment". If only some suites fail, pick the one you understand best and read its log for the test, result number, address, and simulated versus expected value. Find the instruction in the objdump, move that test to the front, open waves at the store address, walk back to the first wrong value with Contributing Signals, fix the cause, and rerun the full regression.

**Q7. How do you handle unreachable code in coverage?** Prove it is unreachable for that configuration or instance (for example, I-cache invalidate logic inside the shared D-cache FSM), then add a scoped exclusion with a written reason, anchored to a tag in the source rather than a line number, as Wally does with GetLineNum and exclusion tags. Review exclusions periodically, because a stale one hides real holes.

**Q8. When is formal the right tool?** For control-dominated blocks with small cones of influence: arbiters, FIFOs, protocol checkers, one-hot and mutual-exclusion properties, hazard and forwarding logic, and equivalence checking after synthesis. It explores every legal input, so it finds corner cases simulation never reaches, and a failure comes with a short counterexample trace. It struggles with wide datapaths and whole cores. OpenHW's formal run on CV32E40P found many bugs but couldn't complete a proof against Sail.

**Q9. Unit-level or system-level testing: how do you choose?** System-level is cheaper to build, since you just load a program, and it catches integration bugs, so it is the default for blocks with complex interfaces such as the LSU. Unit-level pays off when the interface is clean and the input space is huge. Wally's FPU runs millions of TestFloat vectors straight into the execution units, much faster than through programs. In an SoC, teams usually verify whole cores and accelerators, then the integration.

**Q10. Tell me about a famous bug and what it teaches verification.** The 1994 Pentium FDIV bug: a tool dropped 5 of 1,066 entries from the divider's quotient-selection PLA, giving wrong results in about 1 in 9 billion random divisions. The recall cost $475 million. The lessons: rare bugs need volume or proof rather than a few directed corners; verify what is actually built (the tool output, not just the equations); and lock-step on random tests plus equivalence checking after synthesis are the modern defenses.

### Try it

The [Verification Bench](https://claude.ai/artifact/Mi6NpcAFs87APrrt3Zz2Yd) has three parts:

- **Full-adder coverage:** choose vectors, inject one of three bugs, and watch statement coverage stay at 100% while expression coverage exposes the hole.
- **Assertion lab:** an editable AHB timeline where the concurrent assertion re-evaluates edge by edge (the book scenario, plus legal and illegal BUSY→SEQ cases).
- **Self-check:** eight interview questions with explanations.

### How Chapter 5 connects forward

| Ch 5 idea | Where it comes back |
| --- | --- |
| Gate-level checks and equivalence after synthesis | Ch 6 (logic synthesis) |
| Pipeline hazards as coverage targets (cp\_gpr\_hazard) | Ch 7 (pipelined core) |
| Privileged tests, interrupts via CLINT, PLIC and GPIO | Ch 8 |
| Cache FSM coverage and exclusions | Ch 10 (caches) |
| TLB and PMP directed coverage tests | Ch 11 (MMU) |
| TestFloat unit testing | Ch 16 (floating point) |
| CoreMark, Embench, performance validation | Ch 21 |
| Linux boot in lock-step | Ch 22 |
| FPGA emulation and Linux boot | Ch 23 |

The two sections below are from our first pass through this chapter: scripted spoken answers and a three-level Q&A ladder. They are kept as extra drill material.

## Say it in the interview

Practice each out loud until it takes 60–90 seconds. Swap in your own project details wherever you can; a real example beats a perfect definition.

### "How would you verify a RISC-V core?"

> I layer methods so every bug has more than one chance of being caught. Lint first, to remove static problems cheaply. Then ISA compliance with riscv-arch-test, which gives per-instruction coverage but only checks an end-of-test signature. The backbone is lock-step-compare: a tracer publishes every retired instruction on RVVI, and a reference model like ImperasDV or Spike runs the same program and compares PC, registers, CSRs and memory after each instruction, so I see the first divergence, not a symptom millions of cycles later. On top of that, constrained-random generation such as riscv-dv finds combinations no one planned, like an interrupt arriving while fetch is stalled on a TLB miss. Unit testbenches go where vector volume matters, like TestFloat on the FPU. Sign-off is 100% functional coverage from the DV plan, 100% code coverage with reviewed exclusions, a clean regression and no open issues — all while agreeing with the reference model.

### "Why is lock-step better than signature checking? What's hard about it?"

> A signature is one value after many instructions. It can mask errors — early riscv-arch-test FP tests checked results but not the FP flags — and Linux or benchmarks give no signature at all. Lock-step checks the full architectural state after every instruction, so I get the exact instruction where things went wrong. The hard parts are synchronization and legal ambiguity. Interrupts, debug requests and values read from memory or peripherals must be fed into the model at the same instruction boundary, or the models diverge for non-bug reasons. And where the spec allows several behaviors, the model must be configured to match the DUT — XLEN, extensions, WARL fields like whether mstatus.UXL is writable. Once that's right it's very powerful: ImperasDV even found a bug in Sail's implementation of a Zfa instruction.

### "Code coverage vs functional coverage?"

> Code coverage asks whether every line, branch, condition and FSM transition in the RTL ran. It's necessary but blind to features nobody coded. Functional coverage asks whether every feature and scenario in the DV plan happened — every instruction with every register, sign and corner value, hazards, interrupts, cache states. A nice illustration: on a full adder, removing two of the eight vectors leaves statement coverage at 100% while expression coverage drops to 83%, because `cout` never depended on `a` alone. And coverage only counts if the result was also correct, so I collect it while running in lockstep.

### "Unit-level or system-level testing?"

> Both, chosen by interface complexity. Unit testbenches are faster and catch bugs early, but driving every control and stall signal into something like an LSU is expensive. System tests just load a program. So I unit-test large blocks with clean interfaces where volume pays off — the FPU with millions of TestFloat vectors, half to quad precision — and rely on system-level lockstep for the tightly coupled units inside the pipeline.

### "Walk me through debugging a failing regression."

> First, triage the shape: if almost every test fails, it's structural — a compile issue, multiple drivers, a broken config — so I read the first error in any log. If a subset fails, I pick the simplest failing test I understand, read which check failed and the expected versus actual value, and find the instruction in the disassembly. I make it fail early by running it first, open waveforms, find the bad store or write-back, and walk the contributing signals backward stage by stage until a value is wrong while its inputs are right. That's the bug. After fixing it I rerun the full regression, and I ask why nothing caught it sooner — often that means adding an assertion or a coverpoint.

### "When is verification done?"

> When the evidence says so, not the calendar. Every DV-plan feature has tests and coverage; functional coverage is 100%; code coverage is 100% with every exclusion justified and reviewed; regression passes across all supported configurations and simulators; lockstep shows zero mismatches including long runs like a Linux boot; and there are no open bugs. That's essentially the OpenHW TRL5 checklist. I'd also watch the bug-discovery rate — if random tests are still finding bugs, we're not done regardless of the numbers.

## Q&A ladder

Level 1 checks vocabulary, level 2 checks judgment, level 3 is where senior offers are decided. Each answer lists the points to hit and the follow-up you should expect.

### Level 1 — fundamentals

1. **What are the main verification challenges?**
   - Deciding what to test, choosing vectors, building a trustworthy reference model, localizing bugs, long runtimes.
   - *Follow-up:* which is hardest on a CPU? (Usually the reference model and its synchronization.)
2. **Why not test exhaustively?**
   - Fine for a full adder (8 vectors); a 64-bit adder needs 2^128.
   - *Follow-up:* then how do you test a 64-bit adder? (Corner-value cross product — 12 × 12 = 144 — plus random; and remember corners miss mid-range typos.)
3. **Immediate vs concurrent assertions?**
   - Immediate: procedural, checks now. Deferred (`assert final`) waits for glitches to settle. Concurrent: clocked properties across cycles with `|->`, `$past`, `$stable`, `disable iff`.
   - *Follow-up:* write one for a FIFO (no push when full, no pop when empty).
4. **What does lint catch?**
   - Latches, combinational loops, width mismatches, undriven/unused signals, missing case defaults, unsynthesizable code.
   - *Follow-up:* how do you handle a false lint warning? (Waive locally with on/off pragmas and a reason, never globally.)
5. **Why `===` in a testbench?**
   - `==` with X/Z returns X, so a check can silently pass; `===` compares X and Z literally.

### Level 2 — judgment

6. **Pros and cons of booting Linux as a test?**
   - Pro: exercises instruction × exception × cache × VM interplay cheaply. Con: no feature-level coverage, no signature, a pass says little, failures are hard to localize.
   - *Follow-up:* how would you make it a real check? (Run it in lockstep with the reference model.)
7. **Why must the reference model come from a different team?**
   - Same people, same misreading of the spec — both models agree and both are wrong.
   - *Follow-up:* what if the RTL and the model disagree and the spec is ambiguous? (Agree the legal choice, configure the model, record it in the DV plan.)
8. **What goes in a DV plan entry?**
   - Spec reference, feature description, stimulus, checking method, coverage spec, link to the coverage result. Organized area → feature → subfeature.
   - *Follow-up:* write the DIV entry. (All registers, rd = rs, corner values, divide by zero, signed overflow.)
9. **Always-broken vs always-working development?**
   - Late integration leaves the system broken and bugs entangled; incremental integration with regression before every check-in tells you which change broke it.
   - *Follow-up:* how do you keep a large team always-working? (Gated commits, fast pre-commit regression, nightly full regression, quick revert culture.)
10. **You're at 100% code coverage. Are you done?**
    - No. It can't see unimplemented features, and expression/condition holes hide behind 100% statement coverage. Need functional coverage, lockstep agreement and reviewed exclusions.
11. **When would you exclude code from coverage, and what's the risk?**
    - Truly unreachable logic in a configuration (e.g. the I-cache invalidate path inside a shared FSM used as a D-cache). Risk: stale or sloppy exclusions hide real holes; tie exclusions to tags, not line numbers, and review them.
12. **FPGA emulation vs simulation?**
    - Emulation: MHz vs kHz, runs OS boots and long workloads. Simulation: full visibility, fast iteration. Use emulation to find, then reproduce in simulation to debug.

### Level 3 — senior CPU DV

13. **Design a lock-step setup for an out-of-order core.**
    - Compare at retire, in program order; the tracer must expose retire-order state and drop wrong-path instructions.
    - Feed async events (interrupts, debug) at the exact retirement boundary; pass observed load data for non-deterministic sources (device reads, other cores).
    - Configure all WARL and implementation-defined choices.
    - *Follow-up:* how do you handle multiple instructions retiring in one cycle? (Tracer emits each retirement in order; RVVI supports multiple retire slots.)
14. **Your coverage is 100% but a bug escaped. What was missing?**
    - Coverage of the wrong things: no crosses (instruction × hazard × interrupt), no microarchitectural states (queues full, miss under miss), no negative tests, configurations not exercised, or a checker that wasn't comparing that state.
    - *Follow-up:* how would you change the coverage model? (Add microarch coverpoints and crosses; add checks before adding stimulus.)
15. **How do you find bugs in the reference model itself?**
    - Cross-check two models (Sail vs Spike via RISCOF, ImperasDV vs Sail); triage every mismatch without assuming the RTL is wrong.
16. **Where would you apply formal on a CPU, and why not everywhere?**
    - Small-cone, control-heavy blocks: arbiters, decoders, FIFOs, CSR legality, coherence protocol tables, deadlock properties. Whole-core proof against Sail is impractical (OpenHW's CV32E40P experience).
17. **Regression takes 12 hours. Make it faster.**
    - Run suites back-to-back in one simulation to amortize startup; parallelize across a farm; split smoke (pre-commit) from nightly; use a fast simulator like Verilator for gating; rank tests by coverage contribution and drop redundant ones.
18. **Tell me a case where unit testing beats system testing.**
    - FPU with TestFloat: huge vector counts, no code overhead, every precision, found bugs riscv-arch-test missed. Mention the FDIV bug as the cost of not doing it.
19. **What are chicken bits and why do verification engineers care?**
    - Firmware-controlled switches to disable a feature that turns out buggy after tape-out. DV must verify both settings work, because the fallback path becomes the product if the feature fails.

### Tie it to your own work

- Which of these layers did your RISC-V subsystem testbench use, and which did it lack?
- One bug you found, and which layer caught it (assertion, scoreboard, coverage hole, lockstep)?
- How you verified GPIO pinmuxing: what the coverage model looked like and which exclusions you justified.

## Book coverage check (Ch 5 audit)

I compared this tab with all 39 sections of Chapter 5, including every transcript and report excerpt in the book. This tab was already the most complete one. The book details below were still missing; most of them are worth telling as a story in an interview.

### The book's debugging exercise, exactly (5.11.7)

The book plants three bugs in `$WALLY/src`, one for each layer of the flow, then finds them in this order:

| # | Planted bug | Caught by | What the tool says | Lesson |
| --- | --- | --- | --- | --- |
| 1 | `inputt logic clk, reset,` in `ieu/ieu.sv` | `lint-wally` | `syntax error, unexpected logic, expecting ')' or ','`, followed by a cascade of further errors | Fix only the **first** error and ignore the cascade |
| 2 | `fbemux` output renamed to ForwardedSrc**A**E in `ieu/datapath.sv`, so it contends with `faemux` | `regression-wally`: "Regression failed with **72** failed configurations" | Questa `vopt-7045`: "'ForwardedSrcAE' is driven by more than one continuous assignment" | When almost everything fails, the cause is structural, so read the log tail, not the waves |
| 3 | OR written as `A + CondMaskInvB` in `ieu/alu.sv` | Some tests fail: `rv32i_m/I/or-01` (arch32i fails, while wally32periph and arch32m pass) | `Error on test rv32i_m/I/src/or-01.S result 2: adr = 80006118 sim (D$) 00000004 signature = 00000002` | A failure pattern confined to one family points to shared logic |

The waveform procedure for bug 3:

1. Move the failing test to the front of its suite in `tests.vh` so it fails within seconds.
2. Run `wsim --gui rv32imc arch32i`.
3. Search **IEUAdrM** for the bad store address 0x80006118.
4. Step back two cycles: SrcAE = SrcBE = 2, ALUResultE = 4.
5. Use Questa's *Add → To Wave → Contributing Signals* repeatedly: ALUResultE → PreALUResult → FullResult, with ALUSelect = 6.
6. The `case (ALUSelect)` row 3'b110 shows the `+`.

The failing instruction is `or a7, t1, t1` with t1 = 2, stored with `sw a7, 4(gp)`. gp = signature\_x3\_0 = 0x80006114, so result 2 lands at 0x80006118.

**Interview use:** this is a ready answer to "walk me through how you debug a failing regression": failure pattern → smallest failing test → address of the first wrong architectural write → back through the contributing signals to the first wrong value → fix → full regression.

### riscvISACOV details the tab skipped (Fig. 5.5)

- Every coverpoint is guarded by `iff (ins.trap == 0)`. **A trapping instruction never counts toward that instruction's coverage.** Its effects belong to the exception coverage instead.
- Coverage comes in levels set by macros:
  - **Base:** register assignments, signs and the sign cross.
  - **`COVER_LEVEL_COMPL_EXT`** adds rs1 == rs2 per register, toggle and maxvals bins.
  - **`COVER_LEVEL_DV_UP_BAS`** adds rd == rs1 / rd == rs2 (WAR on the same register), value-equality bins and `cp_gpr_hazard` (NO / RAW / WAR / WAW).
  - Choose the level to fit the stage of the project.
- Toggle bins are wildcard bins, one per bit per value (`bit_5_0 = {32'b??…?0?????}`). Maxvals uses `zeros`, `min` = 0x80000000, `max` = 0x7FFFFFFF and `ones`. Sign bins are `neg = {[$:-1]}` and `pos = {[1:$]}` after an `int'()` cast. Zero falls in neither bin, which is why maxvals exists.
- `option.per_instance = 1` reports each covergroup instance on its own. The sampled object is `ins_rv32i_t ins`, filled from RVVI on the clock edge when the instruction retires. `ins.get_gpr_reg()` maps register numbers to names, and `check_gpr_hazards(ins.hart, ins.issue)` compares against recent instructions.

### Smaller facts

- **Effort.** "Logic verification now accounts for nearly twice as much effort as all the other elements of chip design combined." Software bugs get patched; a serious hardware bug costs a new mask set (millions of dollars) plus the cost of shipping late. Defining what to test, the stimulus and the expected results is harder than coding the features.
- **Chicken bits.** Experienced teams assume some bugs will escape and add firmware-programmable configuration bits that disable or work around a defective unit. Mentioning them shows you think past tape-out.
- **Questa practicalities.**
  - Use a do-file with `vlog` / `vopt +acc work.testbench -o workopt` / `vsim workopt` for GUI runs, `vsim -c -do` for batch runs, and `qrun file.sv` for one-shot runs.
  - Remote GUIs should go over X2Go or VNC; `ssh -Y` works but is painfully slow.
  - Questa prefers `$stop`, because it keeps the waves and coverage. Verilator prefers `$finish`.
- **Verilator build.** It generates C++ in `obj_dir/` and builds `verilated.o`, `verilated_vcd_c.o` (tracing), `verilated_timing.o` (the `--timing` coroutines that let `#` delays and event controls in testbenches work) and `verilated_threads.o`. The book used 5.025.
- **Book references.** The functional-coverage definition is from \[Mehta20\]. The book also points to IEEE 1800-2017 for the object-oriented testbench features that Chapter 5 leaves out. That gap is exactly where UVM sits, and Lab 11's RAL notes cover the register side of it.
