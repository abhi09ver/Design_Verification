// LEVEL 1 - Wires and gates: build a 32-bit adder out of 1-bit full adders.
// Combinational logic = no clock, no memory. Output changes when input changes.
module full_adder (input  logic a, b, cin,
                   output logic sum, cout);
  assign sum  = a ^ b ^ cin;                 // odd number of 1s -> sum is 1
  assign cout = (a & b) | (cin & (a ^ b));   // carry when at least two inputs are 1
endmodule

module adder32 (input  logic [31:0] a, b,
                output logic [31:0] sum,
                output logic        cout);
  logic [32:0] c;                            // carry chain: c[0] in, c[32] out
  assign c[0] = 1'b0;
  for (genvar i = 0; i < 32; i++) begin : g_bit   // 'generate' = copy hardware 32 times
    full_adder fa (.a(a[i]), .b(b[i]), .cin(c[i]), .sum(sum[i]), .cout(c[i+1]));
  end
  assign cout = c[32];
endmodule

module tb_L01;
  logic [31:0] a, b, s; logic co; int errors = 0;
  adder32 dut (.a, .b, .sum(s), .cout(co));
  initial begin
    for (int i = 0; i < 1000; i++) begin
      a = $urandom; b = $urandom;
      if (i == 0) begin a = 32'hFFFF_FFFF; b = 1; end      // corner case: wrap-around
      #1;                                                   // let the wires settle
      if ({co, s} !== {1'b0, a} + {1'b0, b}) begin errors++; $display("FAIL %h + %h = %h (cout %b)", a, b, s, co); end
    end
    $display("L01 adder32: %s (%0d errors in 1000 checks)", errors ? "FAIL" : "PASS", errors);
    $finish;
  end
endmodule
