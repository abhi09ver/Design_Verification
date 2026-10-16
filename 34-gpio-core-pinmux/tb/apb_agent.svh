// -----------------------------------------------------------------------------
// apb_agent.svh : APB master agent (item, driver, monitor, agent) + RAL adapter
// -----------------------------------------------------------------------------

class apb_item extends uvm_sequence_item;
  rand bit [7:0]    addr;
  rand bit          write;
  rand bit [31:0]   data;   // write data, or read data after completion
  rand int unsigned idle;   // idle cycles before SETUP (0 = back-to-back)
  longint           cyc;    // set by the monitor: clock cycle of completion

  constraint c_align { soft addr[1:0] == 2'b00; }
  constraint c_idle  { idle dist {0 := 6, [1:3] := 3, [4:10] := 1}; }

  `uvm_object_utils_begin(apb_item)
    `uvm_field_int(addr,  UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(write, UVM_ALL_ON)
    `uvm_field_int(data,  UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(idle,  UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "apb_item");
    super.new(name);
  endfunction
endclass : apb_item

typedef uvm_sequencer #(apb_item) apb_sequencer;


class apb_driver extends uvm_driver #(apb_item);
  `uvm_component_utils(apb_driver)
  virtual apb_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif))
      `uvm_fatal("NOVIF", "apb_vif not set in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    vif.drv_cb.psel    <= 1'b0;
    vif.drv_cb.penable <= 1'b0;
    wait (vif.resetn === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      seq_item_port.item_done();
    end
  endtask

  // SETUP (psel=1, penable=0) -> ACCESS (penable=1) until pready.
  // Write = 2 clocks, read = 3 clocks per the User Guide.
  task drive(apb_item t);
    repeat (t.idle) @(vif.drv_cb);
    vif.drv_cb.paddr   <= t.addr;
    vif.drv_cb.pwrite  <= t.write;
    vif.drv_cb.pwdata  <= t.write ? t.data : 32'h0;
    vif.drv_cb.psel    <= 1'b1;
    vif.drv_cb.penable <= 1'b0;
    @(vif.drv_cb);
    vif.drv_cb.penable <= 1'b1;
    do @(vif.drv_cb); while (vif.drv_cb.pready !== 1'b1);
    if (!t.write) t.data = vif.drv_cb.prdata;
    vif.drv_cb.psel    <= 1'b0;
    vif.drv_cb.penable <= 1'b0;
  endtask
endclass : apb_driver


class apb_monitor extends uvm_monitor;
  `uvm_component_utils(apb_monitor)
  virtual apb_if vif;
  uvm_analysis_port #(apb_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif))
      `uvm_fatal("NOVIF", "apb_vif not set in config_db")
  endfunction

  longint cyc;             // free-running cycle counter, same as pin_monitor's

  // One item per completed transfer (psel & penable & pready).
  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      cyc++;
      if (vif.resetn === 1'b1 && vif.mon_cb.psel && vif.mon_cb.penable && vif.mon_cb.pready) begin
        apb_item t = apb_item::type_id::create("t");
        t.addr  = vif.mon_cb.paddr;
        t.write = vif.mon_cb.pwrite;
        t.data  = vif.mon_cb.pwrite ? vif.mon_cb.pwdata : vif.mon_cb.prdata;
        t.cyc   = cyc;
        ap.write(t);
      end
    end
  endtask
endclass : apb_monitor


class apb_agent extends uvm_agent;
  `uvm_component_utils(apb_agent)
  apb_sequencer seqr;
  apb_driver    drv;
  apb_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = apb_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      seqr = apb_sequencer::type_id::create("seqr", this);
      drv  = apb_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass : apb_agent


// RAL <-> APB. provides_responses = 0: the driver writes read data back into
// the same item, and the map calls bus2reg on it after item_done.
class apb_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(apb_reg_adapter)

  function new(string name = "apb_reg_adapter");
    super.new(name);
    supports_byte_enable = 0;
    provides_responses   = 0;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    apb_item t = apb_item::type_id::create("t");
    t.addr  = rw.addr[7:0];
    t.write = (rw.kind == UVM_WRITE);
    t.data  = rw.data[31:0];
    t.idle  = 0;
    return t;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    apb_item t;
    if (!$cast(t, bus_item)) begin
      `uvm_fatal("CAST", "bus2reg: item is not an apb_item")
      return;
    end
    rw.kind   = t.write ? UVM_WRITE : UVM_READ;
    rw.addr   = t.addr;
    rw.data   = t.data;
    rw.status = UVM_IS_OK;   // no PSLVERR on this IP
  endfunction
endclass : apb_reg_adapter
