// --------------------------------------------------------
// Copyright (C) quicksilicon.io - All Rights Reserved
//
// Unauthorized copying of this file, via any medium is
// strictly prohibited
// Proprietary and confidential
// --------------------------------------------------------

// --------------------------------------------------------
// YARP - Driver
// --------------------------------------------------------

class yarp_driver;

  mailbox #(yarp_transaction)  gen2drv;
  virtual yarp_interface       vif;

  function new (mailbox #(yarp_transaction) gen2drv, virtual yarp_interface vif);
    $display("[INFO] @ %0t: Creating the yarp_driver", $time);
    this.gen2drv = gen2drv;
    this.vif = vif;
  endfunction

  virtual task reset_seq ();
    // Drive reset at the beginning and for 3 cycles
    vif.cb.reset_n <= 1'b0;
    repeat (3) @vif.cb;
    vif.cb.reset_n <= 1'b1;
    @vif.cb;
  endtask

  task wait_for_instr_mem_req ();
    // Wait for the instruction memory request
    $display("[INFO] @ %0t: [YARP Driver] Waiting for instruction memory request", $time);
    forever begin
      if (vif.cb.instr_mem_req) begin
        break;
      end
      // Wait for the clocking block
      @vif.cb;
    end
  endtask

  task process_instr_mem_transaction (yarp_transaction tr);
    int instr_mem_ready_delay;

    instr_mem_ready_delay = tr.instr_mem_ready_delay;
    // Process the instruction memory transaction
    $display("[INFO] @ %0t: [YARP Driver] Processing instruction memory transaction", $time);
    while (instr_mem_ready_delay > 0) begin
      instr_mem_ready_delay--;
      // Wait for the clocking block
      @vif.cb;
    end
    // Drive the instruction memory transaction
    vif.cb.instr_mem_ready <= 1'b1;
    vif.cb.instr_mem_rd_data <= tr.instr_mem_rd_data;
    fork
      begin
        // Wait for the clocking block
        @vif.cb;
        vif.cb.instr_mem_ready <= 1'b0;
        vif.cb.instr_mem_rd_data <= 32'h0;
      end
    join_none
  endtask

  task process_data_mem_transaction (yarp_transaction tr);
    int data_mem_ready_delay;

    data_mem_ready_delay = tr.data_mem_ready_delay;
    @vif.cb;
    // Process the data memory transaction only if the data_mem_req is high
    if (!vif.cb.data_mem_req) begin
      // No data memory request - break from loop
      return;
    end
    $display("[INFO] @ %0t: [YARP Driver] Processing data memory transaction", $time);
    while (data_mem_ready_delay > 0) begin
      // Wait for the clocking block
      @vif.cb;
      data_mem_ready_delay--;
    end
    // Drive the data memory transaction
    vif.cb.data_mem_ready <= 1'b1;
    vif.cb.data_mem_rd_data <= yarp_data_mem_model::read(vif.cb.data_mem_addr, mem_access_size_t'(vif.cb.data_mem_byte_en));
    // Write into the memory model for a store transaction
    if (vif.cb.data_mem_req & vif.cb.data_mem_wr & vif.cb.data_mem_ready) begin
      yarp_data_mem_model::write(vif.cb.data_mem_addr, vif.cb.data_mem_wr_data, mem_access_size_t'(vif.cb.data_mem_byte_en));
    end
    fork
      begin
        // Wait for the clocking block
        @vif.cb;
        vif.cb.data_mem_ready <= 1'b0;
        vif.cb.data_mem_rd_data <= 32'h0;
      end
    join_none
  endtask

  virtual task run ();
    yarp_transaction tr;
    forever begin
      // Get the transaction from the mailbox
      gen2drv.get(tr);
      wait_for_instr_mem_req();
      process_instr_mem_transaction(tr);
      process_data_mem_transaction(tr);
    end
  endtask

endclass
