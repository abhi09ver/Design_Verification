# 33 — YARP Class-Based Testbench: Code Review, Bug Hunt and a Working Run

Code: [`cpu-lab/yarp/qs/`](cpu-lab/yarp/qs/)

| Folder | What it is |
|---|---|
| `course/` | Your course files, unchanged |
| `course_min/` | The same files with only the 3 compile errors fixed, plus a test hook to swap the blueprint |
| **`course_fixed/`** | **Your testbench, fixed in place.** Same files and style, each change tagged `[FIX ..]`. Diff: `course_fixes.patch` |
| `reviewed/` | An independent rewrite, kept for comparison (driver/monitor clocking blocks, register snapshot in the transaction) |
| `rtl_mut/` | Core with 9 bugs, chosen at run time: `+MUT=1..9` (`0` = correct). One build serves every mutant |
| `rtl_vr/` | The YARP core with the valid/ready ports the spec describes (your upload had none) |
| `model/yarp_model.cpp` | The C++ RV32I model behind the 5 DPI calls. It matches the Python ISS on 213/213 programs |
| `mutate.sh`, `mutate_fixed.sh`, `results/` | Mutation campaigns and their output tables |

The flow is the standard class-based one:
- **Driver path:** generator → mailbox → driver. The driver plays both memories.
- **Monitor path:** monitor → mailbox → scoreboard. The scoreboard checks against the C++ model through DPI.

## 1. Results headline

Your testbench compiles once 3 errors are fixed. After that it **passes on clean RTL**, but it is nearly blind:

- **Stimulus is skewed.** About 70% of instructions are JAL or LUI. Over 3 seeds of 50 instructions there were **2 memory accesses** in total, and two of the three seeds had no R-type instructions at all.
- **The store path is broken.** Loads read back 0. Default stimulus never notices, because random addresses almost never hit an earlier store.
- **End of test comes too early.** The last instruction is often not checked (49 of 50).

The reviewed testbench runs 500 instructions per seed across 5 tests with a balanced mix. It sees about 30% memory traffic, misaligned accesses and thousands of stall cycles, and it ends with a completeness check.

### Mutation results: does the testbench catch real bugs?

Original course TB: 50 instructions, 10 seeds. The fixed TB: 500 instructions × tests `default`, `mem`, `cmp` × 3 seeds = 9 runs.

| # | Bug put back into the core | Original TB: real / false alarm / hung | Fixed TB | Caught by |
|---|---|---|---|---|
| 0 | none (correct RTL) | 0 / **4** / 0 | **0/9** | no false alarms |
| 1 | Y1 SLT compares magnitudes | 3 / 3 / 0 | **9/9** | register mismatch |
| 2 | Y2 branch signedness swapped | **0** / 4 / 0 | **9/9** | PC mismatch |
| 3 | Y3 JALR phantom load | 9 / 1 / 0 | **9/9** | data-access mismatch |
| 4 | no instruction latch while pending | 0 / 0 / **10 hung** | 6/9 | SVA R4 |
| 5 | fetch while load pending | **0** / 4 / 0 (was 0/6 even after the first fixes) | 6/9 | **SVA R10, the only way to see it** |
| 6 | PC ignores ready | 10 / 0 / 0 | **9/9** | SVA R2 |
| 7 | load retires without data ready | 9 / 1 / 0 | 6/9 | PC mismatch (fetch stream runs ahead) |
| 8 | SUB executes as ADD | **0** / 4 / 0 | 6/9 | register mismatch |
| 9 | LBU sign-extends | **0** / 4 / 0 | 3/9 (`mem` 3/3) | register mismatch |

How to read it:
- **Original TB:** "false" means it died on the memory model's misalignment `$fatal` (a TB bug), and "hung" means it never ended (no watchdog). On correct RTL, 4 seeds in 10 already fail. Bugs 2, 5, 8 and 9 are never really caught.
- **Fixed TB:** every bug is caught **by the regression**. Single tests miss by design: `cmp` has no loads or stores and no SUB. Bug 9 needs a loaded byte with bit 7 set, which only `mem` produces. This is why sign-off is a *regression × coverage* result, not one test.

