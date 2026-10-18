# 32 — YARP Single-Cycle RV32I Core: Bug Hunt, Interface Review and Protocol SVA

Code: [`cpu-lab/yarp/`](cpu-lab/yarp/). The original upload is in `orig/`, the fixed RTL in `fixed/`, and the diff in `fixes.patch`.

## 1. What was verified

The checks ran every instruction's commit (pc, rd, value) against the Python RV32I ISS (`tools/rv32i.py`). The ISS was driven by 13 directed programs plus 200 constrained-random programs, in two memory modes: normal, and `+IMEM_ALWAYS` (instruction memory answers even when req=0).

| RTL | Directed (normal) | Directed (IMEM_ALWAYS) | Random 200 (both modes) |
|---|---|---|---|
| orig  | 6/13 pass | 5/13 pass | 183/200 **fail** |
| fixed | 13/13 | 13/13 | 0/200 fail |

## 2. Bugs found

| ID | File | Symptom | Root cause | Fix |
|---|---|---|---|---|
| Y1 | yarp_execute.sv | `slt -5, 3` returns 0 | SLT compares magnitudes (two's-complement abs) instead of signed values | `$signed(a) < $signed(b)` |
| Y2 | yarp_branch_control.sv | `blt`/`bge` wrong for negatives, `bltu`/`bgeu` wrong for big values | Signed and unsigned are swapped: BLT/BGE use unsigned `<` (logic is unsigned!), and BLTU/BGEU use magnitudes | BLT/BGE use `$signed`; BLTU/BGEU use plain `<` |
| Y3 | yarp_control.sv | Every `jalr` issues a spurious data-memory read | JALR's `{opcode[4],funct3}` = `0_000` is the same as LB, so the case statement sets `data_req`. The JALR override then forgets to clear it | The override also sets `data_req=0, data_byte=0` |
| Y4 | yarp_top.sv | First instruction executes twice (`addi x1,x1,1` gives 3 or 4) | The PC is frozen for one cycle after reset (`reset_seen_q`), but the regfile and data writes are not gated | Gate `rf wr_en` and `data_req` with `reset_seen_q` |

Interview lessons:
- **Y2.** `logic` is unsigned, so `a < b` is an unsigned compare. "Signed" in SV has to be explicit.
- **Y3.** Decoders that share encodings across opcodes leak control bits. Check that every "override" path clears *all* side-effect signals.
- **Y4.** The only reason Y4 is invisible in the normal mode is that the TB memory returns 0 when req=0. A "polite" testbench model hides real bugs. Make your memory models as hostile as the spec allows.

## 3. RTL vs. spec mismatch (the big one)

The course spec defines a **valid/ready** interface (`instr_mem_ready_i`, `data_mem_ready_i`) with 10 handshake rules. The uploaded `yarp_top` has **no ready inputs**:
- `yarp_instr_mem` drives `req=1` forever.
- The PC advances every cycle no matter what.

This means:
- With ready tied to 1, every protocol assertion passes.
- With ready toggling randomly (which the spec allows: "ready can toggle"), assertion **R2 fires on the first stall**: `instr_mem_addr changed before ready`.

So this RTL is the *no-stall* version of YARP. Before the class-based TB from the course can work, the core needs:
- ready-gated PC update: `pc_q <= nxt_pc` only on fetch handshake and data done;
- a data-pending state that holds the instruction and drops `instr_mem_req` (rule R10).

## 4. Interface review (`if/yarp_interface.sv`)

Your original version had one clocking block with every signal `inout`. That compiles, but:

1. **No driver/monitor separation.** The exercise asks for clocking blocks *for the driver and monitor*. The fix uses two:
   - `drv_cb`: the TB is the memory, so it drives `ready`, `rd_data` and `reset_n`, and samples the requests.
   - `mon_cb`: all inputs.
2. **`inout` everywhere** removes direction checking. A monitor could accidentally drive the bus, and nothing would complain.
3. **No skews.** Explicit `default input #1step output #1` documents the sample/drive timing and avoids race-prone code.
4. **No modports.** `dut_mp`, `drv_mp` and `mon_mp` let the compiler enforce who drives what.
5. **No protocol checks.** The interface is the right home for SVA, because every test then gets them for free.

Assertions added, one per spec rule:

| Rule | Property |
|---|---|
| R1/R2 | `req && !ready \|=> req` and `$stable(addr)` (instruction side) |
| R3 | A new data request only starts in a cycle with an instruction handshake |
| R4–R7 | Data req held; `{addr, byte_en, wr, wr_data}` stable until ready |
| R10 | `data pending \|=> !instr_mem_req` |
| extra | byte_en ≠ reserved `2'b10`; fetch address aligned; no X on fetch address |

Covers: instruction stall, data stall, back-to-back fetches. These prove the checkers were *exercised*, not just vacuously true.

**Timing subtlety to know cold:** with a clocked responder (`drv_cb`), the driver sees `req` one edge late. So a fetch takes at least 2 cycles unless ready is held high in advance (back-to-back). That is exactly why the spec allows `ready` to be high with no request.

## 5. Other code-review notes
- `yarp_pkg` and `yarp_pkg1` are duplicates; `yarp_top` and `yarp_top1` are duplicates. Two sources of truth will drift. Keep one of each.
- The `yarp_regfile` `reset_n` port is unused. Registers come up X, which is legal in RISC-V, but the ISS must agree on the initial state.
- `byte_en` is a **size** code, not byte enables. Load data is expected to be **right-aligned** by memory. Write that contract down, because a memory returning the raw lane breaks LB/LH at non-zero offsets.
- There is no misaligned-access or illegal-instruction handling. An unknown opcode silently acts as a NOP.
- `yarp_top.sv` uses CRLF line endings. Normalise with `.gitattributes`.

## 6. Run it
```bash
cd cpu-lab/yarp
make regress RTL=orig                         # 7 FAIL
make regress RTL=fixed SIM_ARGS=+IMEM_ALWAYS  # 13 PASS
# protocol harness (see if/tb_if.sv): +READY=1 clean, random ready -> R2 fires
```

## 7. 60-second pitch
"I verified a single-cycle RV32I core with a commit-level scoreboard against an ISS, plus random programs. I found four bugs:
- signed/unsigned confusion in SLT and the branches;
- a decoder encoding collision that gave every JALR a phantom load;
- a reset corner where the first instruction retired twice. Our memory model hid that one until I made it answer without a request.

I also rewrote the interface with separate driver and monitor clocking blocks, modports, and one SVA per protocol rule. Random ready immediately showed that the RTL doesn't implement the valid/ready contract at all."
