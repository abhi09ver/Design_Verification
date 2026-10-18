// --------------------------------------------------------
// Copyright (C) quicksilicon.io - All Rights Reserved
//
// Unauthorized copying of this file, via any medium is
// strictly prohibited
// Proprietary and confidential
// --------------------------------------------------------

// --------------------------------------------------------
// YARP - Monitor
// --------------------------------------------------------

class yarp_monitor;

  mailbox #(yarp_transaction) mon2sb;
  virtual yarp_interface      vif;
  yarp_transaction            tr;

  function new (mailbox #(yarp_transaction) mon2sb, virtual yarp_interface vif);
    $display("[INFO] @ %0t: Creating the yarp_monitor", $time);
    this.mon2sb = mon2sb;
    this.vif = vif;
    tr = new();
  endfunction

  virtual task run ();
    forever begin
      // Wait for the clocking block
      @vif.cb;
      // Get the transaction from the interface
      // Instruction memory
      tr.instr_mem_req     = vif.cb.instr_mem_req;
      tr.instr_mem_addr    = vif.cb.instr_mem_addr;
      tr.instr_mem_ready   = vif.cb.instr_mem_ready;
      tr.instr_mem_rd_data = vif.cb.instr_mem_rd_data;
      // Data memory
      tr.data_mem_req      = vif.cb.data_mem_req;
      tr.data_mem_addr     = vif.cb.data_mem_addr;
      tr.data_mem_byte_en  = vif.cb.data_mem_byte_en;
      tr.data_mem_wr       = vif.cb.data_mem_wr;
      tr.data_mem_wr_data  = vif.cb.data_mem_wr_data;
      tr.data_mem_ready    = vif.cb.data_mem_ready;
      tr.data_mem_rd_data  = vif.cb.data_mem_rd_data;
      // Put it in the mailbox
      mon2sb.put(tr.copy());
    end
  endtask

  virtual task end_of_test ();
    // Wait for 32 cycles and check if mailbox is empty
    for (int i = 0; i < 32; i++) begin
      @vif.cb;
    end
  endtask

endclass
