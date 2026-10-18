`timescale 1ns/1ps
// --------------------------------------------------------
// YARP - Top Testbench
// --------------------------------------------------------

`include "yarp_interface.sv"

import yarp_tb_pkg::*;
module yarp_tb_top ();

  logic                       clk;
  yarp_environment            env;
  int                         num_tr;

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

  yarp_interface yarp_if (
    .clk              (clk)
  );

  always begin
    clk = 1'b1;
    #5;
    clk = 1'b0;
    #5;
  end

  initial begin
    $timeformat(-12, 0, " ps", 10);
    num_tr = 50;
    void'($value$plusargs("NUM_TR=%d", num_tr));
    env = new(yarp_if, num_tr);
    // [TEST HOOK] blueprint override selected by plusarg
    if ($test$plusargs("TEST=mem"))   begin yarp_tr_mem   t = new(); env.agent.gen.blueprint = t; end
    if ($test$plusargs("TEST=alu"))   begin yarp_tr_alu   t = new(); env.agent.gen.blueprint = t; end
    if ($test$plusargs("TEST=b2b"))   begin yarp_tr_b2b   t = new(); env.agent.gen.blueprint = t; end
    if ($test$plusargs("TEST=stall")) begin yarp_tr_stall t = new(); env.agent.gen.blueprint = t; end
    if ($test$plusargs("TEST=cmp"))   begin yarp_tr_cmp   t = new(); env.agent.gen.blueprint = t; end
    env.run();
    $display("[INFO] @ %0t: YARP Testbench: Finished running the test", $time);
    $finish();
  end

  // [FIX W1] hang watchdog: a core that stops fetching must FAIL fast,
  // not let the simulation run forever (~36 cycles max per instruction)
  initial begin
    #1;
    #(num_tr * 400ns + 10us);
    $fatal(1, "[ERROR] @ %0t: WATCHDOG, test did not finish (core hung?)", $time);
  end

  initial begin
    $dumpfile(`QS_VCD_DUMP_NAME);
    $dumpvars(2, yarp_tb_top);
  end

endmodule
