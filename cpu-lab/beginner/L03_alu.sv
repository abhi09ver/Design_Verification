// LEVEL 3 - The ALU: a big "case" that picks one math result.
package alu_pkg;
  typedef enum logic [3:0] {ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA} alu_op_t;
endpackage

module alu import alu_pkg::*; (
  input  alu_op_t     op,
  input  logic [31:0] a, b,
  output logic [31:0] y
);
  always_comb begin
    unique case (op)                        // 'unique': simulator warns if no branch matches
      ADD:  y = a + b;
      SUB:  y = a - b;
      AND:  y = a & b;
      OR:   y = a | b;
      XOR:  y = a ^ b;
      SLT:  y = {31'b0, $signed(a) < $signed(b)};
      SLTU: y = {31'b0, a < b};
      SLL:  y = a << b[4:0];
      SRL:  y = a >> b[4:0];
      SRA:  y = $signed(a) >>> b[4:0];      // >>> keeps the sign bit only on a SIGNED value
      default: y = 'x;                      // never silently "do nothing" (see bug B03)
    endcase
  end
endmodule

module tb_L03 import alu_pkg::*; ;
  alu_op_t op; logic [31:0] a, b, y, exp; int errors = 0;
  alu dut (.*);
  function automatic logic [31:0] model(alu_op_t o, logic [31:0] x, logic [31:0] z);
    case (o)
      ADD: return x + z;            SUB: return x - z;
      AND: return x & z;            OR:  return x | z;    XOR: return x ^ z;
      SLT: return ($signed(x) < $signed(z)) ? 1 : 0;      SLTU: return (x < z) ? 1 : 0;
      SLL: return x << z[4:0];      SRL: return x >> z[4:0];
      SRA: return 32'($signed(x) >>> z[4:0]);
    endcase
  endfunction
  initial begin
    logic [31:0] corner [5] = '{0, 1, 32'hFFFF_FFFF, 32'h8000_0000, 32'h7FFF_FFFF};
    for (int i = 0; i < 3000; i++) begin
      op = alu_op_t'($urandom_range(0, 9));
      a = (i % 3 == 0) ? corner[$urandom_range(0,4)] : $urandom;   // mix corners + random
      b = (i % 5 == 0) ? corner[$urandom_range(0,4)] : $urandom;
      #1 exp = model(op, a, b);
      if (y !== exp) begin errors++; if (errors < 5) $display("FAIL %s %h %h -> %h exp %h", op.name(), a, b, y, exp); end
    end
    $display("L03 alu: %s (%0d errors in 3000 checks)", errors ? "FAIL" : "PASS", errors);
    $finish;
  end
endmodule
