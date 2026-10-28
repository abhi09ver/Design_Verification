// periph.sv -- Lab 11 (book Ch 20): the five Wally peripherals behind one APB port.
//
//   0x0200_0000  CLINT  msip +0, mtimecmp +4000/+4004, mtime +BFF8/+BFFC       (Table 20.2)
//   0x0C00_0000  PLIC   priority 4*i, pending +1000, enable +2000/+2080,
//                       threshold/claim +20_0000/+20_0004 (ctx 0 = M), +20_1000/+20_1004 (ctx 1 = S)
//   0x1000_0000  UART   PC16550D: RBR/THR/DLL 0, IER/DLM 1, IIR/FCR 2, LCR 3, MCR 4, LSR 5, MSR 6, SCR 7
//   0x1004_0000  SPI    SiFive FU540 subset (Table 20.4)
//   0x1006_0000  GPIO   SiFive FE310 (Table 20.1, no pue/ds/iof)
//
// RV32 view: every register is 32 bits wide; 64-bit CLINT registers are two words.
// PLIC sources: 3 = GPIO, 6 = SPI, 10 = UART (book's config.vh IDs); every other source 1..31
// comes from the ExtSrc input so a testbench can drive arbitrary interrupt patterns.
//
// Deliberate-bug switches (`define one of them):
//   GPIO   BUG_GPIO_NOT_STICKY       *_ip follows the condition instead of holding it
//          BUG_GPIO_W1C_ALL          a write to an *_ip register clears every bit, not just the 1s
//          BUG_GPIO_NO_SYNC          pins go straight to input_val/edge logic (no 2-flop synchronizer)
//   CLINT  BUG_CLINT_GT              timer interrupt when mtime > mtimecmp (spec: >=)
//          BUG_CLINT_NO_CARRY        mtime[63:32] does not increment when mtime[31:0] wraps
//   PLIC   BUG_PLIC_TIE_HIGH_ID      equal priorities pick the HIGHEST id (spec: lowest)
//          BUG_PLIC_THRESH_GE        interrupt when priority >= threshold (spec: >)
//          BUG_PLIC_NO_GATEWAY       a claimed source can become pending again before completion
//   UART   BUG_UART_PARITY_INV       even and odd parity swapped (in TX and RX alike)
//          BUG_UART_SAMPLE_EARLY     RX samples each bit at 1/16 of the bit instead of the middle
//          BUG_UART_NO_OVERRUN       a character arriving at a full RX FIFO overwrites the newest, no OE
//   SPI    BUG_SPI_IGNORE_PHASE      sckmode.pha ignored (always phase 0), in TX and RX alike
//          BUG_SPI_IGNORE_ENDIAN     fmt.endian ignored (always MSB first)
//          BUG_SPI_TXWM_LE           tx watermark pending when count <= txmark (spec: <)

