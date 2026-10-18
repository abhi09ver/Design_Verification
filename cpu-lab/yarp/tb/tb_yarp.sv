`timescale 1ns/1ps
// tb_yarp: drives the single-cycle YARP core with a simple instruction + data memory,
// prints one COMMIT line per executed instruction (pc, rd, value) so tools/run_yarp.py can
// compare it with the golden ISS, then dumps registers and memory at `halt` (jal x0, 0).
//
// MEMORY CONTRACT assumed by this TB (the core does not shift lanes itself):
//   data_mem_addr_o   = byte address
//   data_mem_byte_en_o= access SIZE (00 byte, 01 half, 11 word) - not a byte mask
//   loads : memory returns the addressed byte/half RIGHT-ALIGNED in [7:0]/[15:0]
//   stores: write data arrives right-aligned; memory places it in the right lane
// +IMEM_ALWAYS : instruction memory answers even when instr_mem_req_o = 0 (see bug Y4)
module tb_yarp;
  logic clk = 0, reset_n = 0;
  always #5 clk = ~clk;
  logic        imem_req, dmem_req, dmem_wr;
  logic [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
  logic [1:0]  dmem_size;

  yarp_top #(.RESET_PC(32'h0)) dut (
    .clk, .reset_n,
    .instr_mem_req_o(imem_req), .instr_mem_addr_o(imem_addr), .instr_mem_rd_data_i(imem_rdata),
    .data_mem_req_o(dmem_req), .data_mem_addr_o(dmem_addr), .data_mem_byte_en_o(dmem_size),
    .data_mem_wr_o(dmem_wr), .data_mem_wr_data_o(dmem_wdata), .data_mem_rd_data_i(dmem_rdata));

  logic [31:0] imem [256];
  logic [31:0] dmem [1024];
  bit imem_always;
  assign imem_rdata = (imem_req || imem_always) ? imem[imem_addr[9:2]] : 32'h0;   // 0 decodes to "nothing"
  wire  [31:0] dword = dmem[dmem_addr[11:2]];
  assign dmem_rdata = dword >> (8 * dmem_addr[1:0]);                                // right-aligned
  always_ff @(posedge clk)
    if (dmem_req && dmem_wr) begin
      case (dmem_size)
        2'b00:   dmem[dmem_addr[11:2]][8*dmem_addr[1:0] +: 8]  <= dmem_wdata[7:0];
        2'b01:   dmem[dmem_addr[11:2]][8*dmem_addr[1:0] +: 16] <= dmem_wdata[15:0];
        default: dmem[dmem_addr[11:2]]                         <= dmem_wdata;
      endcase
    end

  string prog; int cyc = 0, spurious = 0;
  initial begin
    imem_always = $test$plusargs("IMEM_ALWAYS");
    if (!$value$plusargs("PROG=%s", prog)) begin $display("need +PROG="); $finish; end
    foreach (imem[i]) imem[i] = 32'h00000013;
    foreach (dmem[i]) dmem[i] = 0;
    $readmemh(prog, imem);
    foreach (dut.u_yarp_regfile.regfile[i]) dut.u_yarp_regfile.regfile[i] = 0;
    repeat (2) @(negedge clk); reset_n = 1;
  end

  // A cycle "executes" an instruction whenever a valid one is on the decode input.
  always @(negedge clk) if (reset_n) begin
    logic [31:0] ins; ins = imem_rdata;
    cyc++;
    // a data request from an instruction that is neither a load nor a store
    if (dmem_req && !(ins[6:0] inside {7'h03, 7'h23})) begin
      spurious++;
      if (spurious <= 3) $display("[CHECK] spurious data_mem_req at pc=%08h instr=%08h (opcode %02h)", imem_addr, ins, ins[6:0]);
    end
    if (ins == 32'h0000006f && dut.reset_seen_q) begin
      $display("STATUS DONE cycles=%0d spurious_data_req=%0d", cyc, spurious);
      for (int r = 0; r < 32; r++) $display("ARF x%0d=%08h", r, dut.u_yarp_regfile.regfile[r]);
      for (int m = 0; m < 64; m++) $display("MEM %0d=%08h", m, dmem[m]);
      $finish;
    end else if (ins != 0 && dut.reset_seen_q)   // the PC only advances once reset_seen_q is set
      $display("COMMIT pc=%08h rd=%0d val=%08h", imem_addr,
               (dut.ctl_rf_wr_en && dut.dec_rf_rd != 0) ? dut.dec_rf_rd : 5'd0,
               (dut.ctl_rf_wr_en && dut.dec_rf_rd != 0) ? dut.rf_wr_data : 32'd0);
    if (cyc > 20000) begin $display("STATUS TIMEOUT cycles=%0d", cyc); $finish; end
  end
endmodule
