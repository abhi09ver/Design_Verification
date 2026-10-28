# 40 — "You designed a 5-stage pipeline?" The Six Questions, Answered From pq5

A common interview checklist says that if you claim a classic 5-stage pipelined processor, you must be able to cover six things:
1. The five stages.
2. The three hazard types, on a whiteboard.
3. RAW vs WAR vs WAW.
4. Why flushes exist and how they are built.
5. Why stalls exist and how they are built.
6. How the core was verified.

Every answer below comes from the real design in [`cpu-lab/pq5/rtl/pq5.sv`](cpu-lab/pq5/rtl/pq5.sv) (333 lines), and every number is measured ([`cpu-lab/pq5/results/`](cpu-lab/pq5/results/)). Depth: [29 – Pipelined CPU](29-pipelined-in-order-cpu-hazards.md) and atlas plates 11–13 ([39](cpu-lab/pages/riscv_dv_atlas.html)).

## 1. The five stages

| Stage | What it does in pq5 | Register it fills |
|---|---|---|
| **IF** fetch | Sends the PC to instruction memory and predicts the next PC with a static predictor: `jal` and backward branches are taken; everything else goes to pc+4 (`jalr` is left to EX) | `if_id {valid, pc, instr, pred_npc}` |
| **ID** decode | Slices fields, builds the immediate, reads 2 registers and sets control bits (`we, is_load, is_store, is_branch…`). Also hosts the **load-use interlock** | `id_ex` |
| **EX** execute | Forwards operands, runs the ALU, computes the real next PC, and raises **flush** on a wrong guess | `ex_mem` |
| **MEM** memory | A load reads, a store writes byte/half/word lanes | `mem_wb` |
| **WB** write-back | Writes the register file, never x0 | — |

- Every pipeline register carries a **valid** bit; `valid = 0` is a bubble.
- With no hazards, N instructions take **N + 4** cycles. `p01_alu`: 23 instructions in 27 cycles.

## 2. The three hazard types (whiteboard examples)

| Hazard | Example | pq5 answer |
|---|---|---|
| **Structural**: two instructions need the same hardware in the same cycle | One shared memory: a load in MEM and the fetch in IF collide | Removed by design: separate instruction/data memory, a 2-read/1-write register file, a separate PC adder |
| **Data**: a value isn't written back yet | `add x5,x1,x2` → `sub x6,x5,x3` | Forwarding, plus one stall after a load |
| **Control**: the next PC is unknown until the branch resolves in EX | `beq x1,x2,L`: two wrong-path instructions are already in flight | Prediction plus a 2-cycle flush |

## 3. RAW vs WAR vs WAW

| Type | Example | Can it happen in an in-order 5-stage? |
|---|---|---|
| **RAW** (true) | `add x5,…` → `sub …,x5` | **Yes**: the only real data hazard |
| **WAR** (anti) | `sub …,x5` → `add x5,…` | **No**: reads happen in ID, always before a younger instruction's WB |
| **WAW** (output) | `add x5,…` → `lw x5,…` | **No**: writes happen only in WB, in program order |

WAR and WAW appear once instructions can finish out of order (multi-cycle units, OOO issue). That is why OOO cores rename registers ([26](26-ooo-cpu-tomasulo-core.md)).

How pq5 resolves RAW, by distance:

| Distance | Mechanism |
|---|---|
| 1 | Forward from EX/MEM (**priority**) |
| 2 | Forward from MEM/WB |
| 3 | Register-file **write-through**: a same-cycle write is seen by the read |
| load → next instruction | **1-cycle stall** |

```systemverilog
function automatic logic [31:0] fwd(input logic [4:0] r, input logic [31:0] from_rf);
  if (r != 0 && fwd_mem.valid && fwd_mem.we && !fwd_mem.is_load && fwd_mem.rd == r) return fwd_mem.result;
  if (r != 0 && fwd_wb.valid  && fwd_wb.we  && fwd_wb.rd == r)                       return fwd_wb.wdata;
  return from_rf;
endfunction
```

- Every term of the forward condition matters: `r != 0`, `valid`, `we`, and the rd match.
- **Priority matters**: the nearer producer is newer. Reversing the priority fails only **5/100** random programs, so you need a directed test that writes x5 three times in a row (`p02_forwarding`).

## 4. Flush: why, and how

