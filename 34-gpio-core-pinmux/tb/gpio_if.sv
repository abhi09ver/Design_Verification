// -----------------------------------------------------------------------------
// gpio_if.sv : interfaces for the Chipmunk Logic GPIO v1.0 UVM testbench
//
//   apb_if       - APB3 slave side signals (8-bit address, 32-bit data, no PSLVERR)
//   gpio_pin_if  - bidirectional pad model for io_gpio[] plus the o_intr line
//
// Port names follow the GPIO v1.0 User Guide, Table 5.1.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

interface apb_if (input logic clk, input logic resetn);
  logic [7:0]  paddr;
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;

  // Driver drives 1 ns after the edge so the DUT never races the TB.
  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output paddr, psel, penable, pwrite, pwdata;
    input  prdata, pready;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
    input paddr, psel, penable, pwrite, pwdata, prdata, pready;
  endclocking
endinterface : apb_if


// The TB drives a pin only when tb_en[i] = 1. Otherwise it releases the
// pin to 'z so the DUT's tristate buffer can drive it. If both drive at the
// same time the resolved net goes X, which the SVA and the model flag as
// contention.
interface gpio_pin_if #(parameter int W = 8) (input logic clk, input logic resetn);
  wire  [W-1:0] io;       // connect to DUT io_gpio
  logic [W-1:0] tb_en;    // 1 = TB drives pin i
  logic [W-1:0] tb_val;   // value the TB drives
  logic         intr;     // DUT o_intr

  for (genvar i = 0; i < W; i++) begin : g_drv
    assign io[i] = tb_en[i] ? tb_val[i] : 1'bz;
  end

  clocking mon_cb @(posedge clk);
    default input #1step;
    input io, tb_en, intr;
  endclocking

  initial begin
    tb_en  = '0;
    tb_val = '0;
  end
endinterface : gpio_pin_if