### The closure loop that fixed the SLT escape (worth telling in an interview)
1. The first fixed-TB run caught Y1 in only 5 of 6 runs. The escape was `mem` seed 1.
2. Added **compare-corner coverage** in the scoreboard: operand-sign bins for SLT/SLTI/BLT/BGE and an MSB bin for the unsigned forms. It showed `SLT.mixsign=0, SLT.bothneg=0` in that run, and `SLTU.msb=0` in **every** default/mem run.
3. Added the `cmp` test (LUI/ADDI build big and negative values, then mostly compares). The merged regression now has **0 holes**, and Y1 is caught 9/9.
4. The same campaign showed bug 5 (fetch-while-pending) gives **no wrong result at all**. Added protocol SVA to the interface, and it was caught at once.


## 2. Bugs, file by file

### Compile errors (needed to run at all)
| ID | File | Problem | Fix |
|---|---|---|---|
| C1 | data_mem_model / driver | `mem_access_size_t` is used, but `riscv_pkg` never defines it | Add `typedef enum logic[1:0] {BYTE=0, HALF_WORD=1, WORD=3}` |
| C2 | yarp_tb_pkg | `yarp_agent.sv` is included before `yarp_monitor.sv`, so a type is used before it is declared | Reorder the includes, or add `typedef class yarp_monitor;` |
| C3 | scoreboard | `run()` is a **function** that calls `mailbox.get()`, which blocks. Functions cannot consume time | Make it a `task` |

### Stimulus (transaction)
| ID | Problem | Why it matters | Fix |
|---|---|---|---|
| T1 | `randomize()` is uniform over **all solutions** of all rand fields. J/U-type leave funct3, funct7, rs1, rs2 and imm12 free, so they have far more solutions | About 70% of instructions are JAL/LUI. ALU, branch and memory are barely tested, yet the run reports PASS | Pick the opcode first: weighted `randcase` in `pre_randomize`, then `opcode.rand_mode(0)`. The textbook answer is `solve opcode before ...`. Verilator ignored both `dist` and the skew fix, so the portable form is used |
| T2 | B/J offsets can set imm[1]. JALR targets are unconstrained | PC becomes 2-aligned. RV32I without C cannot fetch that (the spec says +4), so the core and model run in undefined territory | `imm12[0]==0` for B, `imm20[0]==0` for J, and JALR uses `rs1==0`, `imm12[1:0]==0` |
| T3 | `copy()` skips opcode, rd, imm and instruction | Any later component that reads them sees defaults | Copy every field |
| — | Alignment constraints on load/store `imm12` | Useless: the address is `rs1 + imm` and rs1 holds a random value | Removed. Misalignment is handled in the memory model instead |

### Driver
| ID | Problem | Effect | Fix |
|---|---|---|---|
| **D2** | The store writes only `if (... & vif.cb.data_mem_ready)`. Reading a signal through the clocking block returns the value **sampled before this edge**, which is still 0 | **Stores never reach the memory model.** Loads return 0, and the C model disagrees | Write when the request is seen. A one-line experiment confirms it (below) |
| D1 | `reset_seq` drives only `reset_n` | `ready` and `rd_data` are X after reset | Drive all responder outputs to 0 |
| D3 | The previous transaction's forked `ready<=0` and the next one's `ready<=1` wake on the **same edge** | Race: the winner depends on the tool. Ready can be lost, or held for an extra cycle | Drop ready inline after the handshake edge |
| D4 | `read()` is called for stores as well | Pointless, and warns on unwritten addresses | Read only for loads |

**One-line experiment:** remove `& vif.cb.data_mem_ready` and run the memory test. Seeds go from 3/3 failing to 4/5 passing. The remaining failure is bug A1.

### Memory model
| ID | Problem | Fix |
|---|---|---|
| M1 | `$fatal` on misaligned addresses. With random registers, misalignment is *normal stimulus*, and the spec says "handle" | Byte-wise access with a counter. Must use the same policy as the C model |
| M2 | Reading a key that was never written returns X, with a warning | `exists()` check, return 0 (same as the C model) |

