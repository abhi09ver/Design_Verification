# Chapter 7 · Pipelined Core

Oct 28, 2026 · @Abhishek

## At a glance

> **Chapter 7 builds Wally's integer core twice: first as a single-cycle RV{32/64}I processor, then as a five-stage pipeline with forwarding, stalls and flushes.** Every later chapter (traps, caches, predictor, FPU) bolts onto this pipeline.

The core is split into three units that match Wally's source tree. The **IFU** (instruction fetch unit) has the PC, the IROM and the next-PC logic. The **IEU** (integer execution unit) has the controller, the register file, the ALU and the comparator. The **LSU** (load/store unit) has the DTIM and the subword logic. A separate **hazard unit** decides every cycle which stages stall and which get flushed.

&#91;embedded content: The chapter's core (after book Figs. 7.1, 7.11 and 7.13), simplified\]

Two feedback paths make a pipeline more than five boxes in a row. The blue forwarding paths feed results from Memory and Writeback back into Execute, so most dependences cost nothing. The branch target path along the top goes back to Fetch, and every taken branch costs two cycles.

| Question | Answer in | Key fact |
| --- | --- | --- |
| What does each instruction class need? | 7.1 | ALU, comparator and +4 run in parallel; ImmSrc builds 5 immediate formats |
| Why pipeline, and what breaks? | 7.2 | data hazards (forward or stall) and control hazards (flush) |
| What does a hazard cost? | 7.2.2.5 | CoreMark CPI 1.32 with no predictor |
| Where is it in the RTL? | 7.3 | `ieu/controller.sv`, `ieu/datapath.sv`, `hazard/hazard.sv` |
| How is it verified? | 7.4 | riscv-arch-test: 12,642 RV32I cases, but almost no hazard interactions |
| What does my core do? | Lab | CPI 1.24 on compiled C; 99.6% of lost cycles are branch flushes |

**Why it matters for CPU verification interviews.** "Draw the five-stage pipeline and walk me through a load-use hazard" is the most common opener in CPU DV interviews. The follow-ups are the corner cases from this chapter: forwarding priority, x0, stall plus flush in the same cycle, wrong-path stores, and how you would prove the hazard unit correct.

## 7.1 The single-cycle RV{32/64}I core

The single-cycle core runs every instruction in one long clock cycle. It is the reference shape for the pipeline: **the pipeline is this datapath cut into five pieces with registers in between.** Compared with the toy core of Chapter 2 it adds every RV32I/RV64I integer instruction, an `AltResult` mux (writes the immediate for `lui` or PC+4 for jump links), a richer ALU, a dedicated branch comparator, and subword loads and stores.

### The instruction set it must run (Table 7.1)

| Category | Opcode | Format | RV{32/64}I | RV64I extra |
| --- | --- | --- | --- | --- |
| R-type ALU | 0x33 / 0x3B | R | add sub and or xor sll srl sra slt sltu | addw subw sllw srlw sraw |
| I-type ALU | 0x13 / 0x1B | I | addi andi ori xori slli srli srai slti sltiu | addiw slliw srliw sraiw |
| Loads | 0x03 | I | lw lh lhu lb lbu | ld lwu |
| Stores | 0x23 | S | sw sh sb | sd |
| Branches | 0x63 | B | beq bne blt bge bltu bgeu |  |
| Jumps | 0x6F / 0x67 | J / I | jal, jalr |  |
| Upper immediate | 0x37 / 0x17 | U | lui, auipc |  |

### 7.1.1 Architectural state

Only two things are architectural: **the PC and the integer register file (IRF) x1–x31**. Everything else added later (pipeline registers, forwarding muxes) is non-architectural and invisible to software. That distinction is what lock-step comparison checks: only architectural state must match the reference model at each retirement.

The IRF has three ports: two reads (A1/RD1, A2/RD2) and one write (A3/WD3/WE3). x0 is hardwired to 0 and writes to it are ignored. The IROM holds the program and the DTIM (data tightly integrated memory) holds data.

### 7.1.2 Immediate extension

The immediate is scattered across the instruction so that rs1, rs2, rd and the sign bit always sit in the same places. The sign bit is always `Instr[31]`. The extender is just a mux selected by `ImmSrc`:

| ImmSrc | Type | ImmExt (RV32) |
| --- | --- | --- |
| 000 | I | `{{20{Instr[31]}}, Instr[31:20]}` |
| 001 | S | `{{20{Instr[31]}}, Instr[31:25], Instr[11:7]}` |
| 010 | B | `{{20{Instr[31]}}, Instr[7], Instr[30:25], Instr[11:8], 1'b0}` |
| 011 | J | `{{12{Instr[31]}}, Instr[19:12], Instr[20], Instr[30:21], 1'b0}` |
| 100 | U | `{Instr[31:12], 12'b0}` |

B and J immediates end in an implied 0 because targets are 2-byte aligned (room for compressed instructions).

### 7.1.3 Arithmetic: three blocks, three jobs

| Block | Job | Why separate |
| --- | --- | --- |
| ALU | arithmetic, logic, shifts, and address calculation (`IEUAdr`) | address comes out of the adder **before** the result mux, to save a mux delay |
| Comparator | eq and lt/ltu flags for branches | branch decision is on the critical path, and the adder is busy computing the target |
| Incrementer | PC + 4 | runs in parallel with everything |

