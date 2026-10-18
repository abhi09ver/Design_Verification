// --------------------------------------------------------
// YARP - Transaction (reviewed)
//   [T1] opcode picked first with weights (pre_randomize + rand_mode(0)).
//        Plain randomize() is uniform over ALL solutions, so J/U-type
//        (many free fields) took about 70% of instructions in the original.
//   [T2] B/J offsets keep bit 1 clear and JALR jumps to an aligned absolute
//        address. RV32I without C cannot fetch a 2-aligned PC.
//   [T3] copy() copies every field (the original dropped the instruction fields).
//   [T4] arch_reg snapshot field, filled by the monitor.
// --------------------------------------------------------
import riscv_pkg::*;
class yarp_transaction;

  rand int              instr_mem_ready_delay;
  rand int              data_mem_ready_delay;

  // Instruction memory interface
  bit                   instr_mem_req;
  bit [31:0]            instr_mem_addr;
  bit                   instr_mem_ready;
  bit [31:0]            instr_mem_rd_data;

  // Data memory interface
  bit                   data_mem_req;
  bit [31:0]            data_mem_addr;
  bit [1:0]             data_mem_byte_en;
  bit                   data_mem_wr;
  bit [31:0]            data_mem_wr_data;
  bit                   data_mem_ready;
  bit [31:0]            data_mem_rd_data;

  // [T4] architectural registers sampled by the monitor (post-update)
  bit [31:0][31:0]      arch_reg;

  // Instruction fields
  bit [31:0]            instruction;
  rand  riscv_op_t      opcode;
  rand  bit[4:0]        rd;
  rand  bit[2:0]        funct3;
  rand  bit[4:0]        rs1;
  rand  bit[4:0]        rs2;
  rand  bit[6:0]        funct7;
  rand  bit[11:0]       imm12;
  rand  bit[19:0]       imm20;

  // [T1] opcode-class weights: tests tune these instead of editing constraints
  int unsigned w_r = 20, w_i = 20, w_ld = 15, w_st = 15, w_br = 10,
               w_lui = 5, w_auipc = 5, w_jal = 5, w_jalr = 5;
  static bit   verbose = 0;

  function void pre_randomize();
    opcode.rand_mode(1);
    randcase
      w_r     : opcode = R_TYPE;
      w_i     : opcode = I_TYPE_1;
      w_ld    : opcode = I_TYPE_0;
      w_st    : opcode = S_TYPE;
      w_br    : opcode = B_TYPE;
      w_lui   : opcode = U_TYPE_0;
      w_auipc : opcode = U_TYPE_1;
      w_jal   : opcode = J_TYPE;
      w_jalr  : opcode = I_TYPE_2;
    endcase
    opcode.rand_mode(0);
  endfunction

  constraint legal_opcode {
    opcode inside {R_TYPE, I_TYPE_0, I_TYPE_1, I_TYPE_2, S_TYPE, B_TYPE, U_TYPE_0, U_TYPE_1, J_TYPE};
  }

  constraint legal_funct3 {
    if (opcode == R_TYPE)        funct3 inside {ADD, SLL, SLT, SLTU, XOR, SRX, OR, AND};
    else if (opcode == I_TYPE_0) funct3 inside {LB, LBU, LH, LHU, LW};
    else if (opcode == I_TYPE_1) funct3 inside {ADDI, SLLI, SLTI, SLTIU, XORI, SRXI, ORI, ANDI};
    else if (opcode == I_TYPE_2) funct3 == 0;
    else if (opcode == S_TYPE)   funct3 inside {SB, SH, SW};
    else if (opcode == B_TYPE)   funct3 inside {BEQ, BNE, BLT, BGE, BLTU, BGEU};
  }

  constraint legal_funct7 {
    if (opcode == R_TYPE) {
      if ((funct3 == ADD) || (funct3 == SRX)) funct7 inside {7'h0, 7'h20};
      else                                    funct7 == 7'h0;
    }
  }

  constraint legal_imm12 {
    if (opcode == I_TYPE_1) {
      if (funct3 == SLLI)      imm12[11:5] == 7'h0;
      else if (funct3 == SRXI) imm12[11:5] inside {7'h0, 7'h20};
    }
  }

  // [T2] keep every fetch word-aligned
  constraint legal_target {
    (opcode == B_TYPE)   -> (imm12[0] == 1'b0);             // imm12 holds imm[12:1]
    (opcode == J_TYPE)   -> (imm20[0] == 1'b0);             // imm20 holds imm[20:1]
    (opcode == I_TYPE_2) -> (rs1 == 0 && imm12[1:0] == 0);  // absolute, aligned JALR
  }

  constraint legal_delay {
    instr_mem_ready_delay dist { 0 := 40, [1:3] := 40, [4:16] := 20 };
    data_mem_ready_delay  dist { 0 := 40, [1:3] := 40, [4:16] := 20 };
    instr_mem_ready_delay inside {[0:16]};
    data_mem_ready_delay  inside {[0:16]};
  }

  function void post_randomize ();
    case (opcode)
      R_TYPE                       : instruction = {funct7, rs2, rs1, funct3, rd, opcode};
      I_TYPE_0, I_TYPE_1, I_TYPE_2 : instruction = {imm12, rs1, funct3, rd, opcode};
      S_TYPE                       : instruction = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], opcode};
      B_TYPE                       : instruction = {imm12[11], imm12[9:4], rs2, rs1, funct3, imm12[3:0], imm12[10], opcode};
      U_TYPE_0, U_TYPE_1           : instruction = {imm20, rd, opcode};
      J_TYPE                       : instruction = {imm20[19], imm20[9:0], imm20[10], imm20[18:11], rd, opcode};
      default                      : instruction = 32'h13;
    endcase
    instr_mem_rd_data = instruction;
    if (verbose) display();
  endfunction

  virtual function void display();
    $display("[INFO] @ %0t: Tr: %-8s 0x%08h ird=%0d drd=%0d", $time, opcode.name(),
             instr_mem_rd_data, instr_mem_ready_delay, data_mem_ready_delay);
  endfunction

  // [T3] full copy
  virtual function yarp_transaction copy ();
    copy = new();
    copy.instr_mem_ready_delay = instr_mem_ready_delay;
    copy.data_mem_ready_delay  = data_mem_ready_delay;
    copy.instr_mem_req     = instr_mem_req;     copy.instr_mem_addr   = instr_mem_addr;
    copy.instr_mem_ready   = instr_mem_ready;   copy.instr_mem_rd_data = instr_mem_rd_data;
    copy.data_mem_req      = data_mem_req;      copy.data_mem_addr    = data_mem_addr;
    copy.data_mem_byte_en  = data_mem_byte_en;  copy.data_mem_wr      = data_mem_wr;
    copy.data_mem_wr_data  = data_mem_wr_data;  copy.data_mem_ready   = data_mem_ready;
    copy.data_mem_rd_data  = data_mem_rd_data;  copy.arch_reg         = arch_reg;
    copy.instruction = instruction; copy.opcode = opcode; copy.rd = rd; copy.funct3 = funct3;
    copy.rs1 = rs1; copy.rs2 = rs2; copy.funct7 = funct7; copy.imm12 = imm12; copy.imm20 = imm20;
    return copy;
  endfunction

endclass
