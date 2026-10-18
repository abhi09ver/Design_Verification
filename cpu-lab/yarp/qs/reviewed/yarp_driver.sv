// --------------------------------------------------------
// YARP - Driver (reviewed): the TB plays both memories
//   [D1] reset_seq also drives ready/rd_data to 0 (they were X after reset)
//   [D2] stores are written when the request is SEEN. The original gated
//        the write on vif.cb.data_mem_ready, which is the value sampled
//        BEFORE this edge (still 0), so stores almost never landed.
//   [D3] ready is dropped inline after the handshake edge, not from a
//        fork/join_none. The forked "ready<=0" and the next transaction's
//        "ready<=1" woke on the same edge: a race with a tool-dependent winner.
//   [D4] reads only for loads; counts finished transactions (n_done) so
//        the agent knows when the last one has really completed.
// --------------------------------------------------------
class yarp_driver;

  mailbox #(yarp_transaction)  gen2drv;
  virtual yarp_interface       vif;
  int unsigned                 n_done;

  function new (mailbox #(yarp_transaction) gen2drv, virtual yarp_interface vif);
    this.gen2drv = gen2drv;
    this.vif     = vif;
  endfunction

  virtual task reset_seq ();
    vif.drv_cb.reset_n           <= 1'b0;
    vif.drv_cb.instr_mem_ready   <= 1'b0;     // [D1]
    vif.drv_cb.instr_mem_rd_data <= '0;
    vif.drv_cb.data_mem_ready    <= 1'b0;
    vif.drv_cb.data_mem_rd_data  <= '0;
    repeat (3) @(vif.drv_cb);
    vif.drv_cb.reset_n <= 1'b1;
    @(vif.drv_cb);
  endtask

  task wait_for_instr_mem_req ();
    while (!vif.drv_cb.instr_mem_req) @(vif.drv_cb);
  endtask

  task process_instr_mem_req (yarp_transaction tr);
    repeat (tr.instr_mem_ready_delay) @(vif.drv_cb);
    vif.drv_cb.instr_mem_ready   <= 1'b1;
    vif.drv_cb.instr_mem_rd_data <= tr.instr_mem_rd_data;
    @(vif.drv_cb);                            // handshake completes on this edge
    vif.drv_cb.instr_mem_ready   <= 1'b0;     // [D3] inline, no fork
    vif.drv_cb.instr_mem_rd_data <= '0;
  endtask

  task process_data_mem_req (yarp_transaction tr);
    bit [31:0] addr, wdata, rdata;
    bit        wr;
    mem_access_size_t sz;
    // R3: a load/store raises data_mem_req in the same cycle its instruction
    // was accepted, so the sample from the handshake edge tells us
    if (!vif.drv_cb.data_mem_req) return;
    addr  = vif.drv_cb.data_mem_addr;
    wr    = vif.drv_cb.data_mem_wr;
    wdata = vif.drv_cb.data_mem_wr_data;
    sz    = mem_access_size_t'(vif.drv_cb.data_mem_byte_en);
    repeat (tr.data_mem_ready_delay) @(vif.drv_cb);
    if (wr) begin
      yarp_data_mem_model::write(addr, wdata, sz);       // [D2]
      rdata = '0;
    end else begin
      rdata = yarp_data_mem_model::read(addr, sz);       // [D4]
    end
    vif.drv_cb.data_mem_ready   <= 1'b1;
    vif.drv_cb.data_mem_rd_data <= rdata;
    @(vif.drv_cb);
    vif.drv_cb.data_mem_ready   <= 1'b0;
    vif.drv_cb.data_mem_rd_data <= '0;
  endtask

  virtual task run ();
    yarp_transaction tr;
    forever begin
      gen2drv.get(tr);
      wait_for_instr_mem_req();
      process_instr_mem_req(tr);
      process_data_mem_req(tr);
      n_done++;
    end
  endtask

endclass
