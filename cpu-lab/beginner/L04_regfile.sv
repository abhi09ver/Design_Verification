// LEVEL 4 - The register file: 32 numbered boxes. Read 2, write 1 per cycle. x0 is always 0.
module regfile (
  input  logic        clk,
  input  logic [4:0]  ra1, ra2,          // read addresses (combinational read)
  output logic [31:0] rd1, rd2,
  input  logic        we,                // write enable
  input  logic [4:0]  wa,
  input  logic [31:0] wd
);
  logic [31:0] r [32];
  always_ff @(posedge clk)
    if (we && wa != 0) r[wa] <= wd;      // writes to x0 are thrown away
  assign rd1 = (ra1 == 0) ? '0 : r[ra1];
  assign rd2 = (ra2 == 0) ? '0 : r[ra2];
endmodule

module tb_L04;
  logic clk = 0, we; logic [4:0] ra1, ra2, wa; logic [31:0] rd1, rd2, wd, model [32];
  int errors = 0;
  regfile dut (.*);
  always #5 clk = ~clk;
  initial begin
    foreach (model[i]) model[i] = 0;
    for (int i = 1; i < 32; i++) begin @(negedge clk); we = 1; wa = i; wd = 0; @(posedge clk); end // clear
    repeat (500) begin
      @(negedge clk);
      we = $urandom_range(0,1); wa = $urandom_range(0,31); wd = $urandom;
      ra1 = $urandom_range(0,31); ra2 = $urandom_range(0,31);
      #1;
      if (rd1 !== model[ra1] || rd2 !== model[ra2]) begin errors++; $display("FAIL read"); end
      @(posedge clk);
      if (we && wa != 0) model[wa] = wd;
    end
    $display("L04 regfile: %s (%0d errors, x0 = %0d)", errors ? "FAIL" : "PASS", errors, model[0]);
    $finish;
  end
endmodule
