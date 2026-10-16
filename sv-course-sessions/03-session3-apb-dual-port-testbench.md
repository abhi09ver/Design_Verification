# Session 3 — Dual-Port APB Driver / Monitor / Scoreboard (no UVM)

Source: `Session3_pdf_SV_OOPS_Unlocked.pdf`, page 45.
Code: [`code/session3_apb_dual_port_tb/session3_apb_dual_port_tb.sv`](code/session3_apb_dual_port_tb/session3_apb_dual_port_tb.sv)
Output: [`logs/s3_apb_tb_clean.log`](logs/s3_apb_tb_clean.log) (PASSED), [`logs/s3_apb_tb_bug.log`](logs/s3_apb_tb_bug.log) (bug caught)

## The task
A class-based environment that verifies an APB interface with **two independent instances**:
1. `apb_txn`: address, data, write/read select, read_data.
2. `apb_driver`: one driver handles both interfaces, routes each transaction to the right port, and sends it to a `drv2sb` mailbox.
3. `apb_monitor`: passive, watches both buses, samples completed transfers, and sends to a `mon2sb` mailbox.
4. `apb_scoreboard`: compares expected against actual for reads and writes, and logs mismatches in detail.
5. `tb`: 2 interfaces, 10 random transactions alternating between ports, everything started in parallel, and the test ends when all are checked.

## Structure

```
gen --gen2drv--> driver --drives--> apb_if1 / apb_if2 --> apb_slave x2 (DUT model)
                   |                     |
                drv2sb              monitor (passive, one thread per port)
                   |                     |
                   +---> scoreboard <----+ mon2sb
                         per-port expected queues + per-port reference memory
```

## Key code decisions
| Decision | Why |
|---|---|
| Driver holds `vif1`, `vif2`; uses `t.port` to pick the bus | Meets "a single driver for both instances" |
| Driver puts `t.copy()` into `drv2sb` | The scoreboard must not see later edits made through a shared handle |
| Monitor samples at `PSEL && PENABLE && PREADY` | With wait states, `PSEL && PENABLE` (as written on the slide) stays high for several cycles, so the monitor would log one transfer many times |
| Scoreboard keeps **per-port** expected queues | Two monitor threads feed one mailbox, so arrival order across ports isn't guaranteed |
| Reference memory `ref_mem[port][addr]` | Each slave is independent; a read is checked against the last write to that port and address |
| End of test: event at N checks, raced against a timeout using `fork…join_any` then `disable fork` | The test can neither hang forever nor end early |

## Three real bugs found while building it (good interview stories)

**1. The static-variable trap**
```systemverilog
initial for (int i = 0; i < 10; i++) begin
  apb_txn t = new();   // WRONG: the initializer runs ONCE (static lifetime)
  ...
```
Variables declared in an `initial` block are **static**, so the declaration's initializer runs once. All 10 `put()` calls sent the **same handle**, and the test still "passed".
**Fix:** declare `apb_txn t;` and then call `t = new();` inside the loop, or declare the variable `automatic`.

**2. A passing scoreboard proved nothing**
- With purely random addresses, reads hit addresses that had never been written, so they compared reset value against reset value. The injected bug (port-2 slave stores `~pwdata`) **passed**.
- **Fix:** 6 writes, then 4 reads constrained with `addr inside {written[port]}`. After that, `+BUG` produces 2 SB ERRORs, each showing expected and actual data.
- **Lesson:** a checker is only as good as the stimulus that exercises it. Always prove your scoreboard **can fail**.

**3. `dist` combined with an inline `with` (a simulator limitation, not a language rule)**
- The class has `write dist {1:=6, 0:=4}`, and the directed transactions add `randomize() with {write == 1;}`.
- Per the LRM this is **legal and satisfiable**. A `dist` restricts the value to its listed set ({0,1}), and the weights only shape the distribution, so `write == 1` is fine.
- Verilator 5.052 nonetheless reported it as unsatisfiable. I worked around it with `t.c_write.constraint_mode(0)` for the directed transactions.
- **Interview takeaway:** know the rule (inline constraints are ANDed with the class constraints; `dist` weights are not hard constraints). Also know the clean ways to override a default: `soft` constraints or `constraint_mode(0)`.

## Likely follow-ups
- **Why mailboxes rather than queues between components?** Blocking `get()` lets threads synchronise without polling.
- **Bounded or unbounded mailbox?** Bounded adds back-pressure, which models a slow scoreboard.
- **How would this map to UVM?**
  | This testbench | UVM equivalent |
  |---|---|
  | `apb_txn` | `uvm_sequence_item` |
  | generator | sequence |
  | driver | `uvm_driver` with `seq_item_port` |
  | monitor | uses an `uvm_analysis_port` |
  | scoreboard | `uvm_analysis_imp` / analysis FIFOs |
  | `done` event | objections |
- **What does the slave model need for realism?** PSLVERR, random wait states (already present), and reset in the middle of a transfer.
- **How do you add coverage?** Call the Session 5 coverage model from the monitor.
- **Race conditions?** The driver uses NBAs (`<=`) at `posedge`, and the monitor samples at `posedge`. In production code, use a clocking block.