What each instruction class uses (Table 7.3):

| Category | ALUResult | IEUResult (to rd) | IEUAdr (goes to) | Comparator |
| --- | --- | --- | --- | --- |
| R-type / I-type | R1 op R2 / R1 op Imm | ALUResult |  |  |
| Load / store |  |  | R1 + Imm (LSU) |  |
| Branch |  |  | PC + Imm (IFU) | R1 cmp R2 |
| jal |  | PC + 4 | PC + Imm (IFU) |  |
| jalr |  | PC + 4 | R1 + Imm (IFU) |  |
| lui |  | Imm |  |  |
| auipc | PC + Imm | ALUResult |  |  |

**Adder.** `SubArith` = 1 inverts B and sets carry-in: A − B = A + \~B + 1. Write `+` in the HDL and let synthesis choose a prefix adder when the path is critical (Chapter 6 showed how much that choice matters).

**Funnel shifter.** Build a (2N−1)-bit word Z, shift it right by k, keep the bottom N bits. Every shift becomes a right shift:

| Shift | Z (RV64) | Shift amount |
| --- | --- | --- |
| srl | `{63'b0, A}` | k |
| sra | `{{63{A[63]}}, A}` | k |
| sll | `{A, 63'b0}` | \~k (= N−1−k) |
| srlw / sraw / sllw | 32-bit variants with zeros or sign above | k / k / \~k |

Worked example (book Example 7.1): `sllw` of 0x24 by 4. Z = `{32'b0, A[31:0], 63'b0}`, amount = \~4 = 59, result = 0x240. The hardware is six levels of 2:1 muxes (shift by 32, 16, 8, 4, 2, 1), and the bus narrows from 127 to 64 bits as it goes, hence "funnel". RV32I has no rotates, so a funnel is simpler than a barrel shifter.

**Set less than from flags.** Compute A − B and look at carry C and sign N = Sum\[N−1\]:

```latex
\text{sltu} = \overline{C} \qquad V = (A_{N-1} \oplus B_{N-1})(A_{N-1} \oplus N) \qquad \text{slt} = N \oplus V
```

Unsigned: A + \~B + 1 produces a carry out exactly when A ≥ B, so **no carry means A < B** and sltu is the inverted carry. People often answer "sltu = C" in interviews, so say which convention you use. Signed: overflow V flips the meaning of the sign bit N, so slt = N XOR V.

**W-type (RV64).** Compute 64 bits, keep the low 32 and sign-extend bit 31 into the top half (the `Trunc` mux). RV32 omits it.

**Comparator.** Wally's comparator is written as `==` and `<` on operands with the sign bit flipped (`af = {a[MSB] ^ sgnd, a[MSB-1:0]}`), so one unsigned compare serves both signed and unsigned. A dedicated comparator needs only N prefix cells instead of the subtractor's N·log2N/2 and skips the sum XORs. Synthesis builds it well from the high-level operators.

### 7.1.4 The controller

Three blocks: a **main decoder** on `op`, **branch logic** that turns flags into `PCSrc`, and an **ALU decoder**.

| Category | op | Branch | Jump | ALUSrc {A,B} | ImmSrc | ALUOp | W64 | ALUResultSrc | ResultSrc | RegWrite | MemRW |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| R-type | 0x33 | 0 | 0 | 00 | x | 1 | 0 | 0 | 0 | 1 | 00 |
| I-type | 0x13 | 0 | 0 | 01 | 000 | 1 | 0 | 0 | 0 | 1 | 00 |
| RW / IW (RV64) | 0x3B / 0x1B | 0 | 0 | 00 / 01 | x / 000 | 1 | 1 | 0 | 0 | 1 | 00 |
| Load | 0x03 | 0 | 0 | 01 | 000 | 0 | 0 | x | 1 | 1 | 10 |
| Store | 0x23 | 0 | 0 | 01 | 001 | 0 | 0 | x | x | 0 | 01 |
| Branch | 0x63 | 1 | 0 | 11 | 010 | 0 | 0 | x | x | 0 | 00 |
| jal | 0x6F | 0 | 1 | 11 | 011 | 0 | 0 | 1 | 0 | 1 | 00 |
| jalr | 0x67 | 0 | 1 | 01 | 000 | 0 | 0 | 1 | 0 | 1 | 00 |
| lui | 0x37 | 0 | 0 | xx | 100 | x | 0 | 1 | 0 | 1 | 00 |
| auipc | 0x17 | 0 | 0 | 11 | 100 | 0 | 0 | 0 | 0 | 1 | 00 |

Wally drives the x entries as 0 so simulation never sees illegal values. `MemRW` is {MemRead, MemWrite}.

**Branch logic** is a 4:1 mux on `Funct3[2:1]` (eq, —, lt, ltu) and an XOR with `Funct3[0]` to invert: bne = !eq, bge = !lt, bgeu = !ltu. Then `PCSrc = Jump | (Branch & BranchTaken)`. Funct3 = 01x is undefined and never taken.

