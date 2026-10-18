// --------------------------------------------------------
// Copyright (C) quicksilicon.io - All Rights Reserved
//
// Unauthorized copying of this file, via any medium is
// strictly prohibited
// Proprietary and confidential
// --------------------------------------------------------

// --------------------------------------------------------
// YARP - Scoreboard
// --------------------------------------------------------

// Define the DPI interface for the scoreboard
import "DPI-C" function void init();
import "DPI-C" function void step(int instruction);
import "DPI-C" function int  compare_instruction_address(int address);
import "DPI-C" function int  compare_data_memory_access(int address, int byte_en, int write, int write_data);
import "DPI-C" function int  compare_architecture_register(int regnum, int value);

class yarp_scoreboard;

  mailbox #(yarp_transaction) mon2sb;
  int unsigned                num_tr;     // [FIX S3] set by the environment
  int unsigned                n_instr;
  bit                         mem_pending;

  // [FIX COV] functional coverage of the compare corners. A signed-compare bug
  // (e.g. |a|<|b|) is invisible unless the operands have DIFFERENT signs or
  // are BOTH negative; an unsigned bug needs an operand with bit 31 set.
  // arch[] = register state BEFORE the current instruction (refreshed after
  // every check), so operand values are known when the instruction arrives.
  bit [31:0]                  arch [32];
  int unsigned                cov [string];
  string                      cov_bins [$] = '{"SLT.aneg_bpos", "SLT.apos_bneg", "SLT.bothneg",
                                               "SLTI.aneg_bpos", "SLTI.apos_bneg", "SLTI.bothneg",
                                               "BLT/BGE.aneg_bpos", "BLT/BGE.apos_bneg", "BLT/BGE.bothneg",
                                               "SLTU.msb", "SLTIU.msb", "BLTU/BGEU.msb",
                                               "LB.neg", "LBU.bit7", "LH.neg", "LHU.bit15"};
  bit [31:0]                  pend_ins;   // the load/store waiting for its data handshake

  // sign/zero-extension bugs only show when the loaded byte/half has its top bit set
  function void sample_load_cov (bit [31:0] ins, bit [31:0] rdata);
    if (ins[6:0] != 7'h03) return;
    case (ins[14:12])
      3'd0: if (rdata[7])  cov["LB.neg"]++;
      3'd4: if (rdata[7])  cov["LBU.bit7"]++;
      3'd1: if (rdata[15]) cov["LH.neg"]++;
      3'd5: if (rdata[15]) cov["LHU.bit15"]++;
      default: ;
    endcase
  endfunction

  function void sample_cov (bit [31:0] ins);
    bit [31:0] a = arch[ins[19:15]];
    bit [31:0] b = (ins[6:0] == 7'h13) ? {{20{ins[31]}}, ins[31:20]} : arch[ins[24:20]];
    string k = "";
    case ({ins[6:0], ins[14:12]})
      {7'h33, 3'd2}: k = "SLT";    {7'h13, 3'd2}: k = "SLTI";
      {7'h33, 3'd3}: k = "SLTU";   {7'h13, 3'd3}: k = "SLTIU";
      {7'h63, 3'd4}, {7'h63, 3'd5}: k = "BLT/BGE";
      {7'h63, 3'd6}, {7'h63, 3'd7}: k = "BLTU/BGEU";
      default: return;
    endcase
    if (ins[6:0] == 7'h33 && ins[31:25] != 0) return;
    if (k inside {"SLTU", "SLTIU", "BLTU/BGEU"}) begin
      if (a[31] || b[31]) cov[{k, ".msb"}]++;
    end else begin
      if (a[31] && !b[31])     cov[{k, ".aneg_bpos"}]++;
      else if (!a[31] && b[31]) cov[{k, ".apos_bneg"}]++;
      else if (a[31] && b[31]) cov[{k, ".bothneg"}]++;
    end
  endfunction

  function void refresh_arch ();
    for (int i = 0; i < 32; i++) arch[i] = `YARP_REGFILE.regfile[i];
  endfunction

  function void report_cov ();
    int holes = 0; string s = "";
    foreach (cov_bins[i]) begin
      s = {s, $sformatf(" %s=%0d", cov_bins[i], cov.exists(cov_bins[i]) ? cov[cov_bins[i]] : 0)};
      if (!cov.exists(cov_bins[i])) holes++;
    end
    $display("[INFO] YARP Scoreboard: compare-corner coverage:%s", s);
    if (holes) $display("[WARN] YARP Scoreboard: %0d coverage HOLE(S): this run could NOT have seen a signed/unsigned compare bug there", holes);
  endfunction

  function new (mailbox #(yarp_transaction) mon2sb);
    $display("[INFO] @ %0t: Creating the yarp_scoreboard", $time);
    this.mon2sb = mon2sb;
    init();
  endfunction

  virtual task run ();   // [MIN-FIX C3] was 'function': mailbox.get() blocks, so it must be a task
    yarp_transaction tr;
    forever begin
      // Wait for the mailbox
      mon2sb.get(tr);
      // Compare the instruction address (PC) with the expected value from the C-model using DPI call
      if (tr.instr_mem_req && tr.instr_mem_ready) begin
        $display("[INFO] @ %0t: YARP Scoreboard: Instruction Memory Address: 0x%h Data: 0x%h", $time, tr.instr_mem_addr, tr.instr_mem_rd_data);
        sample_cov(tr.instr_mem_rd_data);    // [FIX COV] before arch[] is refreshed
        pend_ins = tr.instr_mem_rd_data;
        step(tr.instr_mem_rd_data);
        n_instr++;
        mem_pending = tr.data_mem_req && !tr.data_mem_ready;
        if (compare_instruction_address(tr.instr_mem_addr)==0) begin
          $fatal(1, "[ERROR] @ %0t: YARP Scoreboard: Instruction Address Mismatch", $time);
        end
        if (~tr.data_mem_req) begin
          // Compare the processor state (registers) with the expected value from the C-model using DPI call
          for (int i = 0; i < 32; i++) begin
            if (compare_architecture_register(i, `YARP_REGFILE.regfile[i])==0) begin
              $fatal(1, "[ERROR] @ %0t: YARP Scoreboard: Architecture Register Mismatch", $time);
            end
          end
          refresh_arch();
          $display("[INFO] @ %0t: YARP Scoreboard: Done processing instruction at PC: 0x%h\n", $time, tr.instr_mem_addr);
        end
      end
      // Compare the write data for store instruction with the expected value from the C-model using DPI call
      if (tr.data_mem_req && tr.data_mem_ready) begin
        mem_pending = 0;
        sample_load_cov(pend_ins, tr.data_mem_rd_data);
        $display("[INFO] @ %0t: YARP Scoreboard: Data Memory Address: 0x%h Byte Enable: 0x%h Write: 0x%h  Write Data: 0x%h",
                 $time, tr.data_mem_addr, tr.data_mem_byte_en, tr.data_mem_wr, tr.data_mem_wr_data);
        if (compare_data_memory_access(tr.data_mem_addr, int'(tr.data_mem_byte_en), int'(tr.data_mem_wr), tr.data_mem_wr_data)==0) begin
          $fatal(1, "[ERROR] @ %0t: YARP Scoreboard: Data Memory Access Mismatch", $time);
        end
        // Compare the processor state (registers) with the expected value from the C-model using DPI call
        for (int i = 0; i < 32; i++) begin
          if (compare_architecture_register(i, `YARP_REGFILE.regfile[i])==0) begin
            $fatal(1, "[ERROR] @ %0t: YARP Scoreboard: Architecture Register Mismatch", $time);
          end
        end
        refresh_arch();
        $display("[INFO] @ %0t: YARP Scoreboard: Done processing instruction at PC: 0x%h\n", $time, tr.instr_mem_addr);
      end
    end
  endtask

  function void end_of_test ();
    $display("[INFO] @ %0t: YARP Scoreboard: End of test", $time);
    // [FIX S3] completeness: a hung core or a dropped handshake must not pass
    if (n_instr != num_tr || mem_pending)
      $fatal(1, "[ERROR] @ %0t: YARP Scoreboard: INCOMPLETE, retired %0d of %0d (mem_pending=%0d)",
             $time, n_instr, num_tr, mem_pending);
    report_cov();
    $display("[INFO] @ %0t: YARP Scoreboard: PASS, %0d instructions checked", $time, n_instr);
    // Compare the architecture registers before ending the test
    for (int i = 0; i < 32; i++) begin
      if (compare_architecture_register(i, `YARP_REGFILE.regfile[i])==0) begin
        $fatal(1, "[ERROR] @ %0t: YARP Scoreboard: Architecture Register Mismatch", $time);
      end
    end
  endfunction

endclass
