// LEVEL 11 - A tiny OUT-OF-ORDER CPU. Levels 8 + 9 + 10 glued together.
//   1 instruction dispatched per cycle, in order      (front of house)
//   4-entry reservation station, oldest-ready first   (the cooks' waiting rail)
//   1-cycle ALU (add, addi, sub) and 3-cycle MUL      (the cooks)
//   1 common data bus                                 (the bell: "ticket T is ready")
//   8-entry reorder buffer, 1 commit per cycle        (serve in order)
// Same ideas as your 3-wide core, small enough to read in 15 minutes.
module tiny_ooo (input logic clk, rst);
  // ------------------------------------------------------------------ state
  logic [31:0] imem [32];                       // program; a 0 word means "end"
  logic [31:0] arf  [32];                       // architectural registers (the "real" ones)
  logic        rat_v   [32];  logic [2:0] rat_tag [32];   // rename table (Level 8)
  logic        rob_v [8], rob_done [8];                    // reorder buffer (Level 10)
  logic [4:0]  rob_rd [8];    logic [31:0] rob_val [8], rob_pc [8];
  logic [2:0]  head, tail;    logic [3:0]  count;
  typedef struct packed {
    logic busy, is_mul, is_sub; logic [7:0] age; logic [2:0] dst;
    logic a_rdy; logic [2:0] a_tag; logic [31:0] a;
    logic b_rdy; logic [2:0] b_tag; logic [31:0] b;
  } rs_t;
  rs_t         rs [4];                                     // reservation station (Level 9)
  logic [31:0] pc;            logic [7:0]  age_ctr;
  logic        alu_v;         logic [2:0]  alu_tag;  logic [31:0] alu_res;  // ALU output register
  logic        mv [3];        logic [2:0]  mt [3];   logic [31:0] mr [3];   // 3-stage multiplier

  // ------------------------------------------------------------------ CDB: one result per cycle
  logic cdb_v; logic [2:0] cdb_tag; logic [31:0] cdb_val;
  always_comb begin
    cdb_v = mv[2] || alu_v;
    cdb_tag = mv[2] ? mt[2] : alu_tag;
    cdb_val = mv[2] ? mr[2] : alu_res;
  end

  // ------------------------------------------------------------------ decode the instruction at pc
  wire [31:0] ins   = imem[pc[6:2]];
  wire [6:0]  opc   = ins[6:0];
  wire [4:0]  rd    = ins[11:7], rs1 = ins[19:15], rs2 = ins[24:20];
  wire [31:0] imm   = {{20{ins[31]}}, ins[31:20]};
  wire        is_imm = (opc == 7'b0010011);              // addi
  wire        is_mul = (opc == 7'b0110011) && ins[25];   // funct7 = 0000001
  wire        is_sub = (opc == 7'b0110011) && ins[30];   // funct7 = 0100000

  // where does a source value come from?  register file / finished ROB entry / CDB now / wait
  function automatic void lookup(input logic [4:0] r, output logic rdy, output logic [2:0] tag,
                                 output logic [31:0] val);
    tag = rat_tag[r]; rdy = 1'b1; val = arf[r];
    if (r == 0)                                 val = 0;
    else if (rat_v[r]) begin
      if (rob_done[tag])                        val = rob_val[tag];  // finished, not yet committed
      else if (cdb_v && cdb_tag == tag)         val = cdb_val;       // finishing right now
      else                                      rdy = 1'b0;          // must wait for the bell
    end
  endfunction

  logic a_rdy, b_rdy; logic [2:0] a_tag, b_tag; logic [31:0] a_val, b_val;
  int free_rs, pick;
  logic disp_fire, iss_fire, commit_fire;
  always_comb begin
    lookup(rs1, a_rdy, a_tag, a_val);
    lookup(rs2, b_rdy, b_tag, b_val);
    if (is_imm) begin b_rdy = 1'b1; b_val = imm; end
    free_rs = -1;
    for (int i = 3; i >= 0; i--) if (!rs[i].busy) free_rs = i;
    disp_fire = (ins != 0) && (count < 8) && (free_rs != -1);
    // select: oldest ready entry. An ALU op may not start if a MUL will use the CDB
    // in the same cycle its result appears (structural hazard on the single CDB).
    pick = -1;
    for (int i = 0; i < 4; i++)
      if (rs[i].busy && rs[i].a_rdy && rs[i].b_rdy && (rs[i].is_mul || !mv[1]) &&
          (pick == -1 || rs[i].age < rs[pick].age)) pick = i;
    iss_fire    = (pick != -1);
    commit_fire = rob_v[head] && rob_done[head];
  end

  // ------------------------------------------------------------------ one clock edge
  always_ff @(posedge clk) begin
    if (rst) begin
      pc <= 0; head <= 0; tail <= 0; count <= 0; age_ctr <= 0; alu_v <= 0;
      foreach (rat_v[i]) begin rat_v[i] <= 0; arf[i] <= 0; end
      foreach (rob_v[i]) rob_v[i] <= 0;
      foreach (rs[i])    rs[i].busy <= 0;
      foreach (mv[i])    mv[i] <= 0;
    end else begin
      // 1. WRITEBACK: the CDB marks the ROB entry done and wakes up waiting operands
      if (cdb_v) begin
        rob_done[cdb_tag] <= 1'b1; rob_val[cdb_tag] <= cdb_val;
        for (int i = 0; i < 4; i++) begin
          if (rs[i].busy && !rs[i].a_rdy && rs[i].a_tag == cdb_tag) begin rs[i].a_rdy <= 1; rs[i].a <= cdb_val; end
          if (rs[i].busy && !rs[i].b_rdy && rs[i].b_tag == cdb_tag) begin rs[i].b_rdy <= 1; rs[i].b <= cdb_val; end
        end
      end
      // 2. EXECUTE: ALU result next cycle, MUL result after 3 cycles
      alu_v <= iss_fire && !rs[pick].is_mul;
      mv[0] <= iss_fire &&  rs[pick].is_mul;   mv[1] <= mv[0]; mv[2] <= mv[1];
      mt[1] <= mt[0]; mt[2] <= mt[1];          mr[1] <= mr[0]; mr[2] <= mr[1];
      if (iss_fire) begin
        rs[pick].busy <= 1'b0;
        alu_tag <= rs[pick].dst;  mt[0] <= rs[pick].dst;
        alu_res <= rs[pick].is_sub ? rs[pick].a - rs[pick].b : rs[pick].a + rs[pick].b;
        mr[0]   <= rs[pick].a * rs[pick].b;
      end
      // 3. COMMIT: only the oldest instruction may update the real registers
      if (commit_fire) begin
        if (rob_rd[head] != 0) arf[rob_rd[head]] <= rob_val[head];
        if (rat_v[rob_rd[head]] && rat_tag[rob_rd[head]] == head) rat_v[rob_rd[head]] <= 1'b0;
        rob_v[head] <= 1'b0; head <= head + 1'b1;
      end
      // 4. DISPATCH: rename + ROB slot + RS slot, in program order (written last: wins over 3.)
      if (disp_fire) begin
        rob_v[tail] <= 1; rob_done[tail] <= 0; rob_rd[tail] <= rd; rob_pc[tail] <= pc;
        if (rd != 0) begin rat_v[rd] <= 1'b1; rat_tag[rd] <= tail; end
        rs[free_rs] <= '{busy: 1, is_mul: is_mul, is_sub: is_sub, age: age_ctr, dst: tail,
                         a_rdy: a_rdy, a_tag: a_tag, a: a_val, b_rdy: b_rdy, b_tag: b_tag, b: b_val};
        tail <= tail + 1'b1; pc <= pc + 4; age_ctr <= age_ctr + 1;
      end
      count <= count + disp_fire - commit_fire;
    end
  end
endmodule

module tb_L11;
  logic clk = 0, rst = 1; int cyc = 0, errors = 0;
  tiny_ooo dut (.*);
  always #5 clk = ~clk;
  string asm [8] = '{"addi x1, x0, 5", "addi x2, x0, 6", "mul  x3, x1, x2", "add  x4, x3, x1",
                     "addi x5, x0, 7", "sub  x6, x5, x1", "mul  x3, x6, x6", "add  x7, x3, x4"};
  logic [31:0] prog [8] = '{32'h00500093, 32'h00600113, 32'h022081B3, 32'h00118233,
                            32'h00700293, 32'h40128333, 32'h026301B3, 32'h004183B3};
  int cdb_order[$], commit_order[$];
  // a readable event log, sampled just before each clock edge
  always @(negedge clk) if (!rst) begin
    string s; cyc++; s = "";
    if (dut.disp_fire)   s = {s, $sformatf("  dispatch %-16s -> ticket T%0d", asm[dut.pc/4], dut.tail)};
    if (dut.iss_fire)    s = {s, $sformatf("  start T%0d", dut.rs[dut.pick].dst)};
    if (dut.cdb_v)       begin s = {s, $sformatf("  BELL T%0d=%0d", dut.cdb_tag, dut.cdb_val)}; cdb_order.push_back(dut.rob_pc[dut.cdb_tag]/4); end
    if (dut.commit_fire) begin s = {s, $sformatf("  COMMIT %s", asm[dut.rob_pc[dut.head]/4])}; commit_order.push_back(dut.rob_pc[dut.head]/4); end
    if (s != "") $display("cycle %2d:%s", cyc, s);
  end
  initial begin
    foreach (dut.imem[i]) dut.imem[i] = 0;
    foreach (prog[i]) dut.imem[i] = prog[i];
    repeat (2) @(posedge clk); @(negedge clk); rst = 0;   // change inputs away from the clock edge
    repeat (40) @(posedge clk);
    // golden values: x1=5 x2=6 x3=4 (second mul wins, WAW) x4=35 x5=7 x6=2 x7=39
    if (dut.arf[1] != 5 || dut.arf[2] != 6 || dut.arf[3] != 4 || dut.arf[4] != 35 ||
        dut.arf[5] != 7 || dut.arf[6] != 2 || dut.arf[7] != 39) errors++;
    foreach (commit_order[i]) if (commit_order[i] != i) errors++;
    $display("finished (bell) in order : %p", cdb_order);
    $display("retired (commit) in order: %p", commit_order);
    $display("L11 tiny_ooo: %s (x3=%0d x4=%0d x7=%0d)", errors ? "FAIL" : "PASS", dut.arf[3], dut.arf[4], dut.arf[7]);
    $finish;
  end
endmodule
