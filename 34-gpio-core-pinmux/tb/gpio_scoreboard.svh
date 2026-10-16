// -----------------------------------------------------------------------------
// gpio_scoreboard.svh : reference model + checker for GPIO v1.0
//
// Written from the User Guide, not from the RTL, so a bug in the RTL is not
// copied into the model.
//
// How it works
//   * Two streams come in: completed APB transfers (apb_monitor) and one pin
//     sample per clock (pin_monitor). Both carry the same cycle count.
//   * For every clock the model applies the APB writes that completed before
//     that clock, filters the pin values, detects events, and updates its raw
//     status. It then predicts o_intr and the value of every register read.
//   * The exact DUT latency (sync + glitch filter + status flop) is not in the
//     UG and changes with EN_SYNC/EN_GLF. Instead of a cycle-exact model, a bit
//     is "uncertain" for LAT clocks after its pin or the interrupt
//     config changes, and uncertain bits are not compared. Pulses whose width
//     sits near the filter threshold "taint" the pin until a quiet read of the
//     raw status re-syncs the model.
//   * The cost: a one-cycle race inside the window (W1C vs event) is covered
//     here but not checked. gpio_ref_wb_sva.sv checks that race white-box.
// -----------------------------------------------------------------------------

class gpio_scoreboard extends uvm_component;
  `uvm_component_utils(gpio_scoreboard)

  uvm_tlm_analysis_fifo #(apb_item)   apb_fifo;
  uvm_tlm_analysis_fifo #(pin_sample) pin_fifo;

  gpio_cfg      cfg;
  gpio_coverage cov;

  // ---- model state: register shadows ----
  bit [GPIO_W-1:0] o_data, io_dir, ie, me, typ, evnt, raw;
  bit              gie, gme;

  // ---- model state: input conditioning ----
  bit [GPIO_W-1:0] net_q;                 // last sampled pad value
  bit [GPIO_W-1:0] pin_f;                 // filtered value seen by the detector
  int unsigned     run_len[GPIO_W];       // clocks the current pad level has held
  longint          last_pin_chg[GPIO_W];  // cycle of the last pad change
  longint          last_evt[GPIO_W];      // cycle of the last detected event
  longint          last_cfg;              // cycle of the last interrupt-config write
  bit [GPIO_W-1:0] taint;
  longint          last_apb_cyc;

  // Latency window as a signed value, so cycle differences compare signed.
  longint          LAT;

  // ---- statistics ----
  int unsigned n_reads, n_bits_checked, n_bits_skipped, n_intr_checked, n_errors;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    apb_fifo = new("apb_fifo", this);
    pin_fifo = new("pin_fifo", this);
    if (!uvm_config_db#(gpio_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "gpio_cfg not set")
    LAT = longint'(cfg.lat_max);
    reset_model();
  endfunction

  function void reset_model();
    o_data = cfg.def_o_val;  io_dir = cfg.def_io_dir;
    ie = '0; me = '0; typ = '0; evnt = '0; raw = '0; gie = 0; gme = 0;
    net_q = '0; pin_f = '0; taint = '0;
    foreach (run_len[i]) begin
      run_len[i] = 0; last_pin_chg[i] = 0; last_evt[i] = -100;
    end
    last_cfg = 0; last_apb_cyc = -10;
  endfunction

  // What o_intr and the 0x20 read see.
  function bit [GPIO_W-1:0] masked(bit [GPIO_W-1:0] r);
    if (cfg.gme_enables_mask) return gme ? (r & ~me) : r;
    else                      return r & ~me;
  endfunction

  // Bits whose value can't be predicted exactly at cycle c.
  function bit [GPIO_W-1:0] uncertain(longint c);
    bit [GPIO_W-1:0] u = taint;
    for (int i = 0; i < GPIO_W; i++)
      if (c - last_pin_chg[i] <= LAT) u[i] = 1;
    if (c - last_cfg <= LAT) u = '1;
    return u;
  endfunction

  // ------------------------------------------------------------ main loop ----
  task run_phase(uvm_phase phase);
    pin_sample s;
    apb_item   t;
    forever begin
      pin_fifo.get(s);
      // Apply every APB transfer that completed before this clock.
      while (apb_fifo.try_peek(t) && t.cyc < s.cyc) begin
        void'(apb_fifo.try_get(t));
        on_apb(t);
      end
      on_clock(s);
    end
  endtask

  // ---------------------------------------------------------- APB side ----
  function void on_apb(apb_item t);
    bit [GPIO_W-1:0] d = t.data[GPIO_W-1:0];
    bit aligned = (t.addr[1:0] == 2'b00);
    bit b2b = (t.cyc - last_apb_cyc) <= 3;   // write 2 clk / read 3 clk: no IDLE
    last_apb_cyc = t.cyc;
    cov.cg_apb.sample(t.addr, t.write, b2b);

    if (!t.write) begin
      check_read(t);
      return;
    end
    if (!aligned) return;                    // SPEC GAP: unaligned writes ignored

    case (t.addr)
      ADDR_O_DATA : o_data = d;
      ADDR_IO_DIR : io_dir = d;
      ADDR_GLB    : begin gie = t.data[0]; gme = t.data[1]; last_cfg = t.cyc; end
      ADDR_INTR_EN: begin
        for (int i = 0; i < GPIO_W; i++)
          if (ie[i] && !d[i] && raw[i]) cov.cg_race.sample(RACE_IE_OFF_PENDING);
        ie = d;
        raw &= ie;                           // IE = 0 clears status (UG 7.4)
        taint &= ie;
        last_cfg = t.cyc;
      end
      ADDR_INTR_MSK: begin
        for (int i = 0; i < GPIO_W; i++)
          if (me[i] && !d[i] && raw[i]) cov.cg_race.sample(RACE_UNMASK_PENDING);
        me = d; last_cfg = t.cyc;
      end
      ADDR_INTR_TYP: begin typ  = d; last_cfg = t.cyc; end
      ADDR_INTR_EVT: begin evnt = d; last_cfg = t.cyc; end
      ADDR_INTR_STS: begin                   // W1C
        for (int i = 0; i < GPIO_W; i++) if (d[i]) begin
          if (t.cyc - last_evt[i] <= 2)                 cov.cg_race.sample(RACE_W1C_WITH_EVENT);
          if (!typ[i] && pin_f[i] == evnt[i] && ie[i])  cov.cg_race.sample(RACE_W1C_WHILE_LEVEL);
        end
        raw   &= ~d;
        taint &= ~d;
        last_cfg = t.cyc;
      end
      ADDR_INTR_SET: begin raw |= d & ie; last_cfg = t.cyc; end
      default: ;                             // RO / unmapped: no effect
    endcase
    for (int i = 0; i < GPIO_W; i++)
      cov.cg_pin_cfg.sample(i, io_dir[i], ie[i], me[i], typ[i], evnt[i], gie, gme);
  endfunction

  function void check_read(apb_item t);
    bit [31:0]       exp = '0;
    bit [GPIO_W-1:0] dc  = '0;               // don't-care bits
    bit [GPIO_W-1:0] got = t.data[GPIO_W-1:0];
    n_reads++;

    if (t.addr[1:0] == 2'b00) case (t.addr)
      ADDR_I_DATA  : begin exp[GPIO_W-1:0] = pin_f;
                           for (int i = 0; i < GPIO_W; i++)
                             if (t.cyc - last_pin_chg[i] <= LAT) dc[i] = 1; end
      ADDR_O_DATA  : exp[GPIO_W-1:0] = o_data;
      ADDR_IO_DIR  : exp[GPIO_W-1:0] = io_dir;
      ADDR_GLB     : exp[1:0]        = {gme, gie};
      ADDR_INTR_EN : exp[GPIO_W-1:0] = ie;
      ADDR_INTR_MSK: exp[GPIO_W-1:0] = me;
      ADDR_INTR_TYP: exp[GPIO_W-1:0] = typ;
      ADDR_INTR_EVT: exp[GPIO_W-1:0] = evnt;
      ADDR_INTR_STS: begin exp[GPIO_W-1:0] = masked(raw); dc = uncertain(t.cyc); end
      ADDR_STS_RAW : begin
        exp[GPIO_W-1:0] = raw; dc = uncertain(t.cyc);
        // Re-sync tainted bits whose pin and config have been quiet.
        for (int i = 0; i < GPIO_W; i++)
          if (taint[i] && t.cyc - last_pin_chg[i] > LAT
                       && t.cyc - last_cfg > LAT) begin
            raw[i]   = got[i];
            taint[i] = 0;
          end
      end
      default      : exp = '0;               // 0x28 WO and unmapped read 0
    endcase

    // Reserved bits always 0, every address.
    if (GPIO_W < 32 && (t.data >> GPIO_W) != 0) begin
      n_errors++;
      `uvm_error("SB_RSVD", $sformatf("addr 0x%02h: reserved bits not 0 (0x%08h)",
                                      t.addr, t.data))
    end
    n_bits_checked += GPIO_W - $countones(dc);
    n_bits_skipped += $countones(dc);
    if (((got ^ exp[GPIO_W-1:0]) & ~dc) != 0) begin
      n_errors++;
      `uvm_error("SB_READ", $sformatf(
        "addr 0x%02h @cyc %0d: got 0x%0h exp 0x%0h (don't-care 0x%0h)",
        t.addr, t.cyc, got, exp[GPIO_W-1:0], dc))
    end
  endfunction

  // ---------------------------------------------------------- pin side ----
  function void on_clock(pin_sample s);
    bit [GPIO_W-1:0] new_f = pin_f;
    bit [GPIO_W-1:0] evt   = '0;

    for (int i = 0; i < GPIO_W; i++) begin
      int unsigned fl = cfg.filt_len(i);
      if ($isunknown(s.io[i])) begin         // Z/X: undriven or contention
        last_pin_chg[i] = s.cyc;
        continue;
      end
      if (s.io[i] !== net_q[i]) begin
        // The level that just ended was held for w clocks. A width within one
        // clock of the filter length may or may not get through (async phase),
        // so the model can't know the outcome: taint the pin.
        int unsigned w = run_len[i] + 1;
        cov.cg_pulse.sample(w, fl > 1);
        if (w + 1 >= fl && w <= fl + 1) taint[i] = 1;
        net_q[i] = s.io[i];
        run_len[i] = 0;
        last_pin_chg[i] = s.cyc;
      end else begin
        run_len[i]++;
      end
      if (run_len[i] + 1 >= fl) new_f[i] = net_q[i];   // stable long enough
    end

    // Event detection on the filtered value (UG: type x evnt).
    for (int i = 0; i < GPIO_W; i++) begin
      bit rise = new_f[i] & ~pin_f[i];
      bit fall = ~new_f[i] & pin_f[i];
      if (!typ[i]) evt[i] = (new_f[i] == evnt[i]);
      else         evt[i] = evnt[i] ? rise : fall;

      if (rise || fall || (evt[i] && !typ[i] && !raw[i])) begin
        ev_kind_e k = rise ? EV_RISE : fall ? EV_FALL : (new_f[i] ? EV_HIGH : EV_LOW);
        outcome_e o = !evt[i] ? OUT_NO_MATCH :
                      !ie[i]  ? OUT_DROPPED  :
                      (masked(GPIO_W'(1) << i) == 0) ? OUT_MASKED : OUT_SET;
        cov.cg_event.sample(k, o, typ[i]);
      end
      if (evt[i]) last_evt[i] = s.cyc;
    end
    pin_f = new_f;
    raw   = (raw | evt) & ie;

    // o_intr = GIE & |masked status, checked only when nothing is in flight.
    if (uncertain(s.cyc) == 0) begin
      bit exp_intr = gie && (masked(raw) != 0);
      n_intr_checked++;
      if (s.intr !== exp_intr) begin
        n_errors++;
        `uvm_error("SB_INTR", $sformatf("cyc %0d: o_intr=%b exp %b (raw 0x%0h gie %b gme %b me 0x%0h)",
                                        s.cyc, s.intr, exp_intr, raw, gie, gme, me))
      end
    end
  endfunction

  // A scoreboard that never compares anything passes everything.
  function void check_phase(uvm_phase phase);
    if (n_reads == 0 || n_bits_checked == 0)
      `uvm_error("SB_EMPTY", "scoreboard checked no register bits")
    if (n_intr_checked == 0)
      `uvm_warning("SB_EMPTY", "o_intr was never in a checkable (quiet) state")
    if (apb_fifo.used() != 0)
      `uvm_warning("SB_LEFT", $sformatf("%0d APB items not processed", apb_fifo.used()))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf(
      "reads %0d | bits checked %0d, skipped %0d | o_intr checks %0d | errors %0d",
      n_reads, n_bits_checked, n_bits_skipped, n_intr_checked, n_errors), UVM_LOW)
  endfunction
endclass : gpio_scoreboard
