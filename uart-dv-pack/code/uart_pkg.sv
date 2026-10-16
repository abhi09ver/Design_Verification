// ============================================================================
// uart_pkg.sv — UART UVM reference package (interview study code)
//
// Reference sketches that tie the ten UART interview cards together.
// Written for clarity, not compiled against a specific DUT: adapt names,
// register offsets and spec-specific rules (overrun boundary, break flags,
// resync policy) to the design you are verifying.
//
// Card map:  cfg/item ........ 01, 02
//            driver .......... 03 drift, 04 FE, 05 PE, 06 break, 08 glitch
//            monitor ......... 02 skeleton, 06 break detector, 08 false start
//            checker ......... 03 baud, 04 framing, 05 parity, 08 glitch
//            scoreboard ...... 07 overrun, 08 data/order, 09 LSR flags
//            report catcher .. 09 expected errors
// ============================================================================
`timescale 1ns/1ps

package uart_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum {PAR_NONE, PAR_EVEN, PAR_ODD, PAR_MARK, PAR_SPACE} parity_e;
  typedef enum {INJ_NONE, INJ_FE, INJ_PE, INJ_BREAK, INJ_GLITCH}   inject_e;
  typedef enum {KIND_FRAME, KIND_BREAK}                            kind_e;

  // 16550-style register offsets and LSR bits (card 09)
  localparam bit [2:0] RBR = 3'h0;
  localparam bit [2:0] LSR = 3'h5;
  localparam int LSR_DR = 0, LSR_OE = 1, LSR_PE = 2, LSR_FE = 3, LSR_BI = 4;

  `include "uart_cfg.sv"
  `include "uart_item.sv"
  `include "uart_driver.sv"
  `include "uart_monitor.sv"
  `include "uart_agent.sv"
  `include "uart_checker.sv"
  `include "uart_scoreboard.sv"
  `include "uart_coverage.sv"
  `include "uart_report_catcher.sv"
  `include "uart_seq.sv"
  `include "uart_env.sv"
  `include "uart_tests.sv"
endpackage
