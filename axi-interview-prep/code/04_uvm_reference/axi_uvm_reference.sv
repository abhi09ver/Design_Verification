// =============================================================================
// axi_uvm_reference.sv  -  UVM building blocks from the cheat sheets, in one file
//
// REFERENCE CODE: written to IEEE 1800.2 UVM, but NOT compiled in this repo
// (iverilog has no UVM, constraints or covergroups). Paste into EDA Playground
// (free UVM 1.2 / Questa / VCS) or your simulator to try it.
//
//   Section                         Cheat sheet
//   1. Interface w/ clocking blocks 15 (UVM core)
//   2. AXI4 transaction + constraints 05 (bursts), 11 (verification env)
//   3. Driver config knobs          14 (top-tier roadmap)
//   4. Per-ID read scoreboard       07 (out-of-order)
//   5. Protocol covergroup          14
//   6. AXI-Lite RAL adapter         14
//   7. WRAP address reference model 06 (WRAP burst)
// =============================================================================
`include "uvm_macros.svh"
import uvm_pkg::*;

// -----------------------------------------------------------------------------
// 1. AXI4-Lite interface with driver/monitor clocking blocks and modports
// -----------------------------------------------------------------------------
interface axi4_lite_if (input logic aclk, input logic aresetn);
    logic [31:0] awaddr, wdata, araddr, rdata;
    logic [3:0]  wstrb;
    logic [2:0]  awprot, arprot;
    logic [1:0]  bresp, rresp;
    logic awvalid, awready, wvalid, wready, bvalid, bready;
    logic arvalid, arready, rvalid, rready;

    clocking driver_cb @(posedge aclk);
        default input #1step output #1;
        output awaddr, awprot, awvalid, wdata, wstrb, wvalid, bready,
               araddr, arprot, arvalid, rready;
        input  awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp;
    endclocking

    clocking monitor_cb @(posedge aclk);
        default input #1step;
        input awaddr, awprot, awvalid, awready, wdata, wstrb, wvalid, wready,
              bresp, bvalid, bready, araddr, arprot, arvalid, arready,
              rdata, rresp, rvalid, rready;
    endclocking

    modport DRV (clocking driver_cb, input aresetn);
    modport MON (clocking monitor_cb, input aresetn);
endinterface

// -----------------------------------------------------------------------------
// 2. AXI4 burst transaction with legal-by-construction constraints
// -----------------------------------------------------------------------------
class axi_txn extends uvm_sequence_item;
    `uvm_object_utils(axi_txn)
    localparam int BUS_BYTES = 4, MEM_BYTES = 4096;
    typedef enum bit [1:0] {FIXED = 2'b00, INCR = 2'b01, WRAP = 2'b10} burst_e;

    rand bit         wr;
    rand bit  [3:0]  id;
    rand bit  [31:0] addr;
    rand bit  [7:0]  len;
    rand bit  [2:0]  size;
    rand burst_e     burst;
    rand bit  [31:0] data[];
    rand bit  [3:0]  strb[];
         bit  [1:0]  resp;                       // filled by the monitor

    constraint c_size  { (1 << size) <= BUS_BYTES; }
    constraint c_wrap  { burst == WRAP  -> len inside {1, 3, 7, 15};
                         burst == WRAP  -> addr % (1 << size) == 0; }
    constraint c_fixed { burst == FIXED -> len < 16; }
    constraint c_4k    { burst == INCR  ->
                         (addr % 4096) + (len + 1) * (1 << size) <= 4096; }
    constraint c_range { addr < MEM_BYTES; }
    constraint c_arr   { data.size() == len + 1; strb.size() == len + 1; }
    constraint c_dist  { len dist {0 := 20, [1:15] :/ 50, [16:255] :/ 30};
                         solve burst before len; }

    function new(string name = "axi_txn"); super.new(name); endfunction

    function string convert2string();
        return $sformatf("%s id=%0h addr=%08h len=%0d size=%0d burst=%s resp=%0b",
                         wr ? "WR" : "RD", id, addr, len, size, burst.name(), resp);
    endfunction
endclass

// -----------------------------------------------------------------------------
// 3. Driver knobs: one config object, many traffic shapes, no driver edits
// -----------------------------------------------------------------------------
class axi_cfg extends uvm_object;
    `uvm_object_utils(axi_cfg)
    int unsigned max_skew   = 4;   // AW vs W start delay (either may lead)
    int unsigned max_bstall = 6;   // cycles BREADY held low
    int unsigned max_rstall = 6;   // cycles RREADY held low
    function new(string name = "axi_cfg"); super.new(name); endfunction
endclass
// In the driver's drive_write():
//   fork
//     begin repeat ($urandom_range(0, cfg.max_skew)) @(vif.driver_cb); drive_aw(t); end
//     begin repeat ($urandom_range(0, cfg.max_skew)) @(vif.driver_cb); drive_w(t);  end
//   join
//   repeat ($urandom_range(0, cfg.max_bstall)) @(vif.driver_cb);
//   vif.driver_cb.bready <= 1;

// -----------------------------------------------------------------------------
// 4. Read scoreboard with per-ID ordering (same ID in order, different IDs any)
// -----------------------------------------------------------------------------
`uvm_analysis_imp_decl(_ar)
`uvm_analysis_imp_decl(_r)
class axi_rd_sb extends uvm_scoreboard;
    `uvm_component_utils(axi_rd_sb)
    uvm_analysis_imp_ar #(axi_txn, axi_rd_sb) ar_imp;   // address seen
    uvm_analysis_imp_r  #(axi_txn, axi_rd_sb) r_imp;    // full burst seen
    axi_txn exp_q[bit [3:0]][$];                         // one FIFO per ID
    bit [7:0] mem_model[bit [31:0]];                     // byte-level model
    int unsigned checked, errors;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        ar_imp = new("ar_imp", this);
        r_imp  = new("r_imp",  this);
    endfunction

    function void write_ar(axi_txn t);
        exp_q[t.id].push_back(t);
    endfunction

    function void write_r(axi_txn t);
        axi_txn e;
        if (!exp_q.exists(t.id) || exp_q[t.id].size() == 0) begin
            `uvm_error("SB", $sformatf("RID %0h has no outstanding AR", t.id))
            errors++; return;
        end
        e = exp_q[t.id].pop_front();                     // oldest of SAME ID
        // ... compare t.data[] beat by beat against mem_model at the
        //     addresses produced by wrap_addrs()/INCR/FIXED for e ...
        checked++;
    endfunction

    function void check_phase(uvm_phase phase);
        foreach (exp_q[id]) if (exp_q[id].size())
            `uvm_error("SB", $sformatf("%0d reads with ID %0h never completed", exp_q[id].size(), id))
        if (checked == 0) `uvm_error("SB", "scoreboard checked nothing")
    endfunction
endclass

// -----------------------------------------------------------------------------
// 5. Protocol coverage: what the original repo's coverage could not see
// -----------------------------------------------------------------------------
typedef enum {AW_FIRST, W_FIRST, SAME_CYCLE} order_e;
class axi_proto_cov extends uvm_component;
    `uvm_component_utils(axi_proto_cov)
    covergroup cg_proto with function sample(order_e ord, int bstall, int rstall,
                                             bit wr, bit [1:0] resp);
        cp_ord : coverpoint ord;
        cp_bst : coverpoint bstall { bins none = {0}; bins short_ = {[1:3]}; bins long_ = {[4:$]}; }
        cp_rst : coverpoint rstall { bins none = {0}; bins short_ = {[1:3]}; bins long_ = {[4:$]}; }
        cp_wr  : coverpoint wr;
        cp_resp: coverpoint resp   { bins okay = {0}; bins slverr = {2}; }
        x_ord_bst : cross cp_ord, cp_bst;
        x_dir_resp: cross cp_wr, cp_resp;
    endgroup
    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_proto = new();
    endfunction
endclass

// -----------------------------------------------------------------------------
// 6. RAL adapter for an AXI4-Lite register / memory block
// -----------------------------------------------------------------------------
class axi_lite_item extends uvm_sequence_item;            // minimal AXI-Lite item
    `uvm_object_utils(axi_lite_item)
    rand bit        wr;
    rand bit [31:0] addr, data;
    rand bit [3:0]  wstrb;
         bit [31:0] rdata;
         bit [1:0]  bresp, rresp;
    function new(string name = "axi_lite_item"); super.new(name); endfunction
endclass

class axi_lite_adapter extends uvm_reg_adapter;
    `uvm_object_utils(axi_lite_adapter)
    function new(string name = "axi_lite_adapter"); super.new(name); endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        axi_lite_item t = axi_lite_item::type_id::create("t");
        t.wr    = (rw.kind == UVM_WRITE);
        t.addr  = rw.addr;
        t.data  = rw.data;
        t.wstrb = 4'hF;
        return t;
    endfunction

    virtual function void bus2reg(uvm_sequence_item item, ref uvm_reg_bus_op rw);
        axi_lite_item t;
        if (!$cast(t, item)) `uvm_fatal("ADPT", "bus2reg: wrong item type")
        rw.kind   = t.wr ? UVM_WRITE : UVM_READ;
        rw.addr   = t.addr;
        rw.data   = t.wr ? t.data : t.rdata;
        rw.status = ((t.wr ? t.bresp : t.rresp) == 2'b00) ? UVM_IS_OK : UVM_NOT_OK;
    endfunction
endclass
// Hook-up: reg_model.default_map.set_sequencer(agent.sequencer, adapter);
//          predictor.map = reg_model.default_map; predictor.adapter = adapter;
//          monitor.ap.connect(predictor.bus_in);          // explicit prediction

// -----------------------------------------------------------------------------
// 7. WRAP address reference model (window = (len+1) * 2^size, aligned)
// -----------------------------------------------------------------------------
function automatic void wrap_addrs(input  bit [31:0] start, input bit [7:0] len,
                                   input  bit [2:0]  size,  ref   bit [31:0] q[$]);
    int unsigned nb    = 1 << size;
    int unsigned win   = nb * (len + 1);
    bit [31:0]   lower = (start / win) * win;
    bit [31:0]   upper = lower + win;
    bit [31:0]   a     = start;
    repeat (len + 1) begin
        q.push_back(a);
        a += nb;
        if (a == upper) a = lower;
    end
endfunction
