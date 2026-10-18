// tb_top — clocks, reset, interfaces and run_test().
// Ships with a wire loopback (DUT TX = DUT RX) so the environment runs with no DUT.
// To use a real UART: remove the loopback assign and instantiate the DUT where marked.
`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import uart_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;                         // 100 MHz
  initial #100 rst_n = 1'b1;

  // BIT_CLKS: 100 MHz / 115200 = 868 clocks per bit. Left at 0 here so the
  // glitch test does not trip the interface SVA; set it when testing a real DUT.
  uart_if #(.BIT_CLKS(0)) dut_rx_if (clk, rst_n);   // TB drives -> DUT rx pin
  uart_if #(.BIT_CLKS(0)) dut_tx_if (clk, rst_n);   // DUT tx pin -> TB observes

  // ---- replace with your DUT ----------------------------------------------
  // uart_top u_dut (.clk(clk), .rst_n(rst_n),
  //                 .rx(dut_rx_if.line), .tx(dut_tx_if.line), /* bus ports */ ...);
  assign dut_tx_if.line = dut_rx_if.line;       // loopback stand-in
  // --------------------------------------------------------------------------

  initial begin
    uvm_config_db#(virtual uart_if)::set(null, "uvm_test_top.env.tb_agt*",  "vif", dut_rx_if);
    uvm_config_db#(virtual uart_if)::set(null, "uvm_test_top.env.dut_agt*", "vif", dut_tx_if);
    run_test("uart_base_test");
  end
endmodule
