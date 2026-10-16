// -----------------------------------------------------------------------------
// gpio_seqs.svh : virtual sequences (one per testplan item T1..T15)
//
// Rules every sequence follows, so the testbench never fights the DUT:
//   * The TB drives only pins that are inputs (io_dir = 1), and every input
//     pin is always driven to a known level (no floating X into the syncs).
//   * Before a pin becomes an output, the TB releases it first.
//   * The "ISR" waits until the pins are quiet before reading status, so the
//     scoreboard can compare every bit.
// -----------------------------------------------------------------------------

class gpio_base_vseq extends uvm_sequence;
  `uvm_object_utils(gpio_base_vseq)
  `uvm_declare_p_sequencer(gpio_vsequencer)

  gpio_reg_block   rm;
  gpio_cfg         cfg;
  bit [GPIO_W-1:0] pin_val;                 // what the TB drives on input pins

  function new(string name = "gpio_base_vseq");
    super.new(name);
  endfunction

  task pre_body();
    rm  = p_sequencer.regmodel;
    cfg = p_sequencer.cfg;
    wait (p_sequencer.pin_vif.resetn === 1'b1);
    clocks(2);
  endtask

  // ------------------------------------------------------------ helpers ----
  task clocks(int n);
    repeat (n) @(posedge p_sequencer.pin_vif.clk);
  endtask

  // Long enough for any pin change to settle through sync + filter + status.
  task quiet();
    clocks(cfg.lat_max + 2);
  endtask

  task wr(uvm_reg r, uvm_reg_data_t v);
    uvm_status_e st;
    r.write(st, v, .parent(this));
    if (st != UVM_IS_OK) `uvm_error("WR", {"write failed: ", r.get_name()})
  endtask

  task rd(uvm_reg r, output uvm_reg_data_t v);
    uvm_status_e st;
    r.read(st, v, .parent(this));
    if (st != UVM_IS_OK) `uvm_error("RD", {"read failed: ", r.get_name()})
  endtask

  // Raw APB access, for addresses the register model doesn't have.
  task apb(bit [7:0] addr, bit write, bit [31:0] wdata = 0, int unsigned idle = 0);
    apb_item t = apb_item::type_id::create("t");
    start_item(t, -1, p_sequencer.apb_seqr);
    t.addr = addr; t.write = write; t.data = wdata; t.idle = idle;
    finish_item(t);
  endtask

  function bit [GPIO_W-1:0] inputs();
    return rm.io_dir.get_mirrored_value();
  endfunction

  // Drive input pins. hold = clocks to hold; phase = ns into the clock period.
  task drive(bit [GPIO_W-1:0] val, int unsigned hold = 1, int phase = -1);
    pin_item it = pin_item::type_id::create("it");
    bit [GPIO_W-1:0] en = inputs();
    start_item(it, -1, p_sequencer.pin_seqr);
    if (!it.randomize() with { drive_en == en; value == val; hold_clks == hold;
                               phase >= 0 -> phase_ns == phase; })
      `uvm_fatal("RAND", "pin_item randomize failed")
    finish_item(it);
    pin_val = val;
  endtask

  // Change direction safely: release pins that become outputs, then write dir.
  task set_dir(bit [GPIO_W-1:0] new_dir);
    bit [GPIO_W-1:0] keep = inputs() & new_dir;
    pin_item it = pin_item::type_id::create("it");
    start_item(it, -1, p_sequencer.pin_seqr);
    if (!it.randomize() with { drive_en == keep; value == pin_val; hold_clks == 1; })
      `uvm_fatal("RAND", "pin_item randomize failed")
    finish_item(it);
    wr(rm.io_dir, new_dir);
    drive(pin_val, 1);                         // drive any pin that became an input
  endtask

  // Interrupt service routine as firmware would write it.
  task isr(output bit [GPIO_W-1:0] serviced);
    uvm_reg_data_t raw, sts;
    quiet();
    rd(rm.intr_sts_raw, raw);                  // also re-syncs the model
    rd(rm.intr_sts, sts);
    serviced = sts;
    if (sts != 0) wr(rm.intr_sts, sts);        // W1C what we handled
  endtask

  task init_pins();
    drive('0, 2);                              // every input to a known 0
    quiet();
  endtask
endclass : gpio_base_vseq


// T1 reset values -------------------------------------------------------------
class gpio_reset_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_reset_vseq)
  function new(string name = "gpio_reset_vseq"); super.new(name); endfunction
  task body();
    uvm_reg_hw_reset_seq s = uvm_reg_hw_reset_seq::type_id::create("s");
    init_pins();
    s.model = rm;
    s.start(null);
  endtask
endclass


// T2 register access ------------------------------------------------------------
class gpio_reg_access_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_reg_access_vseq)
  function new(string name = "gpio_reg_access_vseq"); super.new(name); endfunction
  task body();
    uvm_reg_bit_bash_seq bb = uvm_reg_bit_bash_seq::type_id::create("bb");
    uvm_reg_data_t v;
    init_pins();
    // Flipping io_dir under bit-bash would make the DUT drive pins the TB is
    // driving. Direction gets its own test (T3).
    uvm_resource_db#(bit)::set({"REG::", rm.io_dir.get_full_name()},
                               "NO_REG_BIT_BASH_TEST", 1, this);
    bb.model = rm;
    bb.start(null);
    wr(rm.intr_en, 0);                         // bit-bash may leave IE set
    // Read every register once more; the scoreboard checks the values.
    rd(rm.i_data, v);  rd(rm.o_data, v);   rd(rm.io_dir, v);   rd(rm.glb, v);
    rd(rm.intr_en, v); rd(rm.intr_mask, v); rd(rm.intr_type, v); rd(rm.intr_evnt, v);
    rd(rm.intr_sts, v); rd(rm.intr_sts_raw, v); rd(rm.intr_set, v);
  endtask
