// LEVEL 2 - The clock and the flip-flop. Sequential logic REMEMBERS.
// A register only changes on the clock edge. Everything else is "next value" math.
module counter #(parameter int W = 4) (
  input  logic         clk, rst,   // rst: active-high, synchronous
  input  logic         en,
  output logic [W-1:0] count
);
  always_ff @(posedge clk) begin          // always_ff = "this is a flip-flop"
    if (rst)     count <= '0;             // <=  (non-blocking): every flop updates TOGETHER
    else if (en) count <= count + 1'b1;   // wraps 15 -> 0 by itself (4 bits)
  end
endmodule

module tb_L02;
  logic clk = 0, rst = 1, en = 0; logic [3:0] count; int model = 0, errors = 0;
  counter #(4) dut (.*);
  always #5 clk = ~clk;
  initial begin
    @(negedge clk); rst = 0;
    repeat (40) begin
      en = $urandom_range(0, 1);
      @(posedge clk); #1;                          // check just after the edge
      if (en) model = (model + 1) % 16;
      if (count !== model) begin errors++; $display("FAIL count=%0d model=%0d", count, model); end
      @(negedge clk);
    end
    $display("L02 counter: %s (%0d errors)", errors ? "FAIL" : "PASS", errors);
    $finish;
  end
endmodule
