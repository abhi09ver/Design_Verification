// LEVEL 7 - Why simple CPUs wait: a "busy bit" scoreboard for an IN-ORDER pipeline.
// busy[r] = 1 means "someone is still computing register r".
// An instruction may start only if its sources are not busy (RAW) and its destination
// is not busy (WAW). If it must wait, EVERYTHING behind it waits too (in order!).
module scoreboard (
  input  logic       clk, rst,
  input  logic       issue_valid,             // instruction at the front wants to start
  input  logic [4:0] rs1, rs2, rd,
  output logic       stall,
  input  logic       wb_valid,                // a result came back
  input  logic [4:0] wb_rd
);
  logic [31:0] busy;
  assign stall = issue_valid && (busy[rs1] || busy[rs2] || (rd != 0 && busy[rd]));
  always_ff @(posedge clk) begin
    if (rst) busy <= '0;
    else begin
      if (wb_valid)                          busy[wb_rd] <= 1'b0;
      if (issue_valid && !stall && rd != 0)  busy[rd]    <= 1'b1;   // same-cycle set wins
    end
  end
endmodule

module tb_L07;
  logic clk = 0, rst = 1, issue_valid = 0, stall, wb_valid = 0;
  logic [4:0] rs1, rs2, rd, wb_rd; int errors = 0, waited = 0;
  scoreboard dut (.*);
  always #5 clk = ~clk;
  task automatic issue(input [4:0] s1, s2, d);
    @(negedge clk); issue_valid = 1; rs1 = s1; rs2 = s2; rd = d;
    #1 while (stall) begin waited++; @(negedge clk); #1; end
    @(posedge clk); @(negedge clk); issue_valid = 0;
  endtask
  initial begin
    repeat (2) @(posedge clk); @(negedge clk); rst = 0;   // change inputs away from the clock edge
    issue(1, 2, 3);                                // "mul x3, x1, x2" - slow, x3 busy
    fork
      begin repeat (5) @(posedge clk); @(negedge clk); wb_valid = 1; wb_rd = 3; @(posedge clk); @(negedge clk); wb_valid = 0; end
      begin issue(3, 3, 4); end                    // "add x4, x3, x3" must WAIT for x3
    join
    if (waited < 3) begin errors++; $display("FAIL: add did not wait for mul"); end
    waited = 0; issue(5, 6, 7);                    // independent: must NOT wait
    if (waited != 0) begin errors++; $display("FAIL: independent instruction waited"); end
    $display("L07 scoreboard: %s (%0d errors: dependent add must wait, independent op must not)", errors ? "FAIL" : "PASS", errors);
    $finish;
  end
endmodule