endclass


// T3 output drive and live direction changes -------------------------------------
class gpio_out_drive_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_out_drive_vseq)
  rand int unsigned n_iter;
  constraint c_n { n_iter inside {[20:60]}; }
  function new(string name = "gpio_out_drive_vseq"); super.new(name); endfunction
  task body();
    uvm_reg_data_t v;
    init_pins();
    repeat (n_iter) begin
      set_dir($urandom());
      wr(rm.o_data, $urandom());
      drive($urandom(), $urandom_range(1, 4));
      quiet();
      rd(rm.i_data, v);                        // outputs read back their pad value
    end
  endtask
endclass


// T4 input sampling at random phase ------------------------------------------------
class gpio_in_sample_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_in_sample_vseq)
  function new(string name = "gpio_in_sample_vseq"); super.new(name); endfunction
  task body();
    uvm_reg_data_t v;
    init_pins();
    repeat (50) begin
      drive($urandom(), $urandom_range(cfg.lat_max + 2, cfg.lat_max + 10));
      rd(rm.i_data, v);
    end
  endtask
endclass


// T5 random interrupt configuration + random pin activity + ISR -----------------------
class gpio_intr_rand_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_intr_rand_vseq)
  rand int unsigned n_cfg, n_pin;
  constraint c_n { n_cfg inside {[10:30]}; n_pin inside {[10:40]}; }
  function new(string name = "gpio_intr_rand_vseq"); super.new(name); endfunction
  task body();
    bit [GPIO_W-1:0] done;
    init_pins();
    repeat (n_cfg) begin
      // Mostly inputs, so interrupts have sources.
      set_dir($urandom() | $urandom());
      wr(rm.intr_type, $urandom());
      wr(rm.intr_evnt, $urandom());
      wr(rm.intr_mask, ($urandom_range(0, 3) == 0) ? $urandom() : 0);
      wr(rm.glb,       $urandom_range(0, 3));
      wr(rm.intr_en,   $urandom());
      repeat (n_pin) begin
        drive($urandom(), $urandom_range(1, 20));
        if ($urandom_range(0, 4) == 0) isr(done);
      end
      isr(done);
      wr(rm.intr_en, 0);
    end
  endtask
