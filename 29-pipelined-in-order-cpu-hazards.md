# Challenge 29: Pipelined In-Order CPU (Pequeno-Style 5-Stage RV32I): Hazards, Forwarding, Prediction

> **Level:** Fresher → senior
> **Topics:** RV32I formats, 5-stage pipeline, valid/stall/flush, structural/data/control hazards, forwarding, load-use interlock, static prediction, CPI accounting
> **Related:** [11 – coverage plan for a pipeline](11-functional-vs-code-coverage.md), [26 – OOO core](26-ooo-cpu-tomasulo-core.md), [30 – RTL ladder](30-cpu-from-zero-rtl-ladder.md)
> **Code:** [`cpu-lab/`](cpu-lab/README.md) · **Interactive pages:** open the HTML files in [`cpu-lab/pages/`](cpu-lab/pages/) in a browser

---


## 1. The Source

Chipmunk Logic's series *Designing Pequeno RISC-V CPU from scratch* (Mitu Raj), Parts 1–6:
- Part 1: [Getting hold of the ISA](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-1-getting-hold-of-the-isa/)
- Part 2: [Specifications and architecture](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-2-specifications-and-architecture/)
- Part 3: [Dealing with pipeline hazards](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-3-dealing-with-pipeline-hazards/)
- Part 4: [Fetch unit](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-4-fetch-unit/)
- Part 5: [Decode unit](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-5-decode-unit/)
- Part 6: [Register file](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-6-register-file/)

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


### Part 1 – Getting hold of the ISA  ([original post](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-1-getting-hold-of-the-isa/))

*What it covers:* Picks RISC-V's base integer ISA (RV32I: 37 instructions, 32 registers, x0 = 0), explains why a standard ISA beats inventing one, groups instructions into six formats (R, I, S, B, U, J), and introduces the author's own assembler.

*Like you're 10:* An ISA is the **menu** a CPU promises to understand. Every dish (instruction) is written on a 32-box order slip in one of six layouts. The kitchen only has to learn those six layouts. The cleverness: the boxes that say *which* registers (rs1, rs2, rd) are in the same place on every slip, so the kitchen can start fetching ingredients before it has finished reading the order.

*In pq5:* `tools/rv32i.py` is a ~200-line assembler with **labels** (so you can write `bne x1, x0, loop`) plus a golden instruction-set simulator for all 37 instructions. `halt` is `jal x0, 0` (jump to yourself), the usual bare-metal "stop here". The encoder was checked against known encodings before any program was written.

- **Why are B and J immediates scrambled?** — So that every immediate bit sits in the same instruction bit across formats as often as possible (bit 31 is always the sign). The hardware then needs fewer multiplexers. Software (the assembler) pays the cost of shuffling once.
- **No multiply in RV32I** — MUL/DIV live in the M extension. On RV32I you multiply with shift-and-add, as `p09_multiply.s` does.
- **Pseudo-instructions** — `nop` = `addi x0,x0,0`, `mv` = `addi rd,rs,0`, `j` = `jal x0,…`, `ret` = `jalr x0,0(ra)`. They cost no hardware.


### Part 2 – Specifications and architecture  ([original post](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-2-specifications-and-architecture/))

*What it covers:* Sets the spec: 32-bit, RV32I, single-issue, strictly in-order 5-stage pipeline (fetch, decode, execute, memory access, writeback), separate instruction and data memory interfaces, bare-metal (no CSRs, interrupts or exceptions). Each stage hands a packet to the next with a valid bit; stall goes backwards, flush kills older-stage packets.

*Like you're 10:* A sandwich shop with one worker does everything for customer 1, then everything for customer 2. Slow. Five workers in a row (take order, read order, make, wrap, hand over) each do one step and pass the tray on. Each customer still takes 5 steps, but a finished sandwich comes out **every step**. That is pipelining: same latency, 5× the throughput.

*In pq5:* pq5 follows the same spec and stage split: one module per stage, a pipeline register between stages, a `valid` bit in every packet (valid = 0 is a bubble), `stall` from decode back to fetch, and `flush` + `redirect_pc` from execute. Simplifications to stay small: memories are plain arrays (no bus handshake), and fetch has one buffer instead of two.

