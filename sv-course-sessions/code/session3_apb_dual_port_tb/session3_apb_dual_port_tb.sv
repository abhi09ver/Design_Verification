// Session 3 - Dual-port APB Driver / Monitor / Scoreboard testbench (no UVM)
//
//   gen --gen2drv--> driver --drives--> apb_if1 / apb_if2 --> apb_slave x2 (DUT)
//                      |                    |
//                   drv2sb               monitor (passive, both ports)
//                      |                    |
//                      +---> scoreboard <---+ mon2sb
//
// Run:  verilator --binary --timing -Wno-fatal session3_apb_dual_port_tb.sv
//       ./obj_dir/Vtb            (clean run)
//       ./obj_dir/Vtb +BUG       (slave on port 2 corrupts writes -> scoreboard must catch it)

// ============================== interface ==================================
interface apb_if (input logic pclk, input logic presetn);
  logic        psel, penable, pwrite, pready;
  logic [31:0] paddr, pwdata, prdata;
endinterface

// ============================== DUT: APB slave =============================
// 64-word memory, random wait states. With +BUG, the PORT 2 slave stores inverted
// write data - a deliberate bug the scoreboard must catch on read-back.
module apb_slave #(parameter int PORT = 1) (apb_if bus);
  logic [31:0] mem [64];
  logic [1:0]  wait_cnt;
  bit          bug;
  initial bug = (PORT == 2) && $test$plusargs("BUG");

  assign bus.prdata = mem[bus.paddr[7:2]];

  always @(posedge bus.pclk or negedge bus.presetn) begin
    if (!bus.presetn) begin
      bus.pready <= 0;
      wait_cnt   <= 0;
      foreach (mem[i]) mem[i] <= 0;
    end else if (bus.psel && bus.penable) begin
      if (!bus.pready) begin                     // insert 0..3 wait states
        if (wait_cnt == 0) bus.pready <= 1;
        else               wait_cnt   <= wait_cnt - 1;
      end else begin                             // transfer completes this edge
        bus.pready <= 0;
        wait_cnt   <= 2'($urandom_range(0, 3));
        if (bus.pwrite)
          mem[bus.paddr[7:2]] <= bug ? ~bus.pwdata : bus.pwdata;
      end
    end
  end
endmodule

// ============================== 1. transaction =============================
class apb_txn;
  rand bit [31:0] addr;
  rand bit [31:0] data;          // write data
  rand bit        write;         // 1 = write, 0 = read
       bit [31:0] read_data;     // filled by driver / monitor on reads
       int        port;          // 1 or 2: which interface this goes to
       int        id;

  constraint c_addr  { addr inside {[0:15*4]}; addr % 4 == 0; }  // small, word-aligned:
                                                                  // reads hit written words
  constraint c_write { write dist {1 := 6, 0 := 4}; }

  function apb_txn copy();
    copy = new();
    copy.addr = addr; copy.data = data; copy.write = write;
    copy.read_data = read_data; copy.port = port; copy.id = id;
  endfunction

  function string sprint();
    return $sformatf("#%0d port%0d %s addr=%h %s=%h", id, port, write ? "WR" : "RD", addr,
                     write ? "wdata" : "rdata", write ? data : read_data);
  endfunction
endclass

