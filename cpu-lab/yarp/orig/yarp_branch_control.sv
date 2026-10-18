`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.06.2024 11:40:43
// Design Name: 
// Module Name: yarp_branch_control
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module yarp_branch_control import yarp_pkg1::*; (
  // Source operands
  input  logic [31:0] opr_a_i,
  input  logic [31:0] opr_b_i,

  // Branch Type
  input  logic        is_b_type_ctl_i,
  input  logic [2:0]  instr_func3_ctl_i,

  // Branch outcome
  output logic        branch_taken_o
);

  // --------------------------------------------------------
  // Internal signals
  // --------------------------------------------------------
  logic [31:0] twos_compl_a;
  logic [31:0] twos_compl_b;

  logic        branch_taken;

  assign twos_compl_a = opr_a_i[31] ? ~opr_a_i + 32'h1 : opr_a_i;
  assign twos_compl_b = opr_b_i[31] ? ~opr_b_i + 32'h1 : opr_b_i;

  always_comb begin
    case (instr_func3_ctl_i)
      BEQ     : branch_taken = (opr_a_i == opr_b_i);
      BNE     : branch_taken = (opr_a_i != opr_b_i);
      BLT     : branch_taken = (opr_a_i <  opr_b_i);
      BGE     : branch_taken = (opr_a_i >= opr_b_i);
      BLTU    : branch_taken = (twos_compl_a <  twos_compl_b);
      BGEU    : branch_taken = (twos_compl_a >= twos_compl_b);
      default : branch_taken = 1'b0;
    endcase
  end

  assign branch_taken_o = is_b_type_ctl_i & branch_taken;

endmodule
