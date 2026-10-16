// Session 5 - Class-based functional coverage model for APB
//
// Requirements from the slide:
//  1. covergroup with: address in 3 regions (low/mid/high), pwrite (read/write),
//     and the cross region x pwrite
//  2. sample ONLY when penable == 1 && pready == 1 && psel == 1
//  3. class-based model, sample() method takes all signals as inputs
//  4. explicit bins for the three address regions

class apb_coverage;

  // Covergroup with a custom sample() signature: the monitor passes the signals in,
  // so the covergroup does not depend on any interface or hierarchical path.
  covergroup apb_cg with function sample(bit [31:0] paddr, bit [31:0] pwdata,
                                         bit [31:0] prdata, bit pwrite);
    option.per_instance = 1;
    option.name        = "apb_cg";

    cp_addr : coverpoint paddr {
      bins low  = {[32'h0000_0000 : 32'h0000_0FFF]};
      bins mid  = {[32'h0000_1000 : 32'h0000_1FFF]};
      bins high = {[32'h0000_2000 : 32'h0000_FFFF]};
      // outside the spec'd map: flag it rather than silently ignoring it
      illegal_bins out_of_map = {[32'h0001_0000 : 32'hFFFF_FFFF]};
    }

    cp_rw : coverpoint pwrite {
      bins read  = {0};
      bins write = {1};
    }

    // 3 regions x 2 directions = 6 bins: "did we READ and WRITE each region?"
    cx_addr_rw : cross cp_addr, cp_rw;

    // ---- extra credit (not asked, but interviewers like it): data corner values
    cp_wdata : coverpoint pwdata iff (pwrite) {
      bins zero    = {32'h0};
      bins all_one = {32'hFFFF_FFFF};
      bins others  = default;
    }
  endgroup

  int n_calls, n_sampled;

  function new();
    apb_cg = new();            // embedded covergroup: construct in the class constructor
  endfunction

  // Called by the monitor every clock with ALL bus signals.
  // The gating lives here, so the covergroup only ever sees completed transfers.
  function void sample(bit [31:0] paddr, bit [31:0] pwdata, bit [31:0] prdata,
                       bit pwrite, bit penable, bit pready, bit psel);
    n_calls++;
    if (psel && penable && pready) begin
      n_sampled++;
      apb_cg.sample(paddr, pwdata, prdata, pwrite);
    end
  endfunction

  function void report();
    $display("calls=%0d sampled=%0d (gated off: %0d)", n_calls, n_sampled, n_calls - n_sampled);
`ifdef VERILATOR   // this open-source simulator lacks per-coverpoint get_coverage()
    $display("total=%0.1f%%", apb_cg.get_inst_coverage());
`else
    $display("cp_addr=%0.1f%%  cp_rw=%0.1f%%  cross=%0.1f%%  total=%0.1f%%",
             apb_cg.cp_addr.get_coverage(), apb_cg.cp_rw.get_coverage(),
             apb_cg.cx_addr_rw.get_coverage(), apb_cg.get_inst_coverage());
`endif
  endfunction
endclass

// ----------------------------------------------------------------------------
// Directed demo: hits 5 of the 6 cross bins on purpose (never READ the high region)
// and also sends cycles that must be gated off.
module tb;
  apb_coverage cov = new();

  initial begin
    //          paddr          pwdata        prdata  wr en rdy sel
    cov.sample(32'h0000_0010, 32'h1234,      0,      1, 1, 1, 1);  // low  write
    cov.sample(32'h0000_0020, 0,             32'h55, 0, 1, 1, 1);  // low  read
    cov.sample(32'h0000_1800, 32'h0,         0,      1, 1, 1, 1);  // mid  write
    cov.sample(32'h0000_1FFC, 0,             32'hAA, 0, 1, 1, 1);  // mid  read
    cov.sample(32'h0000_8000, 32'hFFFF_FFFF, 0,      1, 1, 1, 1);  // high write
    // gated off - must NOT count:
    cov.sample(32'h0000_9000, 0, 0, 0, 0, 1, 1);   // setup phase (penable=0)
    cov.sample(32'h0000_9000, 0, 0, 0, 1, 0, 1);   // wait state  (pready=0)
    cov.sample(32'h0000_9000, 0, 0, 0, 1, 1, 0);   // not selected
    $display("--- after directed stimulus (high-region READ deliberately missing):");
    cov.report();

    cov.sample(32'h0000_9000, 0, 32'h1, 0, 1, 1, 1);  // close the hole: high read
    $display("--- after closing the hole:");
    cov.report();
    $finish;
  end
endmodule
