// LEVEL 6 - A whole (tiny) CPU in one cycle: fetch -> decode -> execute -> write back.
// Supports: addi, add, sub, and, or, xor, lw, sw, beq, bne.  (RV32I encodings)
// Reuses Level 3 (alu) and Level 4 (regfile).
module tiny_cpu import alu_pkg::*; (
  input  logic        clk, rst,
  output logic [31:0] pc
);
  logic [31:0] imem [64];                 // program (loaded by the testbench)
  logic [31:0] dmem [64];                 // data memory (word addressed: addr[7:2])

  // ---------------- FETCH
  wire  [31:0] instr  = imem[pc[7:2]];
  // ---------------- DECODE: slice the fields out of the 32-bit word
  wire  [6:0]  opcode = instr[6:0];
  wire  [4:0]  rd     = instr[11:7];
  wire  [2:0]  funct3 = instr[14:12];
  wire  [4:0]  rs1    = instr[19:15];
  wire  [4:0]  rs2    = instr[24:20];
  wire  [6:0]  funct7 = instr[31:25];    // ONLY meaningful for R-type (bug B01!)
  // immediates: ALWAYS sign-extended from bit 31 (bug B02!)
  wire  [31:0] imm_i  = {{20{instr[31]}}, instr[31:20]};
  wire  [31:0] imm_s  = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  wire  [31:0] imm_b  = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

  localparam OP_IMM = 7'b0010011, OP_REG = 7'b0110011, LOAD = 7'b0000011,
             STORE  = 7'b0100011, BRANCH = 7'b1100011;

  // ---------------- REGISTER READ
  logic [31:0] a, b, wb_data; logic we;
  regfile rf (.clk, .ra1(rs1), .ra2(rs2), .rd1(a), .rd2(b), .we, .wa(rd), .wd(wb_data));

  // ---------------- EXECUTE
  alu_op_t op; logic [31:0] alu_b, y;
  always_comb begin
    op    = ADD;
    alu_b = imm_i;
    case (opcode)
      OP_REG: begin
        alu_b = b;
        case (funct3)
          3'b000: op = (funct7 == 7'b0100000) ? SUB : ADD;
          3'b111: op = AND;
          3'b110: op = OR;
          3'b100: op = XOR;
          default: op = ADD;
        endcase
      end
      STORE:  alu_b = imm_s;              // address = rs1 + imm_s
      BRANCH: begin alu_b = b; op = SUB; end  // compare by subtracting
      default: ;                          // addi, lw: rs1 + imm_i
    endcase
  end
  alu u_alu (.op, .a, .b(alu_b), .y);

  // ---------------- MEMORY + WRITE BACK
  wire is_load = (opcode == LOAD);
  assign wb_data = is_load ? dmem[y[7:2]] : y;
  assign we      = (opcode == OP_IMM) || (opcode == OP_REG) || is_load;

  // ---------------- NEXT PC
  wire take = (opcode == BRANCH) && ((funct3 == 3'b000) ? (y == 0) : (y != 0)); // beq / bne
  always_ff @(posedge clk) begin
    if (rst) pc <= 0;
    else     pc <= take ? pc + imm_b : pc + 4;
    if (!rst && opcode == STORE) dmem[y[7:2]] <= b;
  end
endmodule

module tb_L06;
  logic clk = 0, rst = 1; logic [31:0] pc;
  tiny_cpu dut (.*);
  always #5 clk = ~clk;
  // Program: sum = 1 + 2 + ... + 10, store it, load it back.
  initial begin
    foreach (dut.imem[i]) dut.imem[i] = 32'h00000013;    // fill with nop (addi x0,x0,0)
    dut.imem[0] = 32'h00000093;  // addi x1, x0, 0      sum = 0
    dut.imem[1] = 32'h00100113;  // addi x2, x0, 1      i   = 1
    dut.imem[2] = 32'h00B00193;  // addi x3, x0, 11     limit
    dut.imem[3] = 32'h002080B3;  // add  x1, x1, x2     loop: sum += i
    dut.imem[4] = 32'h00110113;  // addi x2, x2, 1      i++
    dut.imem[5] = 32'hFE311CE3;  // bne  x2, x3, -8     back to loop while i != 11
    dut.imem[6] = 32'h04102023;  // sw   x1, 64(x0)
    dut.imem[7] = 32'h04002203;  // lw   x4, 64(x0)
    dut.imem[8] = 32'hFFF00293;  // addi x5, x0, -1     sign-extension check
    repeat (2) @(posedge clk); @(negedge clk); rst = 0;   // change inputs away from the clock edge
    repeat (60) @(posedge clk);
    if (dut.rf.r[1] == 55 && dut.rf.r[4] == 55 && dut.rf.r[5] == 32'hFFFF_FFFF)
      $display("L06 tiny_cpu: PASS (x1 = sum 1..10 = %0d, x4 loaded back = %0d, x5 = %h)", dut.rf.r[1], dut.rf.r[4], dut.rf.r[5]);
    else
      $display("L06 tiny_cpu: FAIL x1=%0d x4=%0d x5=%h", dut.rf.r[1], dut.rf.r[4], dut.rf.r[5]);
    $finish;
  end
endmodule
