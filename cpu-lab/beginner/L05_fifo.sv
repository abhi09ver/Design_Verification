// LEVEL 5 - A FIFO with valid/ready: the "queue at the ticket counter".
// RULE: data moves ONLY when valid && ready are both 1 on the same clock edge.
module fifo #(parameter int DEPTH = 4, parameter int W = 8) (
  input  logic         clk, rst,
  input  logic         in_valid,  output logic in_ready,   // producer side
  input  logic [W-1:0] in_data,
  output logic         out_valid, input  logic out_ready,  // consumer side
  output logic [W-1:0] out_data
);
  logic [W-1:0] mem [DEPTH];
  logic [$clog2(DEPTH)-1:0] rd_ptr, wr_ptr;
  logic [$clog2(DEPTH):0]   count;               // one extra bit so it can hold DEPTH
  wire push = in_valid  && in_ready;
  wire pop  = out_valid && out_ready;
  assign in_ready  = (count < DEPTH);
  assign out_valid = (count > 0);
  assign out_data  = mem[rd_ptr];
  always_ff @(posedge clk) begin
    if (rst) begin rd_ptr <= 0; wr_ptr <= 0; count <= 0; end
    else begin
      if (push) begin mem[wr_ptr] <= in_data; wr_ptr <= wr_ptr + 1'b1; end
      if (pop)  rd_ptr <= rd_ptr + 1'b1;
      count <= count + push - pop;               // push AND pop in one cycle: count stays
    end
  end
endmodule

module tb_L05;
  logic clk = 0, rst = 1, in_valid = 0, in_ready, out_valid, out_ready = 0;
  logic [7:0] in_data, out_data, q[$], nxt = 0; int errors = 0, popped = 0;
  fifo #(4, 8) dut (.*);
  always #5 clk = ~clk;
  initial begin
    @(negedge clk); rst = 0;
    repeat (400) begin
      @(negedge clk);
      in_valid = $urandom_range(0,1); in_data = nxt; out_ready = $urandom_range(0,1);
      #1;   // sample the handshake BEFORE the edge - after the edge the outputs have moved on
      if (out_valid && out_ready) begin                     // scoreboard: what comes out must
        if (out_data !== q[0]) errors++;                   // be what went in, in order
        void'(q.pop_front()); popped++;
      end
      if (in_valid && in_ready) begin q.push_back(in_data); nxt++; end
      @(posedge clk);
    end
    $display("L05 fifo: %s (%0d errors, %0d items passed through)", errors ? "FAIL" : "PASS", errors, popped);
    $finish;
  end
endmodule
