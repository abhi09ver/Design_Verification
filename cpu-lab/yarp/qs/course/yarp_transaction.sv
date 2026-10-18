// --------------------------------------------------------
// YARP - Transaction
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

  // Instruction fields
  bit[31:0]             instruction;
  rand  riscv_op_t      opcode;
  rand  bit[4:0]        rd;
  rand  bit[2:0]        funct3;
  rand  bit[4:0]        rs1;
  rand  bit[4:0]        rs2;
  rand  bit[6:0]        funct7;
  rand  bit[11:0]       imm12;
  rand  bit[19:0]       imm20;

  virtual function void display();
    $display("[INFO] @ %0t: Tr: instr_mem_rd_data: 0x%h instr_mem_ready_delay: %2d data_mem_ready_delay: %2d",
              $time, instr_mem_rd_data, instr_mem_ready_delay, data_mem_ready_delay);
  endfunction

  // Ensure opcode is randomized to a legal value
  constraint legal_opcode {
    opcode inside {R_TYPE, I_TYPE_0, I_TYPE_1, I_TYPE_2, S_TYPE, B_TYPE, U_TYPE_0, U_TYPE_1, J_TYPE};
  }

  // Randomize funct3 on the basis of the opcode field
  constraint legal_funct3 {
    if (opcode == R_TYPE) {
      funct3 inside {ADD, SLL, SLT, SLTU, XOR, SRX, OR, AND};
    } else if (opcode == I_TYPE_0) {
      funct3 inside {LB, LBU, LH, LHU, LW};
    } else if (opcode == I_TYPE_1) {
      funct3 inside {ADDI, SLLI, SLTI, SLTIU, XORI, SRXI, ORI, ANDI};
    } else if (opcode == I_TYPE_2) {
      funct3 == 0;
    } else if (opcode == S_TYPE) {
      funct3 inside {SB, SH, SW};
    } else if (opcode == B_TYPE) {
      funct3 inside {BEQ, BNE, BLT, BGE, BLTU, BGEU};
    }
  }

  // For R_TYPE, funct7 can take two separate values for ADD/SUB and SRL/SRA
  constraint legal_funct7 {
    if (opcode == R_TYPE) {
      if ((funct3 == ADD) || (funct3 == SRX)) {
        funct7 inside {7'h0, 7'h20};
      } else {
        funct7 == 7'h0;
      }
    }
  }

  // Constraint the immediate field for SLLI, SRLI and SRAI
  constraint legal_imm12 {
    if (opcode == I_TYPE_1) {
      if (funct3 == SLLI) {
        imm12[11:5] == 7'h0;
      } else if (funct3 == SRXI) {
        imm12[11:5] inside {7'h0, 7'h20};
      }
    }
    if (opcode == I_TYPE_0) {
      if (funct3 == LW) {
        imm12[1:0] == 2'h0;
      } else if ((funct3 == LH) || (funct3 == LHU)) {
        imm12[0] == 1'b0;
      }
    }
    if (opcode == S_TYPE) {
      if (funct3 == SW) {
        imm12[1:0] == 2'h0;
      } else if (funct3 == SH) {
        imm12[0] == 1'b0;
      }
    }
  }

  // Constraint the instr_mem_ready_delay and data_mem_ready_delay
  constraint legal_delay {
    instr_mem_ready_delay inside {[0:16]};
    data_mem_ready_delay inside {[0:16]};
  }

  function void post_randomize ();
    string      gen_instr_msg;
    r_type_t    r_type_funct3;
    i_type0_t   i_type0_funct3;
    i_type1_t   i_type1_funct3;
    s_type_t    s_type_funct3;
    b_type_t    b_type_funct3;
    u_type_t    u_type_funct3;

    r_type_funct3 = r_type_t'(funct3);
    i_type0_funct3 = i_type0_t'(funct3);
    i_type1_funct3 = i_type1_t'(funct3);
    s_type_funct3 = s_type_t'(funct3);
    b_type_funct3 = b_type_t'(funct3);
    u_type_funct3 = u_type_t'(opcode);

    /* verilator lint_off CASEINCOMPLETE */
    // Construct the 32b instruction depending on the opcode field
    case (opcode)
      R_TYPE : begin
        instruction = {funct7, rs2, rs1, funct3, rd, opcode};
        gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\tX%0d\n", $time, opcode.name(), instruction, r_type_funct3.name(), rd, rs1, rs2);
        if ((funct3 == ADD) && (funct7 == 7'h20)) begin
          gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\tX%0d\n", $time, opcode.name(), instruction, "SUB", rd, rs1, rs2);
        end else if ((funct3 == SRX) && (funct7 == 7'h20)) begin
          gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\tX%0d\n", $time, opcode.name(), instruction, "SRA", rd, rs1, rs2);
        end else if (funct3 == SRX) begin
          gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\tX%0d\n", $time, opcode.name(), instruction, "SRL", rd, rs1, rs2);
        end
      end
      I_TYPE_0 : begin
        instruction = {imm12, rs1, funct3, rd, opcode};
        gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\t%0d\n", $time, opcode.name(), instruction, i_type0_funct3.name(), rd, rs1, imm12);
      end
      I_TYPE_1 : begin
        instruction = {imm12, rs1, funct3, rd, opcode};
        gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\t%0d\n", $time, opcode.name(), instruction, i_type1_funct3.name(), rd, rs1, imm12);
        if ((funct3 == SRXI) && (imm12[11:5] == 7'h20)) begin
          gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\t%0d\n", $time, opcode.name(), instruction, "SRAI", rd, rs1, imm12);
        end else if (funct3 == SRXI) begin
          gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\t%0d\n", $time, opcode.name(), instruction, "SRLI", rd, rs1, imm12);
        end
      end
      I_TYPE_2 : begin
        instruction = {imm12, rs1, funct3, rd, opcode};
        gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\t%0d\n", $time, opcode.name(), instruction, "JALR", rd, rs1, imm12);
      end
      S_TYPE : begin
        instruction = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], opcode};
        gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\t+%0d\n", $time, opcode.name(), instruction, s_type_funct3.name(), rs1, rs2, imm12);
      end
      B_TYPE : begin
        instruction = {imm12[11], imm12[9:4], rs2, rs1, funct3, imm12[3:0], imm12[10], opcode};
        gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\tX%0d,\t+%0d\n", $time, opcode.name(), instruction, b_type_funct3.name(), rs1, rs2, imm12);
      end
      U_TYPE_0,
      U_TYPE_1: begin
        instruction = {imm20, rd, opcode};
        gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\t%0d\n", $time, opcode.name(), instruction, u_type_funct3.name(), rd, imm20);
      end
      J_TYPE : begin
        instruction = {imm20[19], imm20[9:0], imm20[10], imm20[18:11], rd, opcode};
        gen_instr_msg = $sformatf ("[INFO] @ %0t: Tr: Generated\t%8s instruction:\t0x%8x: %5s X%0d,\t%0d\n", $time, opcode.name(), instruction, "JAL", rd, imm20);
      end
    endcase
    /* verilator lint_on CASEINCOMPLETE */
    $display(gen_instr_msg);
    instr_mem_rd_data = instruction;
  endfunction

  virtual function yarp_transaction copy ();
    copy = new();

    // Instruction memory interface
    copy.instr_mem_req          = this.instr_mem_req;
    copy.instr_mem_addr         = this.instr_mem_addr;
    copy.instr_mem_ready        = this.instr_mem_ready;
    copy.instr_mem_rd_data      = this.instr_mem_rd_data;
    copy.instr_mem_ready_delay  = this.instr_mem_ready_delay;
    // Data memory interface
    copy.data_mem_req           = this.data_mem_req;
    copy.data_mem_addr          = this.data_mem_addr;
    copy.data_mem_byte_en       = this.data_mem_byte_en;
    copy.data_mem_wr            = this.data_mem_wr;
    copy.data_mem_wr_data       = this.data_mem_wr_data;
    copy.data_mem_ready         = this.data_mem_ready;
    copy.data_mem_rd_data       = this.data_mem_rd_data;
    copy.data_mem_ready_delay   = this.data_mem_ready_delay;

    return copy;
  endfunction

endclass
