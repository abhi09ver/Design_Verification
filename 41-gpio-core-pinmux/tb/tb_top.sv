// -----------------------------------------------------------------------------
// tb_top.sv : UVM top for the GPIO v1.0 testbench
//
//   Default DUT : rtl/gpio_ref_dut.sv (clean-room model from the User Guide)
//   Real DUT    : +define+USE_CHIPMUNK_RTL +define+EN_TRISTATE_BUFF +define+EN_INTR_IF
//                 plus the unlocked gpio_v1_0/src/*.sv files
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import gpio_tb_pkg::*;
  `include "uvm_macros.svh"

  logic clk = 1'b0;
  logic resetn = 1'b0;
  always #(CLK_PERIOD_NS / 2.0) clk = ~clk;

  // UG reset sequence: assert, clock running, hold >= 8 clocks, release.
  initial begin
    repeat (10) @(posedge clk);
    @(negedge clk) resetn = 1'b1;           // released away from the active edge
  end

  apb_if                  apb_vif (.clk(clk), .resetn(resetn));
  gpio_pin_if #(GPIO_W)   pin_vif (.clk(clk), .resetn(resetn));

`ifdef USE_CHIPMUNK_RTL
  gpio_top #(
`else
  gpio_ref_dut #(
    .GLF_LEN    (GLF_LEN),
`endif
    .GPIO_WIDTH (GPIO_W),
    .DEF_O_VAL  (DEF_O_VAL),
    .DEF_IO_DIR (DEF_IO_DIR),
    .EN_SYNC    (EN_SYNC),
    .EN_GLF     (EN_GLF)
  ) dut (
    .clk       (clk),
    .resetn    (resetn),
    .io_gpio   (pin_vif.io),
    .o_intr    (pin_vif.intr),
    .i_paddr   (apb_vif.paddr),
    .i_psel    (apb_vif.psel),
    .i_penable (apb_vif.penable),
    .i_pwrite  (apb_vif.pwrite),
    .i_pwdata  (apb_vif.pwdata),
    .o_prdata  (apb_vif.prdata),
    .o_pready  (apb_vif.pready)
  );

  gpio_sva #(.W(GPIO_W), .DEF_O_VAL(DEF_O_VAL), .DEF_IO_DIR(DEF_IO_DIR)) u_sva (
    .clk, .resetn,
    .i_paddr(apb_vif.paddr), .i_psel(apb_vif.psel), .i_penable(apb_vif.penable),
    .i_pwrite(apb_vif.pwrite), .i_pwdata(apb_vif.pwdata),
    .o_prdata(apb_vif.prdata), .o_pready(apb_vif.pready),
    .o_intr(pin_vif.intr), .io_gpio(pin_vif.io), .tb_en(pin_vif.tb_en));

  initial begin
    uvm_config_db#(virtual apb_if)::set(null, "uvm_test_top.env.apb.*", "apb_vif", apb_vif);
    uvm_config_db#(virtual gpio_pin_if #(GPIO_W))::set(null, "uvm_test_top.env.pins.*",
                                                       "pin_vif", pin_vif);
    run_test("gpio_full_test");
  end

  initial begin
    if ($test$plusargs("WAVES")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_top);
    end
  end
endmodule : tb_top
