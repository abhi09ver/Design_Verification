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

  function new (mailbox #(yarp_transaction) mon2sb);
    $display("[INFO] @ %0t: Creating the yarp_scoreboard", $time);
    this.mon2sb = mon2sb;
    init();
  endfunction

  virtual function void run ();
    yarp_transaction tr;
    forever begin
      // Wait for the mailbox
      mon2sb.get(tr);
      // Compare the instruction address (PC) with the expected value from the C-model using DPI call
      if (tr.instr_mem_req && tr.instr_mem_ready) begin
        $display("[INFO] @ %0t: YARP Scoreboard: Instruction Memory Address: 0x%h Data: 0x%h", $time, tr.instr_mem_addr, tr.instr_mem_rd_data);
        step(tr.instr_mem_rd_data);
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
          $display("[INFO] @ %0t: YARP Scoreboard: Done processing instruction at PC: 0x%h\n", $time, tr.instr_mem_addr);
        end
      end
      // Compare the write data for store instruction with the expected value from the C-model using DPI call
      if (tr.data_mem_req && tr.data_mem_ready) begin
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
        $display("[INFO] @ %0t: YARP Scoreboard: Done processing instruction at PC: 0x%h\n", $time, tr.instr_mem_addr);
      end
    end
  endfunction

  function void end_of_test ();
    $display("[INFO] @ %0t: YARP Scoreboard: End of test", $time);
    // Compare the architecture registers before ending the test
    for (int i = 0; i < 32; i++) begin
      if (compare_architecture_register(i, `YARP_REGFILE.regfile[i])==0) begin
        $fatal(1, "[ERROR] @ %0t: YARP Scoreboard: Architecture Register Mismatch", $time);
      end
    end
  endfunction

endclass