**ALU decoder.** `ALUSelect` = Funct3 for ALU ops, 000 (add) for auipc. `SubArith = ALUOp & (slt | sltu | sra | sub)`, where sub needs `Op[5]` to tell `sub` from `addi` (same Funct3, no Funct7). The decoder is lazy and only checks `Funct7[5]`. With Zicsr enabled, Wally decodes fully and traps on illegal Funct7 values. **Lazy decode is a classic DV escape:** an encoding that should be illegal quietly executes as something else.

### 7.1.5–7.1.6 IFU and LSU

The **IFU** is the PC register, the IROM, the +4 incrementer and the PCNext mux (PC+4 or `IEUAdr`). Chapters 9 and 13 add a bus, cache and branch predictor.

The **LSU** always reads and writes whole native words (LLEN = max(XLEN, FLEN)). Subword handling sits on either side of the memory:

- **Loads:** read the word, select the byte/half/word by the low address bits, then sign- or zero-extend (`lb` vs `lbu`).
- **Stores:** replicate the subword across the word (8 copies of a byte in RV64) and assert **ByteMask** for the bytes to write. Example: `sb` at offset 5 gives 0010\_0000; `sh` at offset 2 gives 0000\_1100; `sw` at offset 4 gives 1111\_0000.

Byte enables avoid read-modify-write, and almost every SRAM generator and FPGA block RAM supports them.

### 7.1.7 Watch one instruction: `lw x1, 4(x0)`

PC = 0x80000000 fetches 0x00402083. The register file reads R1 = x0 = 0 and the extender makes ImmExt = 4. The ALU adds them, so IEUAdr = 4. The DTIM returns 42, ResultSrc picks ReadData, and x1 ← 42 at the clock edge. Meanwhile PC+4 = 0x80000004 is selected as PCNext. **Every unit worked on one instruction for the whole cycle.** That is the waste the pipeline removes.

## 7.2 Pipelining: five stages and the hazards they create

The single-cycle period is the sum of fetch, register read, ALU, memory and writeback. Cutting it into five stages lets five instructions overlap, so the clock can run up to about five times faster at the same CPI of 1. **The cost is hazards: an instruction can need a result, or a decision, that an older instruction has not produced yet.**

| Stage | Suffix | Work |
| --- | --- | --- |
| Fetch | F | read the IROM, compute PC+4 |
| Decode | D | decode, read the register file, build the immediate |
| Execute | E | ALU, branch compare, compute target or address; branches resolve here |
| Memory | M | read or write the DTIM |
| Writeback | W | write the register file |

Three rules keep signals straight:

- **Suffix = stage.** `RdE`, `RdM` and `RdW` are the destinations of three *different* instructions in flight.
- **Control travels with its instruction.** Decode produces `RegWriteD`, then pipeline registers carry it as `RegWriteE`, `RegWriteM`, `RegWriteW`.
- **Architectural state changes only late.** Registers are written in W and memory at the start of W. If a trap is detected in M (Chapter 8), nothing younger has touched state yet, so the trap stays precise.

**The register file writes on the falling clock edge** in the middle of W, and reads happen in the second half of D. An instruction in D therefore sees the value written by the instruction in W in the same cycle, so no W→D bypass is needed. Chapter 6's lab showed the price: the write logic gets half a cycle.

A small saving: `PCLinkE` = PCE + 4 is recomputed in Execute rather than carried through two pipeline registers. A second incrementer is cheaper than XLEN flops per stage.

### 7.2.1 Synchronous memories

Real memories register their read address. That moves timing earlier by a stage:

- **IROM** must see the address *before* the Fetch edge, so it is read with **PCNextF**, not PCF. Reset is applied to the PCNextF mux, not to the PC register.
- **DTIM read:** the address sets up in Execute (`IEUAdrE`), and data comes out during Memory.
- **DTIM write:** address and data set up in Memory (`IEUAdrM`), and the write happens at the start of Writeback.
- A `DTIMAdr` mux picks IEUAdrE for reads and IEUAdrM for writes. Both memories get a chip enable so they hold their output during a stall.

This creates a **structural hazard**: a store in M and a load in E both want the single address port in the same cycle. The fix is a one-cycle `StoreStallD = MemRWE[0] & MemRWD[1]`, a stall when a store is directly followed by a load.

### 7.2.2 Hazards: forward if you can, stall if you must, flush if you guessed wrong

| Hazard | Example | Resolution | Cost |
| --- | --- | --- | --- |
| RAW, distance 1 | `addi t0,...` then `ori t1,t0,1` | forward from M | 0 |
| RAW, distance 2 | `addi t0` ... `lb t2,0(t0)` | forward from W | 0 |
| RAW, distance 3 | written in W, read in D | register file (write first half, read second half) | 0 |
| Load-use | `lb t2` then `and t3,t2,t0` | stall 1 cycle, then forward from W | 1 cycle |
| Store → load (sync DTIM) | `sw` then `lw` | stall 1 cycle | 1 cycle |
| Control | taken `beq` or any jump | predict not-taken; flush D and E when taken | 2 cycles |

**The book's Fig. 7.15 program, run on my Lab 3 pipeline** (`dv/pipeview.py`, real simulator output trimmed to the interesting cycles; my version uses `s0` as the `lb` base):