- **Δ + N − 1** — With Δ = 5 stages and no hazards, N instructions finish in 5 + N − 1 cycles. pq5 measures exactly that: `p01_alu` has 23 instructions and takes 27 cycles.
- **Why not single-cycle?** — The clock must wait for the slowest instruction's whole path (memory + decode + ALU + memory + write). Pipelining cuts that path into 5 short pieces, so the clock can be much faster.
- **A stall in one stage stalls everything older** — In-order means nobody may overtake. The instructions *behind* a stalled one must also hold; the ones ahead keep going, and a bubble appears between them.


### Part 3 – Dealing with pipeline hazards  ([original post](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-3-dealing-with-pipeline-hazards/))

*What it covers:* Classifies hazards. Structural ones are removed by design (split instruction and data memories, a 2-read/1-write register file, local adders). WAR and WAW cannot happen in an in-order pipeline that writes back last. RAW is handled by forwarding, except a load followed immediately by a user, which needs a one-cycle interlock. Control hazards are handled by prediction in fetch plus a flush when execute finds the guess was wrong.

*Like you're 10:* **RAW**: worker 3 needs the sauce worker 4 is still finishing. Instead of waiting for it to be put on the shelf (the register file), worker 4 passes it straight back over the counter: **forwarding**. **Load-use**: the sauce comes from the store-room (memory), one step later; no amount of passing helps, so worker 3 waits one beat. **Branch**: the customer might change their order. We guess and keep working. If the guess was wrong, we throw away the 2 sandwiches started since and start the right one: a **flush**.

- **Forwarding only goes forward in time** — A value can be handed to a later instruction if it already exists. A load's value exists only after MEM, one cycle after its neighbour needs it in EX, hence the single bubble.
- **Penalty depends on where branches resolve** — pq5 resolves branches in EX, so a wrong guess costs 2 bubbles (the instructions in IF/ID and ID). Resolving in ID would cost 1 but needs a comparator and forwarding into decode.
- **CPI = 1 + stall cycles per instruction** — In pq5: cycles = 4 + N + load-use stalls + 2 × flushes. That predicts every measured run exactly (table above).


### Part 4 – Fetch unit  ([original post](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-4-fetch-unit/))

*What it covers:* Fetch sends the PC to instruction memory with a valid/ready-style request, gets {instruction, PC} back, and keeps two buffers. A static predictor looks at buffered instructions: jumps taken, backward branches taken (loops), forward branches not taken. Stall comes only from decode; flush and the correct PC come only from execute. Every stage generates its own stall/flush logic.

*Like you're 10:* Fetch is the worker reading the recipe book. It keeps a bookmark (the PC) and normally turns one page. If the recipe says 'go back to step 3' it can turn back right away (a guess). If someone later shouts 'wrong page!', it jumps to the page they name and throws away what it had just read.

*In pq5:* pq5 predicts straight from the instruction memory output in the same cycle: `jal` taken, backward branch taken, everything else (and `jalr`) not taken. Flush beats stall. Pequeno puts its predictor behind an extra buffer instead, so the prediction logic is not on the memory-to-PC path. It costs one cycle of startup latency and buys a shorter critical path. pq5 chose simple; a real chip would choose Pequeno's way.

- **The stall must freeze the PC too** — If the PC kept moving while IF/ID was frozen, an instruction would be skipped. This is exactly bug B09 in your out-of-order core. pq5 has an assertion that IF/ID never changes during a stall.
- **Why carry the predicted next PC?** — Execute compares the real next PC with what fetch guessed. If they differ, it flushes. That one compare covers wrong direction, wrong target and unpredicted jalr.


### Part 5 – Decode unit  ([original post](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-5-decode-unit/))

*What it covers:* Decode slices fixed fields (opcode, rs1, rs2, rd, funct3, funct7), builds a type flag per format, an ALU opcode, and the immediate for each format. Source register addresses go to the register file combinationally so the register data and the decoded packet arrive at execute in the same cycle. Only execute can stall or flush decode.

*Like you're 10:* Decode is the worker who reads the order slip and writes it out neatly for the cook: which ingredients (registers), how much (immediate), which recipe (ALU operation). It also asks the pantry (register file) for the ingredients right away, so they arrive at the cook together with the instructions.

