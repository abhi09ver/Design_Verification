// tb.sv -- one testbench for both cores
//
//   +HEX=<file>     program image, one 32-bit word per line, loaded at 0x80000000
//   +TRACE=<file>   write one line per retired instruction (compared with the ISS)
//   +MAXCYCLES=<n>  timeout
//
// Compile with -DPIPELINE to test the pipelined core instead of the single-cycle one.
//
// The test ends when the program:
//   * stores to TOHOST (0x8000F000): value 1 = PASS, anything else = FAIL code, or
//   * reaches a "self-loop" (an instruction whose next PC is itself), which is
//     how the book's riscvtest.S ends.
// This mirrors Wally's testbench, which stops on write_tohost or an infinite loop.
//
// Lab 5 (Ch 8, pipeline only): a tiny CLINT-like block for interrupts.
//   0x8000F010/14  mtimecmp (low/high). MTimerInt = (cycle count >= mtimecmp). Reset: all ones.
//   0x8000F020     msip bit 0 drives MSwInt
//   0x8000F024     bit 0 drives MExtInt (stands in for a PLIC output)
// Trap lines in the trace: "trap pc=.. cause=.. tval=..", in retirement order.
//
// Lab 6 (Ch 9, pipeline only): the core's AHB port drives rtl/uncore/uncore.sv
// (RAM at 0x9000_0000, APB GPIO/RXFIFO/CLINT at 0x10xx_xxxx). +RAMWAIT is a
// compile-time parameter: -GRAM_WAIT=<n>. GPIO pads: an input pin reads the value the
// "board" drives (PADS_IN) unless the pin is an output, which reads back GPIOOUT.
// Interrupt lines from the bus CLINT are ORed with the old 0x8000F0xx block.

module tb #(parameter int RAM_WAIT = 0, parameter int DC_WAYS = 2, parameter int DC_SETS = 8, parameter int DC_LINEWORDS = 4,
            parameter int TLB_ENTRIES = 4, parameter bit DC_SYNC = 1,
            parameter int BP_TYPE = 4, parameter int BHT_BITS = 10, parameter int BTB_BITS = 10, parameter int RAS_SIZE = 4);
  localparam logic [31:0] BASE   = 32'h8000_0000;
  localparam logic [31:0] TOHOST = 32'h8000_F000;
  localparam int          WORDS  = 16384;           // 64 KB of memory

  logic clk = 0, reset = 1;
  always #5 clk = ~clk;

  // ---------------- memory: one array, an instruction port and a data port ----------------
  logic [31:0] mem [0:WORDS-1];
  logic [31:0] PC, Instr, DataAdr, WriteDataAligned, ReadDataWord;
  logic        MemWrite;
  logic [3:0]  ByteMask;

  // Upper address bits are ignored, so memory aliases every 64 KB. That lets
  // the book's riscvtest.S (written for address 0) run unchanged at 0x80000000.
  function automatic int idx(input logic [31:0] a); return int'(a[15:2]); endfunction

  assign Instr        = mem[idx(PC)];
  assign ReadDataWord = mem[idx(DataAdr)];
  always_ff @(posedge clk)
    if (MemWrite)
      for (int b = 0; b < 4; b++)
        if (ByteMask[b]) mem[idx(DataAdr)][8*b +: 8] <= WriteDataAligned[8*b +: 8];

  // ---------------- DUT ----------------
  logic        TraceValid, TraceRegWrite, TraceMemWrite, TraceIllegal;
  logic [31:0] TracePC, TraceInstr, TraceResult, TraceMemAdr, TraceMemData, TracePCNext;
  logic [4:0]  TraceRd;
  logic [3:0]  TraceMemMask;