module periph (
  input  logic        clk, reset,
  input  logic        PSEL, PENABLE, PWRITE,
  input  logic [31:0] PADDR, PWDATA,
  output logic [31:0] PRDATA,
  output logic        PREADY,
  // pads
  input  logic [31:0] GPIOPinsIn,
  output logic [31:0] GPIOPinsOut, GPIOPinsEn,
  input  logic        UARTSin,
  output logic        UARTSout,
  input  logic        SPIIn,
  output logic        SPIOut, SPISck,
  output logic [3:0]  SPICS,
  input  logic [31:0] ExtSrc,                 // extra PLIC sources (bits 3, 6, 10 and 0 unused)
  // to the hart
  output logic        MTimerInt, MSwInt, MExtInt, SExtInt,
  output logic        GPIOIntr, UARTIntr, SPIIntr
);
  logic [4:0]  sel;                           // 0 CLINT, 1 PLIC, 2 UART, 3 SPI, 4 GPIO
  logic [31:0] rd [5];
  assign sel[0] = PADDR[31:16] == 16'h0200;
  assign sel[1] = PADDR[31:24] == 8'h0C;
  assign sel[2] = PADDR[31:16] == 16'h1000;
  assign sel[3] = PADDR[31:16] == 16'h1004;
  assign sel[4] = PADDR[31:16] == 16'h1006;
  assign PREADY = 1'b1;
  always_comb begin
    PRDATA = 32'h0;
    for (int i = 0; i < 5; i++) if (sel[i]) PRDATA = rd[i];
  end

  logic [31:0] Src;
  always_comb begin
    Src = ExtSrc;
    Src[0] = 1'b0; Src[3] = GPIOIntr; Src[6] = SPIIntr; Src[10] = UARTIntr;
  end

  clint_apb20 clint(.clk, .reset, .PSEL(PSEL & sel[0]), .PENABLE, .PWRITE, .PADDR(PADDR[15:0]), .PWDATA,
                    .PRDATA(rd[0]), .MTimerInt, .MSwInt);
  plic_apb20  plic (.clk, .reset, .PSEL(PSEL & sel[1]), .PENABLE, .PWRITE, .PADDR(PADDR[23:0]), .PWDATA,
                    .PRDATA(rd[1]), .Src, .MExtInt, .SExtInt);
  uart_apb20  uart (.clk, .reset, .PSEL(PSEL & sel[2]), .PENABLE, .PWRITE, .PADDR(PADDR[2:0]), .PWDATA,
                    .PRDATA(rd[2]), .Sin(UARTSin), .Sout(UARTSout), .Intr(UARTIntr));
  spi_apb20   spi  (.clk, .reset, .PSEL(PSEL & sel[3]), .PENABLE, .PWRITE, .PADDR(PADDR[7:0]), .PWDATA,
                    .PRDATA(rd[3]), .SDI(SPIIn), .SDO(SPIOut), .SCK(SPISck), .CS(SPICS), .Intr(SPIIntr));
  gpio_apb20  gpio (.clk, .reset, .PSEL(PSEL & sel[4]), .PENABLE, .PWRITE, .PADDR(PADDR[7:0]), .PWDATA,
                    .PRDATA(rd[4]), .PinsIn(GPIOPinsIn), .PinsOut(GPIOPinsOut), .PinsEn(GPIOPinsEn),
                    .Intr(GPIOIntr));
endmodule

// ===========================================================================
// GPIO (book Fig. 20.4 / 20.5)
// ===========================================================================
module gpio_apb20 (
  input  logic        clk, reset, PSEL, PENABLE, PWRITE,
  input  logic [7:0]  PADDR,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  input  logic [31:0] PinsIn,
  output logic [31:0] PinsOut, PinsEn,
  output logic        Intr
);
  logic [31:0] input_en, output_en, output_val, out_xor;
  logic [31:0] rise_ie, rise_ip, fall_ie, fall_ip, high_ie, high_ip, low_ie, low_ip;
  logic [31:0] in0, in1, in2, in3, input_val;
  logic        we;
  assign we = PSEL & PENABLE & PWRITE;

  // pin input: gated by input_en, then a 2-flop synchronizer, then one more register for edges
  assign in0 = PinsIn & input_en;
  always_ff @(posedge clk)
    if (reset) {in1, in2, in3} <= '0;
    else begin in1 <= in0; in2 <= in1; in3 <= in2; end
`ifdef BUG_GPIO_NO_SYNC
  logic [31:0] cur, prev;                     // BUG: asynchronous pins used directly
  assign cur = in0;
  always_ff @(posedge clk) prev <= reset ? '0 : in0;
`else
  logic [31:0] cur, prev;
  assign cur = in2; assign prev = in3;
`endif
  assign input_val = cur;

  logic [31:0] rise_c, fall_c, high_c, low_c;
  assign rise_c = cur & ~prev;
  assign fall_c = ~cur & prev;
  assign high_c = cur;
  assign low_c  = ~cur;

  // Fig. 20.5: pending bits are sticky; writing a 1 clears that bit. A condition in the same
  // cycle as the clearing write wins (the event is not lost).
  function automatic logic [31:0] nextip(logic [31:0] ip, logic [31:0] cond, logic wr);
`ifdef BUG_GPIO_NOT_STICKY
    return cond;
`elsif BUG_GPIO_W1C_ALL
    return (wr ? 32'h0 : ip) | cond;
`else
    return (wr ? (ip & ~PWDATA) : ip) | cond;
