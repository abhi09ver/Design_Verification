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

  // ------------------------------------------------------------------
  // [FIX SVA] protocol checks, one per spec rule. Some bugs give NO wrong
  // result (e.g. fetching while a load is pending), so only an assertion
  // can catch them; the scoreboard never will.
  // ------------------------------------------------------------------
  wire i_wait = instr_mem_req && !instr_mem_ready;
  wire d_wait = data_mem_req  && !data_mem_ready;
  wire i_hs   = instr_mem_req &&  instr_mem_ready;

  default clocking sva_cb @(posedge clk); endclocking
  default disable iff (!reset_n);

  a_ireq_hold  : assert property (i_wait |=> instr_mem_req)
    else $error("[SVA] R1 instr_mem_req dropped before ready");
  a_iaddr_stab : assert property (i_wait |=> $stable(instr_mem_addr))
    else $error("[SVA] R2 instr_mem_addr changed before ready");
  a_dreq_start : assert property (data_mem_req && !$past(d_wait) |-> i_hs)
    else $error("[SVA] R3 data_mem_req started without an instruction handshake");
  a_dreq_hold  : assert property (d_wait |=> data_mem_req)
    else $error("[SVA] R4 data_mem_req dropped before ready");
  a_dpay_stab  : assert property (d_wait |=> $stable({data_mem_addr, data_mem_byte_en, data_mem_wr, data_mem_wr_data}))
    else $error("[SVA] R5-R7 data payload changed before ready");
  a_no_fetch   : assert property (d_wait |=> !instr_mem_req)
    else $error("[SVA] R10 fetch issued while a data transfer was pending");
  a_size_legal : assert property (data_mem_req |-> data_mem_byte_en != 2'b10)
    else $error("[SVA] reserved byte_en 2'b10");
  a_ialign     : assert property (instr_mem_req |-> instr_mem_addr[1:0] == 2'b00)
    else $error("[SVA] misaligned fetch address");
endinterface
