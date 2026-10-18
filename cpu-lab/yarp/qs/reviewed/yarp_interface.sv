// --------------------------------------------------------
// YARP - Interface (reviewed version)
//   * drv_cb : TB acts as the MEMORY + reset driver
//              -> drives ready / rd_data / reset_n, samples the core's requests
//   * mon_cb : passive monitor, samples everything
//   * modports pin the direction of each user (DUT / driver / monitor)
//   * Protocol rules from the spec are checked here with SVA, so every
//     test that uses the interface gets them for free.
// --------------------------------------------------------
interface yarp_interface (
  input  logic clk
);

  logic             reset_n;

  // Instruction memory interface
  logic             instr_mem_req;
  logic [31:0]      instr_mem_addr;
  logic             instr_mem_ready;
  logic [31:0]      instr_mem_rd_data;

  // Data memory interface
  logic             data_mem_req;
  logic [31:0]      data_mem_addr;
  logic [1:0]       data_mem_byte_en;   // 00 B, 01 H, 10 reserved, 11 W
  logic             data_mem_wr;
  logic [31:0]      data_mem_wr_data;
  logic             data_mem_ready;
  logic [31:0]      data_mem_rd_data;

  // White-box probe: architectural registers, driven by the top with an
  // assign. The monitor samples it at negedge, so it is race-free (see monitor).
  logic [31:0][31:0] arch_reg;

  // ------------------------------------------------------
  // Driver clocking block: TB plays the memory
  // inputs sampled just before the edge (#1step), outputs driven #1 after it
  // ------------------------------------------------------
  clocking drv_cb @(posedge clk);
    default input #1step output #1;
    output reset_n;
    input  instr_mem_req, instr_mem_addr;
    output instr_mem_ready, instr_mem_rd_data;
    input  data_mem_req, data_mem_addr, data_mem_byte_en,
           data_mem_wr, data_mem_wr_data;
    output data_mem_ready, data_mem_rd_data;
  endclocking

  // ------------------------------------------------------
  // Monitor clocking block: everything is an input
  // ------------------------------------------------------
  clocking mon_cb @(posedge clk);
    default input #1step;
    input reset_n;
    input instr_mem_req, instr_mem_addr, instr_mem_ready, instr_mem_rd_data;
    input data_mem_req, data_mem_addr, data_mem_byte_en, data_mem_wr,
          data_mem_wr_data, data_mem_ready, data_mem_rd_data;
  endclocking

  modport drv_mp (clocking drv_cb, input clk);
  modport mon_mp (clocking mon_cb, input clk);
  modport dut_mp (
    input  clk, reset_n,
    output instr_mem_req, instr_mem_addr,
    input  instr_mem_ready, instr_mem_rd_data,
    output data_mem_req, data_mem_addr, data_mem_byte_en, data_mem_wr, data_mem_wr_data,
    input  data_mem_ready, data_mem_rd_data
  );

  // ------------------------------------------------------
  // Protocol checks (one per spec requirement)
  // ------------------------------------------------------
  wire i_wait = instr_mem_req && !instr_mem_ready;   // request stalled
  wire d_wait = data_mem_req  && !data_mem_ready;
  wire i_hs   = instr_mem_req &&  instr_mem_ready;   // handshake this cycle

  default clocking @(posedge clk); endclocking
  default disable iff (!reset_n);

  // R1/R2: instr req held, addr stable until ready
  a_ireq_hold  : assert property (i_wait |=> instr_mem_req)
    else $error("[SVA] R1 instr_mem_req dropped before ready");
  a_iaddr_stab : assert property (i_wait |=> $stable(instr_mem_addr))
    else $error("[SVA] R2 instr_mem_addr changed before ready");

  // R3: a new data request starts in the same cycle its instruction is accepted
  a_dreq_start : assert property (data_mem_req && !$past(d_wait) |-> i_hs)
    else $error("[SVA] R3 data_mem_req started without an instruction handshake");

  // R4-R7: data req held, payload stable until ready
  a_dreq_hold  : assert property (d_wait |=> data_mem_req)
    else $error("[SVA] R4 data_mem_req dropped before ready");
  a_dpay_stab  : assert property (d_wait |=> $stable({data_mem_addr, data_mem_byte_en,
                                                      data_mem_wr, data_mem_wr_data}))
    else $error("[SVA] R5-R7 data payload changed before ready");

  // R10: no new fetch while a data transfer is outstanding
  a_no_fetch   : assert property (d_wait |=> !instr_mem_req)
    else $error("[SVA] R10 fetch issued while a data transfer was pending");

  // Extra checks a senior reviewer would add
  a_size_legal : assert property (data_mem_req |-> data_mem_byte_en != 2'b10)
    else $error("[SVA] reserved byte_en 2'b10 used");
  a_ialign     : assert property (instr_mem_req |-> instr_mem_addr[1:0] == 2'b00)
    else $error("[SVA] misaligned fetch address");
  a_no_x       : assert property (instr_mem_req |-> !$isunknown(instr_mem_addr))
    else $error("[SVA] X on instr_mem_addr");

  // Coverage: did we actually see the interesting cases?
  c_i_stall    : cover property (i_wait ##1 i_hs);
  c_d_stall    : cover property (d_wait ##1 data_mem_req && data_mem_ready);
  c_b2b_fetch  : cover property (i_hs ##1 i_hs);

endinterface
