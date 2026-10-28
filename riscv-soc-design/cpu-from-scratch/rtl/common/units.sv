// units.sv -- the functional units shared by the single-cycle and pipelined cores
//
// Each module here has a counterpart in Wally:
//   regfile     -> cvw/src/ieu/regfile.sv
//   extend      -> cvw/src/ieu/extend.sv
//   alu         -> cvw/src/ieu/alu.sv        (Wally's also handles RV64 and bitmanip)
//   comparator  -> cvw/src/ieu/comparator.sv
//   decoder     -> the main decoder inside cvw/src/ieu/controller.sv
//   subwordwrite/subwordread -> cvw/src/lsu/subwordwrite.sv, subwordread.sv

// ---------------------------------------------------------------------------
// Register file: 31 x 32-bit registers, x0 hardwired to 0.
// Two combinational read ports, one write port.
// Writes happen on the FALLING edge (same trick as Wally): an instruction in
// Writeback writes in the first half of the cycle, so an instruction in Decode
// can read the new value in the second half. That removes one forwarding path.
// ---------------------------------------------------------------------------
// NEGEDGE = 0 for the single-cycle core: there, the instruction that writes a
// register is also still reading its sources for the rest of the cycle, so a
// mid-cycle write would corrupt e.g. "jalr ra, 0(ra)". The pipelined core uses
// NEGEDGE = 1, because the writer (in W) and the reader (in D) are different
// instructions.
module regfile #(parameter bit NEGEDGE = 1) (
  input  logic        clk, reset,
  input  logic        we3,
  input  logic [4:0]  a1, a2, a3,
  input  logic [31:0] wd3,
  output logic [31:0] rd1, rd2
);
  logic [31:0] rf[31:1];

  if (NEGEDGE) begin : wneg
    always_ff @(negedge clk)
      if (reset) for (int i = 1; i < 32; i++) rf[i] <= '0;
      else if (we3 & (a3 != 5'd0)) rf[a3] <= wd3;
  end else begin : wpos
    always_ff @(posedge clk)
      if (reset) for (int i = 1; i < 32; i++) rf[i] <= '0;
      else if (we3 & (a3 != 5'd0)) rf[a3] <= wd3;
  end

  assign rd1 = (a1 != 5'd0) ? rf[a1] : '0;
  assign rd2 = (a2 != 5'd0) ? rf[a2] : '0;
endmodule

// ---------------------------------------------------------------------------
// Immediate extension. RISC-V scatters immediate bits so that the sign bit is
// always Instr[31] and most bits sit in the same place across formats; that
// keeps this mux small.
//   ImmSrc: 000 I, 001 S, 010 B, 011 J, 100 U
// ---------------------------------------------------------------------------
module extend (
  input  logic [31:7] Instr,
  input  logic [2:0]  ImmSrc,
  output logic [31:0] ImmExt
);
  always_comb
    case (ImmSrc)
      3'b000:  ImmExt = {{20{Instr[31]}}, Instr[31:20]};                                // I
      3'b001:  ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};                   // S
      3'b010:  ImmExt = {{20{Instr[31]}}, Instr[7], Instr[30:25], Instr[11:8], 1'b0};   // B
      3'b011:  ImmExt = {{12{Instr[31]}}, Instr[19:12], Instr[20], Instr[30:21], 1'b0}; // J
      3'b100:  ImmExt = {Instr[31:12], 12'b0};                                          // U
      default: ImmExt = 'x;
    endcase
endmodule

// ---------------------------------------------------------------------------
// ALU. ALUSelect is simply funct3 (Wally does the same), plus SubArith which
// turns add into sub and srl into sra. Sum is also exported as the address /
// branch-target adder output (Wally calls it IEUAdr).
// ---------------------------------------------------------------------------
module alu (
  input  logic [31:0] A, B,
  input  logic [2:0]  ALUSelect,
  input  logic        SubArith,
  output logic [31:0] ALUResult,
  output logic [31:0] Sum
);
  logic [31:0] CondInvB;
  logic        Overflow, Neg, LT, LTU;

  assign CondInvB = SubArith ? ~B : B;
  assign Sum      = A + CondInvB + {31'b0, SubArith};      // A - B = A + ~B + 1

  // slt/sltu need a subtraction even though SubArith is 0 for them, so compute
  // the comparisons directly; this is clearer than reusing Sum.
  assign LT  = $signed(A) < $signed(B);
  assign LTU = A < B;

  always_comb
    case (ALUSelect)
      3'b000:  ALUResult = Sum;                                              // add, sub
      3'b001:  ALUResult = A << B[4:0];                                      // sll
      3'b010:  ALUResult = {31'b0, LT};                                      // slt
      3'b011:  ALUResult = {31'b0, LTU};                                     // sltu
      3'b100:  ALUResult = A ^ B;                                            // xor
      3'b101:  ALUResult = SubArith ? $unsigned($signed(A) >>> B[4:0])       // sra
                                    : A >> B[4:0];                           // srl
`ifdef BUG_OR_PLUS
      3'b110:  ALUResult = A + B;                                            // BUG (book 5.11.7): or became +
`else
      3'b110:  ALUResult = A | B;                                            // or
`endif
      3'b111:  ALUResult = A & B;                                            // and
      default: ALUResult = 'x;
    endcase
endmodule

// ---------------------------------------------------------------------------
// Branch comparator: compares rs1 and rs2 (NOT the ALU operands, because the
// ALU is busy computing PC + offset for the branch target).
// funct3: 000 beq, 001 bne, 100 blt, 101 bge, 110 bltu, 111 bgeu
// bit 0 inverts the result, bit 2 picks lt vs eq, bit 1 picks unsigned.
// ---------------------------------------------------------------------------
module comparator (
  input  logic [31:0] a, b,
  input  logic [2:0]  Funct3,
  output logic        BranchTaken
);
  logic Flag;
  always_comb
    if (~Funct3[2])     Flag = (a == b);
    else if (Funct3[1]) Flag = (a < b);
    else                Flag = ($signed(a) < $signed(b));
  assign BranchTaken = Flag ^ Funct3[0];
endmodule

// ---------------------------------------------------------------------------
// Main decoder: instruction -> control signals. Pure combinational.
// The single-cycle core uses these directly; the pipeline carries them down
// the pipe in registers (Wally's controller does exactly that).
// ---------------------------------------------------------------------------
module decoder (
  input  logic [31:0] Instr,
  output logic        RegWrite,
  output logic [2:0]  ImmSrc,
  output logic        ALUSrcA,       // 0: rs1,  1: PC
  output logic        ALUSrcB,       // 0: rs2,  1: immediate
  output logic [2:0]  ALUSelect,
  output logic        SubArith,
  output logic        ALUResultSrc,  // 0: ALU result, 1: alternate result (imm for lui, PC+4 for jumps)
  output logic        MemRead, MemWrite,
  output logic        Branch, Jump,
  output logic        Illegal
);
  logic [6:0] Op;
  logic [2:0] Funct3;
  logic       Funct7b5;

  assign Op       = Instr[6:0];
  assign Funct3   = Instr[14:12];
  assign Funct7b5 = Instr[30];

  always_comb begin
    // defaults: a harmless no-op
    RegWrite = 0; ImmSrc = 3'b000; ALUSrcA = 0; ALUSrcB = 0;
    ALUSelect = 3'b000; SubArith = 0; ALUResultSrc = 0;
    MemRead = 0; MemWrite = 0; Branch = 0; Jump = 0; Illegal = 0;
    case (Op)
      7'b0110011: begin // R-type: add sub sll slt sltu xor srl sra or and
        RegWrite = 1; ALUSelect = Funct3;
        SubArith = Funct7b5;
        // only add/sub and srl/sra may set funct7 bit 5; everything else must be 0
        Illegal  = (Instr[31:25] != 7'b0) & ~(Funct7b5 & (Funct3 == 3'b000 | Funct3 == 3'b101) & (Instr[31] == 0) & (Instr[29:25] == 0));
      end
      7'b0010011: begin // I-type ALU: addi slti sltiu xori ori andi slli srli srai
        RegWrite = 1; ImmSrc = 3'b000; ALUSrcB = 1; ALUSelect = Funct3;
        // Only srai uses bit 30 as an opcode bit. For addi etc. bit 30 is part
        // of the immediate, so it must NOT turn the add into a subtract.
        SubArith = (Funct3 == 3'b101) & Funct7b5;
      end
      7'b0000011: begin // loads
        RegWrite = 1; ImmSrc = 3'b000; ALUSrcB = 1; MemRead = 1;
        Illegal  = (Funct3 == 3'b011) | (Funct3 == 3'b110) | (Funct3 == 3'b111);
      end
      7'b0100011: begin // stores
        ImmSrc = 3'b001; ALUSrcB = 1; MemWrite = 1;
        Illegal = Funct3[2] | (Funct3[1:0] == 2'b11);
      end
      7'b1100011: begin // branches: ALU computes PC + imm, comparator decides
        ImmSrc = 3'b010; ALUSrcA = 1; ALUSrcB = 1; Branch = 1;
        Illegal = (Funct3 == 3'b010) | (Funct3 == 3'b011);
      end
      7'b1101111: begin // jal: target = PC + imm, rd = PC + 4
        RegWrite = 1; ImmSrc = 3'b011; ALUSrcA = 1; ALUSrcB = 1; Jump = 1; ALUResultSrc = 1;
      end
      7'b1100111: begin // jalr: target = (rs1 + imm) & ~1, rd = PC + 4
        RegWrite = 1; ImmSrc = 3'b000; ALUSrcB = 1; Jump = 1; ALUResultSrc = 1;
        Illegal = (Funct3 != 3'b000);
      end
      7'b0110111: begin // lui: rd = imm
        RegWrite = 1; ImmSrc = 3'b100; ALUResultSrc = 1;
      end
      7'b0010111: begin // auipc: rd = PC + imm
        RegWrite = 1; ImmSrc = 3'b100; ALUSrcA = 1; ALUSrcB = 1;
      end
      7'b0001111: ;      // fence: no-op on a core with no caches or reordering
      default: Illegal = 1;
    endcase
  end
endmodule

// ---------------------------------------------------------------------------
// LSU helpers. Memory is 32 bits wide; byte and halfword stores use a byte
// mask, and loads pick the right bytes out of the word and extend them.
// funct3[1:0] = size (00 byte, 01 half, 10 word); funct3[2] = unsigned load.
// Misaligned accesses are not supported (Wally handles them in lsu/align.sv).
// ---------------------------------------------------------------------------
module subwordwrite (
  input  logic [31:0] WriteData,
  input  logic [1:0]  Size,
  input  logic [1:0]  Offset,
  output logic [31:0] WriteDataAligned,
  output logic [3:0]  ByteMask
);
  always_comb
    case (Size)
      2'b00: begin WriteDataAligned = {4{WriteData[7:0]}};  ByteMask = 4'b0001 << Offset;                  end
      2'b01: begin WriteDataAligned = {2{WriteData[15:0]}}; ByteMask = Offset[1] ? 4'b1100 : 4'b0011;     end
      default: begin WriteDataAligned = WriteData;          ByteMask = 4'b1111;                            end
    endcase
endmodule

module subwordread (
  input  logic [31:0] ReadDataWord,
  input  logic [2:0]  Funct3,
  input  logic [1:0]  Offset,
  output logic [31:0] ReadData
);
  logic [7:0]  Byte;
  logic [15:0] Half;
  assign Byte = ReadDataWord[8*Offset +: 8];
  assign Half = Offset[1] ? ReadDataWord[31:16] : ReadDataWord[15:0];
  always_comb
    case (Funct3)
      3'b000:  ReadData = {{24{Byte[7]}},  Byte};  // lb
      3'b001:  ReadData = {{16{Half[15]}}, Half};  // lh
      3'b100:  ReadData = {24'b0, Byte};           // lbu
      3'b101:  ReadData = {16'b0, Half};           // lhu
      default: ReadData = ReadDataWord;            // lw
    endcase
endmodule
