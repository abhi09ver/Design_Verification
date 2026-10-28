// tb_ahb.sv -- Lab 6 block-level testbench for the uncore, with no CPU.
//
// The core's LSU is a polite manager: one transfer at a time, address held through the Data
// phase, write data valid early. That hides whole classes of subordinate bugs. This bench
// replaces it with a constrained-random AHB manager that does what the protocol allows:
//   * back-to-back pipelined transfers (next Address phase during this Data phase)
//   * random IDLE cycles, random sizes and byte lanes, random devices including unmapped space
//   * HWDATA valid ONLY in the Data phase (garbage otherwise)
// and checks:
//   * every read against a reference model of the devices (scoreboard, in order)
//   * liveness: HREADY may not stay low for more than 32 cycles
// plus functional coverage counters for the scenarios that matter.
//
//   +SEED=<n>  +CYCLES=<n>   (compile with -DBUG_* to inject an uncore bug)

module tb_ahb;
  logic clk = 0, reset = 1;
  always #5 clk = ~clk;

  logic [31:0] HADDR, HWDATA, HRDATA, GPIOOUT, GPIOEN, GPIOIN;
  logic        HWRITE, HREADY, MTimerInt, MSwInt, MExtInt;
  logic [1:0]  HTRANS;
  logic [2:0]  HSIZE;
  logic [3:0]  HWSTRB;
  localparam logic [31:0] PADS_IN = 32'h5A5A_0F0F;
  assign GPIOIN = (GPIOEN & GPIOOUT) | (~GPIOEN & PADS_IN);
  uncore dut(.*);

  // ---------------- random numbers (xorshift32: same stream on every simulator) ----------------
  logic [31:0] rng = 32'h1;
  function automatic logic [31:0] rnd();
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
  endfunction

  // ---------------- reference model (what software would observe) ----------------
  logic [7:0]  ram [int];               // sparse bytes, 0 if never written
  logic [31:0] m_gout = 0, m_gen = 0, m_fifo = 32'h100, m_cmplo = '1, m_cmphi = '1;
  logic        m_msip = 0, m_mext = 0;

  function automatic logic [31:0] model_read(input logic [31:0] a);
    logic [31:0] w = 0;
    if (a[31:16] == 16'h9000) begin
      for (int b = 0; b < 4; b++) w[8*b +: 8] = ram.exists(int'({a[15:2], 2'(b)})) ? ram[int'({a[15:2], 2'(b)})] : 8'h0;
    end else if (a[31:24] == 8'h10) begin
      case (a[23:16])
        8'h06: case (a[3:2]) 2'd0: w = m_gout; 2'd1: w = m_gen; 2'd2: w = (m_gen & m_gout) | (~m_gen & PADS_IN); default: w = 0; endcase
        8'h00: begin w = m_fifo; m_fifo++; end
        8'h20: case (a[4:2]) 3'd0: w = {31'b0, m_msip}; 3'd1: w = m_cmplo; 3'd2: w = m_cmphi; 3'd4: w = {31'b0, m_mext}; default: w = 0; endcase
        default: w = 0;
      endcase
    end
    return w;
  endfunction

  function automatic void model_write(input logic [31:0] a, input logic [31:0] d, input logic [3:0] s);
    if (a[31:16] == 16'h9000) begin
      for (int b = 0; b < 4; b++) if (s[b]) ram[int'({a[15:2], 2'(b)})] = d[8*b +: 8];
    end else if (a[31:24] == 8'h10) begin
      case (a[23:16])
        8'h06: for (int b = 0; b < 4; b++) if (s[b]) begin
                 if (a[3:2] == 2'd0) m_gout[8*b +: 8] = d[8*b +: 8];
                 if (a[3:2] == 2'd1) m_gen [8*b +: 8] = d[8*b +: 8];
               end
        8'h00: m_fifo = d;
        8'h20: case (a[4:2]) 3'd0: if (s[0]) m_msip = d[0]; 3'd1: m_cmplo = d; 3'd2: m_cmphi = d;
                             3'd4: if (s[0]) m_mext = d[0]; default: ; endcase
        default: ;
      endcase
    end
  endfunction

  // ---------------- the random manager ----------------
  typedef struct packed { logic v, w; logic [31:0] a; logic [2:0] sz; logic [3:0] strb; logic [31:0] d; logic [2:0] reg_; } xfer_t;
  xfer_t A, D;                          // transfer in its Address phase, and in its Data phase
  int    errors = 0, cycles = 0, maxcyc = 20000, waitrun = 0, maxwait = 0;
  // coverage
  int c_ram = 0, c_gpio = 0, c_fifo = 0, c_clint = 0, c_unmapped = 0, c_apbnone = 0;
  int c_wr_then_rd_ram = 0, c_b2b = 0, c_waits = 0, c_xdev_wait = 0, c_narrow = 0;

  function automatic xfer_t new_xfer();
    xfer_t x; logic [31:0] r = rnd(); int region = r % 100;
    x = '0;
    if (rnd() % 100 < 20) return x;                       // IDLE
    x.v = 1; x.w = rnd() % 2 == 1;
    x.sz = 3'(rnd() % 3);
    if      (region < 50) begin x.a = 32'h9000_0000 | (rnd() & 32'h3F); x.reg_ = 1; end   // small window: collisions
    else if (region < 65) begin x.a = 32'h1006_0000 | ((rnd() % 3) << 2) | (rnd() & 3); x.reg_ = 2; end
    else if (region < 75) begin x.a = 32'h1000_0000; x.sz = 2; x.reg_ = 3; end
    else if (region < 80) begin
      case (rnd() % 4) 0: x.a = 32'h1020_0000; 1: x.a = 32'h1020_0004; 2: x.a = 32'h1020_0008; default: x.a = 32'h1020_0010; endcase
      x.sz = 2; x.reg_ = 4;
    end
    else if (region < 92) begin x.a = 32'h9800_0000 | (rnd() & 32'hFFC); x.reg_ = 5; end    // unmapped
    else                  begin x.a = 32'h10F0_0000; x.sz = 2; x.reg_ = 6; end              // bridge, no device
    // natural alignment; strobes and data on the lanes the address selects (little-endian)
    if (x.sz == 1) x.a[0] = 0;
    if (x.sz == 2) x.a[1:0] = 0;
    x.strb = (x.sz == 0) ? 4'b0001 << x.a[1:0] : (x.sz == 1) ? 4'b0011 << x.a[1:0] : 4'b1111;
    x.d = rnd();
    return x;
  endfunction

  assign HADDR  = A.a;
  assign HWRITE = A.w;
  assign HTRANS = A.v ? 2'b10 : 2'b00;
  assign HSIZE  = A.sz;
  logic [31:0] garbage;
  assign HWDATA = (D.v & D.w) ? D.d : garbage;           // only meaningful in the Data phase
  assign HWSTRB = (D.v & D.w) ? D.strb : 4'(garbage);

  initial begin
    int seed = 1;
    void'($value$plusargs("SEED=%d", seed));
    void'($value$plusargs("CYCLES=%d", maxcyc));
    rng = 32'(seed) * 32'h9E37_79B9 + 32'd1;
    A = '0; D = '0; garbage = 32'hDEAD_BEEF;
    repeat (2) @(posedge clk);
    #1 reset = 0;
  end

  always @(posedge clk) if (!reset) begin
    cycles++;
    garbage <= rnd();
    if (HREADY) begin
      waitrun = 0;
      // 1) the Data phase in progress completes now: check / update the model
      if (D.v) begin
        if (D.w) model_write(D.a, D.d, D.strb);
        else begin
          logic [31:0] exp = model_read(D.a), mask = 0;
          for (int b = 0; b < 4; b++) if (D.strb[b]) mask[8*b +: 8] = 8'hFF;
          if ((HRDATA & mask) !== (exp & mask)) begin
            errors++;
            if (errors <= 5) $display("ERROR cycle %0d: read %08h size %0d got %08h expected %08h",
                                      cycles, D.a, D.sz, HRDATA & mask, exp & mask);
          end
        end
      end
      // coverage on the hand-over
      if (A.v & D.v) c_b2b++;
      if (A.v & D.v & D.w & ~A.w & A.reg_ == 1 & D.reg_ == 1) c_wr_then_rd_ram++;
      if (A.v) case (A.reg_) 1: c_ram++; 2: c_gpio++; 3: c_fifo++; 4: c_clint++; 5: c_unmapped++; 6: c_apbnone++; endcase
      if (A.v & A.sz != 2) c_narrow++;
      // 2) the Address phase is accepted and becomes the Data phase; 3) start a new one
      D <= A;
      A <= new_xfer();
    end else begin
      // AHB: while HREADY is low the manager holds its Address phase
      c_waits++;
      waitrun++;
      if (waitrun > maxwait) maxwait = waitrun;
      if (A.v & D.v & A.reg_ != D.reg_) c_xdev_wait++;
      if (waitrun > 32) begin
        $display("ERROR cycle %0d: AHB hang, HREADY low for 32 cycles (Data phase %08h)", cycles, D.a);
        errors++;
        report();
        $finish;
      end
    end
    if (cycles >= maxcyc) begin report(); $finish; end
  end

  task automatic report();
    $display("AHBTB %s errors=%0d cycles=%0d | xfers ram=%0d gpio=%0d fifo=%0d clint=%0d unmapped=%0d apb-none=%0d | back-to-back=%0d wr->rd(ram)=%0d narrow=%0d wait-cycles=%0d cross-device-waits=%0d max-wait=%0d",
             errors ? "FAIL" : "PASS", errors, cycles, c_ram, c_gpio, c_fifo, c_clint, c_unmapped, c_apbnone,
             c_b2b, c_wr_then_rd_ram, c_narrow, c_waits, c_xdev_wait, maxwait);
  endtask
endmodule
