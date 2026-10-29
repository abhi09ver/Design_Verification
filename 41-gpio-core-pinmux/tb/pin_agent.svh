// -----------------------------------------------------------------------------
// pin_agent.svh : drives io_gpio pads asynchronously to clk
//
// Each item sets which pins the TB drives and their values, at a random
// offset inside the clock period (phase_ns), then holds for hold_clks.
// A short hold_clks gives a glitch; the random phase exercises the 2-FF
// synchronizer the way a real button or sensor does.
// -----------------------------------------------------------------------------

class pin_item extends uvm_sequence_item;
  rand bit [GPIO_W-1:0] drive_en;   // set to the input pins (io_dir = 1)
  rand bit [GPIO_W-1:0] value;
  rand int unsigned     hold_clks;
  rand int unsigned     phase_ns;   // ns into the clock period

  constraint c_hold  { hold_clks inside {[1:20]}; }
  constraint c_phase { phase_ns < CLK_PERIOD_NS; }

  `uvm_object_utils_begin(pin_item)
    `uvm_field_int(drive_en,  UVM_ALL_ON | UVM_BIN)
    `uvm_field_int(value,     UVM_ALL_ON | UVM_BIN)
    `uvm_field_int(hold_clks, UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(phase_ns,  UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "pin_item");
    super.new(name);
  endfunction
endclass : pin_item

typedef uvm_sequencer #(pin_item) pin_sequencer;


class pin_driver extends uvm_driver #(pin_item);
  `uvm_component_utils(pin_driver)
  virtual gpio_pin_if #(GPIO_W) vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual gpio_pin_if #(GPIO_W))::get(this, "", "pin_vif", vif))
      `uvm_fatal("NOVIF", "pin_vif not set in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    vif.tb_en  = '0;
    vif.tb_val = '0;
    forever begin
      seq_item_port.get_next_item(req);
      @(posedge vif.clk);
      #(req.phase_ns * 1ns);          // asynchronous to clk
      vif.tb_val = req.value;
      vif.tb_en  = req.drive_en;
      repeat (req.hold_clks) @(posedge vif.clk);
      seq_item_port.item_done();
    end
  endtask
endclass : pin_driver


// One sample per clock: the resolved pad values, o_intr, and the cycle count.
// The scoreboard runs its cycle-based model off this stream.
class pin_sample extends uvm_object;
  `uvm_object_utils(pin_sample)
  logic [GPIO_W-1:0] io;
  logic [GPIO_W-1:0] tb_en;
  logic              intr;
  longint            cyc;
  function new(string name = "pin_sample");
    super.new(name);
  endfunction
endclass : pin_sample


class pin_monitor extends uvm_monitor;
  `uvm_component_utils(pin_monitor)
  virtual gpio_pin_if #(GPIO_W) vif;
  uvm_analysis_port #(pin_sample) ap;
  longint cyc;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual gpio_pin_if #(GPIO_W))::get(this, "", "pin_vif", vif))
      `uvm_fatal("NOVIF", "pin_vif not set in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      cyc++;
      if (vif.resetn === 1'b1) begin
        pin_sample s = pin_sample::type_id::create("s");
        s.io    = vif.mon_cb.io;
        s.tb_en = vif.mon_cb.tb_en;
        s.intr  = vif.mon_cb.intr;
        s.cyc   = cyc;
        ap.write(s);
      end
    end
  endtask
endclass : pin_monitor


class pin_agent extends uvm_agent;
  `uvm_component_utils(pin_agent)
  pin_sequencer seqr;
  pin_driver    drv;
  pin_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon  = pin_monitor::type_id::create("mon", this);
    seqr = pin_sequencer::type_id::create("seqr", this);
    drv  = pin_driver::type_id::create("drv", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass : pin_agent
