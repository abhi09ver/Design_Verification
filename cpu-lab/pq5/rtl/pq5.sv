// =============================================================================
// pq5 : a 5-stage, in-order, single-issue RV32I CPU written for the study guide.
// Inspired by the *architecture* of Chipmunk Logic's "Pequeno" series
// (Fetch -> Decode -> Execute -> Memory -> Writeback, stall + flush, forwarding,
//  load-use interlock, static branch prediction). The code here is original and
// deliberately simple; one module per stage so each guide part maps to one module.
//
//  Pipeline registers (each carries a VALID bit; valid = 0 is a "bubble"):
//     IF/ID  : in pq5_fetch      ID/EX : in pq5_decode
//     EX/MEM : in pq5_execute    MEM/WB: in pq5_mem
//  Control:  stall  (decode -> fetch)     : load-use interlock, hold the front
//            flush  (execute -> fetch,decode): wrong-path instructions become bubbles
// =============================================================================
package pq5_pkg;
  typedef enum logic [3:0] {A_ADD, A_SUB, A_SLL, A_SLT, A_SLTU, A_XOR, A_SRL, A_SRA, A_OR, A_AND} alu_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] instr;
    logic [31:0] pred_npc;      // where fetch went next (its guess)
  } if_id_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc, pred_npc, imm, rs1_val, rs2_val;
    logic [4:0]  rs1, rs2, rd;
    logic        we;            // writes rd
    alu_t        alu;
    logic        a_is_pc, b_is_imm;
    logic        is_load, is_store, is_branch, is_jal, is_jalr, is_lui;
    logic [2:0]  funct3;
  } id_ex_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc, result, store_data;
    logic [4:0]  rd;
    logic        we, is_load, is_store;
    logic [2:0]  funct3;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc, wdata;
    logic [4:0]  rd;
    logic        we;
  } mem_wb_t;
endpackage

