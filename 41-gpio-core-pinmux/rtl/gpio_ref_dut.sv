// -----------------------------------------------------------------------------
// gpio_ref_dut.sv : clean-room GPIO model written from the GPIO v1.0 User Guide
//
// This is NOT Chipmunk Logic's RTL. The real sources in gpio_v1_0.rar are
// password-protected, so this module re-implements the behaviour described in
// the User Guide (tristate mode, interrupts enabled) with the same port and
// parameter names as gpio_top. It lets the testbench compile and run before
// the real RTL is unlocked. Compile with +define+USE_CHIPMUNK_RTL to use the
// real gpio_top instead.
//
// Where the User Guide is silent, this model picks one behaviour and marks it
// "SPEC GAP". The testbench config (gpio_cfg.svh) holds the same assumptions.
//
//   Registers (UG Table 6.1)          Behaviour chosen for spec gaps
//   0x00 i_data      RO               - unmapped / unaligned reads return 0
//   0x04 o_data      RW               - GME=1 enables the per-pin mask register
//   0x08 io_dir      RW 0=out 1=in    - hardware set wins over W1C in one cycle
//   0x0C glb [0]GIE [1]GME            - glitch filter = GLF_LEN stable clocks
//   0x10 intr_en     RW (0 clears sts)
//   0x14 intr_mask   RW 1=masked
//   0x18 intr_type   RW 0=level 1=edge
//   0x1C intr_evnt   RW 0=low/fall 1=high/rise
//   0x20 intr_sts    W1C (masked view)
//   0x24 intr_sts_raw RO
//   0x28 intr_set    WO (gated by IE)
//
// Bug injection (to prove the checkers can fail; see Makefile target 'bugs'):
//   +define+BUG_W1C_WINS     W1C beats a same-cycle hardware set (lost event)
//   +define+BUG_NO_RD_WAIT   reads finish in 2 clocks instead of 3
//   +define+BUG_IE_NO_CLEAR  clearing IE leaves the status bit set
//   +define+BUG_MASK_DROPS   a masked event is dropped instead of kept pending
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module gpio_ref_dut #(
  parameter int              GPIO_WIDTH = 8,
  parameter logic [GPIO_WIDTH-1:0] DEF_O_VAL  = '0,
  parameter logic [GPIO_WIDTH-1:0] DEF_IO_DIR = '1,   // 1 = input (safe at power-up)
  parameter logic [GPIO_WIDTH-1:0] EN_SYNC    = '1,
  parameter logic [GPIO_WIDTH-1:0] EN_GLF     = '0,
  parameter int              GLF_LEN    = 4         // SPEC GAP: not in the UG
) (
  input  logic                  clk,
  input  logic                  resetn,
  inout  wire  [GPIO_WIDTH-1:0] io_gpio,
  output logic                  o_intr,
  input  logic [7:0]            i_paddr,
  input  logic                  i_psel,
  input  logic                  i_penable,
  input  logic                  i_pwrite,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0]           i_pwdata,   // only [W-1:0] used
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [31:0]           o_prdata,
  output logic                  o_pready
);
  localparam int W = GPIO_WIDTH;

  // ---------------------------------------------------------------- CSRs ----
  logic [W-1:0] o_data_q, io_dir_q, ie_q, me_q, type_q, evnt_q, raw_q;
  logic         gie_q, gme_q;

  // ------------------------------------------------------- tristate pads ----
  for (genvar i = 0; i < W; i++) begin : g_pad
    assign io_gpio[i] = io_dir_q[i] ? 1'bz : o_data_q[i];   // OE = ~dir
  end

  // ------------------------------------------ sync + glitch filter (irq_sync)
  logic [W-1:0] pin_s;                       // conditioned pin value
  for (genvar i = 0; i < W; i++) begin : g_in
    logic raw_in;

    if (EN_SYNC[i]) begin : g_sync
      logic s1, s2;                          // 2-FF synchronizer
      always_ff @(posedge clk or negedge resetn)
        if (!resetn) {s2, s1} <= '0;
        else         {s2, s1} <= {s1, io_gpio[i]};
      assign raw_in = s2;
    end else begin : g_nosync
      assign raw_in = io_gpio[i];
    end

    // A new level is accepted only after it has been stable for GLF_LEN clocks.
    if (EN_SYNC[i] && EN_GLF[i]) begin : g_glf
      logic filt;
      logic [$clog2(GLF_LEN+1)-1:0] cnt;
      always_ff @(posedge clk or negedge resetn)
        if (!resetn) begin
          filt <= 1'b0;
          cnt  <= '0;
        end else if (raw_in == filt) begin
          cnt  <= '0;
        end else if (cnt == GLF_LEN[$bits(cnt)-1:0] - 1'b1) begin
          filt <= raw_in;
          cnt  <= '0;
        end else begin
          cnt  <= cnt + 1'b1;
        end
      assign pin_s[i] = filt;
    end else begin : g_noglf
      assign pin_s[i] = raw_in;
    end
  end

  // ------------------------------------------- event detect (intr_gateway) ----
  logic [W-1:0] pin_d, evt;
  always_ff @(posedge clk or negedge resetn)
    if (!resetn) pin_d <= '0;
    else         pin_d <= pin_s;

  for (genvar i = 0; i < W; i++) begin : g_evt
    assign evt[i] = !type_q[i] ? (pin_s[i] == evnt_q[i])                 // level
                  :  evnt_q[i] ? ( pin_s[i] & ~pin_d[i])                 // rising
                               : (~pin_s[i] &  pin_d[i]);                // falling
  end

  // ------------------------------------------------------------- APB ----
  // Write: SETUP + 1 ACCESS cycle (2 clk). Read: SETUP + 2 ACCESS cycles
  // (3 clk): one wait state, then registered read data with PREADY.
  logic        rd_wait_q;
  wire         access = i_psel & i_penable;
  wire         wr_en  = access & i_pwrite;                 // pready is 1 for writes
  wire  [5:0]  word   = i_paddr[7:2];
  wire         alignd = (i_paddr[1:0] == 2'b00);

  always_ff @(posedge clk or negedge resetn)
    if (!resetn)                         rd_wait_q <= 1'b0;
    else if (access & ~i_pwrite & ~rd_wait_q) rd_wait_q <= 1'b1;
    else                                 rd_wait_q <= 1'b0;

`ifdef BUG_NO_RD_WAIT
  assign o_pready = access;
`else
  assign o_pready = i_pwrite ? access : (access & rd_wait_q);
`endif

  wire wr_ok = wr_en & alignd;
  wire [W-1:0] wd = i_pwdata[W-1:0];

  always_ff @(posedge clk or negedge resetn)
    if (!resetn) begin
      o_data_q <= DEF_O_VAL;
      io_dir_q <= DEF_IO_DIR;
      {gme_q, gie_q} <= 2'b00;
      ie_q <= '0; me_q <= '0; type_q <= '0; evnt_q <= '0;
    end else if (wr_ok) begin
      case (word)
        6'h01: o_data_q <= wd;
        6'h02: io_dir_q <= wd;
        6'h03: {gme_q, gie_q} <= i_pwdata[1:0];
        6'h04: ie_q     <= wd;
        6'h05: me_q     <= wd;
        6'h06: type_q   <= wd;
        6'h07: evnt_q   <= wd;
        default: ;
      endcase
    end

  // Raw status. Priority (SPEC GAP): IE=0 clear > hardware/software set > W1C.
  wire [W-1:0] w1c   = (wr_ok && word == 6'h08) ? wd : '0;
  wire [W-1:0] swset = (wr_ok && word == 6'h0A) ? wd : '0;
  always_ff @(posedge clk or negedge resetn)
    if (!resetn) raw_q <= '0;
`ifdef BUG_W1C_WINS
    else         raw_q <= ((raw_q | evt | swset) & ~w1c) & ie_q;
`elsif BUG_IE_NO_CLEAR
    else         raw_q <= (raw_q & ~w1c) | ((evt | swset) & ie_q);
`elsif BUG_MASK_DROPS
    else         raw_q <= ((raw_q & ~w1c) | ((evt | swset) & ~(me_q & {W{gme_q}}))) & ie_q;
`else
    else         raw_q <= ((raw_q & ~w1c) | evt | swset) & ie_q;
`endif

  // ----------------------------------------------- output (intr_gen) ----
  wire [W-1:0] sts = gme_q ? (raw_q & ~me_q) : raw_q;
  always_ff @(posedge clk or negedge resetn)
    if (!resetn) o_intr <= 1'b0;
    else         o_intr <= gie_q & (|sts);

  // ------------------------------------------------------------ read mux ----
  logic [31:0] rmux;
  always_comb begin
    rmux = '0;
    if (alignd)
      case (word)
        6'h00: rmux[W-1:0] = pin_s;
        6'h01: rmux[W-1:0] = o_data_q;
        6'h02: rmux[W-1:0] = io_dir_q;
        6'h03: rmux[1:0]   = {gme_q, gie_q};
        6'h04: rmux[W-1:0] = ie_q;
        6'h05: rmux[W-1:0] = me_q;
        6'h06: rmux[W-1:0] = type_q;
        6'h07: rmux[W-1:0] = evnt_q;
        6'h08: rmux[W-1:0] = sts;
        6'h09: rmux[W-1:0] = raw_q;
        default: rmux = '0;        // 0x28 (WO) and unmapped read 0
      endcase
  end

  always_ff @(posedge clk or negedge resetn)
    if (!resetn)                              o_prdata <= '0;
`ifdef BUG_NO_RD_WAIT
    else if (access & ~i_pwrite)              o_prdata <= rmux;
`else
    else if (access & ~i_pwrite & ~rd_wait_q) o_prdata <= rmux;  // ready next clk
`endif
endmodule : gpio_ref_dut
