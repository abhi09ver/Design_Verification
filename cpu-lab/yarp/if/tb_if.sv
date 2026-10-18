// Harness: the YARP core from your upload behind the interface.
// +READY=1 -> ready always high ; +READY=0 -> ready toggles randomly (spec allows it)
module tb_if;
  logic clk = 0; always #5 clk = ~clk;
  yarp_interface vif(clk);
  logic [31:0] imem [0:255];
  logic [31:0] dmem [0:255];
  int unsigned seed = 1, cyc = 0; bit rdy_rand;

  yarp_top #(.RESET_PC(32'h0)) dut (
    .clk(clk), .reset_n(vif.reset_n),
    .instr_mem_req_o(vif.instr_mem_req), .instr_mem_addr_o(vif.instr_mem_addr),
    .instr_mem_rd_data_i(vif.instr_mem_rd_data),
    .data_mem_req_o(vif.data_mem_req), .data_mem_addr_o(vif.data_mem_addr),
    .data_mem_byte_en_o(vif.data_mem_byte_en), .data_mem_wr_o(vif.data_mem_wr),
    .data_mem_wr_data_o(vif.data_mem_wr_data), .data_mem_rd_data_i(vif.data_mem_rd_data));

  // this core has no ready inputs -> memory data must be combinational
  assign vif.instr_mem_rd_data = imem[vif.instr_mem_addr[9:2]];
  assign vif.data_mem_rd_data  = dmem[vif.data_mem_addr[9:2]];

  initial begin
    string p;
    rdy_rand = !$test$plusargs("READY=1");
    for (int i = 0; i < 256; i++) begin imem[i] = 32'h0000006f; dmem[i] = 0; end
    if ($value$plusargs("PROG=%s", p)) $readmemh(p, imem);
    vif.reset_n = 0; vif.instr_mem_ready = 0; vif.data_mem_ready = 0;
    repeat (3) @(vif.drv_cb);
    vif.drv_cb.reset_n <= 1;
    repeat (200) begin
      @(vif.drv_cb);
      vif.drv_cb.instr_mem_ready <= rdy_rand ? 1'($urandom & 1) : 1'b1;
      vif.drv_cb.data_mem_ready  <= rdy_rand ? 1'($urandom & 1) : 1'b1;
    end
    $display("DONE");
    $finish;
  end
endmodule