*In pq5:* pq5's decode also hosts the **load-use interlock**: if the instruction in EX is a load whose destination this instruction reads, decode stalls fetch and sends a bubble forward. Unknown opcodes (fence, ecall) decode to harmless no-ops; `rd = x0` turns off the write.

- **funct7 is not always funct7** — For OP-IMM, bits 31:25 are immediate bits, except for the shift-immediates, where bit 30 picks srai. Your OOO core put immediate bits into its opcode key (bug B01).
- **'Uses rs2?' matters** — An `addi` has bits in the rs2 position, but they are immediate bits. Stalling on them would be a false dependency: slow, not wrong. pq5 computes `use1`/`use2` per format.


### Part 6 – Register file  ([original post](https://chipmunklogic.com/digital-logic-design/designing-pequeno-risc-v-cpu-from-scratch-part-6-register-file/))

*What it covers:* 32 × 32-bit registers, two independent read ports (for rs1 and rs2) used by decode, one write port used by writeback, x0 hard-wired to zero. Reads take one cycle and are registered so the data lines up with decode's packet; during a stall the read enable is turned off so the output holds.

*Like you're 10:* 32 lockers. Two windows to peek in, one slot to drop things in. Locker 0 is glued shut.

*In pq5:* pq5 reads combinationally in decode, and the values are captured in ID/EX together with the instruction, so a stall simply re-reads next cycle. It adds **write-through**: if writeback writes the register decode is reading in the same cycle, decode gets the new value.

- **The same-cycle read/write question** — Instruction A in WB writes x5 while instruction D (3 behind) reads x5 in decode. Without write-through or a write-before-read register file, D reads the stale value. Removing write-through from pq5 breaks 7 of 10 directed programs.
- **Why stall the register file with decode?** — In Pequeno the read data is registered. If decode freezes but the register file output moves on, the data no longer matches the frozen instruction. pq5 avoids the issue by not registering inside the register file.


### Part 7 – Execute unit (beyond the six posts)

*Like you're 10:* The cook. Before cooking it checks: is a fresher ingredient being handed back from the next workers? Then it cooks (ALU). For a branch it checks whether fetch's guess was right; if not, it shouts 'wrong page!' (flush) with the right page number.

Forwarding is two priority checks per operand: the instruction one ahead (EX/MEM) wins over the one two ahead (MEM/WB). The branch unit compares registers, computes the target (`pc + imm`, or `(rs1 + imm) & ~1` for jalr), and flushes if the real next PC differs from the predicted one. jal/jalr write the link address pc + 4.

- **Priority order matters** — If two earlier instructions write the same register, the nearer one is newer. Reversing the priority fails only 2 of 10 directed tests and 5 of 100 random programs, an easy bug to miss without targeted tests (p02_forwarding writes x5 three times in a row on purpose).
- **jalr clears bit 0** — The spec says the target is (rs1 + imm) with the lowest bit cleared.

### Part 8 – Memory access and writeback (beyond the six posts)

*Like you're 10:* Wrapping and handing over. A load reads from the store-room; a store puts something in it. Some orders want only one byte or half a word, so the worker picks the right part of the box and fills the rest with the sign (lb, lh) or with zeros (lbu, lhu).

Data memory is word-addressed internally. The byte offset `addr[1:0]` shifts the wanted byte or half down to bit 0 for loads, and selects the byte lanes for stores. Writeback is just the register file's write port fed from MEM/WB.

- **Stores write in MEM, not WB** — pq5 has no exceptions, so a store in MEM is certain to complete. In a CPU with precise exceptions, a store must not write memory before every older instruction is known to be safe. That is why your OOO core keeps stores in a store queue until commit.

## 4. Deep Dive: Measured Behaviour

### 4.1 The cost formula, checked on every program

`cycles = 4 + N + load_use_stalls + 2 × flushes` (no hazards: Δ + N − 1 with Δ = 5)

