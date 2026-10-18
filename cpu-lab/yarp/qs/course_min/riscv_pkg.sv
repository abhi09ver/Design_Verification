// --------------------------------------------------------
// Copyright (C) quicksilicon.io - All Rights Reserved
//
// Unauthorized copying of this file, via any medium is
// strictly prohibited
// Proprietary and confidential
// --------------------------------------------------------

// --------------------------------------------------------
// RISC-V Package
// --------------------------------------------------------
package riscv_pkg;

  typedef enum logic[6:0] {
    R_TYPE    = 7'h33,
    I_TYPE_0  = 7'h03,
    I_TYPE_1  = 7'h13,
    I_TYPE_2  = 7'h67,
    S_TYPE    = 7'h23,
    B_TYPE    = 7'h63,
    U_TYPE_0  = 7'h37,
    U_TYPE_1  = 7'h17,
    J_TYPE    = 7'h6F
  } riscv_op_t;

  // R Type funct3
  typedef enum logic[2:0] {
    ADD   = 3'h0,
    SLL   = 3'h1,
    SLT   = 3'h2,
    SLTU  = 3'h3,
    XOR   = 3'h4,
    SRX   = 3'h5,
    OR    = 3'h6,
    AND   = 3'h7
  } r_type_t;

  // I Type 0 funct3
  typedef enum logic[2:0] {
    LB    = 3'h0,
    LBU   = 3'h4,
    LH    = 3'h1,
    LHU   = 3'h5,
    LW    = 3'h2
  } i_type0_t;

  // I Type 1 funct3
  typedef enum logic[2:0] {
    ADDI  = 3'h0,
    SLLI  = 3'h1,
    SLTI  = 3'h2,
    SLTIU = 3'h3,
    XORI  = 3'h4,
    SRXI  = 3'h5,
    ORI   = 3'h6,
    ANDI  = 3'h7
  } i_type1_t;

  // I Type 2 funct3
  typedef enum logic[2:0] {
    JALR = 3'h0
  } i_type2_t;

  // S Type funct3
  typedef enum logic[2:0] {
    SB = 3'h0,
    SH = 3'h1,
    SW = 3'h2
  } s_type_t;

  // B Type funct3
  typedef enum logic[2:0] {
    BEQ  = 3'h0,
    BNE  = 3'h1,
    BLT  = 3'h4,
    BGE  = 3'h5,
    BLTU = 3'h6,
    BGEU = 3'h7
  } b_type_t;

  typedef enum logic[6:0] {
    LUI   = U_TYPE_0,
    AUIPC = U_TYPE_1
  } u_type_t;

  // [MIN-FIX C1] used by yarp_data_mem_model but never defined in the package
  typedef enum logic[1:0] {
    BYTE      = 2'b00,
    HALF_WORD = 2'b01,
    WORD      = 2'b11
  } mem_access_size_t;

endpackage
