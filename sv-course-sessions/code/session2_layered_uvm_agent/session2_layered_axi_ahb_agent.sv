// Session 2 - Layered UVM agent: one protocol-independent "bus" layer on top of
// AXI and AHB protocol agents.
//
// WHY LAYERING: tests and sequences are written once against a generic bus_txn
// (read/write, addr, data[]). A translation sequence converts each bus_txn into the
// protocol's own items (AXI bursts with the 4KB rule, AHB bursts with the 1KB rule).
// Switching the SoC port from AHB to AXI changes ONE config knob, not the tests.
//
//                       +-------------------------------+
//    test / vseq ---->  | upper sequencer  (bus_txn)    |   no driver on this layer
//                       +---------------+---------------+
//                                       | get_next_item / item_done (pull)
//            +--------------------------+---------------------------+
//            |                                                      |
//   bus2axi_seq on axi_sequencer                         bus2ahb_seq on ahb_sequencer
//   splits at 4KB, sets AWLEN/AWSIZE                     splits at 1KB, INCR4/8/16/SINGLE
//            |                                                      |
//      axi_driver --> AXI pins                               ahb_driver --> AHB pins
//      axi_monitor --> axi2bus (rebuild bus_txn) ---+---- ahb2bus <-- ahb_monitor
//                                                   v
//                                    bus-level analysis port --> scoreboard / coverage
//
// Drivers here print instead of wiggling pins (no DUT), and loop each item back to
// the monitor path, so the whole layering flow can be shown in a simulator.