`ifdef PIPELINE
  logic        TraceTrap, TraceCSRWrite, MTimerInt, MSwInt, MExtInt;
  logic [31:0] TraceTrapPC, TraceCause, TraceTval, TraceCSRVal;
  logic [11:0] TraceCSRAdr;
  logic [63:0] mtimecmp = '1;
  logic        msip = 0, mext = 0;
  int unsigned clint_cycles = 0;
  // CLINT-like registers, written by ordinary stores (aliased into the 64 KB window)
  always_ff @(posedge clk) if (!reset) begin
    clint_cycles <= clint_cycles + 1;
    if (MemWrite && DataAdr[15:0] == 16'hF010) mtimecmp[31:0]  <= WriteDataAligned;
    if (MemWrite && DataAdr[15:0] == 16'hF014) mtimecmp[63:32] <= WriteDataAligned;
    if (MemWrite && DataAdr[15:0] == 16'hF020) msip <= WriteDataAligned[0];
    if (MemWrite && DataAdr[15:0] == 16'hF024) mext <= WriteDataAligned[0];
  end
  // ---- Ch 9: AHB uncore ----
  localparam logic [31:0] PADS_IN = 32'h5A5A_0F0F;
  logic [31:0] HADDR, HWDATA, HRDATA, GPIOIN, GPIOOUT, GPIOEN;
  logic        HWRITE, HREADY, BusTimerInt, BusSwInt, BusExtInt;
  logic [1:0]  HTRANS;
  logic [2:0]  HSIZE;
  logic [3:0]  HWSTRB;
  logic [2:0]  HBURST;
  assign GPIOIN = (GPIOEN & GPIOOUT) | (~GPIOEN & PADS_IN);
  uncore #(.RAM_WAIT(RAM_WAIT)) unc(.clk, .reset, .HADDR, .HWRITE, .HTRANS, .HSIZE, .HWDATA, .HWSTRB,
    .HREADY, .HRDATA, .GPIOIN, .GPIOOUT, .GPIOEN,
    .MTimerInt(BusTimerInt), .MSwInt(BusSwInt), .MExtInt(BusExtInt));
  assign MTimerInt = (64'(clint_cycles) >= mtimecmp) | BusTimerInt;
  assign MSwInt    = msip | BusSwInt;
  assign MExtInt   = mext | BusExtInt;
  core_pipe #(.DC_WAYS(DC_WAYS), .DC_SETS(DC_SETS), .DC_LINEWORDS(DC_LINEWORDS), .TLB_ENTRIES(TLB_ENTRIES), .DC_SYNC(DC_SYNC),
                .BP_TYPE(BP_TYPE), .BHT_BITS(BHT_BITS), .BTB_BITS(BTB_BITS), .RAS_SIZE(RAS_SIZE)) dut(.*);
  // bus statistics, printed at the end: transfers, cycles the pipeline was held by the bus,
  // and cycles an enabled interrupt had to wait because a transfer was committed
  int unsigned bus_xfers = 0, bus_stall_cycles = 0, irq_deferred = 0;
  always @(posedge clk) if (!reset) begin
    if (HTRANS[1] && HREADY) bus_xfers++;
    if (dut.StallW) bus_stall_cycles++;
    if (dut.BusCommittedM && (|dut.pu.ValidIntsM) && dut.ValidM) irq_deferred++;
  end
  // ---- Ch 10: cache transaction log (+CACHELOG=<file>) for dv/cachemodel.py, and counters ----
  int cfd = 0;
  int unsigned c_acc = 0, c_miss = 0, c_wb = 0, c_fwb = 0, c_reread = 0;
  initial begin string cf; if ($value$plusargs("CACHELOG=%s", cf)) cfd = $fopen(cf, "w"); end
  always @(posedge clk) if (!reset) begin
    if (dut.dc.EvReRead) c_reread++;
    if (dut.dc.EvAccess) begin
      c_acc++; if (!dut.dc.EvHit) c_miss++;
      if (cfd) $fwrite(cfd, "ACC %08h %s %s way=%0d\n", dut.IEUAdrM, dut.dc.RW[0] ? "W" : "R",
                       dut.dc.EvHit ? "HIT" : "MISS", dut.dc.EvWay);
    end
    if (dut.dc.State == 3'd0 && dut.dc.FlushReq && cfd) $fwrite(cfd, "FLUSH\n");
    if (dut.dc.State == 3'd1 && dut.dc.BurstDone) begin c_wb++;  if (cfd) $fwrite(cfd, "WB %08h\n", dut.dc.BurstBase); end
    if (dut.dc.State == 3'd5 && dut.dc.BurstDone) begin c_fwb++; if (cfd) $fwrite(cfd, "WB %08h\n", dut.dc.BurstBase); end
    if (dut.dc.State == 3'd2 && dut.dc.BurstDone && cfd) $fwrite(cfd, "FILL %08h\n", dut.dc.BurstBase);
  end
  // ---- Ch 11: TLB transaction log (+TLBLOG=<file>) for dv/tlbmodel.py, and counters ----
  //   ACC <va> HIT|MISS : first look-up of a translated load/store (MISS starts a walk)
  //   FILL <va> <entry> <mega> : a leaf PTE written into the TLB
  //   SFENCE
  int tfd = 0;
  int unsigned t_acc = 0, t_miss = 0, t_fill = 0, t_wfault = 0;
  logic t_logged = 0;
  initial begin string tf; if ($value$plusargs("TLBLOG=%s", tf)) tfd = $fopen(tf, "w"); end
  always @(posedge clk) if (!reset) begin
    if (dut.dmmu.Translate && dut.dmmu.Access && dut.dmmu.WState == 0 && !t_logged && !dut.InterruptM) begin
      t_acc++; if (!dut.dmmu.CAMHit) t_miss++;
      if (tfd) $fwrite(tfd, "ACC %08h %s\n", dut.IEUAdrM, dut.dmmu.CAMHit ? "HIT" : "MISS");
      t_logged = 1;
    end
    if (dut.dmmu.TLBWrite) begin
      t_fill++;
      if (tfd) $fwrite(tfd, "FILL %08h %0d %0d\n", dut.IEUAdrM, $clog2(dut.dmmu.Victim), dut.dmmu.WState == 1);
    end
    if (dut.dmmu.EvWalkFault) t_wfault++;
    if (dut.dmmu.SfenceVmaM && tfd) $fwrite(tfd, "SFENCE\n");
    if (!dut.StallM || dut.TrapM) t_logged = 0;      // the instruction leaves M (or traps)
  end
  // ---- Ch 13: branch predictor counters (Wally's performance counters, book 8.4.3.1) ----
  //   counted when the instruction commits (leaves Memory without trapping)
  int unsigned bp_br = 0, bp_jmp = 0, bp_ret = 0, bp_wrong = 0, bp_wbr = 0, bp_wjmp = 0, bp_wret = 0, bp_wnon = 0, bp_wdir = 0;
  logic bpw_m;   // the instruction now in M caused a misprediction flush when it was in E
  always @(posedge clk) if (reset) bpw_m <= 0; else if (!dut.StallM) bpw_m <= dut.BPWrongE & !dut.FlushM;
  always @(posedge clk) if (!reset && dut.CommitM) begin
    if (dut.ClassM == 1) bp_br++;
    if (dut.ClassM == 2 || dut.ClassM == 3) bp_jmp++;
    if (dut.ClassM == 4) bp_ret++;
    if (dut.ClassM == 1 && dut.BP_TYPE >= 2 && dut.BPDirM[1] != dut.PCSrcM) bp_wdir++;
    if (bpw_m) begin
      bp_wrong++;
      case (dut.ClassM) 1: bp_wbr++; 2, 3: bp_wjmp++; 4: bp_wret++; default: bp_wnon++; endcase
    end
  end
  // a bus that never answers must fail fast with a clear message, not just time out
  int unsigned busy_run = 0;
  always @(posedge clk) if (!reset) begin
    busy_run = (HREADY) ? 0 : busy_run + 1;
    if (busy_run == 64) begin $display("FAIL: AHB hang: HREADY low for 64 cycles, HADDR=%08h", HADDR); finish(4); end
  end
`else
  core_single dut(.*);
