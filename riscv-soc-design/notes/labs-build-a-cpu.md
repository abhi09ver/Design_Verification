# Build a CPU from scratch

You built a working RV32I core twice — single-cycle, then 5-stage pipelined — with Wally's names and partitioning, and verified it with a mini lock-step flow that catches 5 out of 5 injected pipeline bugs. The code is in the `cpu-from-scratch` package; run `make pipe` and `make bugs` to reproduce everything here.

## Wally source map

Wally's whole core is about 25,000 lines of SystemVerilog in 14 folders under `cvw/src`; the labs give you working versions of the first five rows, so read those first.

| Folder | Lines | What it is | Book | Read first |
| --- | --- | --- | --- | --- |
| `wally` | 463 | Top level: `wallypipelinedcore` wires every unit together | 2.8 | `wallypipelinedcore.sv` |
| `generic` | 1,888 | Flops, muxes, adders, encoders used everywhere | 4.2 | `flop/flopenrc.sv` |
| `ieu` | 3,876 | Integer execution unit: controller + datapath, ALU, regfile | 7 | `datapath.sv`, then `controller.sv` |
| `hazard` | 110 | Every stall and flush in the core | 7.2.2 | `hazard.sv` (read it all) |
| `ifu` | 2,087 | Fetch, PC logic, branch predictor, compressed decode | 13, 14 | `ifu.sv` (PCNextF logic) |
| `lsu` | 1,239 | Load/store unit: alignment, atomics, subword read/write | 12, 17 | `lsu.sv`, `subwordread.sv` |
| `privileged` | 1,950 | CSRs, privilege modes, traps | 8 | `trap.sv` |
| `mdu` | 376 | Multiply/divide | 15 | `mdu.sv` |
| `cache` | 825 | Shared instruction/data cache design and its FSM | 10 | `cachefsm.sv` |
| `mmu` | 1,769 | TLB, page-table walker, PMA/PMP checks | 11 | `tlb/`, `hptw.sv` |
| `ebu` | 801 | External bus unit (AHB) | 9 | `ebu.sv` |
| `fpu` | 6,103 | Floating point: FMA, divide/sqrt, convert | 16 | `fpu.sv` |
| `uncore` | 2,722 | Peripherals: CLINT, PLIC, UART, GPIO, SPI | 20 | `gpio.sv` (ties to your pinmux work) |
| `rvvi` | 540 | RVVI tracer for lock-step and coverage | 5.6 | `wallyTracer.sv` |

**How the labs map onto Wally, line for line:**

| You wrote | Wally equivalent |
| --- | --- |
| `fwd()` in `core_pipe.sv` | `controller.sv` ForwardAE/BE block (lines \~469–477) |
| `LoadStallD` | `controller.sv` MatchDE / LoadStallD (lines \~482–483) |
| `hazard.sv` (4 equations) | `hazard.sv` (same rules, plus cache misses, divides, CSR writes, traps) |
| `IEUAdr = {Sum[31:1], Sum[0] & ~Jump}` | `datapath.sv`: `IEUAdrE = {IEUAdrRawE[XLEN-1:1], IEUAdrRawE[0] & ~JumpE}` |
| `faemux`/`fbemux` order: register, W, M | `datapath.sv`: `mux3 faemux(R1E, ResultW, IFResultM, ForwardAE, ...)` |
| Negedge regfile write | `regfile.sv` |
| Trace from W | `rvvi/wallyTracer.sv` |

## The 5-stage pipeline at a glance

&#91;embedded content: 5-stage pipeline in core\_pipe.sv · forwarding, stall and flush paths\]

Everything interesting happens around Execute: it receives forwarded results from M and W, resolves branches and sends the target back to Fetch, while the hazard unit freezes or clears the stages in front of it.

## Lab 1 — single-cycle core

One instruction per clock: fetch, decode, execute, memory and write-back all happen in one long cycle. It runs the book's `riscvtest` in 19 cycles (CPI 1.00) and writes 25 to address 100.

### How one instruction flows (follow `core_single.sv` top to bottom)