| Cycle | F | D | E | M | W | Hazard unit |
| --- | --- | --- | --- | --- | --- | --- |
| 5 | and | lb | **ori** | addi t0 | addi s0 | forward rs1 from M |
| 6 | beq | **and** | lb | ori | addi t0 | **stall F, D (load-use)** |
| 7 | beq | and | (bubble) | lb | ori |  |
| 8 | sb | beq | **and** | (bubble) | lb | forward rs1 from W |
| 9 | xori | sb | **beq** | and | (bubble) | **flush D, E (taken)**; forward from M |
| 10 | sub | (bubble) | (bubble) | beq | and |  |
| 11 | addi | sub | (bubble) | (bubble) | beq |  |

The self-checking test passes: 15 instructions in 22 cycles, including 4 cycles of fill. You can see each mechanism once. ori gets t0 forwarded from M. and stalls one cycle behind lb and then takes t2 from W. beq resolves in E and kills sb and xori, which become bubbles.

&#91;image: The Fig. 7.15 program stepping through the five stages, one cycle per frame: forwarding arrows, the load-use stall, and the flush of the two wrong-path instructions\]

### 7.2.2.2 Pipeline registers: `flopenrc`

Every pipeline register is a flop with **enable** (driven by \~Stall) and **synchronous clear** (driven by Flush). In Wally's `flopenrc`, priority is reset > enable > clear:

```systemverilog
always_ff @(posedge clk)
  if (reset)   q <= '0;
  else if (en)
    if (clear) q <= '0;
    else       q <= d;
```

**Clear only takes effect when the register is enabled.** A stalled stage cannot be flushed until it is released. The hazard unit has to account for that, and it is exactly the kind of corner a DV engineer should write an assertion for. Flushing needs only the state-changing control bits (RegWrite, MemWrite, ...) cleared. Then the instruction becomes a nop.

### 7.2.2.3 Forwarding logic

```systemverilog
if (Rs1E != 0)
  if      ((Rs1E == RdM) & RegWriteM) ForwardAE = 2'b10;  // newest: Memory stage
  else if ((Rs1E == RdW) & RegWriteW) ForwardAE = 2'b01;  // older: Writeback stage
// else 00: register file value
```

Two rules hide in four lines, and Chapter 5's bug hunt showed that each one, when broken, escapes some tests:

- **Check M before W.** If both match, M holds the newer value. Reversing the priority returns stale data.
- **Never forward x0.** An older instruction "writing" x0 must not override the hardwired zero.

**Load-use detection** happens in Decode, one cycle early, so the dependent instruction can be held:

```systemverilog
MatchDE    = ((Rs1D == RdE) | (Rs2D == RdE)) & (RdE != 0);
LoadStallD = MemReadE & MatchDE;
```

The book's text omits the `RdE != 0` term; Wally's RTL has it. Without it, a load to x0 followed by any reader of x0 stalls for nothing. That is a performance bug, not a functional one, so only a performance test or a cover point would catch it.

### 7.2.2.4 The hazard unit: causes, propagation, combine

The hazard unit is a structured way to answer two questions every cycle: which stages stall, and which get flushed.

1. **Cause generation.** Each event raises a per-stage cause. In this chapter: `FlushDCause = FlushECause = PCSrcE` (taken branch or jump), and `StallDCause = (LoadStallD | StoreStallD) & ~FlushDCause`. **Flushes win over stalls:** there is no point stalling an instruction that is about to be thrown away.
2. **Propagate stalls backward.** If stage X stalls, every older stage must stall too or instructions would pile into it: `StallF = StallFCause | StallD`, `StallD = StallDCause | StallE`, and so on.
3. **Combine flush.** The stage just after the latest stalled stage gets a bubble: `LatestUnstalledE = ~StallE & StallD`, then `FlushE = LatestUnstalledE | FlushECause`.

Wally's real `hazard.sv` is the same skeleton with more causes added in later chapters: `TrapM`, `RetM`, `CSRWriteFenceM`, `BPWrongE` (a branch-predictor miss replaces PCSrcE), divider busy in E, and LSU/IFU stalls in W. The book's warning: **the hazard unit has been the source of many subtle Wally bugs, and there is no known systematic way to design one that is provably correct.** That makes it the highest-value target for assertions, formal checks and hazard-focused coverage.

### 7.2.2.5 Performance: CPI

```latex
\text{Execution time} = N_{\text{instructions}} \times \text{CPI} \times T_c
```

CoreMark on rv32im with no branch predictor (book Table 7.9):

| Class | Share of instructions | CPI | Why |
| --- | --- | --- | --- |
| R/I-type ALU | 49.7% | 1 | forwarding hides every dependence |
| Jumps / returns | 1.8% | 3 | always taken: 2-cycle flush |
| Branches | 22.2% | 1.84 | 41.9% taken × 2 cycles |
| Loads / stores | 26.3% | 1.41 | 40.1% of loads hit a load-use stall |
| **Weighted** |  | **1.32** | measured 1.27 |

Branches cost the most, which is why Chapter 13 adds a predictor. With a predictor and bit-manipulation, Wally reaches CPI 1.14 (Section 21.1).