`endif

  // ---------------- run control and trace ----------------
  string hexfile, tracefile;
  int    fd = 0, maxcycles = 100000, cycles = 0, retired = 0;

  function automatic logic [31:0] maskbytes(input logic [31:0] d, input logic [3:0] m);
    for (int b = 0; b < 4; b++) if (!m[b]) d[8*b +: 8] = 8'h00;
    return d;
  endfunction

  initial begin
    if (!$value$plusargs("HEX=%s", hexfile)) begin $display("need +HEX=<file>"); $finish; end
    void'($value$plusargs("MAXCYCLES=%d", maxcycles));
    for (int i = 0; i < WORDS; i++) mem[i] = 32'h0;
    $readmemh(hexfile, mem);
    if ($value$plusargs("TRACE=%s", tracefile)) fd = $fopen(tracefile, "w");
    if ($test$plusargs("VCD")) begin $dumpfile("wave.vcd"); $dumpvars(0, tb); end  // needs verilator --trace
    repeat (2) @(posedge clk);
    #1 reset = 0;
  end

  // Sample just before the rising edge, when the retiring instruction's values are stable.
  always @(negedge clk) if (!reset) begin
    cycles++;
    if (TraceValid) begin
      retired++;
      if (fd != 0) begin
        $fwrite(fd, "pc=%08h insn=%08h", TracePC, TraceInstr);
        if (TraceRegWrite) $fwrite(fd, " x%0d=%08h", TraceRd, TraceResult);
        if (TraceMemWrite) $fwrite(fd, " mem[%08h]=%08h/%1h", TraceMemAdr,
                                   maskbytes(TraceMemData, TraceMemMask), TraceMemMask);
`ifdef PIPELINE
        if (TraceCSRWrite) $fwrite(fd, " csr[%03h]=%08h", TraceCSRAdr, TraceCSRVal);
