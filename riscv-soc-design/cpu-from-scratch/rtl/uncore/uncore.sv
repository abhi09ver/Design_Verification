// uncore.sv -- Lab 6 (book Ch 9): an AHB uncore with an APB bridge, modelled on Wally's
// src/uncore (uncore.sv, ram_ahb.sv, ahbapbbridge.sv, gpio_apb.sv, clint_apb.sv).
//
// Memory map of the bus (everything else the core keeps in its own IROM/DTIM):
//   0x9000_0000 - 0x9000_FFFF   RAM  (ram_ahb, single-port synchronous SRAM, WAIT extra cycles)
//   0x9100_0000 - 0x9100_FFFF   the same RAM again (Ch 10: the core caches 0x9000, not 0x9100)
//   0x1000_0000 - 0x10FF_FFFF   AHB-to-APB bridge, which decodes:
//        0x1000_0000  RXFIFO  a UART-like receive register: every read pops (side effect!)
//        0x1006_0000  GPIO    OUT +0, EN +4, IN +8 (book Example 9.1; Wally's GPIO base)
//        0x1020_0000  CLINT   msip +0, mtimecmp lo +4 / hi +8, mtime lo +C, ext-int +10
//                             (Wally's CLINT is at 0x0200_0000; here it sits behind the
//                              bridge so one decode range covers all APB devices)
//   anything else               default subordinate: HREADY = 1, HRDATA = 0
//
// Deliberate-bug switches:
//   BUG_HSEL_NOT_DELAYED  read/ready mux uses HSEL (Address phase) instead of HSELD (Data phase)
//   BUG_DEFAULT_HANG      default subordinate never completes a transfer to an unmapped address
//   BUG_RAM_NO_RAW_WAIT   SRAM forgets the wait state for a write followed directly by a read
//   BUG_APB_EARLY_WDATA   bridge drives PWDATA from the Address phase instead of the Data phase

module uncore #(parameter int RAM_WAIT = 0) (
  input  logic        clk, reset,
  // AHB from the manager (the core's LSU, or the random manager in tb_ahb.sv)
  input  logic [31:0] HADDR,
  input  logic        HWRITE,
  input  logic [1:0]  HTRANS,
  input  logic [2:0]  HSIZE,
  input  logic [31:0] HWDATA,
  input  logic [3:0]  HWSTRB,
  output logic        HREADY,
  output logic [31:0] HRDATA,
  // pads and interrupt lines
  input  logic [31:0] GPIOIN,
  output logic [31:0] GPIOOUT, GPIOEN,
  output logic        MTimerInt, MSwInt, MExtInt
);
  // ---------------- address decoder (Wally adrdecs) ----------------
  logic [2:0] HSEL, HSELD;            // [0] none (default subordinate), [1] RAM, [2] APB bridge
  assign HSEL[1] = (HADDR[31:16] == 16'h9000) | (HADDR[31:16] == 16'h9100);   // 0x9100: same RAM (uncached alias, Ch 10)
  assign HSEL[2] = (HADDR[31:24] == 8'h10);
  assign HSEL[0] = ~(HSEL[1] | HSEL[2]);
  // HSELD: who owns the Data phase. Advances only when the current Data phase ends.
  // Reset to the default subordinate so HREADY starts high (book Example 9.2 note).
  always_ff @(posedge clk)
    if (reset)       HSELD <= 3'b001;
    else if (HREADY) HSELD <= HSEL;

  // ---------------- subordinates ----------------
  logic        RamReady, BridgeReady, DefReady;
  logic [31:0] RamRData, BridgeRData;

  ram_ahb #(.WAIT(RAM_WAIT)) ram(.clk, .reset, .HSEL(HSEL[1]), .HADDR, .HWRITE, .HTRANS,
                                 .HWDATA, .HWSTRB, .HREADY, .HREADYOUT(RamReady), .HRDATA(RamRData));

  logic [3:1]  PSEL;
  logic        PENABLE, PWRITE;
  logic [31:0] PADDR, PWDATA, PRDATA1, PRDATA2, PRDATA3;
  logic [3:0]  PSTRB;
  logic        PREADY1, PREADY2, PREADY3;
  ahbapbbridge br(.clk, .reset, .HSEL(HSEL[2]), .HADDR, .HWRITE, .HTRANS, .HWDATA, .HWSTRB, .HREADY,
                  .HREADYOUT(BridgeReady), .HRDATA(BridgeRData),
                  .PSEL, .PENABLE, .PWRITE, .PADDR, .PWDATA, .PSTRB,
                  .PRDATA1, .PRDATA2, .PRDATA3, .PREADY1, .PREADY2, .PREADY3);
  gpio_apb   gpio (.clk, .reset, .PSEL(PSEL[1]), .PENABLE, .PWRITE, .PADDR, .PWDATA, .PSTRB,
                   .PRDATA(PRDATA1), .PREADY(PREADY1), .GPIOIN, .GPIOOUT, .GPIOEN);
  rxfifo_apb fifo (.clk, .reset, .PSEL(PSEL[2]), .PENABLE, .PWRITE, .PADDR, .PWDATA,
                   .PRDATA(PRDATA2), .PREADY(PREADY2));
  clint_apb  clint(.clk, .reset, .PSEL(PSEL[3]), .PENABLE, .PWRITE, .PADDR, .PWDATA, .PSTRB,
                   .PRDATA(PRDATA3), .PREADY(PREADY3), .MTimerInt, .MSwInt, .MExtInt);

  // default subordinate: answers a transfer to an unmapped address in one cycle
  logic DefActive;
  always_ff @(posedge clk)
    if (reset) DefActive <= 1'b0;
