# YARP class-based testbench course: module notes

The course builds a class-based (non-UVM) testbench for the YARP single-cycle RV32I core, one component per module. This folder keeps the course's module descriptions. The code you wrote for each module is in [`../course/`](../course/); the fixed version is in [`../course_fixed/`](../course_fixed/). The review of every bug is in [38](../../../../38-yarp-class-based-testbench-review.md).

| # | Module | What the exercise asks | Notes / pitfalls found in review |
|---|---|---|---|
| 1 | Interface ([text](01-interface-module.txt)) | All memory-interface signals, plus clocking blocks for driver and monitor. The spec's 10 valid/ready rules | One all-`inout` clocking block → split into `drv_cb`/`mon_cb` with skews and modports, one SVA per rule ([37](../../../../37-yarp-single-cycle-core-review.md) §4) |
| 2 | Transaction ([text](02-transaction-module.txt)) | Randomize a legal RV32I instruction per format (opcode → funct3/funct7 → regs → imm), ready delays, `copy()` | **T1** opcode skew (uniform over solutions), **T2** misaligned B/J/JALR targets, **T3** incomplete `copy()`; `riscv_pkg` lacks `mem_access_size_t` (**C1**) |
| 3 | Generator | Blueprint pattern: construct in `new()`, `randomize()` + `copy()` in `run()`, put into the gen→drv mailbox, `num_tr` items | Correct as written. Tests override `blueprint` with a subclass (`yarp_tr_mem`, `yarp_tr_cmp`…) |
| 4 | Driver + agent | `reset_seq`, `wait_for_instr_mem_req`, drive `instr_mem_ready` after `instr_mem_ready_delay`, data ready after `data_mem_ready_delay`; first version returns `0xC0FFEE` | **D1** responder outputs X after reset, **D3** fork/join_none deassert race |
| 5 | Data memory model | Static class, associative-array memory, `read()`/`write()` with byte enable, handle unaligned | **M1** `$fatal` on misaligned (spec says handle), **M2** X for unwritten bytes; driver **D2** writes gated on stale `vif.cb.data_mem_ready` → stores never land |
| 6 | Monitor | Sample every cycle into the mon→sb mailbox; `end_of_test` waits 32 cycles | **C2** included after the agent that uses it; **A1** drain starts from the generator, not the driver |
| 7 | Scoreboard | DPI to a C++ model: `init`, `step`, `compare_instruction_address`, `compare_architecture_register`, `compare_data_memory_access`; `end_of_test` | **C3** `run()` declared as a function; **S2** regfile read races the NBA; **S3** no completeness check |
| 8 | Environment + top | Env builds agent, scoreboard and both mailboxes and runs them; top instantiates DUT and interface, makes the clock, creates the env in `initial` | **E1** bounded mon→sb mailbox; **W1** no hang watchdog |

## The C++ model behind the DPI calls

The course's C model is not included in the course material, so [`../model/yarp_model.cpp`](../model/yarp_model.cpp) implements the same five calls. It was cross-checked against the Python ISS on 213/213 programs before it was trusted.

## Run it

```bash
cd ..                                            # cpu-lab/yarp/qs
./build.sh course_fixed obj_cf                   # Verilator 5.x + z3 on PATH
./obj_cf/Vyarp_tb_top +TEST=cmp +NUM_TR=500      # tests: default mem alu b2b stall cmp
```
