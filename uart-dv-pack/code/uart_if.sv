// uart_if — one serial line plus its clock/reset context.
// Use one instance per direction: TB->DUT (DUT RX) and DUT->TB (DUT TX).
// Timing rules live here as SVA (cards 02, 08); frame-content rules live in uart_checker.
//
// BIT_CLKS = system clocks per bit (from the baud divisor). 0 disables the pulse-width rule.
`timescale 1ns/1ps

interface uart_if #(parameter int BIT_CLKS = 0) (input logic clk, input logic rst_n);

  logic line;

  // Line held at mark (1) while in reset — a low blip looks like a start bit (card 08).
  a_idle_in_reset: assert property (@(posedge clk) !rst_n |-> line === 1'b1)
    else $error("UART_IF: line not idle-high during reset");

  // No X/Z once out of reset (card 08).
  a_no_x: assert property (@(posedge clk) disable iff (!rst_n) !$isunknown(line))
    else $error("UART_IF: X/Z on serial line");

  // Every low period lasts at least ~one bit; one clock of slack for sampling (cards 03, 08).
  generate if (BIT_CLKS > 1) begin : g_pulse
    a_min_low: assert property (@(posedge clk) disable iff (!rst_n)
                                $fell(line) |-> (!line)[*(BIT_CLKS-1)])
      else $error("UART_IF: low pulse shorter than one bit (glitch / false start)");
    c_min_low: cover property (@(posedge clk) disable iff (!rst_n) $fell(line));
  end endgenerate

endinterface
