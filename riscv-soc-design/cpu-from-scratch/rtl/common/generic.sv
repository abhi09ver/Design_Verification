// generic.sv -- small building blocks, named like Wally's src/generic/
//
// Wally builds everything from a handful of flops and muxes. Using the same
// names here means you can open cvw/src and recognize the pieces instantly.
//
//   flopr     : flop with synchronous reset
//   flopenr   : flop with reset + enable          (enable = ~Stall)
//   flopenrc  : flop with reset + clear + enable  (clear  =  Flush)
//   mux2/3/4  : plain muxes, select is a binary code

module flopr #(parameter WIDTH = 32, parameter logic [WIDTH-1:0] RESETVAL = '0) (
  input  logic             clk, reset,
  input  logic [WIDTH-1:0] d,
  output logic [WIDTH-1:0] q
);
  always_ff @(posedge clk)
    if (reset) q <= RESETVAL;
    else       q <= d;
endmodule

module flopenr #(parameter WIDTH = 32, parameter logic [WIDTH-1:0] RESETVAL = '0) (
  input  logic             clk, reset, en,
  input  logic [WIDTH-1:0] d,
  output logic [WIDTH-1:0] q
);
  always_ff @(posedge clk)
    if (reset)   q <= RESETVAL;
    else if (en) q <= d;
endmodule

// Pipeline register. Clear (flush) has priority over enable (stall), exactly
// as in Wally: a flushed stage becomes a bubble even if it was also stalled.
module flopenrc #(parameter WIDTH = 32) (
  input  logic             clk, reset, clear, en,
  input  logic [WIDTH-1:0] d,
  output logic [WIDTH-1:0] q
);
  always_ff @(posedge clk)
    if (reset)      q <= '0;
    else if (en)    q <= clear ? '0 : d;
endmodule

module mux2 #(parameter WIDTH = 32) (
  input  logic [WIDTH-1:0] d0, d1,
  input  logic             s,
  output logic [WIDTH-1:0] y
);
  assign y = s ? d1 : d0;
endmodule

module mux3 #(parameter WIDTH = 32) (
  input  logic [WIDTH-1:0] d0, d1, d2,
  input  logic [1:0]       s,
  output logic [WIDTH-1:0] y
);
  assign y = s[1] ? d2 : (s[0] ? d1 : d0);
endmodule
