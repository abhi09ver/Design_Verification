// registered N-bit adder: flops in, adder, flop out -> one reg-to-reg path
module addr #(parameter N = 32) (input logic clk, input logic [N-1:0] a, b, output logic [N-1:0] y);
  logic [N-1:0] ar, br;
  always_ff @(posedge clk) begin ar <= a; br <= b; y <= ar + br; end
endmodule
