// -----------------------------------------------------------------------------
// gpio_tb_pkg.sv : UVM testbench package for the GPIO v1.0 core
//
// Build constants live here so tb_top (DUT parameters) and the TB classes use
// one source. Override at compile time, e.g. +define+GPIO_W_32.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

package gpio_tb_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---- build configuration (must match the DUT instance in tb_top) ----
`ifdef GPIO_W_32
  localparam int GPIO_W = 32;
`elsif GPIO_W_1
  localparam int GPIO_W = 1;
`else
  localparam int GPIO_W = 8;
`endif
  localparam logic [GPIO_W-1:0] DEF_O_VAL  = '0;
  localparam logic [GPIO_W-1:0] DEF_IO_DIR = '1;          // all inputs at reset
  localparam logic [GPIO_W-1:0] EN_SYNC    = '1;
`ifdef NO_GLF
  localparam logic [GPIO_W-1:0] EN_GLF     = '0;
`else
  localparam logic [GPIO_W-1:0] EN_GLF     = GPIO_W'('h80); // filter on pin 7
`endif
  localparam int GLF_LEN       = 4;       // PLACEHOLDER until the real RTL is read
  localparam int CLK_PERIOD_NS = 10;      // 100 MHz, as on the Basys-3 test

  `include "gpio_cfg.svh"
  `include "apb_agent.svh"
  `include "pin_agent.svh"
  `include "gpio_ral.svh"
  `include "gpio_coverage.svh"
  `include "gpio_scoreboard.svh"
  `include "gpio_env.svh"
  `include "gpio_seqs.svh"
  `include "gpio_tests.svh"
endpackage : gpio_tb_pkg