| program | N | stalls | flushes | predicted | measured | CPI |
|---|---|---|---|---|---|---|
| `p01_alu` | 23 | 0 | 0 | 4+23+0+2×0 = **27** | 27 | 1.17 |
| `p02_forwarding` | 14 | 0 | 0 | 4+14+0+2×0 = **18** | 18 | 1.29 |
| `p03_load_use` | 11 | 3 | 0 | 4+11+3+2×0 = **18** | 18 | 1.64 |
| `p04_loop_sum` | 304 | 0 | 1 | 4+304+0+2×1 = **310** | 310 | 1.02 |
| `p05_if_else` | 9 | 0 | 1 | 4+9+0+2×1 = **15** | 15 | 1.67 |
| `p06_call_ret` | 62 | 0 | 5 | 4+62+0+2×5 = **76** | 76 | 1.23 |
| `p07_bubble_sort` | 243 | 28 | 21 | 4+243+28+2×21 = **317** | 317 | 1.30 |
| `p08_bytes` | 14 | 0 | 0 | 4+14+0+2×0 = **18** | 18 | 1.29 |
| `p09_multiply` | 170 | 0 | 22 | 4+170+0+2×22 = **218** | 218 | 1.28 |
| `p10_fibonacci` | 144 | 0 | 1 | 4+144+0+2×1 = **150** | 150 | 1.04 |

### 4.2 Pipeline pictures straight from simulation (`make pipe T=...`)

Load-use stall (`p03_load_use`, cycle 5: `lw x2` in EX, `addi x3,x2,1` waits in ID):
```
PIPE   1 | IF 000 | ID  -  | EX  -  | MEM  -  | WB  -  |                
PIPE   2 | IF 004 | ID 000 | EX  -  | MEM  -  | WB  -  |                
PIPE   3 | IF 008 | ID 004 | EX 000 | MEM  -  | WB  -  |                
PIPE   4 | IF 00c | ID 008 | EX 004 | MEM 000 | WB  -  |                
PIPE   5 | IF 010 | ID 00c | EX 008 | MEM 004 | WB 000 | STALL(load-use)
PIPE   6 | IF 010 | ID 00c | EX  -  | MEM 008 | WB 004 |                
PIPE   7 | IF 014 | ID 010 | EX 00c | MEM  -  | WB 008 |                
PIPE   8 | IF 018 | ID 014 | EX 010 | MEM 00c | WB  -  |                
```
Wrong guess (`p05_if_else`, cycle 5: forward branch was taken → 2 bubbles):
```
PIPE   1 | IF 000 | ID  -  | EX  -  | MEM  -  | WB  -  |                
PIPE   2 | IF 004 | ID 000 | EX  -  | MEM  -  | WB  -  |                
PIPE   3 | IF 008 | ID 004 | EX 000 | MEM  -  | WB  -  |                
PIPE   4 | IF 00c | ID 008 | EX 004 | MEM 000 | WB  -  |                
PIPE   5 | IF 010 | ID 00c | EX 008 | MEM 004 | WB 000 |                 FLUSH->14
PIPE   6 | IF 014 | ID  -  | EX  -  | MEM 008 | WB 004 |                
PIPE   7 | IF 018 | ID 014 | EX  -  | MEM  -  | WB 008 |                
PIPE   8 | IF 01c | ID 018 | EX 014 | MEM  -  | WB  -  |                
```

### 4.3 Remove one mechanism, see what breaks

```
no forwarding from MEM (distance 1)           directed fails:  9/10 p01,p02,p03,p04,p06,p07,p08,p09,p10 random fails: 100/100
no forwarding from WB (distance 2)            directed fails:  9/10 p01,p02,p03,p04,p06,p07,p08,p09,p10 random fails:  57/100
forwarding priority reversed                  directed fails:  2/10 p02,p08                        random fails:   5/100
forward a load's ADDRESS from MEM             directed fails:  0/10                                random fails:   0/100
no register-file write-through (distance 3)   directed fails:  7/10 p01,p02,p04,p06,p07,p09,p10    random fails:  54/100
no load-use stall                             directed fails:  2/10 p03,p07                        random fails:  26/100
flush forgets the instruction in IF/ID        directed fails:  6/10 p04,p05,p06,p07,p09,p10        random fails:  98/100
flush forgets the instruction in decode       directed fails:  6/10 p04,p05,p06,p07,p09,p10        random fails:  98/100
x0 can be written                             directed fails:  5/10 p02,p03,p05,p06,p09            random fails:  54/100
PERF: no branch prediction (always pc+4)      directed fails:  0/10                                random fails:   0/100  CPI p04_loop_sum=1.66 p09_multiply=1.48
```