1. **IFU** — the PC register drives instruction memory; `Instr` comes back combinationally.
2. **Decode** — `decoder` turns the opcode into control bits; `regfile` reads rs1/rs2; `extend` builds the immediate.
3. **Execute** — two muxes pick ALU operands (rs1 or PC; rs2 or immediate). The ALU computes the result; its adder output `Sum` doubles as the **address and branch/jump target**. `comparator` decides branches from rs1/rs2.
4. **LSU** — `subwordwrite` replicates store data and builds a byte mask; `subwordread` picks and sign/zero-extends bytes on loads.
5. **Write-back + next PC** — the result mux picks ALU/alternate/load data; the PC mux picks PC+4 or the target.

### The control table (all of RV32I in 10 rows)

| Opcode | Instructions | RegWrite | ALU A / B | Special |
| --- | --- | --- | --- | --- |
| 0110011 | add sub sll slt sltu xor srl sra or and | 1 | rs1 / rs2 | ALUSelect = funct3, SubArith = funct7\[5\] |
| 0010011 | addi slti sltiu xori ori andi slli srli srai | 1 | rs1 / imm I | SubArith only for srai |
| 0000011 | lb lh lw lbu lhu | 1 | rs1 / imm I | result from memory |
| 0100011 | sb sh sw | 0 | rs1 / imm S | byte mask |
| 1100011 | beq bne blt bge bltu bgeu | 0 | PC / imm B | comparator decides |
| 1101111 | jal | 1 | PC / imm J | rd = PC+4 |
| 1100111 | jalr | 1 | rs1 / imm I | rd = PC+4, target bit 0 cleared |
| 0110111 | lui | 1 | — | rd = immediate |
| 0010111 | auipc | 1 | PC / imm U |  |
| 0001111 | fence | 0 | — | no-op here |

### Five design decisions worth explaining in an interview

- **ALUSelect is just funct3.** RISC-V's encoding makes the decoder tiny; Wally does the same.
- **One adder, three jobs.** Load/store address, branch target and jump target all come from the ALU adder, so the comparator must be separate.
- **The addi trap.** Bit 30 is an opcode bit for `srai` but an immediate bit for `addi`. Decode SubArith from it for every I-type and `addi x, y, 1024` silently subtracts. The directed test checks exactly this (test 23).
- **jalr clears bit 0 of its target** — easy to forget; tested with an odd target.
- **Register-file write edge.** Single-cycle writes on the *rising* edge. A falling-edge write corrupts `jalr ra, 0(ra)` mid-cycle, because the writer is still reading its own source. The pipeline flips this (next labs).

## Lab 2 — the verification flow

Each test is assembled with gcc, run on both the RTL and an independent Python reference model, and the two retirement traces are compared line by line — the same idea as Wally's ImperasDV lock-step, done after the run instead of during it.

| Piece | File | Industrial equivalent | What it does |
| --- | --- | --- | --- |
| Reference model | `dv/iss.py` | Sail, Spike, ImperasDV | Executes one instruction at a time, purely from the ISA |
| Random generator | `dv/gen.py` | riscv-dv | Constrained-random RV32I programs |
| Tracer | `tb/tb.sv` + core trace ports | RVVI-TRACE, `wallyTracer.sv` | One line per retired instruction: PC, insn, rd write, memory write |
| Compare | `dv/compare.py` | ImperasDV state compare | Reports the **first** divergent instruction and which field differs |
| Coverage | `dv/coverage.py` | riscvISACOV, `vcover merge` | 64 bins: instructions, branch outcomes, hazard distances, corner cases |
| Regression | `dv/regress.py` | `regression-wally` | Build, run directed + N random seeds, merge coverage |

### The constraints that make random useful

- **Small register pool** (mostly x1–x7) and a 50% chance of reading something written in the last 3 instructions → constant RAW hazards.
- **x0 as a destination** 8% of the time → "writes to x0 must vanish" is exercised.
- **Corner values** (0, ±1, 0x7FFFFFFF, 0x80000000) for operands and immediates.
- **Loads/stores in a 256-byte window** so stores and loads alias.
- **Forward-only branches and jumps** (1–4 instructions ahead) → no infinite loops, and every taken branch leaves wrong-path instructions for the pipeline to flush.

### Two lessons the flow forced on me while building it

- **A failing self-checking test still "matches" the reference model**: both execute the failure path identically. The regression now requires *both* a matching trace and a PASS from the test.
- **The reference model was written separately from the RTL** (Python vs SV, ISA spec vs datapath) so they don't share a misunderstanding — the Chapter 5 rule.

**Result:** single-cycle core, 23 tests (book + 2 directed + 20 random seeds): all match, 64/64 coverage bins.