`endif
        $fwrite(fd, "\n");
      end
      if (TraceIllegal) begin
        $display("FAIL: illegal/unsupported instruction %08h at pc %08h", TraceInstr, TracePC);
        finish(2);
      end
      if (TraceMemWrite && TraceMemAdr == TOHOST) begin
        if (TraceMemData == 32'd1) begin $display("PASS: tohost=1 after %0d instructions, %0d cycles", retired, cycles); finish(0); end
        else begin $display("FAIL: tohost=%0d after %0d instructions", TraceMemData, retired); finish(1); end
      end
      if (TracePCNext == TracePC) begin
        $display("DONE: self-loop at pc %08h after %0d instructions, %0d cycles (CPI %0.2f)",
                 TracePC, retired, cycles, real'(cycles) / real'(retired));
        $display("      mem[100] = %0d", mem[25]);
        finish(0);
      end
    end
`ifdef PIPELINE
    // the trap is taken in M; the instruction in W (older) was written above, so order is right
    if (TraceTrap && fd != 0)
      $fwrite(fd, "trap pc=%08h cause=%08h tval=%08h\n", TraceTrapPC, TraceCause, TraceTval);
`endif
    if (cycles >= maxcycles) begin $display("FAIL: timeout after %0d cycles", cycles); finish(3); end
  end

`ifdef PIPELINE
  // +PIPEVIEW: one line per cycle showing what sits in each stage (dv/pipeview.py formats it)
  always @(negedge clk) if (!reset && $test$plusargs("PIPEVIEW"))
    $display("PV %0d %08h %08h %0d %08h %0d %08h %0d %08h %0d %08h %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %08h %0d %0d %0d",
      cycles, dut.PCF, dut.InstrF, dut.ValidD, dut.InstrD, dut.ValidE, dut.InstrE,
      dut.ValidM, dut.InstrM, dut.ValidW, dut.InstrW, 1,
      dut.StallD, dut.FlushD, dut.FlushE, dut.ForwardAE, dut.ForwardBE,
      dut.TrapM, dut.RetM, dut.CSRWriteFlushM, dut.CSRRdStallD, dut.CauseM,
      dut.bfsm.CurrState, dut.StallW, HREADY);
  // +CACHEVIEW: one line per cycle of the D-cache and its bus bursts (Ch 10 waveform figure)
  always @(negedge clk) if (!reset && $test$plusargs("CACHEVIEW"))
    $display("CV %0d %08h %08h %0d %0d %0d %0d %0d %08h %0d %0d %08h %08h %0d %0d %0d",
      cycles, dut.PCM, dut.InstrM, dut.ValidM, dut.dc.State, dut.dc.Hit, dut.dc.CacheStall, HTRANS, HADDR, HWRITE,
      HREADY, HWDATA, HRDATA, dut.dc.AdrBeat, dut.dc.DataBeat, dut.dc.CacheCommitted);
  // +LSUVIEW: one line per cycle of the D-cache's synchronous read path (Ch 12 waveform figure)
  always @(negedge clk) if (!reset && $test$plusargs("LSUVIEW"))
    $display("LV %0d %08h %0d %08h %0d %08h %08h %0d %0d %0d %0d %0d %0d %0d %0d %08h %0d %0d",
      cycles, dut.InstrE, dut.ValidE, dut.InstrM, dut.ValidM, dut.IEUAdrE, dut.IEUAdrM, dut.dc.SelAdr, dut.dc.RdSet,
      dut.dc.DataOutSet, dut.dc.DataOutOK, dut.dc.Hit, dut.dc.ArrayWrite, dut.dc.ReRead, dut.dc.State,
      dut.dc.ReadDataWord, dut.StallW, dut.dc.Set);
  // +BPVIEW: one line per cycle of the branch predictor and PC logic (Ch 13 waveform figure)
  always @(negedge clk) if (!reset && $test$plusargs("BPVIEW"))
    $display("BV2 %0d %08h %08h %0d %08h %0d %0d %08h %0d %08h %0d %0d %08h %08h %0d %0d %0d %08h %0d %0d %0d %0d %0d",
      cycles, dut.PCF, dut.PCNextF, dut.BPTakenF, dut.BPPCF, dut.BPClassF, dut.BPDirF,
      dut.PCD, dut.ValidD, dut.PCE, dut.ValidE, dut.PCSrcE, dut.PredNextE, dut.PCCorrectE, dut.BPWrongE,
      dut.FlushD, dut.FlushE, dut.PCM, dut.ValidM, dut.CommitM, dut.ClassM, dut.BPDirM, dut.PCSrcM);
  // +MMUVIEW: one line per cycle of the MMU, walker and LSU (Ch 11 waveform figure)
  always @(negedge clk) if (!reset && $test$plusargs("MMUVIEW"))
    $display("MV %0d %08h %08h %0d %08h %0d %0d %0d %08h %0d %0d %08h %08h %0d %0d %0d %0d %0d %08h %0d %0d",
      cycles, dut.PCM, dut.InstrM, dut.ValidM, dut.IEUAdrM, dut.dmmu.WState, dut.dmmu.CAMHit, dut.SelHPTW,
      dut.PAdrM, dut.bfsm.CurrState, HTRANS, HADDR, HRDATA, dut.StallW, dut.GatedStallW, dut.dmmu.TLBWrite,
      dut.dmmu.MMUStall, dut.dmmu.BlockAccess, dut.ReadDataWordM, dut.TrapM, dut.dmmu.Translate);
  // +BUSVIEW: one line per cycle of the LSU bus interface (used for the Ch 9 waveform figure)
  always @(negedge clk) if (!reset && $test$plusargs("BUSVIEW"))
    $display("BV %0d %08h %08h %0d %0d %0d %08h %0d %0d %08h %0d %0d %0d %0d %0d %0d",
      cycles, dut.PCM, dut.InstrM, dut.ValidM, dut.bfsm.CurrState, HTRANS, HADDR, HWRITE, HREADY, HRDATA,
      dut.StallW, dut.BusCommittedM, (|dut.pu.ValidIntsM), dut.TrapM, unc.br.State, dut.PCF == dut.PCNextF);