## 7.3 The SystemVerilog: where each box lives in Wally

The rv32i, rv64i and rv32e configurations build exactly this chapter's core. rv32e has 16 registers and uses the AHB bus instead of IROM/DTIM. Every module is parameterized by the `cvw_t P` struct, and `generate` blocks build only configured hardware. **Read the RTL with the diagram open: module names and signal names match the figures one to one.**

| Diagram block | Wally file (cloned Oct 2026) | What to look at |
| --- | --- | --- |
| IFU: PC, IROM, +4, PCNext mux | `src/ifu/ifu.sv`, `irom.sv` | PCNextF feeds the synchronous IROM |
| Register file | `src/ieu/regfile.sv` (57 lines) | `always_ff @(negedge clk)` write; x0 read as 0 |
| Extender | `src/ieu/extend.sv` | the ImmSrc case |
| Forwarding muxes | `datapath.sv`: `faemux`, `fbemux` | 3:1 of R1E, ResultW, IFResultM |
| Comparator | `src/ieu/comparator.sv` | fed **directly** by the forwarding muxes (Chapter 6's critical path) |
| ALU, shifter | `src/ieu/alu.sv`, `shifter.sv` | funnel source generator, W64 truncation |
| Result muxes | `datapath.sv`: `altresultmux`, `ieuresultmux`, `resultmuxW` | in later chapters a mux5 in W adds CSR, MDU and SC results |
| Controller + forwarding + stall detection | `src/ieu/controller.sv` (489 lines) | `ForwardAE/BE`, `MatchDE`, `StructuralStallD` |
| Subword load/store | `src/lsu/subwordread.sv`, `subwordwrite.sv` | byte selection, sign extension, ByteMask |
| Hazard unit | `src/hazard/hazard.sv` (110 lines) | causes → propagate → latest-unstalled flush |
| Pipeline registers | `src/generic/flop/flopenrc.sv` | reset > enable > clear |

Three places where the current repo is richer than the chapter's description. These are useful to know before an interview at a RISC-V shop:

| Chapter text | Wally RTL today | Why it matters |
| --- | --- | --- |
| `FlushDCause = PCSrcE` | `FlushDCause = TrapM \| RetM \| CSRWriteFenceM \| BPWrongE` | with a predictor, flush on a **mispredict**, not on every taken branch |
| `MatchDE = (Rs1D == RdE \| Rs2D == RdE)` | `... & (RdE != 0)` | no false stall on a load to x0 |
| `StructuralStallD = LoadStallD \| StoreStallD` | adds `CSRRdStallD`, `MDUStallD`, `FCvtIntStallD` | any result that appears after E must stall its consumer the same way |

The controller computes **`MatchDE` once and reuses it** for every long-latency producer: loads, CSR reads, multiply/divide and FP-to-integer moves. The general rule is that a producer whose result arrives after Execute must stall its dependent instruction in Decode.

## 7.4 Test plan

The chapter's verification is the **riscv-arch-test** suite (from RISC-V International): rv32i\_m/I, rv32e\_m/E and rv64i\_m/I. Each test is generated by **riscv-ctg** (the constrained test generator) from a YAML constraint file. It writes a **signature** to memory, and the test passes if every signature word matches the reference.

### What the generator constrains (Code Example 7.3, `addi`)

| Constraint group | Values |
| --- | --- |
| Registers | every register as rs1 and as rd, including rs1 == rd |
| Operand relations | rs1 == imm, rs1 != imm, all four sign combinations |
| Corner values | rs1 = 0, 1, most negative, most positive; imm = 0, 1, −2048, +2047 |
| Patterns | walking ones, walking zeros, alternating bits on rs1 and imm |

### How many tests (Table 7.10)

| Suite | Test cases |
| --- | --- |
| RV32I | 12,642 |
| RV32E | 12,521 |
| RV64I | 17,836 |

R-type and branch instructions get about 580–820 cases each. Shifts get about 90 (RV32) to 150 (RV64), auipc and lui 63–64, jal and jalr about 32, and aligned loads and stores 16–135. RV64 has more because there are more operand values to cover.

### What it does not test

The book is explicit about two gaps:

1. **Interactions between instructions.** Each test exercises one instruction in isolation, so pipeline hazards (forwarding, load-use, flush) are barely touched. That is exactly where Chapter 5's bug hunt found the escapes: forwarding priority, x0 forwarding and missing load stall.
2. **Operand coverage is limited.** Wally adds functional coverage tests (riscvISACOV-style, Chapter 5.9) to close these gaps.

**How I would extend the plan for this core** (what an interviewer wants to hear):

| Item | Stimulus | Check | Coverage |
| --- | --- | --- | --- |
| Forwarding | random RAW at distance 1, 2, 3 for every rs1/rs2 position | lock-step vs ISS | cross (distance × operand slot × producer type) |
| x0 handling | writes to x0 followed by reads at each distance | lock-step | rd = 0 at each distance |
| Load-use and store→load | load/store followed by dependent or independent ops | lock-step + `LoadStallD` assertion | stall hit vs not hit |
| Flush | taken/not-taken branches and jumps with wrong-path stores | wrong-path store never reaches memory (assertion) | branch type × taken |
| Stall + flush together | load-use stall in the cycle a branch resolves | `flopenrc` clear vs enable priority | that exact cycle covered |
| Lazy decode | illegal Funct7 encodings | trap or a documented alias | each illegal pattern |

## Lab: measuring my pipeline

Three experiments on the Lab 3 core from `cpu-from-scratch`, each run in lock-step against the ISS. **On compiled C code my pipeline's CPI is 1.24, and 99.6% of the lost cycles are branch and jump flushes, not load-use stalls.**

### Experiment 1: CPI on a real compiled workload

CoreMark needs more memory and runtime than this testbench has, so I wrote `tests/bench/bench.c`. It runs five kernels: insertion sort of 48 words, bitwise CRC-32 over 256 bytes, a 200-step linked-list walk, a substring search, and recursive `fib(15)`. It is compiled with `-O2 -march=rv32i` and a 15-line `crt0.S`. The expected result `0x93268ace` comes from a native x86 build of the same C. On the pipeline it **passed, and all 41,119 retired instructions matched the ISS.**

| Class | Count | Share | My core | Book CoreMark share |
| --- | --- | --- | --- | --- |
| R/I-type ALU, lui, auipc | 28,410 | 69.1% | CPI 1 | 49.7% |
| Branches | 6,158 | 15.0% | 67.1% taken | 22.2% (41.9% taken) |
| Loads | 3,017 | 7.3% | 33 load-use stalls (1.1%) | 26.3% loads + stores (40.1% of loads stall) |
| Stores | 2,800 | 6.8% | no store→load stall (my memory reads are asynchronous) |  |
| Jumps | 734 | 1.8% | always flush | 1.8% |

| Cycles | Count |
| --- | --- |
| Retired instructions | 41,119 |
| Load-use stall cycles | 33 |
| Taken branches + jumps, each flushing 2 slots | 4,869 → 9,738 cycles |
| Total cycles | 50,892 |
| **CPI** | **1.238** (model 1 + (33 + 2 × 4,869) / 41,119 = 1.238) |

Two differences from the book's numbers teach something:

- **Load-use stalls almost vanish (1.1% vs 40.1%).** GCC at `-O2` schedules an independent instruction between most loads and their use. CoreMark's linked lists and state machines leave fewer such slots. Hazard cost depends on the compiler and the workload as much as on the hardware.
- **Branches are taken more often (67% vs 42%)** because tight loops dominate here. Every loop back-edge costs two cycles with predict-not-taken.

What-if arithmetic on the same counts:

| Change | Cycles saved | CPI |
| --- | --- | --- |
| Today: resolve in Execute, predict not-taken |  | 1.238 |
| Resolve branches in Decode (1-cycle penalty) | 4,869 | 1.119 |
| Perfect branch predictor | 9,738 | 1.001 |

This is the case for Chapter 13's branch predictor, measured on my own core.

### Experiment 2: the Fig. 7.15 program, cycle by cycle

The table and animation in 7.2.2 are this run: `python3 dv/pipeview.py tests/directed/hazard_demo.S`. It shows forwarding from M (ori), the load-use stall and forward from W (and), and the two-instruction flush (beq).

### Experiment 3: a performance bug that lock-step cannot see

The book's text writes `MatchDE` without the `RdE != 0` term. I added that version under `-DPERF_LOADSTALL_X0` and ran `tests/directed/x0_loads.S` (100 iterations of `lw x0, ...` followed by an instruction that reads x0):

| Version | Result | Lock-step | Cycles |
| --- | --- | --- | --- |
| Wally's `MatchDE & (RdE != 0)` | PASS | 606/606 match | 808 |
| Book text, no x0 term | PASS | 606/606 match | **1,008 (+200)** |

Every architectural value is identical, so lock-step, signatures and riscv-arch-test all pass. The bug costs exactly two needless stalls per iteration. **Only a performance check (cycle count against a model) or a cover point such as "load-use stall while RdE == 0" exposes it.** That is why CPU DV teams track performance regressions and stall-cause counters as well as functional checks.

## Recap, interview drill and companion

### Ten lines to remember

1. Architectural state is only the **PC and x1–x31**. Pipeline registers and forwarding are invisible to software, which is why lock-step compares only architectural state.
2. Single-cycle: the ALU, comparator and +4 work in parallel. `IEUAdr` leaves the adder before the result mux, and the comparator is separate because branch decisions are on the critical path.
3. The extender always takes the sign from **Instr\[31\]**. B and J immediates end in an implied 0.
4. The funnel shifter turns every shift into a right shift, using \~k for left shifts. **sltu = NOT carry, slt = N XOR V.**
5. Five stages F D E M W. **Signal suffix = stage**, and control travels with its instruction.
6. Forwarding: check **M before W**, never forward **x0**. Load-use costs 1 stall, detected in Decode with `LoadStallD = MemReadE & MatchDE`.
7. Predict not-taken, resolve in Execute, and a taken branch **flushes 2** instructions. Flushes beat stalls.
8. `flopenrc` priority is reset > enable > clear: a stalled register cannot be cleared.
9. The register file writes on the falling edge, so a write in W is seen by a read in D in the same cycle.
10. riscv-arch-test checks instructions in isolation, so **hazard interactions need their own random tests, assertions and coverage**.

### Interview drill (say these out loud)

**Q1. Draw the five-stage pipeline and walk a load-use hazard through it.** F D E M W. `lw t2` is in E while `and t3,t2,t0` is in D. Decode sees `MemReadE & (Rs1D == RdE)`, so it raises LoadStallD. StallF and StallD hold the PC and the D register, and FlushE puts a bubble into Execute. Next cycle the load is in M and the and is still in D. One cycle later the load is in W, the and is in E, and ForwardAE = 01 picks ResultW. Cost: one cycle.

**Q2. Why does the forwarding logic check the Memory stage before Writeback?** If both stages write the same register, M holds the younger instruction, so its value is the architecturally correct one. W would be stale. Getting this wrong only shows up when two back-to-back writes to the same register are followed by a read. That is exactly the cross-coverage point I would require.

**Q3. Why is x0 excluded from forwarding and from load-use detection?** Forwarding: an instruction "writing" x0 must not override the hardwired zero, or the consumer reads garbage, which is a functional bug. Load-use: without `RdE != 0`, a load to x0 followed by any reader of x0 stalls for nothing. That is a performance bug. In my lab both versions pass lock-step, but one takes 1,008 cycles instead of 808.

**Q4. What happens on a taken branch? What if a stall and a flush happen in the same cycle?** The branch resolves in E. PCSrcE redirects Fetch to IEUAdrE, and FlushD and FlushE kill the two wrong-path instructions. Flushes have priority: `StallDCause = StructuralStallD & ~FlushDCause`, because stalling a doomed instruction is pointless. Also, `flopenrc` only clears when enabled, so the hazard unit flushes the latest unstalled stage. I would write an assertion that no stage is both stalled and expected to flush, and cover that exact cycle.

**Q5. How would you verify the hazard unit?** Four layers. (1) Lock-step random tests with dense dependences: short register pools, loads, and branches near each other. (2) Assertions: a flushed instruction never writes state, a wrong-path store never reaches memory, a stalled register holds its value, and no x0 forwarding. (3) Coverage crosses of hazard type × distance × operand slot, plus stall-and-flush in the same cycle. (4) Formal on the hazard unit alone: it is small, purely combinational, and its spec fits in a dozen properties. The book itself says there is no known systematic way to design a provably correct hazard unit, so verification has to carry the burden.

**Q6. Why does Wally write the register file on the falling edge?** So a value written in Writeback is visible to Decode in the same cycle without a third forwarding path. The cost is a half-cycle write path. In my synthesis lab that path, not the forwarding path, set the minimum period at 5.2 ns. The alternative is a rising-edge write plus a W→D bypass mux.

**Q7. What is the CPI of this pipeline, and what dominates it?** On CoreMark without a predictor, 1.32 (measured 1.27). Branches are 22% of instructions and 42% are taken, at 2 cycles each, and 40% of loads stall. On my compiled C benchmark, CPI is 1.24 and 99.6% of lost cycles are branch flushes. GCC scheduling removed almost all load-use stalls. Either way the next step is a branch predictor. A perfect predictor would bring my core to CPI 1.00.

**Q8. Why do synchronous memories create a store-then-load stall?** The DTIM has one address port. A load needs its address set up in Execute (read at the start of Memory), and a store needs it in Memory (write at the start of Writeback). When a store is in M and a load is in E, both want the port in the same cycle, so `StoreStallD = MemRWE[0] & MemRWD[1]` delays the load one cycle. It is a structural hazard, not a data hazard.

**Q9. riscv-arch-test passes. What is missing?** The book lists two gaps: instruction interactions (hazards) and limited operand coverage. I would add constrained-random streams with controlled dependence distance, wrong-path stores, x0 writes, and lock-step comparison, plus riscvISACOV-style functional coverage. Chapter 5's bug hunt showed that forwarding-from-x0 escaped the book's own test, and a missing load stall escaped a 100%-instruction-coverage directed test.

**Q10. The decoder only checks Funct7\[5\]. Is that a bug?** Not for the base core without traps: valid encodings decode correctly, and the book calls the decoder lazy on purpose. Once Zicsr and traps exist, illegal Funct7 values must raise illegal-instruction exceptions, and Wally then decodes strictly. As DV I would cover every illegal Funct7 and Funct3 pattern for each opcode, because silent aliasing of illegal encodings is a classic escape.

### Companion

**[Pipeline Hazard Lab](https://claude.ai/artifact/1ArfG3qooR7A1vs4tmq4Z8)**: a cycle-by-cycle pipeline diagram that reproduces Fig. 7.15 exactly, with forwarding on/off and branch resolution in E or D. It also has naive vs compiler-scheduled loops, a funnel-shifter and slt-flag explorer, an RV32I decoder that reproduces Table 7.6, and an 8-question self-check.

Lab code: `cpu-from-scratch/tests/bench/` (CPI workload), `tests/directed/x0_loads.S` with `-DPERF_LOADSTALL_X0`, and `dv/pipeview.py`. The full regression is now 54/54.

## Book coverage check (Ch 7 audit)

This tab has been checked against every section of Chapter 7 (7.1–7.5) and its 10 tables. Everything below is in the book but was not yet in the tab. The full hazard unit is included because interviewers ask about it the most.

### Commit only in Writeback (margin note, 7.2)

"In a processor with traps, it is important to update the state of the system after all hazards have been resolved." If the register file, memory or a CSR changes before a trap is known, the trap sees a half-updated machine. Wally therefore commits every architectural change (register write, DTIM write, CSR write) in **Writeback**.

**This is the precise-exception principle.** On an OoO core the same rule becomes "commit in order from the ROB." A common interview prompt is "a store in M and a trap in W: does the store happen?" The answer is no, because FlushM kills the store.

### The comparator as a prefix network (7.1.3.6)

- **Precompute** each column: E\_i = A\_i XNOR B\_i (bits equal), L\_i = ¬A\_i · B\_i (A's bit less).
- **Recurse**: E\_i:j = E\_i:k · E\_k−1:j, and L\_i:j = L\_i:k + E\_i:k · L\_k−1:j (the upper half is less, or the upper half is equal and the lower half is less).
- **Output**: eq = E\_N−1:0, ltu = L\_N−1:0.
- **Signed compares use the same hardware**: XOR each operand's MSB with `sgnd`. Flipping the MSB adds 2^(N−1) to both numbers, which maps the signed range onto the unsigned range without changing their order.
- Book Example 7.2:
  - −7 vs 3: 0x7FFFFFF9 < 0x80000003, true.
  - −5 vs −10: 0x7FFFFFFB ≥ 0x7FFFFFF6, true.
- **Cost**: N recurrence cells versus N·log2N/2 for a subtractor, and no sum XORs. With alternating AND/OR stages and bubble-pushing, each level is one AOI/OAI gate. Wally still just writes `==` and `<` and lets DesignWare build the network.

### DTIM access timing (Table 7.8)

| Stage | Load | Store |
| --- | --- | --- |
| E | Compute and set up IEUAdrE | Compute IEUAdrE |
| M | Read ReadDataM synchronously from IEUAdrE | Set up IEUAdrM, WriteDataM, MemRWM |
| W | Write ReadDataW into the register file | Write WriteDataM synchronously to the DTIM |

The register file and the DTIM both read in one stage and write in a later one, so neither has a single consistent place in the pipeline diagram. The book draws each memory where it is read. The structural hazard from the table above (StoreStallD) comes from the shared address port.

### The full Wally hazard unit (`src/hazard/hazard.sv`, reproduced in Ch 6, Code Example 6.2)

```
// WFI
WFIStallM        = wfiM & ~IntPendingM;
WFIInterruptedM  = wfiM &  IntPendingM;
// flush causes
FlushDCause = TrapM | RetM | CSRWriteFenceM | BPWrongE;
FlushECause = TrapM | RetM | CSRWriteFenceM | (BPWrongE & ~(DivBusyE | FDivBusyE));
FlushMCause = TrapM | RetM | CSRWriteFenceM;
FlushWCause = TrapM & ~WFIInterruptedM;
// stall causes (a stage being flushed doesn't need to stall)
StallFCause = '0;
StallDCause = (LoadStallD | StoreStallD | MDUStallD | CSRRdStallD | FCvtIntStallD | FPUStallD) & ~FlushDCause;
StallECause = (DivBusyE | FDivBusyE) & ~FlushECause;
StallMCause = WFIStallM & ~FlushMCause;
StallWCause = (IFUStallF & ~FlushDCause) | (LSUStallM & ~FlushWCause);
// propagate backward
StallF = StallFCause | StallD;  StallD = StallDCause | StallE;
StallE = StallECause | StallM;  StallM = StallMCause | StallW;  StallW = StallWCause;
// bubble behind the youngest stalled stage
LatestUnstalledD = ~StallD & StallF;  ...  LatestUnstalledW = ~StallW & StallM;
FlushD = LatestUnstalledD | FlushDCause;  ...  FlushW = LatestUnstalledW | FlushWCause;
```

What to say about it in an interview:

- **IFU and LSU stalls are applied at W, not F or M.** A cache miss in either unit freezes the whole pipe (StallW, and from there every older stage). Waiting for the bus is all-or-nothing on an in-order core.
- **A mispredict doesn't flush E while a divide is running** (`BPWrongE & ~DivBusyE`). The branch is in E behind the divider, so killing it would lose the divide. **This is a classic corner-case coverpoint: divide busy plus mispredict in the same cycle.**
- **A trap does not flush W when it is a WFI being interrupted** (`TrapM & ~WFIInterruptedM`). Otherwise the WFI would be killed and mepc would be wrong.
- Each stall cause is masked by the flush cause of the same stage. A stage that is about to be flushed doesn't need to stall, which prevents deadlock between a stall and a flush.
- `CSRWriteFenceM` is the "flush the pipe after a CSR write" rule from Ch 2. `RetM` flushes because mret and sret change privilege and PC.

**Coverage to propose:** cross each pair of {stall cause} × {flush cause} in the same cycle, check that `$onehot0` holds on the hazard outputs where it should, and add the assertion `StallX |-> StallY` for every Y older than X.
