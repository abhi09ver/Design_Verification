// --------------------------------------------------------
// YARP - Monitor (reviewed)
//   [MO1] samples the pins through mon_cb (read-only clocking block)
//   [MO2] samples the architectural registers at the FOLLOWING negedge.
//         The original scoreboard read YARP.u_yarp_regfile.regfile from a
//         class thread woken by @cb. That runs in the same time step as
//         the regfile's NBA update, so old vs new value depends on the
//         simulator's scheduler. Half a cycle later it is always settled.
// --------------------------------------------------------
class yarp_monitor;

  mailbox #(yarp_transaction) mon2sb;
  virtual yarp_interface      vif;

  function new (mailbox #(yarp_transaction) mon2sb, virtual yarp_interface vif);
    this.mon2sb = mon2sb;
    this.vif    = vif;
  endfunction

  virtual task run ();
    yarp_transaction tr;
    forever begin
      @(vif.mon_cb);
      tr = new();
      tr.instr_mem_req     = vif.mon_cb.instr_mem_req;
      tr.instr_mem_addr    = vif.mon_cb.instr_mem_addr;
      tr.instr_mem_ready   = vif.mon_cb.instr_mem_ready;
      tr.instr_mem_rd_data = vif.mon_cb.instr_mem_rd_data;
      tr.data_mem_req      = vif.mon_cb.data_mem_req;
      tr.data_mem_addr     = vif.mon_cb.data_mem_addr;
      tr.data_mem_byte_en  = vif.mon_cb.data_mem_byte_en;
      tr.data_mem_wr       = vif.mon_cb.data_mem_wr;
      tr.data_mem_wr_data  = vif.mon_cb.data_mem_wr_data;
      tr.data_mem_ready    = vif.mon_cb.data_mem_ready;
      tr.data_mem_rd_data  = vif.mon_cb.data_mem_rd_data;
      @(negedge vif.clk);
      tr.arch_reg          = vif.arch_reg;            // [MO2]
      mon2sb.put(tr);
    end
  endtask

  virtual task end_of_test ();
    repeat (32) @(vif.mon_cb);
  endtask

endclass
