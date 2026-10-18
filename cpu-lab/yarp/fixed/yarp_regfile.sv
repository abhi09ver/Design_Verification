`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.06.2024 11:35:45
// Design Name: 
// Module Name: yarp_regfile
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


module yarp_regfile (
  input   logic          clk,
  input   logic          reset_n,

  // Source registers
  input   logic [4:0]    rs1_addr_i,
  input   logic [4:0]    rs2_addr_i,

  // Destination register
  input   logic [4:0]    rd_addr_i,
  input   logic          wr_en_i,
  input   logic [31:0]   wr_data_i,

  // Register Data
  output  logic [31:0]   rs1_data_o,
  output  logic [31:0]   rs2_data_o
);

  // --------------------------------------------------------
  // Internal Wires and Registers
  // --------------------------------------------------------
  // Register File
  logic [31:0] [31:0]regfile;

  // --------------------------------------------------------
  // Write logic for the register file
  // --------------------------------------------------------
  for (genvar i=0; i<32; i++) begin : g_regfile_wr
    logic reg_wr_en;
    // Enable the flops only for the register being written
    assign reg_wr_en = (rd_addr_i == i[4:0]) & wr_en_i;
    // Flops for the register file
    always_ff @(posedge clk)
      // Register X0 is hardwired to '0
      if (i==0) begin
        regfile[i] <= 32'h0;
      end else begin
        if(reg_wr_en) begin
          regfile[i] <= wr_data_i;
        end
      end
  end

  // --------------------------------------------------------
  // Read logic for the register file
  // --------------------------------------------------------
  assign rs1_data_o = regfile[rs1_addr_i];
  assign rs2_data_o = regfile[rs2_addr_i];

endmodule

