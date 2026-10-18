# 03 — Fixes for the AXI4-Lite UVM project

Findings and fixes for [NitishVerifies/AXI4_UVM_Verification](https://github.com/NitishVerifies/AXI4_UVM_Verification) at commit `7de78e6`.
Cheat sheets 12 (project explained) and 13 (bugs and fixes) walk through each one.

| # | Bug | Kind | Evidence (repo as-is) | Fix |
|---|---|---|---|---|
| 1 | Regression reports PASS while the scoreboard logs FAILs | TB | `make all_tests` → `PASS=6 FAIL=0`, but the logs show scoreboard FAILs in 5 of 6 tests | `$fatal(1, …)` when `sb_fail > 0` or `sb_pass == 0`, so a failure gives a non-zero exit |
| 2 | Deadlock when W arrives before AW (legal AXI) | DUT | `probe_protocol.sv` case 1: no BVALID after 50 cycles | Accept AW and W independently (`aw_got` / `w_got`), respond when both are in |
| 3 | No SLVERR; out-of-range addresses alias onto real words | DUT | Write `0x400` → BRESP `00`, then read `0x000` → `DEADBEEF` | Range check: no memory update, BRESP/RRESP = `10`, RDATA = 0 |
| 4 | Monitor records a bogus X transaction at start-up | TB | First scoreboard entry `addr=0xxxxxxxxx` | Use `=== 1'b1` in handshake waits |
| 5 | Scoreboard model corrupts data (iverilog limitation) | Tool | `probe_iverilog_class_partselect.sv`: `40895e81` → `81818181` | Copy the class property into a local reg before part-selecting |
| 6 | UVM files in `tb/` are never compiled | TB | Makefile builds only `axi4_pkg.sv`, `axi4_interface.sv`, `axi4_tb_top.sv` | See sheet 13 and `../04_uvm_reference/` (interface with clocking blocks, `uvm_analysis_imp_decl`) |
| 7 | Coverage and stimulus gaps | TB | 5 WSTRB patterns unreachable; no handshake-order or back-pressure coverage | See sheet 14 and `../02_axi_lite_sva/` |

The patch fixes 1–5. Items 6 and 7 are the upgrade work described on sheets 13–15.

## Reproduce

Needs `iverilog` 12 (`sudo apt install iverilog`).

```bash
git clone https://github.com/NitishVerifies/AXI4_UVM_Verification.git
cd AXI4_UVM_Verification
P=<path-to>/axi-interview-prep/code/03_axi4_lite_repo_fixes

# 1. The false PASS: summary says 6/6, logs say otherwise
(cd sim && make all_tests SIM=iverilog) | grep -E "RESULT|PASS=.*FAIL="

# 2 + 3. Deadlock and aliasing on the original RTL
iverilog -g2012 -o p $P/probes/probe_protocol.sv rtl/axi4_slave_ram.sv && vvp p

# Assertion a_b_live (procedural emulation) fires on the original RTL
iverilog -g2012 -o s $P/probes/probe_sva_emulation.sv rtl/axi4_slave_ram.sv && vvp s

# 4 + 5. The two simulator-behaviour probes
iverilog -g2012 -o x $P/probes/probe_x_in_while.sv && vvp x
iverilog -g2012 -o c $P/probes/probe_iverilog_class_partselect.sv && vvp c
```

## Apply the fix

```bash
git apply $P/axi4_lite_fixes.patch        # changes rtl/axi4_slave_ram.sv and tb/axi4_tb_top.sv
(cd sim && make all_tests SIM=iverilog)   # 6/6 pass, every scoreboard reports FAIL=0
```

Then re-run the two probes: case 1 now gets BVALID, case 2 returns BRESP `10` and leaves word 0 untouched, and the assertion emulation reports 0 violations.

## Verified results (iverilog 12)

| Run | Original | Patched |
|---|---|---|
| `make all_tests` summary | PASS=6 (scoreboard FAILs hidden) | PASS=6, scoreboard FAIL=0 in every test |
| Failing test exit code | 0 | 1 (`$fatal`) |
| W before AW | deadlock | BVALID |
| Write to `0x400` | OKAY, word 0 overwritten | SLVERR, word 0 = 0 |
| `a_b_live` emulation | 42 violations | 0 |

## Files

| File | What it is |
|---|---|
| `axi4_lite_fixes.patch` | `git apply`-able diff against `7de78e6` |
| `probes/probe_protocol.sv` | Directed probe: W-first, out-of-range, BREADY hold |
| `probes/probe_sva_emulation.sv` | Same stimulus plus a procedural version of `a_b_live` / `a_b_order` |
| `probes/probe_x_in_while.sv` | Shows `while (!(x && 1))` exits immediately |
| `probes/probe_iverilog_class_partselect.sv` | Shows the iverilog class-property part-select issue |
