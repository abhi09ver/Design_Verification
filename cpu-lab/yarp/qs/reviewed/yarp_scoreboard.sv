// --------------------------------------------------------
// YARP - Scoreboard (reviewed)
//   [S1] run() is a task. A function cannot call mailbox.get(), which blocks.
//   [S2] registers come from the monitor's negedge snapshot (tr.arch_reg),
//        not a hierarchical reference, so there is no scheduler race and
//        no `YARP_REGFILE macro.
//   [S3] end_of_test checks COMPLETENESS: instructions retired == num_tr,
//        and no data access left pending. A hung core or a dropped
//        handshake can no longer pass silently.
//   [S4] functional-coverage counters per opcode class plus stall cycles,
//        printed at the end so a weak stimulus mix is visible.
// --------------------------------------------------------
import "DPI-C" function void init();
import "DPI-C" function void step(int instruction);
import "DPI-C" function int  compare_instruction_address(int address);
import "DPI-C" function int  compare_data_memory_access(int address, int byte_en, int write, int write_data);
import "DPI-C" function int  compare_architecture_register(int regnum, int value);

class yarp_scoreboard;

  mailbox #(yarp_transaction) mon2sb;
  int unsigned num_tr, n_instr, n_mem, n_istall, n_dstall;
  bit          mem_pending;
  int unsigned hist [string];

  function new (mailbox #(yarp_transaction) mon2sb, int num_tr);
    this.mon2sb = mon2sb;
    this.num_tr = num_tr;
    init();
  endfunction

  function void check_regs (yarp_transaction tr, string where);
    for (int i = 0; i < 32; i++)
      if (compare_architecture_register(i, tr.arch_reg[i]) == 0)
        $fatal(1, "[SB] @ %0t: register x%0d mismatch (%s, pc 0x%08h)", $time, i, where, tr.instr_mem_addr);
  endfunction

  function string op_class (bit [31:0] ins);
    case (ins[6:0])
      7'h33: return "R";       7'h13: return "I-alu";  7'h03: return "LOAD";
      7'h23: return "STORE";   7'h63: return "BRANCH"; 7'h37: return "LUI";
      7'h17: return "AUIPC";   7'h6f: return "JAL";    7'h67: return "JALR";
      default: return "OTHER";
    endcase
  endfunction

  virtual task run ();                                   // [S1]
    yarp_transaction tr;
    forever begin
      mon2sb.get(tr);
      if (tr.instr_mem_req  && !tr.instr_mem_ready) n_istall++;
      if (tr.data_mem_req   && !tr.data_mem_ready)  n_dstall++;
      if (tr.instr_mem_req && tr.instr_mem_ready) begin
        step(tr.instr_mem_rd_data);
        n_instr++;
        hist[op_class(tr.instr_mem_rd_data)]++;
        if (compare_instruction_address(tr.instr_mem_addr) == 0)
          $fatal(1, "[SB] @ %0t: PC mismatch at 0x%08h", $time, tr.instr_mem_addr);
        if (!tr.data_mem_req) check_regs(tr, "ALU/branch/jump");
        else                  mem_pending = 1;
      end
      if (tr.data_mem_req && tr.data_mem_ready) begin
        n_mem++;
        if (compare_data_memory_access(tr.data_mem_addr, int'(tr.data_mem_byte_en),
                                       int'(tr.data_mem_wr), tr.data_mem_wr_data) == 0)
          $fatal(1, "[SB] @ %0t: data access mismatch at 0x%08h", $time, tr.data_mem_addr);
        check_regs(tr, "load/store");                  // [S2]
        mem_pending = 0;
      end
    end
  endtask

  function void end_of_test (yarp_transaction last);
    string s = "";
    foreach (hist[k]) s = {s, $sformatf("%s=%0d ", k, hist[k])};
    check_regs(last, "end of test");
    if (n_instr != num_tr || mem_pending)              // [S3]
      $fatal(1, "[SB] INCOMPLETE: retired %0d of %0d instructions (mem_pending=%0d)", n_instr, num_tr, mem_pending);
    $display("[SB] PASS: %0d instructions, %0d data accesses (%0d misaligned), stall cycles instr=%0d data=%0d",
             n_instr, n_mem, yarp_data_mem_model::n_misaligned, n_istall, n_dstall);
    $display("[SB] mix: %s", s);
  endfunction

endclass
