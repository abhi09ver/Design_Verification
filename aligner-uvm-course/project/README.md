# Aligner project: RTL + UVM environment

This is the EDA Playground project from Cristian Slav's course *Design Verification with SystemVerilog and UVM Library*, as you downloaded it. The files are kept flat, the way EDA Playground has them, so every `` `include `` resolves as-is.

| Area | Files |
|---|---|
| RTL (DUT) | `design.sv` (top-level includes), `cfs_aligner.v`, `cfs_aligner_core.v`, `cfs_regs.v`, `cfs_rx_ctrl.v`, `cfs_ctrl.v`, `cfs_tx_ctrl.v`, `cfs_synch*.v`, `cfs_edge_detect.v` |
| Base library | `uvm_ext_pkg.sv` (parameterized agent, config, driver, monitor, sequencer and coverage bases) |
| APB agent | `cfs_apb_if.sv`, `cfs_apb_pkg.sv` (also contains the RAL adapter) |
| MD agent | `cfs_md_if.sv`, `cfs_md_pkg.sv` (master plus reactive slave) |
| Registers | `cfs_algn_reg_pkg.sv`, `cfs_algn_reg_predictor.sv`, `cfs_algn_reg_access_status_info.sv`, `cfs_algn_clr_cnt_drop.sv` |
| Environment | `cfs_algn_env.sv`, `cfs_algn_env_config.sv`, `cfs_algn_if.sv`, `cfs_algn_model.sv`, `cfs_algn_scoreboard.sv`, `cfs_algn_coverage.sv`, `cfs_algn_split_info.sv`, `cfs_algn_virtual_sequencer.sv`, `cfs_algn_pkg.sv` |
| Sequences and tests | `cfs_algn_virtual_sequence_*.sv`, `cfs_algn_seq_reg_config.sv`, `cfs_algn_test_*.sv`, `testbench.sv` |
| Run control | `messages.f` (`+uvm_set_verbosity` filters), `dump.tcl` (VCD probes) |

## Run (Xcelium, as on EDA Playground)

```sh
xrun -Q -unbuffered -timescale 1ns/1ns -sysv -coverage functional -svseed random -access +rw \
     +UVM_TESTNAME=cfs_algn_test_random +UVM_MAX_QUIT_COUNT=1 -f messages.f \
     -uvmnocdnsextra -uvmhome $UVM_HOME $UVM_HOME/src/uvm_macros.svh design.sv testbench.sv
```

The tests are `cfs_algn_test_random` and `cfs_algn_test_reg_access`. For `cfs_algn_test_random_rx_err`, copy the files from `../exercises/rx_err/` into this folder; they replace `cfs_algn_pkg.sv` and `cfs_algn_test_pkg.sv`.

## Known issue still in this copy

`cfs_regs.v` around line 164: the `assign irq = ...` ORs only 4 of the 5 interrupt sources. The fix:

```verilog
assign irq =
  (edge_rx_fifo_empty & irqen_rx_fifo_empty) |
  (edge_rx_fifo_full  & irqen_rx_fifo_full)  |
  (edge_tx_fifo_empty & irqen_tx_fifo_empty) |
  (edge_tx_fifo_full  & irqen_tx_fifo_full)  |
  (edge_max_drop      & irqen_max_drop);       // missing in this copy
```

`cfs_algn_test_random_rx_err` exposes it on seeds where the random IRQEN configuration enables MAX_DROP. See `../cheatsheets/BUGS-AND-TRAPS.md` for the full list.
