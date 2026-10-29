// -----------------------------------------------------------------------------
// gpio_coverage.svh : functional coverage for GPIO v1.0
//
// The scoreboard calls these sample functions, because it is the one place
// that knows both the configuration and what each pin event did. Covering
// outcomes ("set / masked / dropped") instead of raw signals means a bin is
// only hit when the behaviour actually happened.
// -----------------------------------------------------------------------------

typedef enum {EV_RISE, EV_FALL, EV_HIGH, EV_LOW} ev_kind_e;

class gpio_coverage extends uvm_component;
  `uvm_component_utils(gpio_coverage)

  // ---------------------------------------- per-pin configuration space ----
  covergroup cg_pin_cfg with function sample(int pin, bit dir, bit ie, bit me,
                                             bit typ, bit evt, bit gie, bit gme);
    option.per_instance = 1;
    cp_pin : coverpoint pin { bins p[] = {[0:GPIO_W-1]}; }
    cp_dir : coverpoint dir { bins output_ = {0}; bins input_ = {1}; }
    cp_ie  : coverpoint ie;
    cp_me  : coverpoint me;
    cp_typ : coverpoint typ { bins level = {0}; bins edge_ = {1}; }
    cp_evt : coverpoint evt { bins low_fall = {0}; bins high_rise = {1}; }
    cp_gie : coverpoint gie;
    cp_gme : coverpoint gme;
    x_trigger : cross cp_typ, cp_evt;                 // 4 trigger kinds
    x_gating  : cross cp_ie, cp_me, cp_gie, cp_gme;   // 16 gating combos
    x_pin_trig: cross cp_pin, cp_typ, cp_evt;         // every pin, every trigger
  endgroup

  // ------------------------------------------------- what an event did ----
  covergroup cg_event with function sample(ev_kind_e kind, outcome_e res, bit typ);
    option.per_instance = 1;
    cp_kind : coverpoint kind;
    cp_res  : coverpoint res { bins set = {OUT_SET}; bins masked = {OUT_MASKED};
                               bins dropped = {OUT_DROPPED}; bins no_match = {OUT_NO_MATCH}; }
    cp_typ  : coverpoint typ { bins level = {0}; bins edge_ = {1}; }
    x_kind_res : cross cp_kind, cp_res {
      // A level event is a state, not a transition; an edge pin only "matches" on
      // a transition. Kinds that can't produce a result for the pin type:
      ignore_bins lvl_no_match = binsof(cp_kind) intersect {EV_HIGH, EV_LOW} &&
                                 binsof(cp_res)  intersect {OUT_NO_MATCH};
    }
  endgroup

  // ------------------------------------------- input pulse width (clocks) ----
  covergroup cg_pulse with function sample(int unsigned width, bit has_glf);
    option.per_instance = 1;
    cp_w : coverpoint width {
      bins short_      = {[1:GLF_LEN-2]};    // always filtered (GLF pins)
      bins thr_minus_1 = {GLF_LEN-1};        // around the threshold: the bugs
      bins thr         = {GLF_LEN};
      bins thr_plus_1  = {GLF_LEN+1};
      bins long_       = {[GLF_LEN+2:$]};    // always accepted
    }
    cp_glf : coverpoint has_glf;
    x_w_glf : cross cp_w, cp_glf;
  endgroup

  // -------------------------------------------- the hard-to-hit corners ----
  covergroup cg_race with function sample(race_e r);
    option.per_instance = 1;
    cp_race : coverpoint r;              // all four must be hit
  endgroup

  // ------------------------------------------------------- APB traffic ----
  covergroup cg_apb with function sample(bit [7:0] addr, bit write, bit b2b);
    option.per_instance = 1;
    cp_addr : coverpoint addr {
      bins regs[]   = {8'h00, 8'h04, 8'h08, 8'h0C, 8'h10, 8'h14,
                       8'h18, 8'h1C, 8'h20, 8'h24, 8'h28};
      bins unmapped = {[8'h2C:8'hFC]} with (item[1:0] == 0);
      bins unaligned= {[8'h00:8'hFF]} with (item[1:0] != 0);
    }
    cp_wr  : coverpoint write;
    cp_b2b : coverpoint b2b;             // no IDLE before this transfer
    x_addr_wr : cross cp_addr, cp_wr;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_pin_cfg = new();
    cg_event   = new();
    cg_pulse   = new();
    cg_race    = new();
    cg_apb     = new();
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf(
      "cfg %0.1f%% | event %0.1f%% | pulse %0.1f%% | race %0.1f%% | apb %0.1f%%",
      cg_pin_cfg.get_inst_coverage(), cg_event.get_inst_coverage(),
      cg_pulse.get_inst_coverage(), cg_race.get_inst_coverage(),
      cg_apb.get_inst_coverage()), UVM_LOW)
  endfunction
endclass : gpio_coverage