`include "uvm_macros.svh"
package layered_pkg;
  import uvm_pkg::*;

  // ======================================================================
  // UPPER LAYER: protocol-independent transaction
  // ======================================================================
  typedef enum bit {BUS_READ, BUS_WRITE} bus_kind_e;

  class bus_txn extends uvm_sequence_item;
    rand bus_kind_e kind;
    rand bit [31:0] addr;
    rand bit [31:0] data[];          // one 32-bit word per element
    constraint c_len  { data.size() inside {[1:32]}; }
    constraint c_addr { addr % 4 == 0; }
    `uvm_object_utils(bus_txn)
    function new(string name = "bus_txn"); super.new(name); endfunction
    function string convert2string();
      return $sformatf("%s addr=%h words=%0d", kind.name(), addr, data.size());
    endfunction
  endclass

  typedef uvm_sequencer #(bus_txn) bus_sequencer;

  // ======================================================================
  // LOWER LAYER A: AXI
  // ======================================================================
  class axi_item extends uvm_sequence_item;
    bit        write;
    bit [31:0] addr;
    bit [7:0]  len;       // beats - 1
    bit [2:0]  size;      // bytes/beat = 2**size
    bit [1:0]  burst;     // 1 = INCR
    bit [31:0] data[$];
    `uvm_object_utils(axi_item)
    function new(string name = "axi_item"); super.new(name); endfunction
    function string convert2string();
      return $sformatf("AXI %s addr=%h AxLEN=%0d AxSIZE=%0d INCR", write ? "WR" : "RD",
                       addr, len, size);
    endfunction
  endclass

  typedef uvm_sequencer #(axi_item) axi_sequencer;

  class axi_driver extends uvm_driver #(axi_item);
    `uvm_component_utils(axi_driver)
    uvm_analysis_port #(axi_item) ap;    // loop-back stands in for the monitor
    function new(string n, uvm_component p); super.new(n, p); ap = new("ap", this); endfunction
    task run_phase(uvm_phase phase);
      forever begin
        seq_item_port.get_next_item(req);
        `uvm_info("AXI_DRV", req.convert2string(), UVM_LOW)
        #10;                                 // real driver: AW/W/B or AR/R handshakes
        ap.write(req);
        seq_item_port.item_done();
      end
    endtask
  endclass

  class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)
    axi_sequencer sqr;  axi_driver drv;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      sqr = axi_sequencer::type_id::create("sqr", this);
      drv = axi_driver   ::type_id::create("drv", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ======================================================================
  // LOWER LAYER B: AHB
  // ======================================================================
  typedef enum bit [2:0] {SINGLE = 0, INCR = 1, INCR4 = 3, INCR8 = 5, INCR16 = 7} hburst_e;

  class ahb_item extends uvm_sequence_item;
    bit        hwrite;
    bit [31:0] haddr;            // address of the first beat
    hburst_e   hburst;
    bit [2:0]  hsize;            // 2 = word
    bit [31:0] data[$];
    `uvm_object_utils(ahb_item)
    function new(string name = "ahb_item"); super.new(name); endfunction
    function string convert2string();
      return $sformatf("AHB %s haddr=%h HBURST=%s beats=%0d (NONSEQ + %0d SEQ)",
                       hwrite ? "WR" : "RD", haddr, hburst.name(), data.size(), data.size() - 1);
    endfunction
  endclass

  typedef uvm_sequencer #(ahb_item) ahb_sequencer;

  class ahb_driver extends uvm_driver #(ahb_item);
    `uvm_component_utils(ahb_driver)
    uvm_analysis_port #(ahb_item) ap;
    function new(string n, uvm_component p); super.new(n, p); ap = new("ap", this); endfunction
    task run_phase(uvm_phase phase);
      forever begin
        seq_item_port.get_next_item(req);
        `uvm_info("AHB_DRV", req.convert2string(), UVM_LOW)
        #10;                                 // real driver: pipelined addr/data phases
        ap.write(req);
        seq_item_port.item_done();
      end
    endtask
  endclass

  class ahb_agent extends uvm_agent;
    `uvm_component_utils(ahb_agent)
    ahb_sequencer sqr;  ahb_driver drv;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      sqr = ahb_sequencer::type_id::create("sqr", this);
      drv = ahb_driver   ::type_id::create("drv", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  // ======================================================================
  // DOWNWARD TRANSLATION: layering sequences (run on the LOWER sequencer)
  // ======================================================================
  class bus2axi_seq extends uvm_sequence #(axi_item);
    `uvm_object_utils(bus2axi_seq)
    bus_sequencer up_sqr;                       // set by the env before start()
    function new(string name = "bus2axi_seq"); super.new(name); endfunction

    task body();
      bus_txn b;
      forever begin
        up_sqr.get_next_item(b);                // PULL from the upper layer
        send_split(b);
        up_sqr.item_done();                     // upper sequence unblocks only now
      end
    endtask

    // One bus_txn may become several AXI bursts: an INCR burst must not cross 4KB.
    task send_split(bus_txn b);
      int idx = 0;
      bit [31:0] a = b.addr;
      while (idx < b.data.size()) begin
        int room  = (4096 - (a % 4096)) / 4;    // words left in this 4KB page
        int beats = b.data.size() - idx;
        axi_item it;
        if (beats > room) beats = room;
        if (beats > 256)  beats = 256;          // AXI4 INCR max
        it = axi_item::type_id::create("it");
        start_item(it);
        it.write = (b.kind == BUS_WRITE);
        it.addr  = a;  it.size = 2;  it.burst = 1;  it.len = 8'(beats - 1);
        for (int k = 0; k < beats; k++) it.data.push_back(b.data[idx + k]);
        finish_item(it);
        idx += beats;  a += beats * 4;
      end
    endtask
  endclass

  class bus2ahb_seq extends uvm_sequence #(ahb_item);
    `uvm_object_utils(bus2ahb_seq)
    bus_sequencer up_sqr;
    function new(string name = "bus2ahb_seq"); super.new(name); endfunction

    task body();
      bus_txn b;
      forever begin
        up_sqr.get_next_item(b);
        send_split(b);
        up_sqr.item_done();
      end
    endtask

    // Pick the largest fixed INCR burst (16/8/4) that fits and doesn't cross 1KB;
    // otherwise SINGLE. (INCR undefined-length is legal too; fixed bursts show more.)
    task send_split(bus_txn b);
      int idx = 0;
      bit [31:0] a = b.addr;
      while (idx < b.data.size()) begin
        int left = b.data.size() - idx;
        int room = (1024 - (a % 1024)) / 4;     // AHB: bursts must not cross 1KB
        int beats;  hburst_e hb;
        ahb_item it;
        if      (left >= 16 && room >= 16) begin beats = 16; hb = INCR16; end
        else if (left >=  8 && room >=  8) begin beats =  8; hb = INCR8;  end
        else if (left >=  4 && room >=  4) begin beats =  4; hb = INCR4;  end
        else                               begin beats =  1; hb = SINGLE; end
        it = ahb_item::type_id::create("it");
        start_item(it);
        it.hwrite = (b.kind == BUS_WRITE);  it.haddr = a;  it.hburst = hb;  it.hsize = 2;
        for (int k = 0; k < beats; k++) it.data.push_back(b.data[idx + k]);
        finish_item(it);
        idx += beats;  a += beats * 4;
      end
    endtask
  endclass

  // ======================================================================
  // UPWARD TRANSLATION: rebuild bus-level transactions from protocol items
  // (a real design merges split bursts back; kept 1:1 here for clarity)
  // ======================================================================
  class axi2bus extends uvm_subscriber #(axi_item);
    `uvm_component_utils(axi2bus)
    uvm_analysis_port #(bus_txn) ap;
    function new(string n, uvm_component p); super.new(n, p); ap = new("ap", this); endfunction
    function void write(axi_item t);
      bus_txn b = bus_txn::type_id::create("b");
      b.kind = t.write ? BUS_WRITE : BUS_READ;  b.addr = t.addr;  b.data = t.data;
      ap.write(b);
    endfunction
  endclass

  class ahb2bus extends uvm_subscriber #(ahb_item);
    `uvm_component_utils(ahb2bus)
    uvm_analysis_port #(bus_txn) ap;
    function new(string n, uvm_component p); super.new(n, p); ap = new("ap", this); endfunction
    function void write(ahb_item t);
      bus_txn b = bus_txn::type_id::create("b");
      b.kind = t.hwrite ? BUS_WRITE : BUS_READ;  b.addr = t.haddr;  b.data = t.data;
      ap.write(b);
    endfunction
  endclass

  // bus-level checker: proves the words that reached the protocol layer are the
  // words the test asked for, whichever protocol is underneath
  class bus_checker extends uvm_subscriber #(bus_txn);
    `uvm_component_utils(bus_checker)
    int words;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void write(bus_txn t); words += t.data.size(); endfunction
  endclass

  // ======================================================================
  // LAYERED ENV: config knob picks the protocol under the same upper layer
  // ======================================================================
  typedef enum {PROTO_AXI, PROTO_AHB} proto_e;

  class layered_env extends uvm_env;
    `uvm_component_utils(layered_env)
    proto_e       proto = PROTO_AXI;
    bus_sequencer bus_sqr;
    axi_agent     axi;   axi2bus axi_up;
    ahb_agent     ahb;   ahb2bus ahb_up;
    bus_checker   chk;

    function new(string n, uvm_component p); super.new(n, p); endfunction

    function void build_phase(uvm_phase phase);
      void'(uvm_config_db #(proto_e)::get(this, "", "proto", proto));
      bus_sqr = bus_sequencer::type_id::create("bus_sqr", this);
      chk     = bus_checker  ::type_id::create("chk", this);
      if (proto == PROTO_AXI) begin
        axi    = axi_agent::type_id::create("axi", this);
        axi_up = axi2bus  ::type_id::create("axi_up", this);
      end else begin
        ahb    = ahb_agent::type_id::create("ahb", this);
        ahb_up = ahb2bus  ::type_id::create("ahb_up", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (proto == PROTO_AXI) begin
        axi.drv.ap.connect(axi_up.analysis_export);
        axi_up.ap.connect(chk.analysis_export);
      end else begin
        ahb.drv.ap.connect(ahb_up.analysis_export);
        ahb_up.ap.connect(chk.analysis_export);
      end
    endfunction

    // start the translation sequence on the lower sequencer; it runs forever
    task run_phase(uvm_phase phase);
      if (proto == PROTO_AXI) begin
        bus2axi_seq s = bus2axi_seq::type_id::create("bus2axi");
        s.up_sqr = bus_sqr;
        s.start(axi.sqr);
      end else begin
        bus2ahb_seq s = bus2ahb_seq::type_id::create("bus2ahb");
        s.up_sqr = bus_sqr;
        s.start(ahb.sqr);
      end
    endtask
  endclass

  // ======================================================================
  // ONE protocol-independent test sequence
  // ======================================================================
  class bus_smoke_seq extends uvm_sequence #(bus_txn);
    `uvm_object_utils(bus_smoke_seq)
    int total_words;
    function new(string name = "bus_smoke_seq"); super.new(name); endfunction
    task body();
      // directed: 20 words starting 8 bytes before a 4KB page (and 1KB) boundary
      req = bus_txn::type_id::create("req");
      start_item(req);
      req.kind = BUS_WRITE;  req.addr = 32'h0000_0FF8;  req.data = new[20];
      foreach (req.data[i]) req.data[i] = i;
      finish_item(req);
      total_words += req.data.size();
      `uvm_info("BUS_SEQ", {"sent ", req.convert2string()}, UVM_LOW)
      // a few random ones
      repeat (2) begin
        req = bus_txn::type_id::create("req");
        start_item(req);
        if (!req.randomize()) `uvm_error("BUS_SEQ", "randomize failed")
        finish_item(req);
        total_words += req.data.size();
        `uvm_info("BUS_SEQ", {"sent ", req.convert2string()}, UVM_LOW)
      end
    endtask
  endclass

  class layered_test extends uvm_test;
    `uvm_component_utils(layered_test)
    layered_env env;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      string p;
      proto_e proto = PROTO_AXI;
      if ($value$plusargs("PROTO=%s", p) && p == "AHB") proto = PROTO_AHB;
      uvm_config_db #(proto_e)::set(this, "env", "proto", proto);
      env = layered_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      bus_smoke_seq s = bus_smoke_seq::type_id::create("s");
      phase.raise_objection(this);
      s.start(env.bus_sqr);           // test talks ONLY to the upper layer
      #50;
      if (env.chk.words != s.total_words)
        `uvm_error("TEST", $sformatf("words in=%0d out=%0d", s.total_words, env.chk.words))
      else
        `uvm_info("TEST", $sformatf("PASS: %0d words through %s layer", env.chk.words,
                                    env.proto.name()), UVM_LOW)
      phase.drop_objection(this);
    endtask
  endclass
endpackage

module tb;
  import uvm_pkg::*;
  import layered_pkg::*;
  initial run_test("layered_test");
endmodule