// =============================================================================
// PART 4 - FETCH: PC generator + instruction memory + static branch predictor
// =============================================================================
module pq5_fetch import pq5_pkg::*; #(parameter int IMEM_WORDS = 256) (
  input  logic        clk, rst,
  input  logic        stall,                 // from decode (load-use): hold everything
  input  logic        flush,                 // from execute: wrong path!
  input  logic [31:0] redirect_pc,           //   ... restart here
  output if_id_t      if_id
);
  logic [31:0] imem [IMEM_WORDS];
  logic [31:0] pc;
  wire  [31:0] instr = imem[pc[$clog2(IMEM_WORDS)+1:2]];

  // static prediction (needs no history):
  //   jal              -> always taken (target known from the instruction)
  //   branch, offset<0 -> taken      (backward branch = probably a loop)
  //   branch, offset>0 -> not taken  (forward branch = probably an if/else skip)
  //   jalr             -> not predicted (target is in a register; execute fixes it)
  wire [31:0] imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
  wire [31:0] imm_b = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
  logic [31:0] pred_npc;
  always_comb begin
    pred_npc = pc + 4;
    if (instr[6:0] == 7'b1101111)                     pred_npc = pc + imm_j;  // jal
    else if (instr[6:0] == 7'b1100011 && instr[31])   pred_npc = pc + imm_b;  // backward branch
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= 0; if_id.valid <= 1'b0;
    end else if (flush) begin                  // flush wins over stall
      pc <= redirect_pc; if_id.valid <= 1'b0;  // the instruction we were holding is wrong-path
    end else if (!stall) begin
      pc <= pred_npc;
      if_id <= '{valid: 1'b1, pc: pc, instr: instr, pred_npc: pred_npc};
    end                                        // stall: keep pc and if_id exactly as they are
  end
endmodule

// =============================================================================
// PART 6 - REGISTER FILE: 2 read ports (decode), 1 write port (writeback)
// =============================================================================
module pq5_regfile (
  input  logic        clk,
  input  logic [4:0]  ra1, ra2,
  output logic [31:0] rd1, rd2,
  input  logic        we,
  input  logic [4:0]  wa,
  input  logic [31:0] wd
);
  logic [31:0] r [32];
  always_ff @(posedge clk) if (we && wa != 0) r[wa] <= wd;
  // write-through ("internal forwarding"): if writeback writes the register decode
  // is reading in the SAME cycle, hand decode the new value. Without this an
  // instruction exactly 3 behind its producer reads a stale value.
  always_comb begin
    rd1 = (ra1 == 0) ? '0 : (we && wa == ra1) ? wd : r[ra1];
    rd2 = (ra2 == 0) ? '0 : (we && wa == ra2) ? wd : r[ra2];
  end
endmodule

// =============================================================================
// PART 5 - DECODE: fields, immediates, control, register read, load-use interlock
// =============================================================================
module pq5_decode import pq5_pkg::*; (
  input  logic        clk, rst,
  input  logic        flush,
  input  if_id_t      if_id,
  output logic        stall,                  // to fetch
  output logic [4:0]  ra1, ra2,               // to register file
  input  logic [31:0] rd1, rd2,
  output id_ex_t      id_ex
);
  wire [31:0] in   = if_id.instr;
  wire [6:0]  opc  = in[6:0];
  wire [2:0]  f3   = in[14:12];
  wire        f7b5 = in[30];
  localparam OP=7'b0110011, OPI=7'b0010011, LD=7'b0000011, ST=7'b0100011, BR=7'b1100011,
             JAL=7'b1101111, JALR=7'b1100111, LUI=7'b0110111, AUIPC=7'b0010111;

  id_ex_t d;     // what this instruction becomes
  logic use1, use2;
  always_comb begin
    d = '0;
    d.valid  = if_id.valid;
    d.pc     = if_id.pc;   d.pred_npc = if_id.pred_npc;
    d.rs1    = in[19:15];  d.rs2 = in[24:20];  d.rd = in[11:7];
    d.funct3 = f3;
    // immediates: bit 31 is ALWAYS the sign
    unique case (opc)
      ST:          d.imm = {{20{in[31]}}, in[31:25], in[11:7]};
      BR:          d.imm = {{20{in[31]}}, in[7], in[30:25], in[11:8], 1'b0};
      JAL:         d.imm = {{12{in[31]}}, in[19:12], in[20], in[30:21], 1'b0};
      LUI, AUIPC:  d.imm = {in[31:12], 12'b0};
      default:     d.imm = {{20{in[31]}}, in[31:20]};          // I-type
    endcase
    // control
    d.alu = A_ADD;
    case (opc)
      OP:    begin d.we = 1; d.alu = alu_from(f3, f7b5); end
      OPI:   begin d.we = 1; d.b_is_imm = 1; d.alu = alu_from(f3, (f3 == 3'b101) ? f7b5 : 1'b0); end
      LD:    begin d.we = 1; d.b_is_imm = 1; d.is_load = 1; end
      ST:    begin d.b_is_imm = 1; d.is_store = 1; end
      BR:    begin d.is_branch = 1; end
      JAL:   begin d.we = 1; d.is_jal = 1; end
      JALR:  begin d.we = 1; d.is_jalr = 1; d.b_is_imm = 1; end
      LUI:   begin d.we = 1; d.is_lui = 1; end
      AUIPC: begin d.we = 1; d.a_is_pc = 1; d.b_is_imm = 1; end
      default: ;                                  // fence/ecall/ebreak/unknown: harmless no-op
    endcase
    if (d.rd == 0) d.we = 0;                      // x0 is never written
    use1 = !(opc inside {LUI, AUIPC, JAL});
    use2 = (opc inside {OP, ST, BR});
  end

  function automatic alu_t alu_from(input logic [2:0] f3, input logic sub_sra);
    case (f3)
      3'b000: return sub_sra ? A_SUB : A_ADD;
      3'b001: return A_SLL;   3'b010: return A_SLT;   3'b011: return A_SLTU;
      3'b100: return A_XOR;   3'b101: return sub_sra ? A_SRA : A_SRL;
      3'b110: return A_OR;    default: return A_AND;
    endcase
  endfunction

  // register file is read right now; values travel in ID/EX with the instruction
  assign ra1 = d.rs1;
  assign ra2 = d.rs2;

  // LOAD-USE INTERLOCK: the load in EX only gets its data in MEM. An instruction that
  // needs it right now must wait one cycle (one bubble) - forwarding cannot go back in time.
  assign stall = if_id.valid && id_ex.valid && id_ex.is_load && id_ex.we &&
                 ((use1 && id_ex.rd == d.rs1) || (use2 && id_ex.rd == d.rs2));

  always_ff @(posedge clk) begin
    if (rst || flush || stall) id_ex.valid <= 1'b0;   // bubble (flush: wrong path, stall: wait)
    else begin
      id_ex <= d;
      id_ex.rs1_val <= rd1;
      id_ex.rs2_val <= rd2;
    end
  end
endmodule

// =============================================================================
// PART 7 - EXECUTE: forwarding, ALU, branch resolve, mispredict -> flush
// =============================================================================
module pq5_execute import pq5_pkg::*; (
  input  logic        clk, rst,
  input  id_ex_t      id_ex,
  input  ex_mem_t     fwd_mem,               // instruction 1 ahead (now in MEM)
  input  mem_wb_t     fwd_wb,                // instruction 2 ahead (now in WB)
  output logic        flush,
  output logic [31:0] redirect_pc,
  output ex_mem_t     ex_mem
);
  // FORWARDING: take the newest value of rs1/rs2. Nearest producer wins.
  function automatic logic [31:0] fwd(input logic [4:0] r, input logic [31:0] from_rf);
    if (r != 0 && fwd_mem.valid && fwd_mem.we && !fwd_mem.is_load && fwd_mem.rd == r) return fwd_mem.result;
    if (r != 0 && fwd_wb.valid  && fwd_wb.we  && fwd_wb.rd == r)                         return fwd_wb.wdata;
    return from_rf;
  endfunction
  wire [31:0] a_reg = fwd(id_ex.rs1, id_ex.rs1_val);
  wire [31:0] b_reg = fwd(id_ex.rs2, id_ex.rs2_val);
  wire [31:0] a = id_ex.a_is_pc  ? id_ex.pc  : a_reg;
  wire [31:0] b = id_ex.b_is_imm ? id_ex.imm : b_reg;

  logic [31:0] y;
  always_comb begin
    case (id_ex.alu)
      A_ADD:  y = a + b;                 A_SUB:  y = a - b;
      A_SLL:  y = a << b[4:0];           A_SLT:  y = {31'b0, $signed(a) < $signed(b)};
      A_SLTU: y = {31'b0, a < b};        A_XOR:  y = a ^ b;
      A_SRL:  y = a >> b[4:0];           A_SRA:  y = $signed(a) >>> b[4:0];
      A_OR:   y = a | b;                 default: y = a & b;
    endcase
  end

  // BRANCH UNIT: decide the real next PC and compare with what fetch guessed
  logic taken; logic [31:0] target, actual_npc;
  always_comb begin
    case (id_ex.funct3)
      3'b000: taken = (a_reg == b_reg);                    // beq
      3'b001: taken = (a_reg != b_reg);                    // bne
      3'b100: taken = ($signed(a_reg) <  $signed(b_reg));  // blt
      3'b101: taken = ($signed(a_reg) >= $signed(b_reg));  // bge
      3'b110: taken = (a_reg <  b_reg);                    // bltu
      3'b111: taken = (a_reg >= b_reg);                    // bgeu
      default: taken = 1'b0;
    endcase
    taken  = (id_ex.is_branch && taken) || id_ex.is_jal || id_ex.is_jalr;
    target = id_ex.is_jalr ? ((a_reg + id_ex.imm) & ~32'd1) : (id_ex.pc + id_ex.imm);
    actual_npc = taken ? target : id_ex.pc + 4;
  end
  assign flush       = id_ex.valid && (actual_npc != id_ex.pred_npc);   // the guess was wrong
  assign redirect_pc = actual_npc;

  always_ff @(posedge clk) begin
    if (rst) ex_mem.valid <= 1'b0;
    else begin
      ex_mem.valid      <= id_ex.valid;
      ex_mem.pc         <= id_ex.pc;
      ex_mem.result     <= (id_ex.is_jal || id_ex.is_jalr) ? id_ex.pc + 4 :   // link address
                           id_ex.is_lui ? id_ex.imm : y;
      ex_mem.store_data <= b_reg;
      ex_mem.rd         <= id_ex.rd;
      ex_mem.we         <= id_ex.we;
      ex_mem.is_load    <= id_ex.is_load;
      ex_mem.is_store   <= id_ex.is_store;
      ex_mem.funct3     <= id_ex.funct3;
    end
  end
endmodule

// =============================================================================
// PART 8 - MEMORY ACCESS: byte-addressed data memory, lb/lh/lw/lbu/lhu, sb/sh/sw
// =============================================================================
module pq5_mem import pq5_pkg::*; #(parameter int DMEM_WORDS = 1024) (
  input  logic    clk, rst,
  input  ex_mem_t ex_mem,
  output mem_wb_t mem_wb
);
  logic [31:0] dmem [DMEM_WORDS];
  wire  [$clog2(DMEM_WORDS)-1:0] wi = ex_mem.result[$clog2(DMEM_WORDS)+1:2];
  wire  [1:0]  off  = ex_mem.result[1:0];
  wire  [31:0] word = dmem[wi];
  wire  [31:0] sh   = word >> (8 * off);               // bring the wanted byte/half to bit 0
  logic [31:0] load_val;
  always_comb begin
    case (ex_mem.funct3)
      3'b000:  load_val = {{24{sh[7]}},  sh[7:0]};       // lb
      3'b001:  load_val = {{16{sh[15]}}, sh[15:0]};      // lh
      3'b100:  load_val = {24'b0, sh[7:0]};              // lbu
      3'b101:  load_val = {16'b0, sh[15:0]};             // lhu
      default: load_val = word;                          // lw
    endcase
  end
  always_ff @(posedge clk) begin
    if (rst) mem_wb.valid <= 1'b0;
    else begin
      if (ex_mem.valid && ex_mem.is_store) begin
        case (ex_mem.funct3[1:0])
          2'b00:   dmem[wi][8*off +: 8]  <= ex_mem.store_data[7:0];       // sb
          2'b01:   dmem[wi][8*off +: 16] <= ex_mem.store_data[15:0];      // sh (aligned)
          default: dmem[wi]              <= ex_mem.store_data;            // sw
        endcase
      end
      mem_wb.valid <= ex_mem.valid;
      mem_wb.pc    <= ex_mem.pc;
      mem_wb.rd    <= ex_mem.rd;
      mem_wb.we    <= ex_mem.we;
      mem_wb.wdata <= ex_mem.is_load ? load_val : ex_mem.result;
    end
  end
endmodule

// =============================================================================
// TOP - wires the five stages together. PART 9 - WRITEBACK is just the
//       register-file write port fed from MEM/WB.
// =============================================================================
module pq5_core import pq5_pkg::*; (input logic clk, rst);
  if_id_t if_id; id_ex_t id_ex; ex_mem_t ex_mem; mem_wb_t mem_wb;
  logic stall, flush; logic [31:0] redirect_pc;
  logic [4:0] ra1, ra2; logic [31:0] rd1, rd2;

  pq5_fetch   u_fetch (.clk, .rst, .stall, .flush, .redirect_pc, .if_id);
  pq5_decode  u_dec   (.clk, .rst, .flush, .if_id, .stall, .ra1, .ra2, .rd1, .rd2, .id_ex);
  pq5_regfile u_rf    (.clk, .ra1, .ra2, .rd1, .rd2,
                       .we(mem_wb.valid && mem_wb.we), .wa(mem_wb.rd), .wd(mem_wb.wdata));  // WRITEBACK
  pq5_execute u_ex    (.clk, .rst, .id_ex, .fwd_mem(ex_mem), .fwd_wb(mem_wb), .flush, .redirect_pc, .ex_mem);
  pq5_mem     u_mem   (.clk, .rst, .ex_mem, .mem_wb);

  // performance counters (CPI = cycles / retired)
  int unsigned cycles, retired, stall_cycles, flushes;
  always_ff @(posedge clk)
    if (rst) begin cycles <= 0; retired <= 0; stall_cycles <= 0; flushes <= 0; end
    else begin
      cycles <= cycles + 1;
      retired <= retired + mem_wb.valid;
      stall_cycles <= stall_cycles + (stall && !flush);
      flushes <= flushes + flush;
    end
endmodule