- **Why:** fetch *guessed* the next PC. If EX finds the guess wrong, the instructions in IF/ID and ID are on the wrong path and must leave no architectural trace.
- **How:** each instruction carries its `pred_npc`, and one compare covers a wrong direction, a wrong target and an unpredicted `jalr`:

```systemverilog
assign flush       = id_ex.valid && (actual_npc != id_ex.pred_npc);
assign redirect_pc = actual_npc;
// fetch : if (flush) begin pc <= redirect_pc; if_id.valid <= 0; end   // flush wins over stall
// decode: if (rst || flush || stall) id_ex.valid <= 0;                 // bubble
```

- **Cost:** a mispredict costs 2 cycles. **cycles = 4 + N + load-use stalls + 2 × flushes**; this predicts every measured run exactly.
- **Example:** `p07_bubble_sort` runs 243 instructions in 317 cycles, with 28 stalls and 21 flushes.
- **Performance check:** turning prediction off fails *no* functional test, but CPI on `p04_loop_sum` goes **1.02 → 1.66**.

## 5. Stall: why, and how

- **Why:** a load's data exists only at the end of MEM, but the next instruction needs it at the start of EX. Forwarding cannot go back in time, so one bubble is needed.
- **How:** the check sits in decode:

```systemverilog
assign stall = if_id.valid && id_ex.valid && id_ex.is_load && id_ex.we &&
               ((use1 && id_ex.rd == d.rs1) || (use2 && id_ex.rd == d.rs2));
```

- Fetch holds `pc` and `if_id`, and decode injects a bubble into `id_ex`.
- Flush beats stall: the stalled instruction is on the wrong path anyway. pq5 also *proves* the two never coincide (`a_noflushstall`).
- **Example:** `p03_load_use` has 3 stalls → CPI 1.64.

## 6. How it was verified

- **Golden model:** a Python RV32I ISS. The TB compares every retired instruction's `{pc, rd, value}` in order, then the final registers and memory.
- **Directed:** 10 programs, each aimed at one mechanism (ALU, forwarding, load-use, loop, if/else, call/ret, bubble sort, bytes, multiply, Fibonacci): **10/10**.
- **Constrained-random:** 500 programs drawn from a small register pool, so dependences are frequent: **500/500**.
- **SVA:**
  - `a_x0`: x0 is never written.
  - `a_hold`: a stall freezes IF/ID.
  - `a_noflushstall`: flush and stall never coincide.
  - `a_loaduse`: proves the `!is_load` forwarding guard is unreachable, because the interlock already stalls.
- **Mutation testing** (remove one mechanism, see what breaks):

| Mechanism removed | Directed fails | Random fails |
|---|---|---|
| Forward from MEM (dist 1) | 9/10 | 100/100 |
| Forward from WB (dist 2) | 9/10 | 57/100 |
| Write-through (dist 3) | 7/10 | 54/100 |
| Load-use stall | 2/10 | 26/100 |
| Forwarding priority reversed | 2/10 | **5/100** |
| Flush of IF/ID | 6/10 | 98/100 |
| x0 writable | 5/10 | 54/100 |
| Branch prediction | 0/10 | 0/100 (CPI 1.02 → 1.66) |

## Likely follow-ups

- **Resolve branches in ID instead?** The penalty drops to 1, but ID then needs a comparator plus forwarding into ID, and a load just ahead adds a stall.
- **Why is there no stall for store data?** rs2 of a store is forwarded like any operand. A load → store-data pair at distance 1 still needs the load-use stall in pq5, which is conservative.
- **What changes with a multi-cycle divider?** WAW becomes possible (a short op after a long op to the same rd), so you need a scoreboard or renaming.
- **Where is the precise-exception point?** pq5 has no traps. In a full design, exceptions are taken in order at MEM/WB and younger instructions are flushed.

## 60-second answer

"Five stages, each register with a valid bit. Structural hazards are removed by design. RAW is the only data hazard in-order: forwarding at distances 1–3, plus a one-cycle load-use stall in decode. Control hazards use static prediction, and EX flushes the two younger stages when the real next PC differs from the guess, for a 2-cycle penalty. Cycles always measure 4 + N + stalls + 2×flushes. I verified it against an ISS with 10 directed and 500 random programs, assertions on the stall/flush rules, and mutation testing; disabling prediction broke no test but raised CPI from 1.02 to 1.66, so I check performance too."
