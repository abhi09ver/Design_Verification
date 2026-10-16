// -----------------------------------------------------------------------------
// gpio_ref_wb_sva.sv : white-box assertions bound into gpio_ref_dut
//
// Port-level checks can't see a one-cycle race inside the status logic. These
// look at internal signals. They are written for gpio_ref_dut's names; for the
// real gpio_top, copy the file and change the names in the bind port list.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module gpio_ref_wb_sva #(parameter int W = 8) (
  input logic         clk,
  input logic         resetn,
  input logic [W-1:0] evt,      // per-pin event this cycle
  input logic [W-1:0] w1c,      // per-pin W1C strobe this cycle
  input logic [W-1:0] swset,    // per-pin software set this cycle
  input logic [W-1:0] ie,
  input logic [W-1:0] raw       // raw status register
);
  `define CK @(posedge clk) disable iff (!resetn)

  for (genvar i = 0; i < W; i++) begin : g
    // A set and a clear in the same cycle: the set must win (no lost event).
    a_set_beats_w1c: assert property (`CK (evt[i] || swset[i]) && w1c[i] && ie[i]
                                      |=> raw[i])
      else $error("pin %0d: event lost, W1C won a same-cycle set", i);
    // Status can never be set on a pin whose IE is 0.
    a_ie_blocks: assert property (`CK !ie[i] |=> !raw[i] || ie[i])
      else $error("pin %0d: status set with IE = 0", i);
    // W1C with no new event clears the bit.
    a_w1c_clears: assert property (`CK w1c[i] && !evt[i] && !swset[i] |=> !raw[i])
      else $error("pin %0d: W1C did not clear", i);
    // Proof the race was actually exercised (look for it in the coverage report).
    c_race: cover property (`CK evt[i] && w1c[i] && ie[i]);
  end

  `undef CK
endmodule : gpio_ref_wb_sva

bind gpio_ref_dut gpio_ref_wb_sva #(.W(GPIO_WIDTH)) u_wb_sva (
  .clk, .resetn, .evt, .w1c, .swset, .ie(ie_q), .raw(raw_q));