## Lab 3 — the 5-stage pipeline

Same units, cut into F / D / E / M / W with `flopenrc` registers between them. Up to five instructions are in flight, so every signal carries its stage: `RdE`, `RdM` and `RdW` belong to three different instructions. It passes 53/53 tests (book + 2 directed + 50 random) at 100% coverage; the book test now takes 28 cycles (CPI 1.47) because of pipeline fill and three taken branches.

### The hazard rules (all of `hazard.sv` + the forwarding function)

| Hazard | Detected | Fix | Cost |
| --- | --- | --- | --- |
| RAW, producer 1 ahead | Rs1E/Rs2E == RdM, RegWriteM, rs ≠ x0 | Forward IEUResultM | 0 cycles |
| RAW, producer 2 ahead | Rs1E/Rs2E == RdW, RegWriteW, rs ≠ x0 | Forward ResultW | 0 cycles |
| RAW, producer 3 ahead | — | Falling-edge regfile write, read in second half | 0 cycles |
| Both M and W match | — | M wins: it is the newer instruction | 0 cycles |
| Load-use | MemReadE and RdE == Rs1D/Rs2D (≠ x0) | Stall F and D, bubble into E, then forward from W | 1 cycle |
| Taken branch or jump | PCSrcE in Execute | Flush D and E (2 wrong-path instructions) | 2 cycles |

Two general rules come straight from Wally's `hazard.sv`: a stage stalls if the next one stalls, and the first unstalled stage after a stall must flush, or the same instruction would be issued twice.

### Watching it: the book's Fig. 7.15 program on your RTL

`python3 dv/pipeview.py tests/directed/hazard_demo.S` prints what sits in each stage every cycle:

```
cyc | F               | D               | E               | M               | W               | hazard unit
  4 | lb t2,0(s0)     | ori t1,t0,1     | addi t0,zero,42 | addi s0,s0,0    | auipc s0,0x8    |
  5 | and t3,t2,t0    | lb t2,0(s0)     | ori t1,t0,1     | addi t0,zero,42 | addi s0,s0,0    | fwd rs1 from M
  6 | beq t3,zero,+12 | and t3,t2,t0    | lb t2,0(s0)     | ori t1,t0,1     | addi t0,zero,42 | STALL F,D (load-use)
  7 | beq t3,zero,+12 | and t3,t2,t0    | (bubble)        | lb t2,0(s0)     | ori t1,t0,1     |
  8 | sb t3,0(s0)     | beq t3,zero,+12 | and t3,t2,t0    | (bubble)        | lb t2,0(s0)     | fwd rs1 from W
  9 | xori t4,t3,1    | sb t3,0(s0)     | beq t3,zero,+12 | and t3,t2,t0    | (bubble)        | FLUSH D,E, fwd rs1 from M
 10 | sub t5,t1,t4    | (bubble)        | (bubble)        | beq t3,zero,+12 | and t3,t2,t0    |
```

Read it like the book's figure:

- **Cycle 5:** `ori` needs `t0` from the `addi` one ahead (now in M) → forward from M.
- **Cycle 6:** `and` needs `t2` from the `lb` right ahead; the data doesn't exist yet → stall F and D.
- **Cycle 7:** the bubble enters E; `beq` and `and` hold their places.
- **Cycle 8:** `lb` reaches W → forward its data to `and`.
- **Cycle 9:** `beq` resolves taken in E → `sb` and `xori` are flushed.
- **Cycle 10:** `sub` (the target) is fetched; two bubbles follow it down the pipe.

**Simplifications vs Wally:** memories answer in the same cycle (no caches or bus stalls), no exceptions or CSRs, no branch predictor, no compressed instructions. Each is a next lab (below).

## Bug hunt — which tests catch which bug

Random lock-step caught all five injected pipeline bugs; each of the two directed tests missed one, and the coverage report predicted exactly which. Run it yourself with `make bugs`.

| Injected bug (`-D` switch) | Book test | Directed self-check | Random lock-step (20 seeds) |
| --- | --- | --- | --- |
| `BUG_FWD_PRIORITY` — W checked before M | caught | caught | 20/20 |
| `BUG_NO_FWD_W` — no Writeback forwarding | caught | caught | 20/20 |
| `BUG_FWD_X0` — x0 treated as a real destination | **missed** | caught | 20/20 |
| `BUG_NO_LOAD_STALL` — forwards the load address, not data | caught | **missed** | 19/20 |
| `BUG_NO_FLUSH_E` — one wrong-path instruction survives | caught | caught | 20/20 |