`endif

  task automatic finish(input int code);
`ifdef PIPELINE
    $display("BUSSTATS xfers=%0d stall_cycles=%0d irq_deferred_cycles=%0d", bus_xfers, bus_stall_cycles, irq_deferred);
    $display("CACHESTATS accesses=%0d misses=%0d writebacks=%0d flush_writebacks=%0d rereads=%0d", c_acc, c_miss, c_wb, c_fwb, c_reread);
    $display("BPSTATS branches=%0d jumps=%0d returns=%0d flushes=%0d br_wrong=%0d jmp_wrong=%0d ret_wrong=%0d noncfi_wrong=%0d dir_wrong=%0d",
             bp_br, bp_jmp, bp_ret, bp_wrong, bp_wbr, bp_wjmp, bp_wret, bp_wnon, bp_wdir);
    $display("TLBSTATS lookups=%0d misses=%0d fills=%0d walk_faults=%0d", t_acc, t_miss, t_fill, t_wfault);
    if (tfd) $fclose(tfd);
    if (cfd) $fclose(cfd);
    // +RAMDUMP=<file>: every nonzero word of the bus RAM, for an end-of-test memory-image compare
    begin string rf; int rfd;
      if ($value$plusargs("RAMDUMP=%s", rf)) begin
        rfd = $fopen(rf, "w");
        for (int i = 0; i < 16384; i++) if (unc.ram.mem[i] != 0) $fwrite(rfd, "%04x %08x\n", i * 4, unc.ram.mem[i]);
        $fclose(rfd);
      end
    end
`endif
    if (fd != 0) $fclose(fd);
    $finish;
  endtask
endmodule
