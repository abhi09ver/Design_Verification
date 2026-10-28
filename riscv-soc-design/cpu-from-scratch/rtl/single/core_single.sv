// core_single.sv -- Lab 1: single-cycle RV32I core, written from scratch
//
// Every instruction does fetch, decode, execute, memory and writeback in ONE
// clock cycle. Slow (the clock period must cover the whole path) but the
// easiest way to see how an ISA turns into hardware.
//
// Partitioned like Wally's wallypipelinedcore.sv:
//   ifu  : holds the PC and picks the next PC         (cvw/src/ifu/ifu.sv)
//   ieu  : controller + datapath                      (cvw/src/ieu/ieu.sv)
//   lsu  : lines up store data, extracts load data    (cvw/src/lsu/lsu.sv)
//
// Supports all 37 RV32I user instructions except ecall/ebreak/csr
// (those need the privileged unit, Chapter 8). Memories live in the testbench.

module core_single #(parameter logic [31:0] RESET_VECTOR = 32'h8000_0000) (
  input  logic        clk, reset,
  // instruction memory port
  output logic [31:0] PC,
  input  logic [31:0] Instr,
  // data memory port
  output logic        MemWrite,
  output logic [31:0] DataAdr,          // word-aligned byte address
  output logic [31:0] WriteDataAligned,
  output logic [3:0]  ByteMask,
  input  logic [31:0] ReadDataWord,
  // retirement trace (an RVVI-like view for the testbench; see Chapter 5)
  output logic        TraceValid,
  output logic [31:0] TracePC, TraceInstr,
  output logic        TraceRegWrite,
  output logic [4:0]  TraceRd,
  output logic [31:0] TraceResult,
  output logic        TraceMemWrite,
  output logic [31:0] TraceMemAdr, TraceMemData,
  output logic [3:0]  TraceMemMask,
  output logic [31:0] TracePCNext,
  output logic        TraceIllegal
);
  // ---------------- decode ----------------
  logic        RegWrite, ALUSrcA, ALUSrcB, SubArith, ALUResultSrc;
  logic        MemRead, Branch, Jump, Illegal;
  logic [2:0]  ImmSrc, ALUSelect, Funct3;
  logic [4:0]  Rs1, Rs2, Rd;

  decoder dec(.Instr, .RegWrite, .ImmSrc, .ALUSrcA, .ALUSrcB, .ALUSelect, .SubArith,
              .ALUResultSrc, .MemRead, .MemWrite, .Branch, .Jump, .Illegal);

  assign Funct3 = Instr[14:12];
  assign Rs1    = Instr[19:15];
  assign Rs2    = Instr[24:20];
  assign Rd     = Instr[11:7];

  // ---------------- datapath (IEU) ----------------
  logic [31:0] R1, R2, ImmExt, SrcA, SrcB, ALUResult, Sum;
  logic [31:0] PCPlus4, AltResult, IEUResult, IEUAdr, ReadData, Result;
  logic        BranchTaken, PCSrc;

  regfile #(.NEGEDGE(0)) regf(.clk, .reset, .we3(RegWrite), .a1(Rs1), .a2(Rs2), .a3(Rd),
                .wd3(Result), .rd1(R1), .rd2(R2));
  extend     ext(.Instr(Instr[31:7]), .ImmSrc, .ImmExt);

  mux2       srcamux(R1, PC, ALUSrcA, SrcA);
  mux2       srcbmux(R2, ImmExt, ALUSrcB, SrcB);
  alu        alu(.A(SrcA), .B(SrcB), .ALUSelect, .SubArith, .ALUResult, .Sum);
  comparator cmp(.a(R1), .b(R2), .Funct3, .BranchTaken);

  // IEUAdr is the adder output: load/store address, or branch/jump target.
  // jalr must clear bit 0 of its target (Wally: IEUAdrE = {IEUAdrRawE[XLEN-1:1], ... & ~JumpE}).
  assign IEUAdr = {Sum[31:1], Sum[0] & ~Jump};

  assign PCPlus4 = PC + 32'd4;
  mux2       altmux(ImmExt, PCPlus4, Jump, AltResult);           // lui -> imm, jal/jalr -> PC+4
  mux2       ieuresmux(ALUResult, AltResult, ALUResultSrc, IEUResult);

  // ---------------- LSU ----------------
  assign DataAdr = {IEUAdr[31:2], 2'b00};
  subwordwrite sww(.WriteData(R2), .Size(Funct3[1:0]), .Offset(IEUAdr[1:0]),
                   .WriteDataAligned, .ByteMask);
  subwordread  swr(.ReadDataWord, .Funct3, .Offset(IEUAdr[1:0]), .ReadData);

  mux2       resmux(IEUResult, ReadData, MemRead, Result);

  // ---------------- IFU: next PC ----------------
  logic [31:0] PCNext;
  assign PCSrc = Jump | (Branch & BranchTaken);
  mux2       pcmux(PCPlus4, IEUAdr, PCSrc, PCNext);
  flopr #(32, RESET_VECTOR) pcreg(clk, reset, PCNext, PC);

  // ---------------- trace ----------------
  // In a single-cycle core every cycle retires exactly one instruction.
  assign TraceValid    = ~reset;
  assign TracePC       = PC;
  assign TraceInstr    = Instr;
  assign TraceMemWrite = MemWrite;
  assign TraceMemAdr   = DataAdr;
  assign TraceMemData  = WriteDataAligned;
  assign TraceMemMask  = ByteMask;
  assign TraceRegWrite = RegWrite & (Rd != 5'd0);
  assign TraceRd       = Rd;
  assign TraceResult   = Result;
  assign TracePCNext   = PCNext;
  assign TraceIllegal  = Illegal;
endmodule