### 4.4 The code

All stages: [`cpu-lab/pq5/rtl/pq5.sv`](cpu-lab/pq5/rtl/pq5.sv) (333 lines). The execute stage, which holds the forwarding and the branch check:

```systemverilog
module pq5_execute import pq5_pkg::*; (
  input  logic        clk, rst,
  input  id_ex_t      id_ex,
  input  ex_mem_t     fwd_mem,               // instruction 1 ahead (now in MEM)
  input  mem_wb_t     fwd_wb,                // instruction 2 ahead (now in WB)
  output logic        flush,
  output logic [31:0] redirect_pc,
  output ex_mem_t     ex_mem
);
  // FORWARDING: take the newest value of rs1/rs2. Nearest producer wins.
  function automatic logic [31:0] fwd(input logic [4:0] r, input logic [31:0] from_rf);
    if (r != 0 && fwd_mem.valid && fwd_mem.we && !fwd_mem.is_load && fwd_mem.rd == r) return fwd_mem.result;
    if (r != 0 && fwd_wb.valid  && fwd_wb.we  && fwd_wb.rd == r)                         return fwd_wb.wdata;
    return from_rf;
  endfunction
  wire [31:0] a_reg = fwd(id_ex.rs1, id_ex.rs1_val);
  wire [31:0] b_reg = fwd(id_ex.rs2, id_ex.rs2_val);
  wire [31:0] a = id_ex.a_is_pc  ? id_ex.pc  : a_reg;
  wire [31:0] b = id_ex.b_is_imm ? id_ex.imm : b_reg;

  logic [31:0] y;
  always_comb begin
    case (id_ex.alu)
      A_ADD:  y = a + b;                 A_SUB:  y = a - b;
      A_SLL:  y = a << b[4:0];           A_SLT:  y = {31'b0, $signed(a) < $signed(b)};
      A_SLTU: y = {31'b0, a < b};        A_XOR:  y = a ^ b;
      A_SRL:  y = a >> b[4:0];           A_SRA:  y = $signed(a) >>> b[4:0];
      A_OR:   y = a | b;                 default: y = a & b;
    endcase
  end

  // BRANCH UNIT: decide the real next PC and compare with what fetch guessed
  logic taken; logic [31:0] target, actual_npc;
  always_comb begin
    case (id_ex.funct3)
      3'b000: taken = (a_reg == b_reg);                    // beq
      3'b001: taken = (a_reg != b_reg);                    // bne
      3'b100: taken = ($signed(a_reg) <  $signed(b_reg));  // blt
      3'b101: taken = ($signed(a_reg) >= $signed(b_reg));  // bge
      3'b110: taken = (a_reg <  b_reg);                    // bltu
      3'b111: taken = (a_reg >= b_reg);                    // bgeu
      default: taken = 1'b0;
    endcase
    taken  = (id_ex.is_branch && taken) || id_ex.is_jal || id_ex.is_jalr;
    target = id_ex.is_jalr ? ((a_reg + id_ex.imm) & ~32'd1) : (id_ex.pc + id_ex.imm);
    actual_npc = taken ? target : id_ex.pc + 4;
  end
  assign flush       = id_ex.valid && (actual_npc != id_ex.pred_npc);   // the guess was wrong
  assign redirect_pc = actual_npc;

  always_ff @(posedge clk) begin
    if (rst) ex_mem.valid <= 1'b0;
    else begin
      ex_mem.valid      <= id_ex.valid;
      ex_mem.pc         <= id_ex.pc;
      ex_mem.result     <= (id_ex.is_jal || id_ex.is_jalr) ? id_ex.pc + 4 :   // link address
                           id_ex.is_lui ? id_ex.imm : y;
      ex_mem.store_data <= b_reg;
      ex_mem.rd         <= id_ex.rd;
      ex_mem.we         <= id_ex.we;
      ex_mem.is_load    <= id_ex.is_load;
      ex_mem.is_store   <= id_ex.is_store;
      ex_mem.funct3     <= id_ex.funct3;
    end
  end
endmodule
```