### Why each directed test missed its bug — coverage tells you

| Test | Coverage | Hole that matters |
| --- | --- | --- |
| Book `riscvtest` | 21/64 bins (33%) | `x0_fwd` never hit: it never reads x0 right after writing it |
| Directed self-check | 58/64 bins (91%), **100% instruction and branch coverage** | `raw.load.dist1` never hit: no consumer right after a load |
| Random, 50 seeds | 64/64 bins | — |

The second row is Chapter 5's warning in miniature: complete **architectural** coverage, yet a **microarchitectural** bug slips through. The fix is a coverpoint that names the hazard, not more instructions.

### What the first divergence looks like (real output)

**Forwarding priority.** The `la x30, L` pseudo-instruction expands to `auipc x30` then `addi x30, x30, 20`, and the next `jalr` reads x30. With W checked first, `jalr` gets the stale `auipc` value and jumps to the wrong place:

```
   ok   pc=80000160 insn=00000f17 x30=80000160     auipc x30
   ok   pc=80000164 insn=014f0f13 x30=80000174     addi  x30,x30,20
   ok   pc=80000168 insn=000f01e7 x3=8000016c      jalr  x3,0(x30)
   ref  pc=80000174 ...                            correct target
   dut  pc=80000160 ...                            used the OLDER x30
```

**No E flush, subtle case.** A `bge` whose target is PC+4 is "taken" to the very next instruction. Without the E flush, that instruction runs twice — the trace shows pc 80000100 retiring twice.

**x0 forwarding.** `andi x0, x6, -1131` "writes" x0, then `li x6, 0` (really `addi x6, x0, 0`) reads x0 and gets 0x80000180 instead of 0.

### The interview story this gives you

> "I built a 5-stage RV32I core and a lock-step flow against my own reference model, then injected five classic pipeline bugs. The book's directed test missed the x0-forwarding bug, and my own directed test — 100% instruction and branch coverage — missed the load-use bug. Constrained-random lock-step caught all five, usually within a few hundred instructions, and the first-divergence report pointed at the exact instruction. The coverage report explained both misses before I even looked at waveforms, so I added hazard-distance coverpoints. That's why I don't treat ISA coverage as sign-off for a pipeline."

## Next labs toward Wally

Each lab adds one Wally unit, one new kind of hazard, and one new verification problem — the order below follows the book and the interview priority list.

| Lab | Add | New hazard / problem | Book | Wally file to compare |
| --- | --- | --- | --- | --- |
| 4 | CSRs, ecall, illegal-instruction trap, mret | Precise exceptions: flush everything younger, never retire the trapping instruction | 8 | `privileged/trap.sv`, `hazard.sv` FlushWCause |
| 5 | M extension with a multi-cycle divider | A stall that starts in E (`DivBusyE`); divide-by-0 and overflow corners | 15 | `mdu/`, `hazard.sv` StallECause |
| 6 | 2-bit/gshare predictor + BTB in Fetch | Mispredict recovery; performance as a verification target (misprediction rate) | 13, 21 | `ifu/bpred/` |
| 7 | Direct-mapped D-cache with a miss FSM | Whole-pipeline stall on a miss; writeback on eviction | 10, 12 | `cache/cachefsm.sv` |
| 8 | SVA for the hazard unit | e.g. never forward from x0; a flushed stage never writes; load-use always stalls exactly 1 cycle | 5.7 | — |
| 9 | Swap `iss.py` for Spike, run riscv-arch-test | Matching a real reference model's legal choices | 3.7, 5.11 | `tests/riscof/` |

When you send the next chapter (Chapter 7 is the natural one), I'll write its notes against this code, so every concept points at a line you can run.

### Interview questions this code now lets you answer from experience

- *Why does the register file write on the falling edge in a pipeline but not in a single-cycle core?*
- *Why does forwarding prefer M over W, and how would you test that?* (the `la` + `jalr` case)
- *Why can't a load result be forwarded from M?* (its value only exists at the end of M)
- *Why must both D and E be flushed on a taken branch here, and how many cycles does it cost?*
- *Your directed test has 100% instruction coverage. Why might it still miss a pipeline bug?*
- *How would you design a lock-step checker for this core, and what would you compare?*