// ============================== 2. driver ==================================
// ONE driver, TWO virtual interfaces; txn.port selects which bus to drive.
class apb_driver;
  virtual apb_if vif1, vif2;
  mailbox #(apb_txn) gen2drv, drv2sb;

  function new(virtual apb_if v1, virtual apb_if v2, mailbox #(apb_txn) g2d, mailbox #(apb_txn) d2s);
    vif1 = v1; vif2 = v2; gen2drv = g2d; drv2sb = d2s;
  endfunction

  task reset_bus(virtual apb_if vif);
    vif.psel <= 0; vif.penable <= 0; vif.pwrite <= 0; vif.paddr <= 0; vif.pwdata <= 0;
  endtask

  task run();
    reset_bus(vif1); reset_bus(vif2);
    forever begin
      apb_txn t;
      gen2drv.get(t);
      if (t.port == 1) drive(vif1, t);
      else             drive(vif2, t);
      drv2sb.put(t.copy());               // copy: later edits can't corrupt the SB's view
    end
  endtask

  task drive(virtual apb_if vif, apb_txn t);
    // SETUP phase
    @(posedge vif.pclk);
    vif.psel   <= 1;  vif.penable <= 0;
    vif.pwrite <= t.write;  vif.paddr <= t.addr;  vif.pwdata <= t.data;
    // ACCESS phase
    @(posedge vif.pclk);
    vif.penable <= 1;
    // hold until slave says ready
    do @(posedge vif.pclk); while (!vif.pready);
    if (!t.write) t.read_data = vif.prdata;
    vif.psel <= 0;  vif.penable <= 0;
  endtask
endclass

// ============================== 3. monitor =================================
// Passive. One thread per interface, both push into the same mailbox.
class apb_monitor;
  virtual apb_if vif1, vif2;
  mailbox #(apb_txn) mon2sb;

  function new(virtual apb_if v1, virtual apb_if v2, mailbox #(apb_txn) m2s);
    vif1 = v1; vif2 = v2; mon2sb = m2s;
  endfunction

  task run();
    fork
      watch(vif1, 1);
      watch(vif2, 2);
    join
  endtask

  task watch(virtual apb_if vif, int port);
    forever begin
      @(posedge vif.pclk);
      // the transfer completes on the edge where PSEL && PENABLE && PREADY
      if (vif.presetn && vif.psel && vif.penable && vif.pready) begin
        apb_txn t = new();
        t.port  = port;
        t.addr  = vif.paddr;
        t.write = vif.pwrite;
        if (vif.pwrite) t.data      = vif.pwdata;
        else            t.read_data = vif.prdata;
        mon2sb.put(t);
      end
    end
  endtask
endclass

// ============================== 4. scoreboard ==============================
class apb_scoreboard;
  mailbox #(apb_txn) drv2sb, mon2sb;
  bit [31:0] ref_mem [int][bit [31:0]];  // [port][addr] reference model, one memory per slave
  apb_txn    exp_q   [int][$];           // per-port queue of what the driver sent
  int n_checked, n_errors, n_expected;
  event done;

  function new(mailbox #(apb_txn) d2s, mailbox #(apb_txn) m2s, int n);
    drv2sb = d2s; mon2sb = m2s; n_expected = n;
  endfunction

  task run();
    fork
      forever begin apb_txn d; drv2sb.get(d); exp_q[d.port].push_back(d); end
      forever begin apb_txn m; mon2sb.get(m); check(m); end
    join
  endtask

  task check(apb_txn act);
    apb_txn exp;
    bit [31:0] model_val;
    // the driver's copy arrives after the transfer finishes; wait for it
    wait (exp_q.exists(act.port) && exp_q[act.port].size() > 0);
    exp = exp_q[act.port].pop_front();
    model_val = (ref_mem.exists(act.port) && ref_mem[act.port].exists(act.addr))
                ? ref_mem[act.port][act.addr] : 0;

    if (act.addr != exp.addr || act.write != exp.write)
      error(exp, act, "control mismatch (addr/direction)");
    else if (act.write) begin
      if (act.data != exp.data) error(exp, act, "write data on bus != driven data");
      else begin
        ref_mem[act.port][act.addr] = act.data;   // update reference model
        act.id = exp.id; pass(act);
      end
    end else begin
      if (act.read_data != model_val)
        error(exp, act, $sformatf("read data mismatch, model expects %h", model_val));
      else begin act.id = exp.id; pass(act); end
    end
    n_checked++;
    if (n_checked == n_expected) -> done;
  endtask

  function void pass(apb_txn t);
    $display("[%0t] SB PASS  %s", $time, t.sprint());
  endfunction

  function void error(apb_txn exp, apb_txn act, string why);
    n_errors++;
    $display("[%0t] SB ERROR %s", $time, why);
    $display("            expected: port%0d %s addr=%h data=%h", exp.port,
             exp.write ? "WR" : "RD", exp.addr, exp.write ? exp.data : 32'h0);
    act.id = exp.id;
    $display("            actual  : %s", act.sprint());
  endfunction

  function void report();
    $display("\n==== SCOREBOARD: %0d checked, %0d errors -> %s ====",
             n_checked, n_errors, (n_errors == 0 && n_checked == n_expected) ? "PASSED" : "FAILED");
  endfunction
endclass

// ============================== 5. testbench top ===========================
module tb;
  localparam int N_TXN = 10;
  logic clk = 0, rstn = 0;
  always #5 clk = ~clk;

  apb_if if1 (clk, rstn);
  apb_if if2 (clk, rstn);

  apb_slave #(.PORT(1)) dut1 (if1);
  apb_slave #(.PORT(2)) dut2 (if2);

  mailbox #(apb_txn) gen2drv = new();
  mailbox #(apb_txn) drv2sb  = new();
  mailbox #(apb_txn) mon2sb  = new();

  apb_driver     drv;
  apb_monitor    mon;
  apb_scoreboard sb;

  initial begin
    drv = new(if1, if2, gen2drv, drv2sb);
    mon = new(if1, if2, mon2sb);
    sb  = new(drv2sb, mon2sb, N_TXN);

    repeat (3) @(posedge clk);
    rstn = 1;

    // generator: 10 randomized transactions, alternating port 1 / port 2.
    // First 6 are writes, last 4 are reads constrained to addresses already written
    // on that port - otherwise reads only ever hit reset values and a write-path
    // bug can never show up (try it: drop the 'with' and +BUG passes).
    begin
      bit [31:0] written [int][$];       // per-port list of written addresses
      for (int i = 0; i < N_TXN; i++) begin
        // TRAP: 'apb_txn t = new();' here would run ONCE - variables declared in a
        // static initial block are static, so the same handle would be put 10 times.
        apb_txn t;
        t = new();
        t.id   = i;
        t.port = (i % 2) + 1;
        t.c_write.constraint_mode(0);    // generator decides the direction itself
        if (i < 6) begin
          if (!t.randomize() with { write == 1; }) $fatal(1, "randomize failed");
          written[t.port].push_back(t.addr);
        end else begin
          if (!t.randomize() with { write == 0; addr inside {written[port]}; })
            $fatal(1, "randomize failed");
        end
        gen2drv.put(t);
      end
    end

    // start all components in parallel, stop when the scoreboard has checked everything
    fork
      drv.run();
      mon.run();
      sb.run();
    join_none

    fork
      @(sb.done);
      begin #20000; $display("TIMEOUT: scoreboard saw only %0d of %0d", sb.n_checked, N_TXN); end
    join_any
    disable fork;

    sb.report();
    $finish;
  end
endmodule