`endif
  endfunction

  always_ff @(posedge clk)
    if (reset) begin
      {input_en, output_en, output_val, out_xor} <= '0;
      {rise_ie, rise_ip, fall_ie, fall_ip, high_ie, high_ip, low_ie, low_ip} <= '0;
    end else begin
      if (we)
        case (PADDR)
          8'h04: input_en   <= PWDATA;
          8'h08: output_en  <= PWDATA;
          8'h0C: output_val <= PWDATA;
          8'h18: rise_ie    <= PWDATA;
          8'h20: fall_ie    <= PWDATA;
          8'h28: high_ie    <= PWDATA;
          8'h30: low_ie     <= PWDATA;
          8'h40: out_xor    <= PWDATA;
          default: ;
        endcase
      rise_ip <= nextip(rise_ip, rise_c, we & PADDR == 8'h1C);
      fall_ip <= nextip(fall_ip, fall_c, we & PADDR == 8'h24);
      high_ip <= nextip(high_ip, high_c, we & PADDR == 8'h2C);
      low_ip  <= nextip(low_ip,  low_c,  we & PADDR == 8'h34);
    end

  always_comb
    case (PADDR)
      8'h00: PRDATA = input_val;
      8'h04: PRDATA = input_en;
      8'h08: PRDATA = output_en;
      8'h0C: PRDATA = output_val;
      8'h18: PRDATA = rise_ie;  8'h1C: PRDATA = rise_ip;
      8'h20: PRDATA = fall_ie;  8'h24: PRDATA = fall_ip;
      8'h28: PRDATA = high_ie;  8'h2C: PRDATA = high_ip;
      8'h30: PRDATA = low_ie;   8'h34: PRDATA = low_ip;
      8'h40: PRDATA = out_xor;
      default: PRDATA = 32'h0;
    endcase

  assign PinsOut = output_val ^ out_xor;
  assign PinsEn  = output_en;
  assign Intr    = |((rise_ip & rise_ie) | (fall_ip & fall_ie) | (high_ip & high_ie) | (low_ip & low_ie));
endmodule

// ===========================================================================
// CLINT (book Fig. 20.7), RV32 view
// ===========================================================================
module clint_apb20 (
  input  logic        clk, reset, PSEL, PENABLE, PWRITE,
  input  logic [15:0] PADDR,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  output logic        MTimerInt, MSwInt
);
  logic [63:0] mtime, mtimecmp;
  logic        msip, we;
  assign we = PSEL & PENABLE & PWRITE;
  always_ff @(posedge clk)
    if (reset) begin mtime <= '0; mtimecmp <= '1; msip <= 1'b0; end
    else begin
      // mtime counts every cycle unless that half is being written
      if (we & PADDR == 16'hBFF8)      mtime[31:0]  <= PWDATA;
      else if (we & PADDR == 16'hBFFC) mtime[63:32] <= PWDATA;
      else begin
`ifdef BUG_CLINT_NO_CARRY
        mtime[31:0] <= mtime[31:0] + 1;      // BUG: two 32-bit counters, no carry between them
