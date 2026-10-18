// --------------------------------------------------------
// YARP - Interface   (user's original version, unchanged)
// --------------------------------------------------------
interface yarp_interface (
  input   logic     clk
);
  logic             reset_n;
  logic             instr_mem_req;
  logic [31:0]      instr_mem_addr;
  logic             instr_mem_ready;
  logic [31:0]      instr_mem_rd_data;
  logic             data_mem_req;
  logic [31:0]      data_mem_addr;
  logic [1:0]       data_mem_byte_en;
  logic             data_mem_wr;
  logic [31:0]      data_mem_wr_data;
  logic             data_mem_ready;
  logic [31:0]      data_mem_rd_data;

  clocking cb @(posedge clk);
    inout    reset_n;
    inout    instr_mem_req;
    inout    instr_mem_addr;
    inout    instr_mem_ready;
    inout    instr_mem_rd_data;
    inout    data_mem_req;
    inout    data_mem_addr;
    inout    data_mem_byte_en;
    inout    data_mem_wr;
    inout    data_mem_wr_data;
    inout    data_mem_ready;
    inout    data_mem_rd_data;
  endclocking
endinterface
