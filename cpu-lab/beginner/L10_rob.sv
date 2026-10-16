// LEVEL 10 - The reorder buffer (ROB): finish in ANY order, retire in program order.
// Think of a restaurant pass: dishes may be cooked in any order, but they are
// served to the table in the order they were ordered.
module rob #(parameter int N = 8) (
  input  logic clk, rst,
  input  logic         alloc_valid, output logic alloc_ready,
  input  logic [4:0]   alloc_rd,    output logic [$clog2(N)-1:0] alloc_tag,
  input  logic         done_valid,  input  logic [$clog2(N)-1:0] done_tag,
  input  logic [31:0]  done_val,
  output logic         commit_valid, output logic [4:0] commit_rd,
  output logic [31:0]  commit_val,   output logic [$clog2(N)-1:0] commit_tag
);
  logic valid [N], done [N]; logic [4:0] rd [N]; logic [31:0] val [N];
  logic [$clog2(N)-1:0] head, tail;          // head = oldest (commit), tail = next free (alloc)
  logic [$clog2(N):0]   count;
  assign alloc_ready  = (count < N);
  assign alloc_tag    = tail;
  assign commit_valid = valid[head] && done[head];   // ONLY the oldest may leave
  assign commit_rd    = rd[head];  assign commit_val = val[head];  assign commit_tag = head;
  wire do_alloc = alloc_valid && alloc_ready;
  always_ff @(posedge clk) begin
    if (rst) begin foreach (valid[i]) valid[i] <= 0; head <= 0; tail <= 0; count <= 0; end
    else begin
      if (done_valid) begin done[done_tag] <= 1; val[done_tag] <= done_val; end
      if (commit_valid) begin valid[head] <= 0; head <= head + 1'b1; end
      if (do_alloc) begin valid[tail] <= 1; done[tail] <= 0; rd[tail] <= alloc_rd; tail <= tail + 1'b1; end
      count <= count + do_alloc - commit_valid;
    end
  end
endmodule

module tb_L10;
  logic clk = 0, rst = 1, alloc_valid = 0, alloc_ready, done_valid = 0, commit_valid;
  logic [4:0] alloc_rd, commit_rd; logic [2:0] alloc_tag, done_tag, commit_tag;
  logic [31:0] done_val, commit_val; int errors = 0, order[$];
  int finish_order[5] = '{2, 4, 0, 3, 1};
  rob #(8) dut (.*);
  always #5 clk = ~clk;
  always @(negedge clk) if (!rst && commit_valid) begin
    order.push_back(commit_tag);
    // check the VALUE too - order alone would accept a ROB that retires unfinished entries
    if (commit_val !== 100 + commit_tag) begin errors++; $display("FAIL: ticket %0d retired with %0d", commit_tag, commit_val); end
  end
  initial begin
    repeat (2) @(posedge clk); @(negedge clk); rst = 0;   // change inputs away from the clock edge
    for (int i = 0; i < 5; i++) begin @(negedge clk); alloc_valid = 1; alloc_rd = i + 1; end
    @(negedge clk); alloc_valid = 0;
    foreach (finish_order[k]) begin                  // finish OUT of order: 2,4,0,3,1
      @(negedge clk); done_valid = 1; done_tag = finish_order[k]; done_val = 100 + finish_order[k];
    end
    @(negedge clk); done_valid = 0;
    repeat (6) @(negedge clk);
    if (order.size() != 5) errors++;
    foreach (order[i]) if (order[i] != i) errors++;
    $display("L10 rob: %s (finished in order 2,4,0,3,1 -> retired in order %p)", errors ? "FAIL" : "PASS", order);
    $finish;
  end
endmodule