### Monitor, agent, scoreboard, environment
| ID | Problem | Effect | Fix |
|---|---|---|---|
| **A1** | The agent starts the 32-cycle drain when the **generator** returns. With a size-1 mailbox that is up to two transactions early (~66 cycles at max delay) | The last instruction is never checked (49/50), or the registers are compared while a load is still pending → **false FAIL** (seed 3: `lbu x3` "mismatch") | Driver counts `n_done`. Agent does `wait(drv.n_done == num_tr)`, then drains |
| S2 | The scoreboard reads `YARP.u_yarp_regfile.regfile` hierarchically, from a thread woken by `@cb` in the **same time step** as the regfile's NBA write | Whether it sees the old or new value depends on the scheduler. It works in Verilator; another simulator may compare stale registers | The monitor snapshots `arch_reg` at the following **negedge** and puts it in the transaction |
| S3 | `end_of_test` never checks how many instructions retired | A hung core, or a dropped handshake, **passes** | `n_instr == num_tr && !mem_pending`, plus a hang watchdog in the top |
| S4 | No coverage | You can't see that the mix is skewed | Opcode-class histogram, stall-cycle counters and a misaligned count, printed at the end |
| E1 | `mon2sb = new(1)` | Bounded. A monitor that samples every cycle must never block | Unbounded |

## 3. The timing ideas behind D2, D3 and S2 (know these cold)

- **Clocking-block input = the value just before the edge** (`#1step`). Reading `vif.cb.x` *after* you drive `vif.cb.x <= 1` still gives the old value until the next edge. That is D2.
- **Clocking-block output** is applied in the re-NBA region of that edge. Two threads driving the same cb output on the same edge is a race, and the last write wins. That is D3.
- **Class threads woken by `@cb`** run before the design's NBA updates of that time step. Peeking at RTL state from them is order-dependent. Sample at a later point (negedge), or probe the write port. That is S2.
- **A responder driver sees `req` one edge late.** Even with delay 0, a fetch takes 2 cycles unless `ready` is held high in advance. The spec allows ready without a request for exactly this reason.

## 4. Spec rules → where they are checked

| Spec rule | Check |
|---|---|
| R1/R2: instruction req held, addr stable until ready | SVA `a_ireq_hold`, `a_iaddr_stab` in the interface |
| R3: data req starts in the instruction-accept cycle | SVA `a_dreq_start` |
| R4–R7: data req and payload stable until ready | SVA `a_dreq_hold`, `a_dpay_stab` |
| R10: no fetch while data is pending | SVA `a_no_fetch` |
| PC starts at reset address, +4 / jump / branch | `compare_instruction_address` on every fetch handshake |
| Execute and write back | 32 registers compared after every retire; load/store address, size and data compared |

## 5. Run it
```bash
cd cpu-lab/yarp/qs
./build.sh course_fixed obj_cf                 # needs verilator 5.x with z3 on PATH (randomize)
./obj_cf/Vyarp_tb_top +TEST=mem +NUM_TR=500    # tests: default mem alu b2b stall cmp
RTLDIR=rtl_mut ./build.sh course_fixed obj_mf3 && ./obj_mf3/Vyarp_tb_top +MUT=1 +TEST=cmp   # catch bug 1
./mutate_fixed.sh                              # full table (build obj_mf3 first; mutate.sh also needs obj_mc)
```

## 6. 60-second pitch
"I brought up a class-based testbench for a single-cycle RV32I core: generator with the blueprint pattern, a responder driver for both valid/ready memories, a per-cycle monitor, and a scoreboard stepping a C++ ISS over DPI. It passed out of the box, which made me suspicious.

- **Coverage check.** 70% of instructions were JAL/LUI. Uniform-over-solutions randomization favours opcodes with free fields. I fixed it by choosing the opcode class first.
- **Stores.** Once memory traffic was real, loads failed. The store write was gated on a clocking-block sample of ready from before the edge, so stores never landed.
- **End of test.** It also fired before the last load completed.

I fixed those and added a completeness check plus protocol SVA. Then I proved the testbench with mutation testing: every one of 9 injected bugs is caught by the regression, with zero false alarms, where the original testbench missed 4 completely and false-failed 40% of clean seeds."