`ifdef BUG_DEFAULT_HANG
    else if (HSEL[0] & HTRANS[1] & HREADY) DefActive <= 1'b1;     // BUG: never finishes
`else
    else       DefActive <= HSEL[0] & HTRANS[1] & HREADY;
`endif
`ifdef BUG_DEFAULT_HANG
  assign DefReady = ~DefActive;
`else
  assign DefReady = 1'b1;
`endif

  // ---------------- response mux (Wally: AND-OR mux selected by HSELD) ----------------
  logic [2:0] MuxSel;
`ifdef BUG_HSEL_NOT_DELAYED
  assign MuxSel = HSEL;               // BUG: whoever owns the ADDRESS phase, not the Data phase
`else
  assign MuxSel = HSELD;
`endif
  assign HREADY = MuxSel[1] ? RamReady : MuxSel[2] ? BridgeReady : DefReady;
  assign HRDATA = MuxSel[1] ? RamRData : MuxSel[2] ? BridgeRData : 32'h0;
endmodule

// ---------------------------------------------------------------------------
// ram_ahb: single-port synchronous SRAM behind AHB (book Fig. 9.13)
//   * reads use the live HADDR at the end of the Address phase (data appears in Data phase)
//   * writes use the delayed HADDRD at the end of the Data phase (HWDATA arrives late)
//   * a write followed immediately by a read wants the one port twice on the same edge,
//     so insert ONE wait state for that case only
//   * WAIT adds extra Data-phase cycles to every access (a slow memory)
// ---------------------------------------------------------------------------
module ram_ahb #(parameter int WORDS = 16384, parameter int WAIT = 0) (
  input  logic        clk, reset, HSEL,
  input  logic [31:0] HADDR,
  input  logic        HWRITE,
  input  logic [1:0]  HTRANS,
  input  logic [31:0] HWDATA,
  input  logic [3:0]  HWSTRB,
  input  logic        HREADY,
  output logic        HREADYOUT,
  output logic [31:0] HRDATA
);
  logic [31:0] mem [0:WORDS-1];
  initial for (int i = 0; i < WORDS; i++) mem[i] = 32'h0;

  logic        initTrans, Active, IsWrite, WriteDone, WritingNow, Conflict;
  logic [31:0] HADDRD, RdReg;
  int          Cnt;
  assign initTrans  = HSEL & HTRANS[1] & HREADY;
  assign WritingNow = Active & IsWrite & (Cnt == 0) & ~WriteDone;      // port busy writing on this edge
`ifdef BUG_RAM_NO_RAW_WAIT
  assign Conflict   = 1'b0;
