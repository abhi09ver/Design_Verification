// LEVEL 9 - Reservation station + common data bus (CDB).
// Each waiting instruction listens to the CDB ("ticket #5 is ready, value 42!").
// When both operands are known it raises its hand; select picks the OLDEST hand.
module res_station #(parameter int N = 4, parameter int TW = 3) (
  input  logic clk, rst,
  // insert (from rename)
  input  logic          ins_valid,  output logic ins_ready,
  input  logic [3:0]    ins_op,
  input  logic          ins_a_rdy,  input logic [TW-1:0] ins_a_tag, input logic [31:0] ins_a_val,
  input  logic          ins_b_rdy,  input logic [TW-1:0] ins_b_tag, input logic [31:0] ins_b_val,
  input  logic [TW-1:0] ins_dst,
  // CDB broadcast
  input  logic          cdb_valid,  input logic [TW-1:0] cdb_tag,   input logic [31:0] cdb_val,
  // issue to the execution unit
  output logic          iss_valid,  output logic [3:0] iss_op,
  output logic [31:0]   iss_a, iss_b, output logic [TW-1:0] iss_dst
);
  typedef struct packed {
    logic busy; logic [3:0] op; logic [7:0] age;
    logic a_rdy; logic [TW-1:0] a_tag; logic [31:0] a_val;
    logic b_rdy; logic [TW-1:0] b_tag; logic [31:0] b_val;
    logic [TW-1:0] dst;
  } ent_t;
  ent_t e [N];
  logic [7:0] age_ctr;
  int free_i, pick;

  always_comb begin                                   // first free slot
    free_i = -1;
    for (int i = N-1; i >= 0; i--) if (!e[i].busy) free_i = i;
  end
  assign ins_ready = (free_i != -1);

  always_comb begin                                   // select: oldest ready entry
    pick = -1;
    for (int i = 0; i < N; i++)
      if (e[i].busy && e[i].a_rdy && e[i].b_rdy && (pick == -1 || e[i].age < e[pick].age)) pick = i;
  end
  assign iss_valid = (pick != -1);
  assign iss_op  = iss_valid ? e[pick].op    : '0;
  assign iss_a   = iss_valid ? e[pick].a_val : '0;
  assign iss_b   = iss_valid ? e[pick].b_val : '0;
  assign iss_dst = iss_valid ? e[pick].dst   : '0;

  always_ff @(posedge clk) begin
    if (rst) begin foreach (e[i]) e[i].busy <= 1'b0; age_ctr <= 0; end
    else begin
      // wakeup: every waiting operand compares its tag with the CDB (valid bit, NOT tag!=0)
      for (int i = 0; i < N; i++) begin
        if (e[i].busy && !e[i].a_rdy && cdb_valid && e[i].a_tag == cdb_tag) begin e[i].a_rdy <= 1; e[i].a_val <= cdb_val; end
        if (e[i].busy && !e[i].b_rdy && cdb_valid && e[i].b_tag == cdb_tag) begin e[i].b_rdy <= 1; e[i].b_val <= cdb_val; end
      end
      if (iss_valid) e[pick].busy <= 1'b0;            // leaves the RS when issued
      if (ins_valid && ins_ready) begin
        e[free_i].busy <= 1; e[free_i].op <= ins_op; e[free_i].dst <= ins_dst; e[free_i].age <= age_ctr;
        // also catch a broadcast that happens in the SAME cycle we are inserted (classic miss!)
        e[free_i].a_rdy <= ins_a_rdy || (cdb_valid && cdb_tag == ins_a_tag);
        e[free_i].a_val <= ins_a_rdy ? ins_a_val : cdb_val;
        e[free_i].a_tag <= ins_a_tag;
        e[free_i].b_rdy <= ins_b_rdy || (cdb_valid && cdb_tag == ins_b_tag);
        e[free_i].b_val <= ins_b_rdy ? ins_b_val : cdb_val;
        e[free_i].b_tag <= ins_b_tag;
        age_ctr <= age_ctr + 1;
      end
    end
  end
endmodule

module tb_L09;
  logic clk = 0, rst = 1, ins_valid = 0, ins_ready, ins_a_rdy, ins_b_rdy, cdb_valid = 0, iss_valid;
  logic [3:0] ins_op, iss_op; logic [2:0] ins_a_tag, ins_b_tag, ins_dst, cdb_tag, iss_dst;
  logic [31:0] ins_a_val, ins_b_val, cdb_val, iss_a, iss_b; int errors = 0;
  res_station dut (.*);
  always #5 clk = ~clk;
  initial begin
    repeat (2) @(posedge clk); @(negedge clk); rst = 0;   // change inputs away from the clock edge
    // A: waits for ticket 0 (operand a) ;  B: fully ready but younger
    @(negedge clk); ins_valid = 1; ins_op = 1; ins_dst = 5; ins_a_rdy = 0; ins_a_tag = 0; ins_b_rdy = 1; ins_b_val = 10; ins_b_tag = 0;
    @(negedge clk); ins_op = 2; ins_dst = 6; ins_a_rdy = 1; ins_a_val = 7; ins_b_rdy = 1; ins_b_val = 8;
    @(negedge clk); ins_valid = 0; #1;
    if (!(iss_valid && iss_dst == 6)) begin errors++; $display("FAIL: ready B should issue first (out of order!)"); end
    @(negedge clk); #1;
    if (iss_valid) begin errors++; $display("FAIL: A issued before its operand arrived"); end
    cdb_valid = 1; cdb_tag = 0; cdb_val = 32;                 // "ticket 0 is ready: 32"
    @(negedge clk); cdb_valid = 0; #1;
    if (!(iss_valid && iss_dst == 5 && iss_a == 32 && iss_b == 10)) begin errors++; $display("FAIL: A not woken by tag 0"); end
    $display("L09 reservation station: %s (%0d errors: younger ready op first, tag-0 wakeup)", errors ? "FAIL" : "PASS", errors);
    $finish;
  end
endmodule