endclass


// T6 level interrupt cleared while the source is still active -----------------------
class gpio_level_storm_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_level_storm_vseq)
  function new(string name = "gpio_level_storm_vseq"); super.new(name); endfunction
  task body();
    bit [GPIO_W-1:0] done;
    init_pins();
    wr(rm.intr_type, 0);                       // all level
    wr(rm.intr_evnt, '1);                      // active-high
    wr(rm.glb, 1);
    wr(rm.intr_en, '1);
    drive('1, 4);                              // every source active
    repeat (3) isr(done);                      // status keeps coming back
    drive('0, 4);                              // remove the source
    isr(done);
    isr(done);                                 // now it stays clear
    wr(rm.intr_en, 0);
  endtask
endclass


// T7 W1C in the same cycle as a new edge (offset sweep) ---------------------------------
class gpio_w1c_race_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_w1c_race_vseq)
  function new(string name = "gpio_w1c_race_vseq"); super.new(name); endfunction
  task body();
    bit [GPIO_W-1:0] done;
    init_pins();
    wr(rm.intr_type, '1);                      // edge
    wr(rm.intr_evnt, '1);                      // rising
    wr(rm.glb, 1);
    wr(rm.intr_en, '1);
    for (int k = 0; k < 2 * cfg.lat_max; k++) begin
      drive('0, 2); quiet();
      wr(rm.intr_set, '1);                     // something pending to clear
      fork
        begin clocks(k); drive('1, 1, $urandom_range(0, CLK_PERIOD_NS - 1)); end
        wr(rm.intr_sts, '1);
      join
      isr(done);
    end
    wr(rm.intr_en, 0);
  endtask
endclass


// T8 event while masked, then unmask ---------------------------------------------------
class gpio_mask_pending_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_mask_pending_vseq)
  function new(string name = "gpio_mask_pending_vseq"); super.new(name); endfunction
  task body();
    uvm_reg_data_t v;
    bit [GPIO_W-1:0] done;
    init_pins();
    wr(rm.intr_type, '1); wr(rm.intr_evnt, '1);
    wr(rm.glb, 3);                             // GIE + GME
    wr(rm.intr_mask, '1);
    wr(rm.intr_en, '1);
    drive('1, 4); quiet();
    rd(rm.intr_sts_raw, v);                    // latched
    rd(rm.intr_sts, v);                        // hidden
    wr(rm.intr_mask, 0);                       // o_intr must rise now
    quiet();
    isr(done);
    wr(rm.intr_en, 0);
  endtask
endclass


// T9 + T10 IE clears status; software set is gated by IE -------------------------------
class gpio_ie_swset_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_ie_swset_vseq)
  function new(string name = "gpio_ie_swset_vseq"); super.new(name); endfunction
  task body();
    uvm_reg_data_t v;
    bit [GPIO_W-1:0] done;
    init_pins();
    wr(rm.intr_type, '1); wr(rm.intr_evnt, '1); wr(rm.glb, 1);
    wr(rm.intr_set, '1); quiet(); rd(rm.intr_sts_raw, v);   // IE=0: ignored
    wr(rm.intr_en, 'h5);
    wr(rm.intr_set, '1); quiet(); rd(rm.intr_sts_raw, v);   // only IE pins
    rd(rm.intr_set, v);                                     // WO reads 0
    wr(rm.intr_en, 0);   quiet(); rd(rm.intr_sts_raw, v);   // IE=0 clears
    isr(done);
  endtask
endclass


// T11 glitch / pulse-width sweep -------------------------------------------------------
class gpio_glitch_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_glitch_vseq)
  function new(string name = "gpio_glitch_vseq"); super.new(name); endfunction
  task body();
    bit [GPIO_W-1:0] done;
    init_pins();
    wr(rm.intr_type, '1); wr(rm.intr_evnt, '1); wr(rm.glb, 1); wr(rm.intr_en, '1);
    for (int w = 1; w <= GLF_LEN + 3; w++)
      repeat (4) begin
        drive('1, w, $urandom_range(0, CLK_PERIOD_NS - 1));   // pulse w clocks
        drive('0, 2);
        isr(done);
      end
    wr(rm.intr_en, 0);
  endtask
endclass


// T12 every pin at once ----------------------------------------------------------------
class gpio_multi_pin_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_multi_pin_vseq)
  function new(string name = "gpio_multi_pin_vseq"); super.new(name); endfunction
  task body();
    bit [GPIO_W-1:0] done;
    init_pins();
    wr(rm.intr_type, '1); wr(rm.intr_evnt, '1); wr(rm.glb, 1); wr(rm.intr_en, '1);
    repeat (10) begin
      drive('1, 6); isr(done);                 // all rise in one cycle
      drive('0, 6); isr(done);
    end
    wr(rm.intr_en, 0);
  endtask
endclass


// T13 reconfigure type / polarity / direction while IE = 1 -------------------------------
class gpio_reconfig_live_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_reconfig_live_vseq)
  function new(string name = "gpio_reconfig_live_vseq"); super.new(name); endfunction
  task body();
    bit [GPIO_W-1:0] done;
    init_pins();
    wr(rm.glb, 1); wr(rm.intr_en, '1);
    repeat (20) begin
      fork
        drive($urandom(), $urandom_range(1, 6));
        begin
          wr(rm.intr_type, $urandom());
          wr(rm.intr_evnt, $urandom());
        end
      join
      isr(done);
    end
    wr(rm.intr_en, 0);
  endtask
endclass


// T14 APB robustness: unmapped, unaligned, back-to-back, RO/WO accesses ---------------------
class gpio_apb_robust_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_apb_robust_vseq)
  function new(string name = "gpio_apb_robust_vseq"); super.new(name); endfunction
  task body();
    init_pins();
    for (int a = 'h2C; a <= 'hFC; a += 4) begin
      apb(a, 1, $urandom(), 0);                // write: no side effect
      apb(a, 0, 0, 0);                         // read: 0 (scoreboard + SVA)
    end
    repeat (20) apb($urandom() | 8'h01, $urandom_range(0, 1), $urandom(), 0); // unaligned
    apb(ADDR_I_DATA, 1, '1, 0);                // write to RO
    apb(ADDR_INTR_SET, 0, 0, 0);               // read of WO
    repeat (50) apb(ADDR_O_DATA, $urandom_range(0, 1), $urandom(), 0);  // back-to-back
  endtask
endclass


// Everything, in an order that leaves the DUT clean between pieces ---------------------
class gpio_full_vseq extends gpio_base_vseq;
  `uvm_object_utils(gpio_full_vseq)
  function new(string name = "gpio_full_vseq"); super.new(name); endfunction
  task body();
    gpio_base_vseq list[$];
    list.push_back(gpio_reset_vseq::type_id::create("reset"));
    list.push_back(gpio_reg_access_vseq::type_id::create("regs"));
    list.push_back(gpio_out_drive_vseq::type_id::create("out"));
    list.push_back(gpio_in_sample_vseq::type_id::create("in"));
    list.push_back(gpio_level_storm_vseq::type_id::create("storm"));
    list.push_back(gpio_w1c_race_vseq::type_id::create("race"));
    list.push_back(gpio_mask_pending_vseq::type_id::create("mask"));
    list.push_back(gpio_ie_swset_vseq::type_id::create("ie"));
    list.push_back(gpio_glitch_vseq::type_id::create("glitch"));
    list.push_back(gpio_multi_pin_vseq::type_id::create("multi"));
    list.push_back(gpio_reconfig_live_vseq::type_id::create("reconfig"));
    list.push_back(gpio_intr_rand_vseq::type_id::create("rand"));
    list.push_back(gpio_apb_robust_vseq::type_id::create("apb"));
    foreach (list[i]) begin
      if (!list[i].randomize()) `uvm_fatal("RAND", "vseq randomize failed")
      list[i].start(p_sequencer, this);
    end
  endtask
endclass