`else
  assign Conflict   = WritingNow & HSEL & HTRANS[1] & ~HWRITE;          // a read waits in the Address phase
`endif
  assign HREADYOUT  = ~Active | ((Cnt == 0) & ~Conflict);
  assign HRDATA     = RdReg;

  always_ff @(posedge clk)
    if (reset) begin
      Active <= 1'b0; IsWrite <= 1'b0; WriteDone <= 1'b0; Cnt <= 0; HADDRD <= '0; RdReg <= '0;
    end else begin
      if (Active & Cnt > 0) Cnt <= Cnt - 1;
      if (WritingNow) begin                                            // the one port writes
        for (int b = 0; b < 4; b++)
          if (HWSTRB[b]) mem[HADDRD[15:2]][8*b +: 8] <= HWDATA[8*b +: 8];
        WriteDone <= 1'b1;
      end
      if (HREADYOUT) Active <= 1'b0;                                   // Data phase ends
      if (initTrans) begin                                             // next Address phase accepted
        Active <= 1'b1; IsWrite <= HWRITE; HADDRD <= HADDR; Cnt <= WAIT; WriteDone <= 1'b0;
        // the port reads now -- unless it is busy writing (only possible with the bug)
        if (!HWRITE) RdReg <= WritingNow ? mem[HADDRD[15:2]] : mem[HADDR[15:2]];
      end
    end
endmodule

