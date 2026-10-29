// -----------------------------------------------------------------------------
// gpio_sva.sv : port-level assertions for GPIO v1.0
//
// Uses only top-level ports, so it works on the real gpio_top and on
// gpio_ref_dut without knowing either one's internal signal names. It snoops
// APB writes to keep its own copy of o_data and io_dir.
//
// Instantiated in tb_top (or `bind gpio_top gpio_sva #(...) u_sva (.*);`).
// Internal-signal properties for the real RTL are listed at the bottom as
// templates; fill in the names once the sources are unlocked.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module gpio_sva #(parameter int W = 8,
                  parameter logic [W-1:0] DEF_O_VAL  = '0,
                  parameter logic [W-1:0] DEF_IO_DIR = '1) (
  input logic         clk,
  input logic         resetn,
  input logic [7:0]   i_paddr,
  input logic         i_psel,
  input logic         i_penable,
  input logic         i_pwrite,
  input logic [31:0]  i_pwdata,
  input logic [31:0]  o_prdata,
  input logic         o_pready,
  input logic         o_intr,
  input wire  [W-1:0] io_gpio,
  input logic [W-1:0] tb_en          // 1 = testbench drives pin i
);
  // Every property states its own clock and reset (no default clocking /
  // default disable iff), and avoids ## inside sequences, so the same file
  // runs on Verilator 5.x as well as VCS / Xcelium / Questa.
  `define CK @(posedge clk) disable iff (!resetn)

  wire access  = i_psel & i_penable;
  wire done    = access & o_pready;
  wire wr_done = done & i_pwrite;
  wire rd_done = done & ~i_pwrite;

  // ---------------------------------------------------------- APB rules ----
  // SETUP comes first: PENABLE is never high in the first PSEL cycle.
  a_setup_first: assert property (`CK $rose(i_psel) |-> !i_penable)
    else $error("APB: PENABLE high in the SETUP cycle");
  // Then ACCESS follows SETUP.
  a_access_next: assert property (`CK i_psel && !i_penable |=> i_psel && i_penable)
    else $error("APB: SETUP not followed by ACCESS");
  // Address, direction and write data hold while the slave waits.
  a_stable: assert property (`CK access && !o_pready |=>
                             $stable({i_paddr, i_pwrite, i_pwdata}) && i_psel && i_penable)
    else $error("APB: master changed signals during a wait state");
  // Completed reads never return X.
  a_rd_known: assert property (`CK rd_done |-> !$isunknown(o_prdata))
    else $error("APB: PRDATA unknown on read completion");
  // UG timing: write = 2 clk (no wait), read = 3 clk (one wait state).
  a_wr_no_wait: assert property (`CK access && i_pwrite |-> o_pready)
    else $error("APB: write took a wait state (UG says 2-cycle write)");
  logic access_q, rd_start_q;
  wire  rd_start = access & ~i_pwrite & ~access_q;  // first ACCESS cycle of a read
  always_ff @(posedge clk or negedge resetn)
    if (!resetn) {access_q, rd_start_q} <= '0;
    else         {access_q, rd_start_q} <= {access, rd_start};
  a_rd_wait: assert property (`CK rd_start |-> !o_pready)
    else $error("APB: read finished without the wait state (UG: 3-cycle read)");
  a_rd_ready: assert property (`CK rd_start_q && access |-> o_pready)
    else $error("APB: read took more than 3 cycles (UG)");
  // No slave can hang the bus: every access finishes within 4 clocks.
  int unsigned wait_cnt;
  always_ff @(posedge clk or negedge resetn)
    if (!resetn)                 wait_cnt <= 0;
    else if (access && !o_pready) wait_cnt <= wait_cnt + 1;
    else                         wait_cnt <= 0;
  a_no_hang: assert property (`CK wait_cnt < 4)
    else $error("APB: transfer did not complete");

  // ---------------------------------------- reserved bits read as zero ----
  if (W < 32) begin : g_rsvd
    a_rsvd_zero: assert property (`CK rd_done |-> o_prdata[31:W] == '0)
      else $error("Reserved bits [31:%0d] not zero, addr 0x%02h", W, i_paddr);
  end
  // Unmapped (0x2C..0xFC) and WO 0x28 read as 0 (SPEC GAP decision).
  a_unmapped_zero: assert property (`CK rd_done && (i_paddr >= 8'h28) |-> o_prdata == '0)
    else $error("Read of 0x%02h returned 0x%08h, expected 0", i_paddr, o_prdata);

  // ------------------------------------ shadow of o_data / io_dir / GIE ----
  logic [W-1:0] o_sh, dir_sh;
  logic         gie_sh;
  always_ff @(posedge clk or negedge resetn)
    if (!resetn) begin
      o_sh   <= DEF_O_VAL;
      dir_sh <= DEF_IO_DIR;
      gie_sh <= 1'b0;
    end else if (wr_done && i_paddr == 8'h04) o_sh   <= i_pwdata[W-1:0];
    else if    (wr_done && i_paddr == 8'h08) dir_sh <= i_pwdata[W-1:0];
    else if    (wr_done && i_paddr == 8'h0C) gie_sh <= i_pwdata[0];

  // ---------------------------------------------------- pads / tristate ----
  // These need 4-state values (Z and X). Verilator is 2-state and cannot
  // sample a tristate net inside an assertion, so they are skipped there;
  // run them on a 4-state simulator (VCS, Xcelium, Questa).
`ifndef VERILATOR
  for (genvar i = 0; i < W; i++) begin : g_pin
    // Output pin: pad shows o_data one clock after the CSR write.
    a_drive: assert property (`CK !dir_sh[i] && $stable(dir_sh[i]) && $stable(o_sh[i])
                              |-> io_gpio[i] === o_sh[i])
      else $error("pin %0d: output pad 0x%b, expected %b", i, io_gpio[i], o_sh[i]);
    // Input pin the TB isn't driving: DUT must release it (Hi-Z).
    a_release: assert property (`CK dir_sh[i] && $stable(dir_sh[i]) && !tb_en[i]
                                |-> io_gpio[i] === 1'bz)
      else $error("pin %0d: DUT drives a pin configured as input", i);
    // Never two drivers: an X on the net means contention.
    a_no_contention: assert property (`CK !$isunknown(io_gpio[i]) || io_gpio[i] === 1'bz)
      else $error("pin %0d: X on pad (contention?)", i);
    // The TB must only drive pins that are inputs (a check on the testbench).
    a_tb_legal: assert property (`CK tb_en[i] && $past(tb_en[i]) |-> dir_sh[i])
      else $error("pin %0d: TB drives a pin configured as output", i);
  end
`endif

  // ---------------------------------------------------------- interrupt ----
  a_intr_known: assert property (`CK !$isunknown(o_intr))
    else $error("o_intr is X/Z");
  // With GIE = 0 for 2+ clocks, o_intr must be low (allows 1 register stage).
  a_gie_gate: assert property (`CK !gie_sh && $past(!gie_sh) |-> !o_intr)
    else $error("o_intr high while GIE = 0");

  // ------------------------------------------------------------ covers ----
  c_back_to_back: cover property (`CK $past(done) && i_psel && !i_penable);
  c_intr_rise:    cover property (`CK $rose(o_intr));
  c_w1c_write:    cover property (`CK wr_done && i_paddr == 8'h20);

  // ------------------------------------------------------------- reset ----
  // Checked outside disable iff: values right after reset release.
  a_reset_intr: assert property (@(posedge clk) disable iff (1'b0)
                                 $rose(resetn) |-> !o_intr)
    else $error("o_intr not 0 coming out of reset");

  // -------------------------------------------------------------------------
  // Templates for internal signals of the real RTL (names are placeholders):
  //
  // a_ie_blocks : assert property (`CK !u_dut.ie[i] |-> !u_dut.sts_raw[i]);
  // a_w1c_edge  : assert property (`CK w1c_wr && i_pwdata[i] && u_dut.type[i]
  //                                && !u_dut.evt[i] |=> !u_dut.sts_raw[i]);
  // a_intr_eq   : assert property (`CK o_intr == $past(u_dut.gie && |u_dut.sts));
  // a_sync_lat  : assert property (`CK $changed(io_gpio[i]) && u_dut.en_sync[i]
  //                                |-> ##[2:3] u_dut.pin_s[i] == $past(io_gpio[i],2));
  // -------------------------------------------------------------------------
  `undef CK
endmodule : gpio_sva