`else
        mtime <= mtime + 64'd1;
`endif
      end
      if (we & PADDR == 16'h0000) msip <= PWDATA[0];
      if (we & PADDR == 16'h4000) mtimecmp[31:0]  <= PWDATA;
      if (we & PADDR == 16'h4004) mtimecmp[63:32] <= PWDATA;
    end
  always_comb
    case (PADDR)
      16'h0000: PRDATA = {31'b0, msip};
      16'h4000: PRDATA = mtimecmp[31:0];
      16'h4004: PRDATA = mtimecmp[63:32];
      16'hBFF8: PRDATA = mtime[31:0];
      16'hBFFC: PRDATA = mtime[63:32];
      default:  PRDATA = 32'h0;
    endcase
`ifdef BUG_CLINT_GT
  assign MTimerInt = mtime > mtimecmp;
`else
  assign MTimerInt = mtime >= mtimecmp;
`endif
  assign MSwInt = msip;
endmodule

// ===========================================================================
// PLIC: 31 sources, 2 contexts (0 = M, 1 = S), 3-bit priorities (book 20.3.3)
// ===========================================================================
module plic_apb20 (
  input  logic        clk, reset, PSEL, PENABLE, PWRITE,
  input  logic [23:0] PADDR,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  input  logic [31:0] Src,
  output logic        MExtInt, SExtInt
);
  logic [2:0]  prio [32];
  logic [31:0] pending, inprog, en [2];
  logic [2:0]  thresh [2];
  logic [4:0]  best [2];
  logic [2:0]  bestp [2];
  logic        we, re;
  assign we = PSEL & PENABLE & PWRITE;
  assign re = PSEL & PENABLE & ~PWRITE;

  // which context's claim/complete register is addressed
  logic       claimAdr;
  logic       ctx;
  assign claimAdr = (PADDR[23:13] == 11'h100) & (PADDR[11:0] == 12'h004);   // 0x20_0004 / 0x20_1004
  assign ctx      = PADDR[12];

  // per context: highest priority pending & enabled source; ties go to the lowest id
  always_comb
    for (int c = 0; c < 2; c++) begin
      best[c] = 5'd0; bestp[c] = 3'd0;
      for (int i = 1; i < 32; i++)
        if (pending[i] & en[c][i] & (prio[i] != 0))
`ifdef BUG_PLIC_TIE_HIGH_ID
          if (prio[i] >= bestp[c]) begin best[c] = i[4:0]; bestp[c] = prio[i]; end
`else
          if (prio[i] >  bestp[c]) begin best[c] = i[4:0]; bestp[c] = prio[i]; end
`endif
    end
`ifdef BUG_PLIC_THRESH_GE
  assign MExtInt = (best[0] != 0) & (bestp[0] >= thresh[0]);
  assign SExtInt = (best[1] != 0) & (bestp[1] >= thresh[1]);
`else
  assign MExtInt = (best[0] != 0) & (bestp[0] >  thresh[0]);
  assign SExtInt = (best[1] != 0) & (bestp[1] >  thresh[1]);
`endif

  // gateway: a level request becomes pending unless that source is in progress (claimed and
  // not yet completed). A claim clears pending and sets in-progress; a completion clears it.
  logic [31:0] claimNow, complNow;
  always_comb begin
    claimNow = '0; complNow = '0;
    if (re & claimAdr & best[ctx] != 0) claimNow[best[ctx]] = 1'b1;
    if (we & claimAdr & PWDATA[31:5] == 0 & en[ctx][PWDATA[4:0]]) complNow[PWDATA[4:0]] = 1'b1;
  end
  always_ff @(posedge clk)
    if (reset) begin
      pending <= '0; inprog <= '0; en[0] <= '0; en[1] <= '0; thresh[0] <= '0; thresh[1] <= '0;
      for (int i = 0; i < 32; i++) prio[i] <= '0;
    end else begin
`ifdef BUG_PLIC_NO_GATEWAY
      pending <= ((pending | Src) & ~claimNow) & ~32'h1;
`else
      pending <= ((pending | (Src & ~inprog)) & ~claimNow) & ~32'h1;
`endif
      inprog  <= (inprog | claimNow) & ~complNow;
      if (we) begin
        if (PADDR < 24'h000080 & PADDR[1:0] == 0 & PADDR[6:2] != 0) prio[PADDR[6:2]] <= PWDATA[2:0];
        if (PADDR == 24'h002000) en[0] <= PWDATA & ~32'h1;
        if (PADDR == 24'h002080) en[1] <= PWDATA & ~32'h1;
        if (PADDR == 24'h200000) thresh[0] <= PWDATA[2:0];
        if (PADDR == 24'h201000) thresh[1] <= PWDATA[2:0];
      end
    end
  always_comb begin
    PRDATA = 32'h0;
    if (PADDR < 24'h000080 & PADDR[1:0] == 0) PRDATA = {29'b0, prio[PADDR[6:2]]};
    if (PADDR == 24'h001000) PRDATA = pending;
    if (PADDR == 24'h002000) PRDATA = en[0];
    if (PADDR == 24'h002080) PRDATA = en[1];
    if (PADDR == 24'h200000) PRDATA = {29'b0, thresh[0]};
    if (PADDR == 24'h201000) PRDATA = {29'b0, thresh[1]};
    if (claimAdr)            PRDATA = {27'b0, best[ctx]};
  end
endmodule

// ===========================================================================
// UART: PC16550D-compatible subset (book 20.4). 16-deep FIFOs, 16x oversampling,
// baud tick = PCLK / divisor (UART_PRESCALE = 0). No modem-status inputs.
// ===========================================================================
module uart_apb20 (
  input  logic        clk, reset, PSEL, PENABLE, PWRITE,
  input  logic [2:0]  PADDR,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  input  logic        Sin,
  output logic        Sout,
  output logic        Intr
);
  logic [7:0] IER, LCR, MCR, SCR, DLL, DLM, FCR;
  logic       we, re, dlab;
  assign we = PSEL & PENABLE & PWRITE;
  assign re = PSEL & PENABLE & ~PWRITE;
  assign dlab = LCR[7];
  logic [7:0] wd; assign wd = PWDATA[7:0];

  // ---- baud: one tick every {DLM,DLL} clocks (16 ticks per bit) ----
  logic [15:0] div, bcnt;
  logic        tick;
  assign div = {DLM, DLL};
  always_ff @(posedge clk)
    if (reset | div == 0) begin bcnt <= 16'd1; end
    else bcnt <= (bcnt >= div) ? 16'd1 : bcnt + 16'd1;
  assign tick = (div != 0) & (bcnt >= div);

  // frame shape from LCR
  logic [3:0] nbits; assign nbits = 4'd5 + {2'b0, LCR[1:0]};
  logic       stop2; assign stop2 = LCR[2];
  logic       pen;   assign pen   = LCR[3];
`ifdef BUG_UART_PARITY_INV
  logic       eps;   assign eps   = ~LCR[4];
`else
  logic       eps;   assign eps   = LCR[4];               // 1 = even parity
`endif
  function automatic logic parbit(logic [7:0] d);
    logic p; p = ^(d & ((8'hFF) >> (8 - nbits)));
    return eps ? p : ~p;                                    // even: make total ones even
  endfunction

  // ---- FIFOs ----
  logic [7:0]  txq [16]; logic [4:0] txn; logic [3:0] txh;
  logic [10:0] rxq [16]; logic [4:0] rxn; logic [3:0] rxh;   // {BI, FE, PE, data}
  logic        txPop, rxPush, rxPop;
  logic [10:0] rxIn;
  logic        loop; assign loop = MCR[4];

  // ---- transmitter ----
  logic [3:0]  tsub; logic [3:0] tbit; logic tbusy; logic [11:0] tsh; logic [3:0] tlen;
  logic        txLine;
  always_ff @(posedge clk)
    if (reset) begin tbusy <= 0; tsub <= 0; tbit <= 0; tsh <= '1; tlen <= 0; end
    else if (~tbusy) begin
      if (txn != 0 & tick) begin
        // {stop(s), parity, data LSB first, start}
        logic [11:0] f; f = '1;
        f[0] = 1'b0;
        for (int i = 0; i < 8; i++) if (i < nbits) f[1 + i] = txq[txh][i];
        if (pen) f[1 + nbits] = parbit(txq[txh]);
        tsh <= f; tlen <= 4'd1 + nbits + {3'b0, pen} + (stop2 ? 4'd2 : 4'd1);
        tbusy <= 1; tsub <= 0; tbit <= 0;
      end
    end else if (tick) begin
      tsub <= tsub + 1;
      if (tsub == 4'd15) begin
        tsh <= {1'b1, tsh[11:1]};
        tbit <= tbit + 1;
        if (tbit + 1 == tlen) tbusy <= 0;
      end
    end
  assign txPop  = ~tbusy & txn != 0 & tick;
  assign txLine = tbusy ? tsh[0] : 1'b1;
  assign Sout   = loop ? 1'b1 : (LCR[6] ? 1'b0 : txLine);

  // ---- receiver: synchronize, find the start bit, sample mid-bit ----
  logic s1, s2, rin;
  always_ff @(posedge clk) if (reset) {s1, s2} <= 2'b11; else {s1, s2} <= {loop ? txLine : Sin, s1};
  assign rin = s2;
  logic        rbusy, rwait; logic [3:0] rsub; logic [3:0] rbit; logic [10:0] rsh; logic [3:0] rlen;
`ifdef BUG_UART_SAMPLE_EARLY
  localparam logic [3:0] MID = 4'd1;
`else
  localparam logic [3:0] MID = 4'd7;
`endif
  always_ff @(posedge clk)
    if (reset) begin rbusy <= 0; rwait <= 0; rsub <= 0; rbit <= 0; rsh <= 0; rxPush <= 0; rxIn <= 0; end
    else begin
      rxPush <= 0;
      if (tick) begin
        if (rwait) begin
          if (rin) rwait <= 0;                                  // after a framing error: wait for idle
        end else if (~rbusy) begin
          if (~rin) begin rbusy <= 1; rsub <= 0; rbit <= 0; rsh <= 0; end
        end else begin
          rsub <= rsub + 1;
          if (rsub == MID) begin
            if (rbit == 0) begin
              if (rin) rbusy <= 0;                              // glitch, not a start bit
            end else rsh[rbit - 1] <= rin;                      // data, then parity, then stop
            rbit <= rbit + 1;
            if (rbit == nbits + {3'b0, pen} + 1) begin            // the (first) stop bit
              logic [7:0] d; logic pe, fe, bi;
              d = 8'h0;
              for (int i = 0; i < 8; i++) if (i < nbits) d[i] = rsh[i];
              pe = pen & (rsh[nbits] != parbit(d));
              fe = ~rin;
              bi = (d == 0) & ~rin & (~pen | ~rsh[nbits]);
              rxIn <= {bi, fe, pe, d}; rxPush <= 1;
              rbusy <= 0; rwait <= fe;
            end
          end
        end
      end
    end

  // ---- FIFO bookkeeping, LSR, interrupts ----
  logic oe, threInt, rxPopR;
  logic [4:0] trig;
  always_comb case (FCR[7:6]) 2'd0: trig = 1; 2'd1: trig = 4; 2'd2: trig = 8; default: trig = 14; endcase
  logic [10:0] rxHead; assign rxHead = rxq[rxh];
  logic dr; assign dr = rxn != 0;
  logic rlsErr; assign rlsErr = oe | (dr & |rxHead[10:8]);
  logic [7:0] LSR;
  assign LSR = {1'b0, (txn == 0) & ~tbusy, txn == 0, dr & rxHead[10], dr & rxHead[9], dr & rxHead[8], oe, dr};
  logic [3:0] iid;
  always_comb
    if (IER[2] & rlsErr)                          iid = 4'b0110;
    else if (IER[0] & dr & (rxn >= (FCR[0] ? trig : 5'd1))) iid = 4'b0100;
    else if (IER[1] & threInt)                   iid = 4'b0010;
    else                                         iid = 4'b0001;
  assign Intr = ~iid[0];

  assign rxPop = re & PADDR == 3'd0 & ~dlab & dr;
  always_ff @(posedge clk)
    if (reset) begin
      IER <= 0; LCR <= 8'h03; MCR <= 0; SCR <= 0; DLL <= 0; DLM <= 0; FCR <= 0;
      txn <= 0; txh <= 0; rxn <= 0; rxh <= 0; oe <= 0; threInt <= 0;
    end else begin
      logic push; push = we & PADDR == 3'd0 & ~dlab & txn != 16;
      // reading LSR clears overrun; an overrun in the same cycle wins (set after clear below).
      // (Lab 11 found this: with the clear last, an overrun that landed on the polling read was lost.)
      if (re & PADDR == 3'd5) oe <= 0;
      // TX FIFO
      if (push) txq[txh + txn[3:0]] <= wd;
      if (txPop) txh <= txh + 1;
      txn <= txn + (push ? 1 : 0) - (txPop ? 1 : 0);
      // RX FIFO (a pop in the same cycle frees the head slot before the push lands)
      if (rxPush) begin
        if (rxn == 16 & ~rxPop) begin
`ifdef BUG_UART_NO_OVERRUN
          rxq[rxh + 4'd15] <= rxIn;                  // BUG: overwrite the newest character, no OE
`else
          oe <= 1;                                   // overrun: the new character is lost
`endif
        end else rxq[rxh + rxn[3:0]] <= rxIn;
      end
      if (rxPop) rxh <= rxh + 1;
      rxn <= rxn + ((rxPush & (rxn != 16 | rxPop)) ? 1 : 0) - (rxPop ? 1 : 0);
      // THRE interrupt: set when the TX FIFO becomes empty (or ETBEI turns on while empty);
      // cleared by writing THR or by reading IIR while it is the reported source
      if ((txPop & txn == 1) | (we & PADDR == 3'd1 & ~dlab & wd[1] & ~IER[1] & txn == 0)) threInt <= 1;
      if (push) threInt <= 0;
      if (re & PADDR == 3'd2 & iid == 4'b0010) threInt <= 0;
      // registers
      if (we)
        case (PADDR)
          3'd0: if (dlab) DLL <= wd;
          3'd1: if (dlab) DLM <= wd; else IER <= wd & 8'h0F;
          3'd2: begin
                  FCR <= wd & 8'hC1;
                  if (wd[1]) begin rxn <= 0; rxh <= 0; end
                  if (wd[2]) begin txn <= 0; txh <= 0; end
                end
          3'd3: LCR <= wd;
          3'd4: MCR <= wd & 8'h1F;
          3'd7: SCR <= wd;
          default: ;
        endcase
    end

  always_comb
    case (PADDR)
      3'd0: PRDATA = dlab ? {24'b0, DLL} : {24'b0, rxHead[7:0]};
      3'd1: PRDATA = dlab ? {24'b0, DLM} : {24'b0, IER};
      3'd2: PRDATA = {24'b0, FCR[0] ? 2'b11 : 2'b00, 2'b00, iid};
      3'd3: PRDATA = {24'b0, LCR};
      3'd4: PRDATA = {24'b0, MCR};
      3'd5: PRDATA = {24'b0, LSR};
      3'd6: PRDATA = 32'h0;                         // MSR: no modem inputs here
      default: PRDATA = {24'b0, SCR};
    endcase
endmodule

// ===========================================================================
// SPI: SiFive FU540 subset (Table 20.4). Single data line, 1..8-bit frames, csmode AUTO/HOLD/OFF.
// ===========================================================================
module spi_apb20 (
  input  logic        clk, reset, PSEL, PENABLE, PWRITE,
  input  logic [7:0]  PADDR,
  input  logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  input  logic        SDI,
  output logic        SDO, SCK,
  output logic [3:0]  CS,
  output logic        Intr
);
  logic [11:0] sckdiv; logic [1:0] sckmode; logic [1:0] csid; logic [3:0] csdef; logic [1:0] csmode;
  logic [31:0] delay0, delay1; logic [3:0] fmtlen; logic fmtend; logic [2:0] txmark, rxmark; logic [1:0] ie;
  logic        we, re;
  assign we = PSEL & PENABLE & PWRITE;
  assign re = PSEL & PENABLE & ~PWRITE;

  logic [7:0] txq [8]; logic [3:0] txn; logic [2:0] txh;
  logic [7:0] rxq [8]; logic [3:0] rxn; logic [2:0] rxh;
  logic       txPop, rxPush; logic [7:0] rxIn;

  logic pha, pol, lsb;
`ifdef BUG_SPI_IGNORE_PHASE
  assign pha = 1'b0;
`else
  assign pha = sckmode[0];
`endif
  assign pol = sckmode[1];
`ifdef BUG_SPI_IGNORE_ENDIAN
  assign lsb = 1'b0;
`else
  assign lsb = fmtend;
`endif

  // ---- engine: a half-period counter; a frame of L bits is 2L SCK edges ----
  // edge k even = leading, odd = trailing.  pha 0: bit i is driven before leading edge 2i and
  // sampled on it, the next bit is driven on trailing edge 2i+1.  pha 1: bit i is driven on
  // leading edge 2i and sampled on trailing edge 2i+1.
  typedef enum logic [1:0] {IDLE, LEAD, XFER, TRAIL} st_t;
  st_t st;
  logic [11:0] hc; logic half; logic [4:0] edges; logic [7:0] tbits, rxv; logic sckInt, csAct, sdoR;
  assign half = (hc == sckdiv);
  function automatic logic [7:0] order(logic [7:0] d);    // data -> transmission order (bit 0 first)
    logic [7:0] r; r = 0;
    for (int i = 0; i < 8; i++) if (i < fmtlen) r[i] = lsb ? d[i] : d[fmtlen - 1 - i];
    return r;
  endfunction
  function automatic logic [7:0] unorder(logic [7:0] t);  // transmission order -> data
    logic [7:0] r; r = 0;
    for (int i = 0; i < 8; i++) if (i < fmtlen) r[lsb ? i : fmtlen - 1 - i] = t[i];
    return r;
  endfunction
  always_ff @(posedge clk)
    if (reset) begin st <= IDLE; hc <= 0; edges <= 0; tbits <= 0; rxv <= 0; sckInt <= 0; csAct <= 0; sdoR <= 0; rxPush <= 0; rxIn <= 0; end
    else begin
      rxPush <= 0;
      hc <= half ? 12'd0 : hc + 1;
      case (st)
        IDLE:  if (txn != 0 & half) begin
                 logic [7:0] o; o = order(txq[txh]);
                 tbits <= o; csAct <= 1; edges <= 0; rxv <= 0;
                 if (~pha) sdoR <= o[0];
                 st <= LEAD;
               end else if (csmode != 2'd2) csAct <= 0;    // AUTO/OFF: release CS when idle
        LEAD:  if (half) st <= XFER;                        // CS-to-SCK setup: one half period
        XFER:  if (half) begin
                 logic [3:0] idx; logic [7:0] r;
                 idx = edges[4:1];
                 sckInt <= ~sckInt;
                 edges  <= edges + 1;
                 r = rxv;
                 if (~pha) begin
                   if (~edges[0]) begin rxv[idx] <= SDI; r[idx] = SDI; end
                   else if (idx + 1 < fmtlen) sdoR <= tbits[idx + 1];
                 end else begin
                   if (~edges[0]) sdoR <= tbits[idx];
                   else begin rxv[idx] <= SDI; r[idx] = SDI; end
                 end
                 if (edges == {fmtlen, 1'b0} - 5'd1) begin
                   rxIn <= unorder(r); rxPush <= 1; st <= TRAIL;
                 end
               end
        TRAIL: if (half) begin st <= IDLE; if (csmode == 2'd0) csAct <= 0; end
        default: st <= IDLE;
      endcase
    end
  assign txPop = (st == IDLE) & txn != 0 & half;
  assign SCK = sckInt ^ pol;
  assign SDO = sdoR;
  always_comb begin
    CS = csdef;
    if (csAct & csmode != 2'd3) CS[csid] = ~csdef[csid];
  end

  logic txwm, rxwm;
`ifdef BUG_SPI_TXWM_LE
  assign txwm = txn <= {1'b0, txmark};
`else
  assign txwm = txn <  {1'b0, txmark};
`endif
  assign rxwm = rxn >  {1'b0, rxmark};
  assign Intr = (ie[0] & txwm) | (ie[1] & rxwm);

  logic rxPop; assign rxPop = re & PADDR == 8'h4C & rxn != 0;
  always_ff @(posedge clk)
    if (reset) begin
      sckdiv <= 12'd3; sckmode <= 0; csid <= 0; csdef <= 4'hF; csmode <= 0; delay0 <= 32'h0001_0001;
      delay1 <= 32'h0000_0001; fmtlen <= 4'd8; fmtend <= 0; txmark <= 0; rxmark <= 0; ie <= 0;
      txn <= 0; txh <= 0; rxn <= 0; rxh <= 0;
    end else begin
      logic push; push = we & PADDR == 8'h48 & txn != 8;
      if (push) txq[txh + txn[2:0]] <= PWDATA[7:0];
      if (txPop) txh <= txh + 1;
      txn <= txn + (push ? 1 : 0) - (txPop ? 1 : 0);
      if (rxPush & rxn != 8) rxq[rxh + rxn[2:0]] <= rxIn;      // FU540: a full RX FIFO drops
      if (rxPop) rxh <= rxh + 1;
      rxn <= rxn + ((rxPush & rxn != 8) ? 1 : 0) - (rxPop ? 1 : 0);
      if (we)
        case (PADDR)
          8'h00: sckdiv  <= PWDATA[11:0];
          8'h04: sckmode <= PWDATA[1:0];
          8'h10: csid    <= PWDATA[1:0];
          8'h14: csdef   <= PWDATA[3:0];
          8'h18: csmode  <= PWDATA[1:0];
          8'h28: delay0  <= PWDATA & 32'h00FF_00FF;
          8'h2C: delay1  <= PWDATA & 32'h00FF_00FF;
          8'h40: begin fmtend <= PWDATA[2]; fmtlen <= (PWDATA[19:16] == 0 | PWDATA[19:16] > 8) ? 4'd8 : PWDATA[19:16]; end
          8'h50: txmark  <= PWDATA[2:0];
          8'h54: rxmark  <= PWDATA[2:0];
          8'h70: ie      <= PWDATA[1:0];
          default: ;
        endcase
    end
  always_comb
    case (PADDR)
      8'h00: PRDATA = {20'b0, sckdiv};
      8'h04: PRDATA = {30'b0, sckmode};
      8'h10: PRDATA = {30'b0, csid};
      8'h14: PRDATA = {28'b0, csdef};
      8'h18: PRDATA = {30'b0, csmode};
      8'h28: PRDATA = delay0;
      8'h2C: PRDATA = delay1;
      8'h40: PRDATA = {12'b0, fmtlen, 12'b0, 1'b0, fmtend, 2'b0};
      8'h48: PRDATA = {txn == 8, 31'b0};
      8'h4C: PRDATA = {rxn == 0, 23'b0, rxn != 0 ? rxq[rxh] : 8'h0};
      8'h50: PRDATA = {29'b0, txmark};
      8'h54: PRDATA = {29'b0, rxmark};
      8'h70: PRDATA = {30'b0, ie};
      8'h74: PRDATA = {30'b0, rxwm, txwm};
      default: PRDATA = 32'h0;
    endcase
endmodule