// ---------------------------------------------------------------------------
// ahbapbbridge: AHB subordinate on one side, APB requester on the other (book Fig. 9.14)
// Every APB transfer is Setup then Access (until PREADY); the AHB Data phase waits for it.
// PWDATA/PSTRB come straight from HWDATA/HWSTRB, which are valid during the Data phase.
// ---------------------------------------------------------------------------
module ahbapbbridge (
  input  logic        clk, reset, HSEL,
  input  logic [31:0] HADDR,
  input  logic        HWRITE,
  input  logic [1:0]  HTRANS,
  input  logic [31:0] HWDATA,
  input  logic [3:0]  HWSTRB,
  input  logic        HREADY,
  output logic        HREADYOUT,
  output logic [31:0] HRDATA,
  output logic [3:1]  PSEL,
  output logic        PENABLE, PWRITE,
  output logic [31:0] PADDR, PWDATA,
  output logic [3:0]  PSTRB,
  input  logic [31:0] PRDATA1, PRDATA2, PRDATA3,
  input  logic        PREADY1, PREADY2, PREADY3
);
  localparam logic [1:0] IDLE = 2'd0, SETUP = 2'd1, ACCESS = 2'd2;
  logic [1:0]  State;
  logic        initTrans, WriteR, PREADY;
  logic [31:0] AddrR, EarlyWData;
  logic [3:0]  EarlyStrb;
  logic [3:1]  Sel;
  assign initTrans = HSEL & HTRANS[1] & HREADY;

  always_ff @(posedge clk)
    if (reset) begin State <= IDLE; AddrR <= '0; WriteR <= 1'b0; EarlyWData <= '0; EarlyStrb <= '0; end
    else begin
      case (State)
        IDLE:    if (initTrans) State <= SETUP;
        SETUP:   State <= ACCESS;
        ACCESS:  if (PREADY) State <= initTrans ? SETUP : IDLE;
        default: State <= IDLE;
      endcase
      if (initTrans) begin
        AddrR <= HADDR; WriteR <= HWRITE;
        EarlyWData <= HWDATA; EarlyStrb <= HWSTRB;    // what is on HWDATA during the ADDRESS phase
      end
    end

  // APB decode on the registered address
  assign Sel[1] = (AddrR[23:16] == 8'h06);           // GPIO
  assign Sel[2] = (AddrR[23:16] == 8'h00);           // RXFIFO
  assign Sel[3] = (AddrR[23:16] == 8'h20);           // CLINT
  assign PSEL    = (State == SETUP | State == ACCESS) ? Sel : 3'b000;
  assign PENABLE = (State == ACCESS);
  assign PWRITE  = WriteR;
  assign PADDR   = AddrR;
`ifdef BUG_APB_EARLY_WDATA
  assign PWDATA  = EarlyWData;                       // BUG: data from the wrong phase
  assign PSTRB   = EarlyStrb;
`else
  assign PWDATA  = HWDATA;
  assign PSTRB   = HWSTRB;
`endif
  // APB mux; with no device selected, PREADY = 1 so the bus cannot hang
  assign PREADY  = Sel[1] ? PREADY1 : Sel[2] ? PREADY2 : Sel[3] ? PREADY3 : 1'b1;
  assign HRDATA  = Sel[1] ? PRDATA1 : Sel[2] ? PRDATA2 : Sel[3] ? PRDATA3 : 32'h0;
  assign HREADYOUT = (State == IDLE) | ((State == ACCESS) & PREADY);
endmodule

// ---------------------------------------------------------------------------
// gpio_apb (book Example 9.1, plus byte strobes). The pads' tristates live in the testbench.
// ---------------------------------------------------------------------------
module gpio_apb (
  input  logic        clk, reset, PSEL, PENABLE, PWRITE,
  input  logic [31:0] PADDR, PWDATA,
  input  logic [3:0]  PSTRB,
  output logic [31:0] PRDATA,
  output logic        PREADY,
  input  logic [31:0] GPIOIN,
  output logic [31:0] GPIOOUT, GPIOEN
);
  logic Wr;
  assign PREADY = 1'b1;                               // never waits
  assign Wr     = PSEL & PENABLE & PWRITE;
  always_ff @(posedge clk)
    if (reset) begin GPIOOUT <= '0; GPIOEN <= '0; end
    else if (Wr)
      for (int b = 0; b < 4; b++) if (PSTRB[b])
        case (PADDR[3:2])
          2'd0: GPIOOUT[8*b +: 8] <= PWDATA[8*b +: 8];
          2'd1: GPIOEN [8*b +: 8] <= PWDATA[8*b +: 8];
          default: ;                                  // GPIOIN is read-only
        endcase
  always_comb
    case (PADDR[3:2])
      2'd0:    PRDATA = GPIOOUT;
      2'd1:    PRDATA = GPIOEN;
      2'd2:    PRDATA = GPIOIN;
      default: PRDATA = 32'h0;
    endcase
endmodule

// ---------------------------------------------------------------------------
// rxfifo_apb: stands in for a UART receive buffer register (book 9.5.5 margin note).
// Reading it POPS: the next read returns the next value. Such a read has a side effect,
// so it must happen exactly once per load instruction. One wait state per access.
// ---------------------------------------------------------------------------
module rxfifo_apb (
  input  logic        clk, reset, PSEL, PENABLE, PWRITE,
  input  logic [31:0] PADDR, PWDATA,
  output logic [31:0] PRDATA,
  output logic        PREADY
);
  logic [31:0] Head;
  logic        Waited;
  assign PREADY = Waited;
  assign PRDATA = Head;
  always_ff @(posedge clk)
    if (reset) begin Head <= 32'h100; Waited <= 1'b0; end
    else begin
      Waited <= PSEL & PENABLE & ~Waited;
      if (PSEL & PENABLE & PREADY) begin
        if (PWRITE) Head <= PWDATA;                   // write sets the next value (for tests)
        else        Head <= Head + 32'd1;             // read pops
      end
    end
endmodule

// ---------------------------------------------------------------------------
// clint_apb: machine timer and software interrupt (Wally clint_apb.sv, cut down)
// ---------------------------------------------------------------------------
module clint_apb (
  input  logic        clk, reset, PSEL, PENABLE, PWRITE,
  input  logic [31:0] PADDR, PWDATA,
  input  logic [3:0]  PSTRB,
  output logic [31:0] PRDATA,
  output logic        PREADY,
  output logic        MTimerInt, MSwInt, MExtInt
);
  logic [63:0] MTIME, MTIMECMP;
  logic        MSIP, MEXT;
  assign PREADY = 1'b1;
  always_ff @(posedge clk)
    if (reset) begin MTIME <= '0; MTIMECMP <= '1; MSIP <= 1'b0; MEXT <= 1'b0; end
    else begin
      MTIME <= MTIME + 64'd1;
      if (PSEL & PENABLE & PWRITE)
        case (PADDR[4:2])
          3'd0: if (PSTRB[0]) MSIP <= PWDATA[0];
          3'd1: MTIMECMP[31:0]  <= PWDATA;
          3'd2: MTIMECMP[63:32] <= PWDATA;
          3'd4: if (PSTRB[0]) MEXT <= PWDATA[0];
          default: ;
        endcase
    end
  always_comb
    case (PADDR[4:2])
      3'd0:    PRDATA = {31'b0, MSIP};
      3'd1:    PRDATA = MTIMECMP[31:0];
      3'd2:    PRDATA = MTIMECMP[63:32];
      3'd3:    PRDATA = MTIME[31:0];
      3'd4:    PRDATA = {31'b0, MEXT};
      default: PRDATA = 32'h0;
    endcase
  assign MTimerInt = (MTIME >= MTIMECMP);
  assign MSwInt    = MSIP;
  assign MExtInt   = MEXT;
endmodule
