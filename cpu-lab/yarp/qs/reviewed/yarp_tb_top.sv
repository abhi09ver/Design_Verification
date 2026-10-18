`timescale 1ns/1ps
// --------------------------------------------------------
// YARP - Top Testbench (reviewed)
//   +NUM_TR=<n>   +TEST=default|mem|alu|b2b|stall   +VERBOSE
// --------------------------------------------------------
`include "yarp_interface.sv"

import yarp_tb_pkg::*;
module yarp_tb_top ();

  logic             clk;
  yarp_environment  env;
  int               num_tr;
  string            test;

  yarp_top YARP (
    .clk                  (clk),
    .reset_n              (yarp_if.reset_n),
    .instr_mem_req_o      (yarp_if.instr_mem_req),
    .instr_mem_addr_o     (yarp_if.instr_mem_addr),
    .instr_mem_ready_i    (yarp_if.instr_mem_ready),
    .instr_mem_rd_data_i  (yarp_if.instr_mem_rd_data),
    .data_mem_req_o       (yarp_if.data_mem_req),
    .data_mem_addr_o      (yarp_if.data_mem_addr),
    .data_mem_byte_en_o   (yarp_if.data_mem_byte_en),
    .data_mem_wr_o        (yarp_if.data_mem_wr),
    .data_mem_wr_data_o   (yarp_if.data_mem_wr_data),
    .data_mem_ready_i     (yarp_if.data_mem_ready),
    .data_mem_rd_data_i   (yarp_if.data_mem_rd_data)
  );

  yarp_interface yarp_if (.clk(clk));

  // white-box probe of the architectural state (one place, in the top)
  assign yarp_if.arch_reg = YARP.u_yarp_regfile.regfile;

  always begin
    clk = 1'b1; #5;
    clk = 1'b0; #5;
  end

  initial begin
    $timeformat(-12, 0, " ps", 10);
    num_tr = 500;
    void'($value$plusargs("NUM_TR=%d", num_tr));
    if (!$value$plusargs("TEST=%s", test)) test = "default";
    yarp_transaction::verbose = $test$plusargs("VERBOSE");
    env = new(yarp_if, num_tr);
    // blueprint override: the whole point of the generator pattern
    case (test)
      "mem"   : begin yarp_tr_mem   t = new(); env.agent.gen.blueprint = t; end
      "alu"   : begin yarp_tr_alu   t = new(); env.agent.gen.blueprint = t; end
      "b2b"   : begin yarp_tr_b2b   t = new(); env.agent.gen.blueprint = t; end
      "stall" : begin yarp_tr_stall t = new(); env.agent.gen.blueprint = t; end
      default : ;
    endcase
    $display("[INFO] test=%s num_tr=%0d", test, num_tr);
    env.run();
    $finish();
  end

  // hang watchdog: a core that stops fetching must FAIL, not time out quietly
  initial begin
    #(num_tr * 400ns + 10us);
    $fatal(1, "[WATCHDOG] no end of test after %0t", $time);
  end

`ifdef DUMP
  initial begin $dumpfile(`QS_VCD_DUMP_NAME); $dumpvars(2, yarp_tb_top); end
`endif

endmodule