## 5. Likely Interviewer Follow-ups

**Q: Where is rs1 in an S-type instruction?**

Bits 19:15, the same as in every other format that has rs1.

**Q: What does `addi x5, x0, -1` put in x5?**

0xFFFFFFFF. The 12-bit -1 is sign-extended to 32 bits.

**Q: Which instruction is a 'free' NOP?**

`addi x0, x0, 0`. The write to x0 is thrown away.

**Q: Why is RISC-V popular for teaching and for industry?**

Open and royalty-free, small clean base ISA with optional extensions, fixed 32-bit encoding with register fields in fixed positions (simple decoders), and a big open tool and RTL ecosystem.

**Q: A program has 100 instructions and no hazards. How many cycles on a 5-stage pipeline?**

5 + 100 − 1 = 104.

**Q: What is a bubble?**

A pipeline slot carrying nothing (valid = 0). It moves through the stages like an instruction but changes no state.

**Q: Throughput vs latency for a pipeline?**

Latency per instruction stays about the same (or grows slightly because of pipeline registers). Throughput approaches 1 instruction per cycle at a higher clock frequency. The cost is area, power and hazards.

**Q: Why can't WAW happen in an in-order 5-stage pipeline?**

All writes happen in the same stage (WB) in program order, so the later write always lands last.

**Q: `lw x2,0(x0)` then `add x3,x2,x2`. How many bubbles?**

One. With one independent instruction in between: zero.

**Q: A loop runs 100 times. The backward branch is predicted taken. How many flushes?**

One, on the final exit, when the branch falls through. `p04_loop_sum` shows exactly 1.

**Q: Explain forwarding, and where the muxes go.**

Muxes at the ALU inputs in EX choose between the register value read in decode, the result in EX/MEM (distance 1), or the value in MEM/WB (distance 2). The nearest producer wins. Distance 3 is covered by the register file writing before (or through to) the read. Loads in EX/MEM are not forwardable, so an interlock inserts a bubble.

**Q: What happens to CPI with 20% branches, 30% mispredicted, 2-cycle penalty?**

1 + 0.2 × 0.3 × 2 = 1.12, ignoring other stalls.

**Q: Why is a backward branch predicted taken?**

Backward branches usually close loops, and loops usually go round again.

**Q: Which instruction can't a static predictor guess the target of, and why?**

`jalr`. Its target is in a register, which fetch doesn't have yet.

**Q: Static vs dynamic branch prediction?**

Static: a fixed rule from the instruction itself (backward taken), no state, ~60-70% accurate. Dynamic: learns from history (2-bit counters, gshare, TAGE), 90%+, needs tables, update logic and recovery of speculative history.

**Q: Which formats have no rs1?**

U (lui, auipc) and J (jal).

**Q: Why does a store need rs2?**

rs2 holds the data being stored; rs1 holds the base address.

**Q: Where would you put the load-use detection and why?**

In decode, because the dependent instruction is there when the load is in EX, the last moment you can hold it back cheaply, and holding decode + fetch is simple.

**Q: How many read ports does a 2-wide superscalar CPU need?**

Four (two sources each). Port count is a big area cost of wide CPUs.

**Q: Name two ways to make x0 read as zero.**

Guard the read (`ra == 0 ? 0 : r[ra]`), or guard the write so r[0] is never written (and reset it to 0). pq5 does both.

**Q: Write-first vs read-first register file?**

Write-first returns the value being written in the same cycle (no extra forwarding path needed for distance 3). Read-first returns the old value, so the pipeline must forward from WB. FPGA block RAMs can be configured either way.
**Q: Design a hazard unit for a 5-stage pipeline. What inputs does it need?**

Sources and 'uses' flags of the instruction in ID; destination, write-enable and 'is load' of EX and MEM; the branch outcome from EX. Outputs: stall IF+ID with a bubble into EX on load-use; flush IF/ID+ID/EX on mispredict; forwarding selects per ALU operand.

**Q: Why is the load-use penalty 1 cycle and not 2?**

Load data exists at the end of MEM; the dependent instruction needs it at the start of its EX. One bubble lines them up, then forward from MEM/WB.


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
