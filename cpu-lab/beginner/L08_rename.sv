// LEVEL 8 - Renaming: give every result a fresh "ticket number" (tag).
// RAT[r] says: "the newest value of register r will come from ticket #tag".
// If RAT says nothing (valid=0), the value is already in the register file.
module rename_table #(parameter int NREG = 8, parameter int NTAG = 8) (
  input  logic clk, rst,
  // rename one instruction per cycle
  input  logic                      ren_valid,
  input  logic [$clog2(NREG)-1:0]   rs1, rs2, rd,
  input  logic [$clog2(NTAG)-1:0]   new_tag,      // ticket number handed out (ROB slot)
  output logic                      s1_pending, s2_pending,
  output logic [$clog2(NTAG)-1:0]   s1_tag, s2_tag,
  // a ticket is finished and its value is now in the register file
  input  logic                      commit_valid,
  input  logic [$clog2(NREG)-1:0]   commit_rd,
  input  logic [$clog2(NTAG)-1:0]   commit_tag
);
  logic                     map_valid [NREG];   // a SEPARATE valid bit: tag 0 is a real tag!
  logic [$clog2(NTAG)-1:0]  map_tag   [NREG];   // (using 0 to mean "none" was bug B04)
  assign s1_pending = map_valid[rs1];  assign s1_tag = map_tag[rs1];
  assign s2_pending = map_valid[rs2];  assign s2_tag = map_tag[rs2];
  always_ff @(posedge clk) begin
    if (rst) foreach (map_valid[i]) map_valid[i] <= 1'b0;
    else begin
      // clear ONLY if the mapping still points at the finishing ticket
      if (commit_valid && map_valid[commit_rd] && map_tag[commit_rd] == commit_tag)
        map_valid[commit_rd] <= 1'b0;
      // a new rename of the same register wins (written last)
      if (ren_valid && rd != 0) begin map_valid[rd] <= 1'b1; map_tag[rd] <= new_tag; end
    end
  end
endmodule

module tb_L08;
  logic clk = 0, rst = 1, ren_valid = 0, commit_valid = 0, s1_pending, s2_pending;
  logic [2:0] rs1, rs2, rd, commit_rd, new_tag, commit_tag, s1_tag, s2_tag; int errors = 0;
  rename_table dut (.*);
  always #5 clk = ~clk;
  task automatic ren(input [2:0] a, b, d, t);
    @(negedge clk); ren_valid = 1; rs1 = a; rs2 = b; rd = d; new_tag = t; @(posedge clk); @(negedge clk); ren_valid = 0;
  endtask
  task automatic commit(input [2:0] d, t);
    @(negedge clk); commit_valid = 1; commit_rd = d; commit_tag = t; @(posedge clk); @(negedge clk); commit_valid = 0;
  endtask
  task automatic expect_src(input [2:0] r, input logic pend, input [2:0] t, input string why);
    @(negedge clk); rs1 = r; #1;
    if (s1_pending !== pend || (pend && s1_tag !== t)) begin errors++; $display("FAIL %s: x%0d pending=%b tag=%0d", why, r, s1_pending, s1_tag); end
  endtask
  initial begin
    repeat (2) @(posedge clk); @(negedge clk); rst = 0;   // change inputs away from the clock edge
    ren(1, 2, 3, 0);   expect_src(3, 1, 0, "x3 from ticket 0 (tag 0 is real)");
    ren(4, 5, 3, 1);   expect_src(3, 1, 1, "WAW: x3 now from the NEWER ticket 1");
    commit(3, 0);      expect_src(3, 1, 1, "old ticket 0 finishing must NOT clear x3");
    commit(3, 1);      expect_src(3, 0, 0, "ticket 1 finishing clears x3 -> read the register file");
    $display("L08 rename: %s (%0d errors)", errors ? "FAIL" : "PASS", errors);
    $finish;
  end
endmodule
