// tb_periph.sv -- Lab 11 (book Ch 20): block-level verification of the five peripherals.
//
// What a subsystem DV bench needs, in plain SystemVerilog (Verilator 5, --timing):
//   * an APB driver (apb_wr / apb_rd) with random idle gaps
//   * a register model: reset values, writable masks, read-back (test "regs")
//   * reference models that run every cycle and check every output pin and every read:
//       GPIO   2-flop synchronizer + edge register, sticky W1C pending bits    (exact, cycle by cycle)
//       CLINT  64-bit mtime, >= compare                                        (exact)
//       PLIC   gateway, priority/lowest-id arbitration, threshold, claim/complete (exact)
//   * independent protocol agents that do NOT share code with the RTL:
//       UART   a TX monitor that decodes frames on the pin, an RX driver with baud-rate error
//              and parity/framing error injection
//       SPI    an SPI peripheral (slave) model for all four clock modes and both bit orders
//   * functional coverage counters (COV lines) and one PASS/FAIL line
//
// Plusargs: +TEST=all|regs|gpio|clint|plic|uart|spi  +SEED=n  +ITER=n  +VCD=file  +SHOW (print frames)
// Last line: PERIPH PASS|FAIL test=... errors=N  (plus COVERAGE hit/total)

`timescale 1ns/1ps
module tb_periph;
  logic clk = 0, reset = 1;
  always #5 clk = ~clk;
  int unsigned cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // ------------------------------------------------------------------ DUT
  logic        PSEL = 0, PENABLE = 0, PWRITE = 0;
  logic [31:0] PADDR = 0, PWDATA = 0, PRDATA;
  logic        PREADY;
  logic [31:0] GPIOPinsIn, GPIOPinsOut, GPIOPinsEn, ExtSrc = 0;
  logic        UARTSin, UARTSout, SPIIn, SPIOut, SPISck;
  logic [3:0]  SPICS;
  logic        MTimerInt, MSwInt, MExtInt, SExtInt, GPIOIntr, UARTIntr, SPIIntr;

  logic [31:0] tbPins = 0;        // what the outside world drives onto the GPIO pads
  bit          gpioLoop = 0;      // GPIO_LOOPBACK_TEST: inputs see outputs where enabled
  logic        uartRx = 1;        // RX line driven by the tb's UART agent
  bit          spiLoop = 0;       // SPI_LOOPBACK_TEST: SDI = SDO
  logic        slaveSdo = 0;
  assign GPIOPinsIn = gpioLoop ? ((GPIOPinsOut & GPIOPinsEn) | (tbPins & ~GPIOPinsEn)) : tbPins;
  assign UARTSin    = uartRx;
  assign SPIIn      = spiLoop ? SPIOut : slaveSdo;

  periph dut(.clk, .reset, .PSEL, .PENABLE, .PWRITE, .PADDR, .PWDATA, .PRDATA, .PREADY,
             .GPIOPinsIn, .GPIOPinsOut, .GPIOPinsEn, .UARTSin, .UARTSout, .SPIIn, .SPIOut, .SPISck,
             .SPICS, .ExtSrc, .MTimerInt, .MSwInt, .MExtInt, .SExtInt, .GPIOIntr, .UARTIntr, .SPIIntr);

  // ------------------------------------------------------------------ bookkeeping
  int errors = 0;
  string testname;
  bit show = 0;
  // +BOOKPLAN: check the way the book's test plan does -- UART and SPI only in loopback,
  // GPIO only after the inputs have settled (no cycle-exact model of the synchronizer).
  bit bookplan = 0;
  task automatic err(string m);
    errors++;
    if (errors <= 12) $display("ERROR @%0d: %s", cyc, m);
  endtask

  // coverage: named bins, hit counts
  int cov[string];
  string covBins[$];
  function automatic void bin(string n); if (!cov.exists(n)) begin cov[n] = 0; covBins.push_back(n); end endfunction
  function automatic void hit(string n); if (!cov.exists(n)) bin(n); cov[n]++; endfunction

  // ------------------------------------------------------------------ APB driver
  // The access-phase transfer is visible to the models in the same cycle through these:
  logic        evWr = 0, evRd = 0;
  logic [31:0] evAdr = 0, evData = 0;
  int          maxGap = 2;
  logic [31:0] last_g, last_c, last_p;            // the models' view of the register being read
  task automatic apb(input bit wr, input logic [31:0] a, input logic [31:0] d, output logic [31:0] q);
    int g = $urandom_range(0, maxGap);
    repeat (g) @(negedge clk);
    @(negedge clk); PSEL = 1; PENABLE = 0; PWRITE = wr; PADDR = a; PWDATA = wr ? d : $urandom;
    @(negedge clk); PENABLE = 1; evWr = wr; evRd = ~wr; evAdr = a; evData = d;
    #1 q = PRDATA;                                     // PREADY is always 1: the access ends this edge
    last_g = g_read(a[7:0]); last_c = c_read(a[15:0]); last_p = p_read(a[23:0]);   // model view, same cycle
    @(posedge clk); #1; PSEL = 0; PENABLE = 0; evWr = 0; evRd = 0;
  endtask
  task automatic apb_wr(input logic [31:0] a, input logic [31:0] d); logic [31:0] q; apb(1, a, d, q); endtask
  task automatic apb_rd(input logic [31:0] a, output logic [31:0] q); apb(0, a, 0, q); endtask
  task automatic apb_chk(input logic [31:0] a, input logic [31:0] exp, input string what);
    logic [31:0] q; apb_rd(a, q);
    if (q !== exp) err($sformatf("%s: read 0x%08h = 0x%08h, expected 0x%08h", what, a, q, exp));
  endtask

  task automatic do_reset();
    @(negedge clk); reset = 1; tbPins = 0; ExtSrc = 0; uartRx = 1; gpioLoop = 0; spiLoop = 0;
    repeat (3) @(negedge clk); reset = 0;
  endtask

  localparam logic [31:0] GPIO = 32'h1006_0000, CLINT = 32'h0200_0000, PLIC = 32'h0C00_0000,
                          UART = 32'h1000_0000, SPI = 32'h1004_0000;

  // ================================================================== GPIO reference model
  // Spec: input_en gates the pin, then a 2-stage synchronizer, then one more register for edges.
  // *_ip set by the condition, cleared by writing 1, condition wins in the same cycle.
  logic [31:0] g_ien, g_oen, g_oval, g_xor, g_ie[4], g_ip[4], g_s1, g_s2, g_s3;
  localparam logic [7:0] GIPOFF[4] = '{8'h1C, 8'h24, 8'h2C, 8'h34};   // rise fall high low
  localparam logic [7:0] GIEOFF[4] = '{8'h18, 8'h20, 8'h28, 8'h30};
  function automatic logic [31:0] g_cond(int k);
    case (k) 0: return g_s2 & ~g_s3; 1: return ~g_s2 & g_s3; 2: return g_s2; default: return ~g_s2; endcase
  endfunction
  always @(posedge clk)
    if (reset) begin
      g_ien <= 0; g_oen <= 0; g_oval <= 0; g_xor <= 0; g_s1 <= 0; g_s2 <= 0; g_s3 <= 0;
      for (int k = 0; k < 4; k++) begin g_ie[k] <= 0; g_ip[k] <= 0; end
    end else begin
      bit gsel; gsel = evAdr[31:16] == 16'h1006;
      for (int k = 0; k < 4; k++) begin
        logic [31:0] clr; clr = (evWr & gsel & evAdr[7:0] == GIPOFF[k]) ? evData : 32'h0;
        g_ip[k] <= (g_ip[k] & ~clr) | g_cond(k);
        if (evWr & gsel & evAdr[7:0] == GIEOFF[k]) g_ie[k] <= evData;
        if (g_cond(k) != 0 & (g_ip[k] & clr & g_cond(k)) != 0) hit("gpio: clear and set in the same cycle");
      end
      g_s1 <= GPIOPinsIn & g_ien; g_s2 <= g_s1; g_s3 <= g_s2;
      if (evWr & gsel) case (evAdr[7:0])
        8'h04: g_ien <= evData; 8'h08: g_oen <= evData; 8'h0C: g_oval <= evData; 8'h40: g_xor <= evData;
        default: ;
      endcase
    end
  function automatic logic [31:0] g_read(logic [7:0] off);
    case (off)
      8'h00: return g_s2;  8'h04: return g_ien; 8'h08: return g_oen; 8'h0C: return g_oval; 8'h40: return g_xor;
      8'h18: return g_ie[0]; 8'h1C: return g_ip[0]; 8'h20: return g_ie[1]; 8'h24: return g_ip[1];
      8'h28: return g_ie[2]; 8'h2C: return g_ip[2]; 8'h30: return g_ie[3]; 8'h34: return g_ip[3];
      default: return 0;
    endcase
  endfunction
  // pin and interrupt checks every cycle (sampled just after the edge)
  always @(posedge clk) if (!reset && !bookplan) begin
    logic intr; #2;
    intr = 0; for (int k = 0; k < 4; k++) intr |= |(g_ip[k] & g_ie[k]);
    if (GPIOIntr !== intr) err($sformatf("GPIOIntr = %b, model %b", GPIOIntr, intr));
    if (GPIOPinsOut !== (g_oval ^ g_xor)) err("GPIOPinsOut != output_val ^ out_xor");
    if (GPIOPinsEn !== g_oen) err("GPIOPinsEn != output_en");
    if (intr) hit("gpio: GPIOIntr asserted");
  end

  // ================================================================== CLINT reference model
  logic [63:0] c_mtime, c_cmp; logic c_msip;
  always @(posedge clk)
    if (reset) begin c_mtime <= 0; c_cmp <= '1; c_msip <= 0; end
    else begin
      bit csel; csel = evAdr[31:16] == 16'h0200;
      if (evWr & csel & evAdr[15:0] == 16'hBFF8)      c_mtime <= {c_mtime[63:32], evData};
      else if (evWr & csel & evAdr[15:0] == 16'hBFFC) c_mtime <= {evData, c_mtime[31:0]};
      else begin
        if (c_mtime[31:0] == 32'hFFFF_FFFF) hit("clint: mtime low word wraps (carry)");
        c_mtime <= c_mtime + 1;
      end
      if (evWr & csel & evAdr[15:0] == 16'h0000) c_msip <= evData[0];
      if (evWr & csel & evAdr[15:0] == 16'h4000) c_cmp[31:0]  <= evData;
      if (evWr & csel & evAdr[15:0] == 16'h4004) c_cmp[63:32] <= evData;
    end
  always @(posedge clk) if (!reset) begin
    #2;
    if (MTimerInt !== (c_mtime >= c_cmp)) err($sformatf("MTimerInt = %b, model mtime %0d mtimecmp %0d", MTimerInt, c_mtime, c_cmp));
    if (MSwInt !== c_msip) err("MSwInt != msip");
    if (c_mtime == c_cmp) hit("clint: mtime == mtimecmp (boundary)");
    if (MTimerInt) hit("clint: timer interrupt"); if (MSwInt) hit("clint: software interrupt");
  end
  function automatic logic [31:0] c_read(logic [15:0] off);
    case (off) 16'h0: return {31'b0, c_msip}; 16'h4000: return c_cmp[31:0]; 16'h4004: return c_cmp[63:32];
      16'hBFF8: return c_mtime[31:0]; 16'hBFFC: return c_mtime[63:32]; default: return 0; endcase
  endfunction

  // ================================================================== PLIC reference model
  // Written from the spec text, deliberately not in the RTL's style:
  //   best = scan ids 1..31 and keep the first one with the strictly highest priority
  logic [2:0]  p_prio[32]; logic [31:0] p_pend, p_prog, p_en[2]; logic [2:0] p_th[2];
  function automatic int p_best(int c);
    int b = 0, bp = 0;
    for (int i = 1; i < 32; i++)
      if (p_pend[i] && p_en[c][i] && p_prio[i] > bp) begin b = i; bp = p_prio[i]; end
    return b;
  endfunction
  logic [31:0] p_src;
  always_comb begin p_src = ExtSrc; p_src[0] = 0; p_src[3] = GPIOIntr; p_src[6] = SPIIntr; p_src[10] = UARTIntr; end
  always @(posedge clk)
    if (reset) begin
      p_pend <= 0; p_prog <= 0; p_en[0] <= 0; p_en[1] <= 0; p_th[0] <= 0; p_th[1] <= 0;
      for (int i = 0; i < 32; i++) p_prio[i] <= 0;
    end else begin
      bit psel; logic [23:0] off; logic [31:0] claim, compl; int c;
      psel = evAdr[31:24] == 8'h0C; off = evAdr[23:0]; claim = 0; compl = 0;
      c = off[12];
      if (psel & (off == 24'h200004 | off == 24'h201004)) begin
        if (evRd && p_best(c) != 0) claim[p_best(c)] = 1;
        if (evWr && evData < 32 && p_en[c][evData[4:0]]) begin
          compl[evData[4:0]] = 1;
          if (!p_prog[evData[4:0]]) hit("plic: completion of a source not in progress (ignored)");
        end
        if (evWr && !(evData < 32 && p_en[c][evData[4:0]])) hit("plic: completion with an id not enabled (ignored)");
        if (evRd && p_best(c) == 0) hit("plic: claim with nothing pending returns 0");
      end
      for (int i = 1; i < 32; i++) if (p_src[i] & p_prog[i]) hit("plic: source still high while in progress");
      p_pend <= ((p_pend | (p_src & ~p_prog)) & ~claim) & ~32'h1;
      p_prog <= (p_prog | claim) & ~compl;
      if (evWr & psel) begin
        if (off < 24'h80 && off[1:0] == 0 && off[6:2] != 0) p_prio[off[6:2]] <= evData[2:0];
        if (off == 24'h2000) p_en[0] <= evData & ~32'h1;
        if (off == 24'h2080) p_en[1] <= evData & ~32'h1;
        if (off == 24'h200000) p_th[0] <= evData[2:0];
        if (off == 24'h201000) p_th[1] <= evData[2:0];
      end
    end
  function automatic logic [31:0] p_read(logic [23:0] off);
    if (off < 24'h80 && off[1:0] == 0) return {29'b0, p_prio[off[6:2]]};
    case (off)
      24'h1000: return p_pend; 24'h2000: return p_en[0]; 24'h2080: return p_en[1];
      24'h200000: return {29'b0, p_th[0]}; 24'h201000: return {29'b0, p_th[1]};
      24'h200004: return p_best(0); 24'h201004: return p_best(1);
      default: return 0;
    endcase
  endfunction
  always @(posedge clk) if (!reset) begin
    int b0, b1; logic m, s; #2;
    b0 = p_best(0); b1 = p_best(1);
    m = b0 != 0 && p_prio[b0] > p_th[0];
    s = b1 != 0 && p_prio[b1] > p_th[1];
    if (MExtInt !== m) err($sformatf("MExtInt = %b, model %b (best id %0d prio %0d threshold %0d)", MExtInt, m, b0, p_prio[b0], p_th[0]));
    if (SExtInt !== s) err($sformatf("SExtInt = %b, model %b (best id %0d prio %0d threshold %0d)", SExtInt, s, b1, p_prio[b1], p_th[1]));
    if (b0 != 0 && p_prio[b0] == p_th[0]) hit("plic: best priority == threshold (masked)");
    if (m) hit("plic: MExtInt"); if (s) hit("plic: SExtInt");
    for (int i = 1; i < 32; i++)
      if (i != b0 && p_pend[i] && p_en[0][i] && p_prio[i] == p_prio[b0] && b0 != 0) hit("plic: tie broken by lowest id");
  end

  // checked read of any modelled register (GPIO, CLINT, PLIC)
  task automatic chk_rd(input logic [31:0] a, input string what);
    logic [31:0] q, e;
    apb_rd(a, q);
    // the model state was sampled in the same cycle as the read (before the edge)
    e = (a[31:16] == 16'h1006) ? last_g : (a[31:16] == 16'h0200) ? last_c : last_p;
    if (q !== e) err($sformatf("%s: read 0x%08h = 0x%08h, model 0x%08h", what, a, q, e));
  endtask

  // ================================================================== UART agent
  // Configuration the tb believes the DUT has (set by the tests through uart_config)
  int  u_div = 1, u_bits = 8; bit u_pen = 0, u_even = 0, u_stop2 = 0;
  byte unsigned u_txExp[$];                       // bytes written to THR, in order
  int  u_txSeen = 0;
  // TX monitor: decodes frames on UARTSout with its own timing, checks parity and stop bits
  bit u_monOn = 1;
  initial begin
    forever begin
      @(posedge clk);
      if (!reset && u_monOn && UARTSout == 0) begin
        int P; logic [7:0] d; logic par, ok; P = 16 * u_div;
        d = 0; ok = 1;
        repeat (P / 2 - 1) @(posedge clk);
        if (UARTSout !== 0) begin err("UART TX: start bit not low at its middle"); ok = 0; end
        for (int i = 0; i < u_bits; i++) begin repeat (P) @(posedge clk); d[i] = UARTSout; end
        if (u_pen) begin
          repeat (P) @(posedge clk); par = UARTSout;
          if (par !== (u_even ? ^d : ~^d)) begin err($sformatf("UART TX: wrong %s parity bit %b for data 0x%02h", parname(u_even ? 2 : 1), par, d)); ok = 0; end
        end
        repeat (P) @(posedge clk);
        if (UARTSout !== 1) begin err("UART TX: stop bit not high"); ok = 0; end
        if (u_stop2) begin
          repeat (P) @(posedge clk);
          if (UARTSout !== 1) begin err("UART TX: second stop bit not high"); ok = 0; end
        end
        if (show) $display("UART TX frame @%0d: 0x%02h", cyc, d);
        if (u_txExp.size() == 0) err($sformatf("UART TX: unexpected frame 0x%02h", d));
        else begin
          byte unsigned e; e = u_txExp.pop_front();
          e = e & byte'((1 << u_bits) - 1);
          if (d !== e) err($sformatf("UART TX: sent 0x%02h, expected 0x%02h", d, e));
        end
        u_txSeen++;
        repeat (P / 2 - 2) @(posedge clk);      // the stop bit's second half (next start can follow)
      end
    end
  end
  // RX driver: one frame on UARTSin. scale > 1.0 = the remote end is slower than nominal.
  task automatic uart_send(byte unsigned d, real scale, bit badPar, bit badStop);
    real P, t; logic bits[$];
    bits.delete();
    P = 16.0 * u_div * scale;
    bits.push_back(0);
    for (int i = 0; i < u_bits; i++) bits.push_back(d[i]);
    if (u_pen) begin logic p; p = u_even ? ^(d & 8'((1 << u_bits) - 1)) : ~^(d & 8'((1 << u_bits) - 1)); bits.push_back(badPar ? ~p : p); end
    bits.push_back(badStop ? 0 : 1);
    if (u_stop2) bits.push_back(1);
    t = 0;
    @(posedge clk); #1;                          // change the line away from the sampling edge
    foreach (bits[i]) begin
      int n;
      uartRx = bits[i];
      n = int'($floor(t + P)) - int'($floor(t)); t += P;
      if (show) $display("  bit %0d = %b for %0d cycles (t %f P %f) @%0d", i, bits[i], n, t, P, cyc);
      repeat (n) @(posedge clk);
      #1;
    end
    uartRx = 1;
    repeat (int'(P)) @(posedge clk);            // idle gap
  endtask
  function automatic string parname(int p); if (p == 0) return "none"; if (p == 1) return "odd"; return "even"; endfunction
  task automatic uart_config(int div, int bits, bit pen, bit even, bit stop2, bit fifo, int trig);
    u_div = div; u_bits = bits; u_pen = pen; u_even = even; u_stop2 = stop2;
    apb_wr(UART + 3, 8'h80);                    // DLAB = 1
    apb_wr(UART + 0, div & 8'hFF);              // DLL
    apb_wr(UART + 1, div >> 8);                 // DLM
    apb_wr(UART + 3, {2'b00, 1'b0, even, pen, stop2, 2'(bits - 5)});   // DLAB = 0
    apb_wr(UART + 2, {2'(trig), 3'b0, 1'b1, 1'b1, fifo});                // FCR: reset both FIFOs
    hit($sformatf("uart: %0d bits, parity %s, %0d stop", bits, parname(pen ? (even ? 2 : 1) : 0), stop2 ? 2 : 1));
  endtask

  // ================================================================== SPI peripheral (slave) model
  bit s_pha = 0, s_pol = 0, s_lsb = 0; int s_len = 8; int s_cs = 0;
  byte unsigned s_resp[$], s_got[$];
  bit s_chk = 1;                                  // CPOL/CS checks off while the tb reconfigures
  logic s_prevSck = 0, s_prevCs = 0; int s_bit = 0; byte unsigned s_cur = 0, s_rx = 0; bit s_have = 0;
  function automatic void s_load(); s_cur = s_resp.size() ? s_resp.pop_front() : 8'hA5; s_have = 1; endfunction
  function automatic logic s_outbit(byte unsigned v, int i); return s_lsb ? v[i] : v[s_len - 1 - i]; endfunction
  always @(posedge clk) begin
    logic act; #1;
    act = !reset && SPICS[s_cs] == 0;
    for (int k = 0; k < 4; k++) if (s_chk && k != s_cs && SPICS[k] == 0 && !reset) err($sformatf("SPI: CS%0d active while CS%0d is the target", k, s_cs));
    if (s_chk && !act && !reset && SPISck !== s_pol) err($sformatf("SPI: SCK = %b while CS is inactive, CPOL = %b", SPISck, s_pol));
    if (act && !s_prevCs) begin                              // frame (or held burst) starts
      s_bit = 0; s_rx = 0;
      if (!s_have) s_load();
      if (!s_pha) slaveSdo = s_outbit(s_cur, 0);
      hit("spi: chip select asserted");
    end
    if (act && SPISck !== s_prevSck) begin
      bit leading, sample; leading = (SPISck !== s_pol);
      sample = s_pha ? !leading : leading;
      if (sample) begin
        if (s_lsb) s_rx[s_bit] = SPIOut; else s_rx[s_len - 1 - s_bit] = SPIOut;
        s_bit++;
        if (s_bit == s_len) begin                           // frame done
          s_got.push_back(s_rx);
          if (show) $display("SPI frame @%0d: peripheral got 0x%02h, sent 0x%02h", cyc, s_rx, s_cur);
          s_bit = 0; s_rx = 0; s_have = 0;
          if (!s_pha) begin s_load(); slaveSdo = s_outbit(s_cur, 0); end   // next frame's first bit, before its first edge
        end
      end else begin
        if (s_pha) begin if (!s_have) s_load(); slaveSdo = s_outbit(s_cur, s_bit); end   // drive on the leading edge
        else if (s_bit < s_len) slaveSdo = s_outbit(s_cur, s_bit);
      end
    end
    if (!act && s_prevCs && s_bit != 0) err($sformatf("SPI: CS released in the middle of a frame (%0d bits)", s_bit));
    s_prevSck = SPISck; s_prevCs = act;
  end

  // ================================================================== tests
  task automatic t_regs();
    logic [31:0] RA[$], RR[$], RM[$]; string RN[$]; logic [31:0] q;
    RA.push_back(GPIO + 8'h04); RR.push_back(0); RM.push_back('1); RN.push_back("gpio.input_en");
    RA.push_back(GPIO + 8'h08); RR.push_back(0); RM.push_back('1); RN.push_back("gpio.output_en");
    RA.push_back(GPIO + 8'h0C); RR.push_back(0); RM.push_back('1); RN.push_back("gpio.output_val");
    RA.push_back(GPIO + 8'h18); RR.push_back(0); RM.push_back('1); RN.push_back("gpio.rise_ie");
    RA.push_back(GPIO + 8'h20); RR.push_back(0); RM.push_back('1); RN.push_back("gpio.fall_ie");
    RA.push_back(GPIO + 8'h28); RR.push_back(0); RM.push_back('1); RN.push_back("gpio.high_ie");
    RA.push_back(GPIO + 8'h30); RR.push_back(0); RM.push_back('1); RN.push_back("gpio.low_ie");
    RA.push_back(GPIO + 8'h40); RR.push_back(0); RM.push_back('1); RN.push_back("gpio.out_xor");
    RA.push_back(CLINT + 0); RR.push_back(0); RM.push_back(1); RN.push_back("clint.msip");
    RA.push_back(CLINT + 16'h4000); RR.push_back('1); RM.push_back('1); RN.push_back("clint.mtimecmp_lo");
    RA.push_back(CLINT + 16'h4004); RR.push_back('1); RM.push_back('1); RN.push_back("clint.mtimecmp_hi");
    RA.push_back(PLIC + 4); RR.push_back(0); RM.push_back(7); RN.push_back("plic.priority1");
    RA.push_back(PLIC + 12); RR.push_back(0); RM.push_back(7); RN.push_back("plic.priority3");
    RA.push_back(PLIC + 124); RR.push_back(0); RM.push_back(7); RN.push_back("plic.priority31");
    RA.push_back(PLIC + 24'h2000); RR.push_back(0); RM.push_back(32'hFFFF_FFFE); RN.push_back("plic.enable_ctx0");
    RA.push_back(PLIC + 24'h2080); RR.push_back(0); RM.push_back(32'hFFFF_FFFE); RN.push_back("plic.enable_ctx1");
    RA.push_back(PLIC + 24'h200000); RR.push_back(0); RM.push_back(7); RN.push_back("plic.threshold0");
    RA.push_back(PLIC + 24'h201000); RR.push_back(0); RM.push_back(7); RN.push_back("plic.threshold1");
    RA.push_back(UART + 1); RR.push_back(0); RM.push_back(8'h0F); RN.push_back("uart.IER");
    RA.push_back(UART + 4); RR.push_back(0); RM.push_back(8'h1F); RN.push_back("uart.MCR");
    RA.push_back(UART + 7); RR.push_back(0); RM.push_back(8'hFF); RN.push_back("uart.SCR");
    RA.push_back(SPI + 8'h00); RR.push_back(3); RM.push_back(12'hFFF); RN.push_back("spi.sckdiv");
    RA.push_back(SPI + 8'h04); RR.push_back(0); RM.push_back(3); RN.push_back("spi.sckmode");
    RA.push_back(SPI + 8'h10); RR.push_back(0); RM.push_back(3); RN.push_back("spi.csid");
    RA.push_back(SPI + 8'h14); RR.push_back(4'hF); RM.push_back(4'hF); RN.push_back("spi.csdef");
    RA.push_back(SPI + 8'h18); RR.push_back(0); RM.push_back(3); RN.push_back("spi.csmode");
    RA.push_back(SPI + 8'h28); RR.push_back(32'h0001_0001); RM.push_back(32'h00FF_00FF); RN.push_back("spi.delay0");
    RA.push_back(SPI + 8'h2C); RR.push_back(32'h0000_0001); RM.push_back(32'h00FF_00FF); RN.push_back("spi.delay1");
    RA.push_back(SPI + 8'h50); RR.push_back(0); RM.push_back(7); RN.push_back("spi.txmark");
    RA.push_back(SPI + 8'h54); RR.push_back(0); RM.push_back(7); RN.push_back("spi.rxmark");
    RA.push_back(SPI + 8'h70); RR.push_back(0); RM.push_back(3); RN.push_back("spi.ie");
    s_chk = 0;                                   // random SPI settings below would trip the SPI agent
    // 1. reset values, including read-only status registers
    foreach (RA[i]) apb_chk(RA[i], RR[i], {"reset value of ", RN[i]});
    apb_chk(GPIO + 8'h1C, 0, "reset value of gpio.rise_ip"); apb_chk(PLIC + 24'h1000, 0, "reset value of plic.pending");
    apb_chk(PLIC + 24'h200004, 0, "reset value of plic.claim0");
    apb_chk(UART + 2, 8'h01, "reset value of uart.IIR"); apb_chk(UART + 5, 8'h60, "reset value of uart.LSR");
    apb_chk(UART + 3, 8'h03, "reset value of uart.LCR");
    apb_chk(SPI + 8'h40, 32'h0008_0000, "reset value of spi.fmt");
    apb_chk(SPI + 8'h48, 0, "reset value of spi.txdata (not full)"); apb_chk(SPI + 8'h4C, 32'h8000_0000, "reset value of spi.rxdata (empty)");
    apb_chk(SPI + 8'h74, 0, "reset value of spi.ip (txmark 0: 0 entries is not < 0)");
    hit("regs: reset values");
    // 2. write ones, zeros, random; read back masked
    foreach (RA[i]) begin
      logic [31:0] v[3]; v = '{'1, 0, $urandom};
      if (RN[i] == "spi.csmode") v[0] = 2;       // keep CS behaviour sane
      foreach (v[j]) begin apb_wr(RA[i], v[j]); apb_chk(RA[i], v[j] & RM[i], {"read-back of ", RN[i]}); end
      apb_wr(RA[i], RR[i]);
    end
    hit("regs: walking read-back");
    // 3. DLAB-banked divisor latches
    apb_wr(UART + 3, 8'h83); apb_wr(UART + 0, 8'h5A); apb_wr(UART + 1, 8'hC3);
    apb_chk(UART + 0, 8'h5A, "uart.DLL"); apb_chk(UART + 1, 8'hC3, "uart.DLM");
    apb_wr(UART + 3, 8'h03); apb_chk(UART + 1, 0, "uart.IER after DLAB cleared");
    hit("regs: DLAB banking");
    // 4. SPI txmark watermark semantics from the register side: tx empty (0 entries)
    apb_wr(SPI + 8'h50, 1); apb_chk(SPI + 8'h74, 1, "spi.ip.txwm with 0 entries and txmark 1");
    apb_wr(SPI + 8'h50, 0); apb_chk(SPI + 8'h74, 0, "spi.ip.txwm with 0 entries and txmark 0");
    // 5. unmapped offsets read as zero
    apb_chk(GPIO + 8'h44, 0, "gpio unmapped offset"); apb_chk(CLINT + 16'h8000, 0, "clint unmapped offset");
  endtask

  task automatic t_gpio(int iters);
    apb_wr(GPIO + 8'h04, $urandom | 32'h0000_FFFF);
    for (int it = 0; it < iters; it++) begin
      int r = $urandom_range(0, 99);
      if (it == 0 || it == iters / 2) begin                // first half external pins, second loopback
        gpioLoop = (it != 0);
        hit(gpioLoop ? "gpio: loopback mode" : "gpio: external pins");
      end
      if (r < 30) begin                                   // pins change asynchronously
        begin int d = $urandom_range(1, 8); #(d >= 5 ? d + 1 : d); end
        tbPins = tbPins ^ (32'h1 << $urandom_range(0, 31)) ^ ($urandom_range(0, 3) == 0 ? $urandom : 0);
        hit("gpio: pin change");
      end else if (r < 45) begin                          // clear pending bits (W1C)
        int k = $urandom_range(0, 3); apb_wr(GPIO + GIPOFF[k], $urandom_range(0, 1) ? '1 : $urandom);
        hit("gpio: W1C write");
      end else if (r < 60) begin                          // configuration
        logic [7:0] o[8]; o = '{8'h04, 8'h08, 8'h0C, 8'h18, 8'h20, 8'h28, 8'h30, 8'h40};
        apb_wr(GPIO + o[$urandom_range(0, 7)], $urandom & ($urandom | $urandom));
      end else if (r < 95) begin                          // checked reads
        logic [7:0] o[14]; o = '{8'h00, 8'h04, 8'h08, 8'h0C, 8'h18, 8'h1C, 8'h20, 8'h24, 8'h28, 8'h2C, 8'h30, 8'h34, 8'h40, 8'h00};
        if (bookplan) repeat (4) @(negedge clk);          // let the inputs settle first
        chk_rd(GPIO + o[$urandom_range(0, 13)], "gpio");
      end else repeat ($urandom_range(1, 6)) @(negedge clk);
    end
    // Example 20.1: switches on pins 0,1, LED on pin 2 -- the book's program as a directed check
    // (the book's program assumes out_xor is still 0 from reset; the random phase left it random)
    gpioLoop = 0; apb_wr(GPIO + 8'h40, 0); apb_wr(GPIO + 8'h04, 3); apb_wr(GPIO + 8'h08, 4);
    for (int i = 0; i < 4; i++) begin
      logic [31:0] q; tbPins = i; repeat (3) @(negedge clk);
      apb_rd(GPIO + 0, q); apb_wr(GPIO + 8'h0C, q != 0 ? 4 : 0); @(negedge clk);
      if (GPIOPinsOut[2] !== (i != 0)) err($sformatf("Example 20.1: switches %b, LED %b", i[1:0], GPIOPinsOut[2]));
    end
    hit("gpio: book Example 20.1");
  endtask

  task automatic t_clint(int iters);
    for (int it = 0; it < iters; it++) begin
      int r = $urandom_range(0, 99);
      if (r < 15) begin apb_wr(CLINT + 16'h4000, c_mtime[31:0] + $urandom_range(0, 40)); apb_wr(CLINT + 16'h4004, c_mtime[63:32]); hit("clint: mtimecmp near mtime"); end
      else if (r < 22) begin apb_wr(CLINT + 16'h4004, '1); apb_wr(CLINT + 16'h4000, $urandom); end
      else if (r < 30) begin apb_wr(CLINT + 16'hBFF8, 32'hFFFF_FFFF - $urandom_range(0, 60)); hit("clint: mtime written near 2^32"); end
      else if (r < 35) begin apb_wr(CLINT + 16'hBFFC, $urandom_range(0, 3)); end
      else if (r < 45) apb_wr(CLINT + 0, $urandom_range(0, 1));
      else if (r < 90) begin logic [15:0] o[5]; o = '{16'h0, 16'h4000, 16'h4004, 16'hBFF8, 16'hBFFC}; chk_rd(CLINT + o[$urandom_range(0, 4)], "clint"); end
      else begin
        // RV32 software must read a 64-bit counter as hi, lo, hi and retry if hi changed
        logic [31:0] h1, lo, h2; int tries = 0;
        do begin apb_rd(CLINT + 16'hBFFC, h1); apb_rd(CLINT + 16'hBFF8, lo); apb_rd(CLINT + 16'hBFFC, h2); tries++; end while (h1 != h2);
        if (tries > 1) hit("clint: torn 64-bit read retried");
        hit("clint: hi-lo-hi read");
      end
    end
  endtask

  task automatic t_plic(int iters);
    // random configuration, then act like interrupt handlers on both contexts
    for (int i = 1; i < 32; i++) apb_wr(PLIC + 4 * i, $urandom_range(0, 7) & ($urandom_range(0, 3) == 0 ? 3 : 7));
    apb_wr(PLIC + 24'h2000, $urandom | $urandom); apb_wr(PLIC + 24'h2080, $urandom);
    apb_wr(PLIC + 24'h200000, $urandom_range(0, 3)); apb_wr(PLIC + 24'h201000, $urandom_range(0, 3));
    for (int it = 0; it < iters; it++) begin
      int r = $urandom_range(0, 99);
      if (r < 25) begin ExtSrc = ExtSrc | (32'h1 << $urandom_range(1, 31)); ExtSrc[3] = 0; ExtSrc[6] = 0; ExtSrc[10] = 0; end
      else if (r < 50 && (MExtInt || SExtInt || $urandom_range(0, 9) == 0)) begin
        // handler: claim, service (drop the source some time later), complete
        int c;
        c = MExtInt ? 0 : SExtInt ? 1 : $urandom_range(0, 1);
        chk_rd(PLIC + (c ? 24'h201004 : 24'h200004), "plic claim");
        chk_rd(PLIC + 24'h1000, "plic pending after a claim");
        repeat ($urandom_range(0, 8)) @(negedge clk);
        // the handler services the device: its request drops (some stay high a while longer)
        if ($urandom_range(0, 3) != 0) ExtSrc = ExtSrc & ~p_prog;   // service everything in progress
        repeat ($urandom_range(0, 4)) @(negedge clk);
        for (int i = 1; i < 32; i++) if (p_prog[i] && $urandom_range(0, 1)) begin
          apb_wr(PLIC + (c ? 24'h201004 : 24'h200004), i); hit("plic: complete"); break;
        end
        hit(c ? "plic: claim on context 1 (S)" : "plic: claim on context 0 (M)");
      end else if (r < 55) apb_wr(PLIC + 24'h200004 + 24'h1000 * $urandom_range(0, 1), $urandom_range(0, 31));   // stray completion
      else if (r < 62) apb_wr(PLIC + 4 * $urandom_range(1, 31), $urandom_range(0, 7));
      else if (r < 66) apb_wr(PLIC + 24'h200000 + 24'h1000 * $urandom_range(0, 1), $urandom_range(0, 7));
      else if (r < 90) begin
        logic [23:0] o[6]; o = '{24'h1000, 24'h2000, 24'h2080, 24'h200000, 24'h201000, 24'h000004 * $urandom_range(1, 31)};
        chk_rd(PLIC + o[$urandom_range(0, 5)], "plic");
      end else repeat ($urandom_range(1, 10)) @(negedge clk);
    end
    // the book's Example 20.3 as a directed check: GPIO (id 3, prio 5) beats UART (id 10, prio 4)
    do_reset();
    apb_wr(PLIC + 12, 5); apb_wr(PLIC + 40, 4); apb_wr(PLIC + 24'h2000, (1 << 3) | (1 << 10)); apb_wr(PLIC + 24'h200000, 2);
    apb_wr(GPIO + 8'h04, 1); apb_wr(GPIO + 8'h28, 1); tbPins = 1;                 // GPIO high interrupt on pin 0
    apb_wr(UART + 1, 2);                                                          // UART THRE interrupt (TX empty)
    repeat (4) @(negedge clk);
    if (!MExtInt) err("Example 20.3: no MExtInt with GPIO and UART both requesting");
    apb_chk(PLIC + 24'h200004, 3, "Example 20.3: first claim (GPIO, priority 5)");
    apb_chk(PLIC + 24'h200004, 10, "Example 20.3: second claim (UART, priority 4)");
    apb_wr(UART + 1, 0); tbPins = 0; apb_wr(GPIO + 8'h28, 0); apb_wr(GPIO + 8'h2C, '1);
    apb_wr(PLIC + 24'h200004, 10); apb_wr(PLIC + 24'h200004, 3);
    repeat (4) @(negedge clk);
    apb_chk(PLIC + 24'h1000, 0, "Example 20.3: nothing pending after both completions");
    hit("plic: book Example 20.3");
  endtask

  task automatic t_uart(int iters, int seed);
    for (int it = 0; it < iters; it++) begin
      // walk the 24 frame formats (4 lengths x 3 parities x 2 stop) so the cross closes; the rest random
      int combo = (it + seed) % 24;
      int div = $urandom_range(1, 3), bits = 5 + combo % 4, trig = $urandom_range(0, 3), n;
      bit pen = (combo / 4) % 3 != 0, even = (combo / 4) % 3 == 2, stop2 = combo / 12;
      int trigN[4]; logic [31:0] q; byte unsigned sent[$]; bit quiet;
      sent.delete();
      trigN = '{1, 4, 8, 14};
      uart_config(div, bits, pen, even, stop2, 1, trig);
      // ---- transmit: the monitor decodes the pin ----
      n = $urandom_range(1, 16);
      apb_wr(UART + 1, 8'h02);                                  // ETBEI
      for (int i = 0; i < n; i++) begin byte unsigned b = $urandom; u_txExp.push_back(b); apb_wr(UART + 0, b); end
      begin int np = 0; do begin apb_rd(UART + 5, q); np++; if (show && np % 2000 == 1) $display("LSR 0x%02h @%0d txn %0d tbusy %b txexp %0d", q, cyc, dut.uart.txn, dut.uart.tbusy, u_txExp.size()); end while (!q[6]); end   // TEMT
      repeat (16 * div) @(negedge clk);
      if (u_txExp.size() != 0) err($sformatf("UART TX: %0d bytes never appeared on the pin", u_txExp.size()));
      u_txExp.delete();
      apb_chk(UART + 2, 8'hC2, "UART IIR = THRE after the TX FIFO drained");
      apb_chk(UART + 2, 8'hC1, "UART IIR: reading IIR cleared the THRE interrupt");
      hit("uart: THRE interrupt raised and cleared by IIR read");
      apb_wr(UART + 1, 8'h05);                                  // ERBFI + ELSI
      if (show) $display("UART RX phase @%0d", cyc);
      // ---- receive: drive the pin with baud-rate error and injected errors ----
      n = $urandom_range(0, 1) ? trigN[trig] + $urandom_range(0, 1) : $urandom_range(1, 15);
      if (n > 15) n = 15;
      quiet = n >= trigN[trig];                                 // no errors or early reads: let the trigger level be reached
      for (int i = 0; i < n; i++) begin
        byte unsigned b; real sc; bit bp, bs; logic [31:0] iir;
        b = $urandom; if (b == 0) b = 1;
        begin int e; e = $urandom_range(0, 40); e = e - 20; sc = ($urandom_range(0, 3) == 0) ? 1.03 : 1.0 + e / 1000.0; end
        if (sc > 1.025) hit("uart: remote 3% slow"); else if (sc < 0.985) hit("uart: remote 1.5%+ fast");
        bp = !quiet && pen && $urandom_range(0, 7) == 0; bs = !quiet && $urandom_range(0, 9) == 0;
        uart_send(b, sc, bp, bs);
        if (show) $display("UART sent 0x%02h scale %f pe %b fe %b @%0d", b, sc, bp, bs, cyc);
        sent.push_back(b);
        // after each character: RLS if the character at the head has an error, else RDA once the
        // FIFO holds the trigger level (characters with errors are drained at once, so the head
        // only has an error when this character is alone in the FIFO)
        apb_rd(UART + 2, iir);
        if ((bp || bs) && sent.size() == 1) begin
          if (iir[3:0] != 4'h6) err($sformatf("UART: IIR 0x%02h, expected RLS (0x6) for a %s error", iir, bp ? "parity" : "framing"));
        end else if (!(bp || bs)) begin
          logic [3:0] e; e = (sent.size() >= trigN[trig]) ? 4'h4 : 4'h1;
          if (iir[3:0] != e) err($sformatf("UART: IIR 0x%02h with %0d characters in the FIFO, trigger %0d", iir, sent.size(), trigN[trig]));
          if (e == 4'h4 && sent.size() == trigN[trig]) hit($sformatf("uart: RDA at trigger level %0d", trigN[trig]));
        end
        // read everything received so far, checking flags then data
        if (bp || bs || (!quiet && $urandom_range(0, 5) == 0)) begin
          int k = 0;
          while (sent.size()) begin
            byte unsigned e; logic [31:0] lsr, d;
            e = sent.pop_front() & byte'((1 << bits) - 1);
            apb_rd(UART + 5, lsr);
            if (!lsr[0]) begin err("UART: LSR.DR = 0 with characters outstanding"); break; end
            apb_rd(UART + 0, d);
            if (d[7:0] !== e && !(sent.size() == 0 && bs && e == 0)) err($sformatf("UART RX: read 0x%02h, sent 0x%02h", d[7:0], e));
            if (sent.size() == 0) begin
              if (lsr[2] !== bp) err($sformatf("UART RX: LSR.PE = %b for the last character, injected %b", lsr[2], bp));
              if (lsr[3] !== bs) err($sformatf("UART RX: LSR.FE = %b for the last character, injected %b", lsr[3], bs));
              if (bp) hit("uart: parity error detected"); if (bs) hit("uart: framing error detected");
            end
            k++;
          end
          hit("uart: RX FIFO drained");
        end
      end
      while (sent.size()) begin logic [31:0] d; byte unsigned e; e = sent.pop_front() & byte'((1 << bits) - 1); apb_rd(UART + 0, d); if (d[7:0] !== e) err($sformatf("UART RX: read 0x%02h, sent 0x%02h", d[7:0], e)); end
    end
    // ---- overrun: 17 characters into a 16-deep FIFO ----
    begin
      logic [31:0] q; byte unsigned ov[$];
      uart_config(1, 8, 0, 0, 0, 1, 3);
      for (int i = 0; i < 17; i++) begin byte unsigned b = 8'h40 + i; ov.push_back(b); uart_send(b, 1.0, 0, 0); end
      apb_rd(UART + 5, q);
      if (!q[1]) err("UART overrun: LSR.OE not set after 17 characters"); else hit("uart: overrun detected");
      apb_rd(UART + 5, q); if (q[1]) err("UART overrun: LSR.OE not cleared by reading LSR");
      for (int i = 0; i < 16; i++) begin logic [31:0] d; apb_rd(UART + 0, d); if (d[7:0] !== ov[i]) err($sformatf("UART overrun: FIFO entry %0d = 0x%02h, expected 0x%02h (the 17th character must be lost, not the 16th)", i, d[7:0], ov[i])); end
    end
    // ---- internal loopback (MCR.LOOP): the self-consistent check the book's test plan uses ----
    begin
      u_monOn = 0;
      uart_config(2, 8, 1, 1, 0, 1, 0); apb_wr(UART + 4, 8'h10);
      for (int i = 0; i < 6; i++) begin
        logic [31:0] d, l; byte unsigned b = $urandom;
        apb_wr(UART + 0, b);
        do apb_rd(UART + 5, l); while (!l[0]);
        apb_rd(UART + 0, d); if (d[7:0] !== b) err($sformatf("UART loopback: got 0x%02h, sent 0x%02h", d[7:0], b));
      end
      apb_wr(UART + 4, 0); u_monOn = 1; hit("uart: internal loopback");
    end
  endtask

  // the book's UART plan: every frame format in internal loopback, trigger levels, overflow
  task automatic t_uart_loop(int iters, int seed);
    u_monOn = 0;
    for (int it = 0; it < iters; it++) begin
      int combo = (it + seed) % 24, trig = $urandom_range(0, 3), n = $urandom_range(1, 12);
      int trigN[4]; logic [31:0] q;
      trigN = '{1, 4, 8, 14};
      uart_config($urandom_range(1, 3), 5 + combo % 4, (combo / 4) % 3 != 0, (combo / 4) % 3 == 2, combo / 12, 1, trig);
      apb_wr(UART + 4, 8'h10); apb_wr(UART + 1, 8'h01);
      for (int i = 0; i < n; i++) begin
        byte unsigned b = $urandom; logic [31:0] d, l, iir;
        b &= byte'((1 << u_bits) - 1);
        apb_wr(UART + 0, b);
        do apb_rd(UART + 5, l); while (!l[6]);                  // TEMT: the frame went round
        repeat (16 * u_div) @(negedge clk);
        if (l[3:1] != 0) err($sformatf("UART loopback: LSR 0x%02h shows an error", l));
        apb_rd(UART + 0, d); if (d[7:0] !== b) err($sformatf("UART loopback: got 0x%02h, sent 0x%02h", d[7:0], b));
      end
      hit("uart: internal loopback");
    end
    begin                                                       // overflow in loopback
      logic [31:0] q, l;
      uart_config(1, 8, 0, 0, 0, 1, 3); apb_wr(UART + 4, 8'h10);
      for (int i = 0; i < 16; i++) apb_wr(UART + 0, 8'h40 + i);
      do apb_rd(UART + 5, l); while (!l[6]);
      repeat (16) @(negedge clk);
      apb_wr(UART + 0, 8'h7E);
      // reading LSR clears OE, so the polling loop itself must collect it (a first version of this
      // test polled TEMT, then read LSR again, and found OE "never set")
      begin bit oe = 0;
        do begin apb_rd(UART + 5, l); oe |= l[1]; end while (!l[6]);
        repeat (16) @(negedge clk);
        apb_rd(UART + 5, l); oe |= l[1];
        if (!oe) err($sformatf("UART loopback overflow: LSR.OE not set (rxn %0d txn %0d LSR 0x%02h)", dut.uart.rxn, dut.uart.txn, l)); else hit("uart: overrun detected");
      end
      for (int i = 0; i < 16; i++) begin apb_rd(UART + 0, q); if (q[7:0] !== 8'h40 + i) err($sformatf("UART loopback overflow: entry %0d = 0x%02h", i, q[7:0])); end
      apb_wr(UART + 4, 0);
    end
    u_monOn = 1;
  endtask

  task automatic t_spi(int iters, int seed);
    for (int it = 0; it < iters; it++) begin
      int mode = (it + seed) % 4, len = ($urandom_range(0, 2) == 0) ? $urandom_range(1, 7) : 8, n;
      int div = $urandom_range(0, 3), csid = $urandom_range(0, 3), csmode = $urandom_range(0, 1) ? 2 : 0;
      bit lsb = ((it + seed) / 4) % 2;
      byte unsigned tx[$], resp[$]; logic [31:0] q;
      tx.delete(); resp.delete();                 // (block-local queues are not re-created per iteration)
      spiLoop = bookplan || ($urandom_range(0, 4) == 0);
      repeat (4) @(negedge clk);
      s_chk = 0;
      apb_wr(SPI + 8'h18, 0);
      apb_wr(SPI + 8'h00, div); apb_wr(SPI + 8'h04, mode); apb_wr(SPI + 8'h10, csid);
      apb_wr(SPI + 8'h40, {12'b0, 4'(len), 12'b0, 1'b0, lsb, 2'b0});
      apb_wr(SPI + 8'h18, csmode);
      repeat (4) @(negedge clk);
      s_pha = mode[0]; s_pol = mode[1]; s_lsb = lsb; s_len = len; s_cs = csid;
      s_resp.delete(); s_got.delete(); s_have = 0; s_chk = 1;
      if (show) $display("SPI config @%0d: mode %0d %s len %0d sckdiv %0d cs %0d csmode %0d loop %0b", cyc, mode, lsb ? "LSB" : "MSB", len, div, csid, csmode, spiLoop);
      hit($sformatf("spi: mode %0d %s-first", mode, lsb ? "LSB" : "MSB"));
      hit(spiLoop ? "spi: loopback" : "spi: external peripheral");
      if (len < 8) hit("spi: short frame (< 8 bits)");
      hit(csmode == 2 ? "spi: csmode HOLD" : "spi: csmode AUTO");
      n = $urandom_range(1, 8);
      for (int i = 0; i < n; i++) begin byte unsigned r = $urandom; resp.push_back(r); s_resp.push_back(r); end
      for (int i = 0; i < n; i++) begin
        byte unsigned b = $urandom; tx.push_back(b);
        do apb_rd(SPI + 8'h48, q); while (q[31]);
        apb_wr(SPI + 8'h48, b);
      end
      for (int i = 0; i < n; i++) begin
        byte unsigned e, m; m = byte'((1 << len) - 1);
        e = spiLoop ? tx[i] : resp[i];
        do apb_rd(SPI + 8'h4C, q); while (q[31]);
        if ((q[7:0] & m) !== (e & m)) err($sformatf("SPI mode %0d %s len %0d: received 0x%02h, expected 0x%02h", mode, lsb ? "LSB" : "MSB", len, q[7:0] & m, e & m));
      end
      if (csmode == 2) begin apb_wr(SPI + 8'h18, 0); repeat (8 * (div + 1)) @(negedge clk); end
      repeat (4 * (div + 1)) @(negedge clk);
      if (!spiLoop) begin
        if (s_got.size() != n) err($sformatf("SPI: peripheral saw %0d frames, %0d sent", s_got.size(), n));
        foreach (s_got[i]) if (i < n && (s_got[i] & byte'((1 << len) - 1)) !== (tx[i] & byte'((1 << len) - 1)))
          err($sformatf("SPI mode %0d %s len %0d: peripheral got 0x%02h, controller sent 0x%02h", mode, lsb ? "LSB" : "MSB", len, s_got[i], tx[i] & byte'((1 << len) - 1)));
      end
      // receive watermark interrupt
      apb_wr(SPI + 8'h54, 0); apb_wr(SPI + 8'h70, 2);
      apb_wr(SPI + 8'h48, 8'h3C);
      do apb_rd(SPI + 8'h74, q); while (!q[1]);
      if (!SPIIntr) err("SPI: ip.rxwm = 1 and ie.rxwm = 1 but SPIIntr = 0"); else hit("spi: rx watermark interrupt");
      apb_rd(SPI + 8'h4C, q); apb_wr(SPI + 8'h70, 0);
      repeat (4 * (div + 1)) @(negedge clk);
      void'(s_got.size());
    end
  endtask

  // ================================================================== main
  initial begin
    int seed = 1, iters = 300; string vcd;
    if (!$value$plusargs("TEST=%s", testname)) testname = "all";
    void'($value$plusargs("SEED=%d", seed));
    void'($value$plusargs("ITER=%d", iters));
    show = $test$plusargs("SHOW");
    bookplan = $test$plusargs("BOOKPLAN");
    if ($value$plusargs("VCD=%s", vcd)) begin $dumpfile(vcd); $dumpvars(0, tb_periph); end
    void'($urandom(seed));
    // declare every bin up front so misses show as 0
    begin
      string all_bins[] = '{"regs: reset values", "regs: walking read-back", "regs: DLAB banking",
        "gpio: external pins", "gpio: loopback mode", "gpio: pin change", "gpio: W1C write", "gpio: GPIOIntr asserted",
        "gpio: clear and set in the same cycle", "gpio: book Example 20.1",
        "clint: mtimecmp near mtime", "clint: mtime == mtimecmp (boundary)", "clint: timer interrupt", "clint: software interrupt",
        "clint: mtime written near 2^32", "clint: mtime low word wraps (carry)", "clint: hi-lo-hi read", "clint: torn 64-bit read retried",
        "plic: MExtInt", "plic: SExtInt", "plic: claim on context 0 (M)", "plic: claim on context 1 (S)", "plic: complete",
        "plic: tie broken by lowest id", "plic: best priority == threshold (masked)", "plic: claim with nothing pending returns 0",
        "plic: source still high while in progress", "plic: completion with an id not enabled (ignored)", "plic: book Example 20.3",
        "uart: THRE interrupt raised and cleared by IIR read", "uart: parity error detected", "uart: framing error detected",
        "uart: remote 3% slow", "uart: remote 1.5%+ fast", "uart: RX FIFO drained", "uart: overrun detected", "uart: internal loopback",
        "spi: mode 0 MSB-first", "spi: mode 1 MSB-first", "spi: mode 2 MSB-first", "spi: mode 3 MSB-first",
        "spi: mode 0 LSB-first", "spi: mode 1 LSB-first", "spi: mode 2 LSB-first", "spi: mode 3 LSB-first",
        "spi: short frame (< 8 bits)", "spi: csmode HOLD", "spi: csmode AUTO", "spi: loopback", "spi: external peripheral",
        "spi: chip select asserted", "spi: rx watermark interrupt"};
      foreach (all_bins[i]) bin(all_bins[i]);
      for (int b = 5; b <= 8; b++) for (int p = 0; p < 3; p++) for (int st = 1; st <= 2; st++)
        bin($sformatf("uart: %0d bits, parity %s, %0d stop", b, parname(p), st));
      bin("uart: RDA at trigger level 1"); bin("uart: RDA at trigger level 4"); bin("uart: RDA at trigger level 8"); bin("uart: RDA at trigger level 14");
    end
    do_reset();
    if (testname == "all" || testname == "regs")  begin do_reset(); t_regs(); end
    if (testname == "all" || testname == "gpio")  begin do_reset(); t_gpio(iters * 2); end
    if (testname == "all" || testname == "clint") begin do_reset(); t_clint(iters); end
    if (testname == "all" || testname == "plic")  begin do_reset(); t_plic(iters); end
    if (testname == "all" || testname == "uart")  begin do_reset(); if (bookplan) t_uart_loop(iters / 8 + 2, seed); else t_uart(iters / 8 + 2, seed); end
    if (testname == "all" || testname == "spi")   begin do_reset(); t_spi(iters / 10 + 4, seed); end
    repeat (10) @(negedge clk);
    begin
      int h = 0, tot = 0;
      foreach (covBins[i]) begin
        if (testname == "all" || covBins[i].substr(0, testname.len() - 1) == testname) begin
          tot++; if (cov[covBins[i]] > 0) h++;
          $display("COV %6d  %s", cov[covBins[i]], covBins[i]);
        end
      end
      $display("COVERAGE %0d/%0d bins hit", h, tot);
      $display("PERIPH %s test=%s seed=%0d errors=%0d cycles=%0d", errors ? "FAIL" : "PASS", testname, seed, errors, cyc);
    end
    $finish;
  end
  initial begin #50_000_000; $display("PERIPH FAIL test=%s timeout", testname); $finish; end
endmodule
