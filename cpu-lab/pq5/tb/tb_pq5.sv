`timescale 1ns/1ps
// tb_pq5: loads +PROG=<hex>, runs until the `halt` instruction retires, prints a commit
// trace, perf counters, registers and memory for tools/run_pq5.py to check against the ISS.
// +PIPE prints a one-line picture of the pipeline every cycle.
module tb_pq5;
  import pq5_pkg::*;
  logic clk = 0, rst = 1;
  pq5_core dut (.clk, .rst);
  always #5 clk = ~clk;

  string prog; int cyc = 0; bit pipe;
  function automatic string slot(logic v, logic [31:0] pc);
    return v ? $sformatf("%3h", pc) : " - ";
  endfunction

  initial begin
    pipe = $test$plusargs("PIPE");
    if (!$value$plusargs("PROG=%s", prog)) begin $display("need +PROG=file.hex"); $finish; end
    foreach (dut.u_fetch.imem[i]) dut.u_fetch.imem[i] = 32'h00000013;
    foreach (dut.u_mem.dmem[i])   dut.u_mem.dmem[i]   = 0;
    foreach (dut.u_rf.r[i])       dut.u_rf.r[i]       = 0;
    $readmemh(prog, dut.u_fetch.imem);
    repeat (2) @(posedge clk); @(negedge clk); rst = 0;
  end

  always @(negedge clk) if (!rst) begin
    cyc++;
    if (pipe)
      $display("PIPE %3d | IF %3h | ID %s | EX %s | MEM %s | WB %s |%s%s", cyc, dut.u_fetch.pc,
               slot(dut.if_id.valid, dut.if_id.pc), slot(dut.id_ex.valid, dut.id_ex.pc),
               slot(dut.ex_mem.valid, dut.ex_mem.pc), slot(dut.mem_wb.valid, dut.mem_wb.pc),
               dut.stall ? " STALL(load-use)" : "", dut.flush ? $sformatf(" FLUSH->%0h", dut.redirect_pc) : "");
    if (dut.mem_wb.valid) begin
      if (dut.u_fetch.imem[dut.mem_wb.pc[9:2]] == 32'h0000006f) begin      // halt retired
        $display("PERF cycles=%0d retired=%0d stall_cycles=%0d flushes=%0d",
                 dut.cycles, dut.retired, dut.stall_cycles, dut.flushes);
        $display("STATUS DONE cycles=%0d", cyc);
        for (int r = 0; r < 32; r++) $display("ARF x%0d=%08h", r, dut.u_rf.r[r]);
        for (int m = 0; m < 64; m++) $display("MEM %0d=%08h", m, dut.u_mem.dmem[m]);
        $finish;                       // note: $finish does not leave this block by itself...
      end else                         // ...so the commit print must be in an else
      $display("COMMIT pc=%08h rd=%0d val=%08h", dut.mem_wb.pc,
               dut.mem_wb.we ? dut.mem_wb.rd : 5'd0, dut.mem_wb.we ? dut.mem_wb.wdata : 32'd0);
    end
    if (cyc > 20000) begin $display("STATUS TIMEOUT cycles=%0d", cyc); $finish; end
  end

  // a few white-box checks (SVA)
  a_x0:    assert property (@(posedge clk) disable iff (rst) !(dut.mem_wb.valid && dut.mem_wb.we && dut.mem_wb.rd == 0))
             else $error("[SVA] x0 write");
  a_hold:  assert property (@(posedge clk) disable iff (rst) (dut.stall && !dut.flush) |=> $stable(dut.if_id))
             else $error("[SVA] IF/ID changed during a stall");
  a_noflushstall: assert property (@(posedge clk) disable iff (rst) !(dut.stall && dut.flush))
             else $error("[SVA] stall and flush together (should be impossible)");
  // The interlock guarantees a load is never one stage ahead of an instruction that reads its
  // result. This proves the `!fwd_mem.is_load` forwarding guard can never matter (mutation survives).
  wire use1 = !(dut.id_ex.is_lui || dut.id_ex.a_is_pc || dut.id_ex.is_jal);
  wire use2 = dut.id_ex.is_store || dut.id_ex.is_branch || (!dut.id_ex.b_is_imm && !dut.id_ex.is_jal && !dut.id_ex.is_lui);
  a_loaduse: assert property (@(posedge clk) disable iff (rst)
             !(dut.ex_mem.valid && dut.ex_mem.is_load && dut.ex_mem.we && dut.id_ex.valid &&
               ((use1 && dut.id_ex.rs1 == dut.ex_mem.rd) || (use2 && dut.id_ex.rs2 == dut.ex_mem.rd))))
             else $error("[SVA] load result needed one stage too early");
endmodule
