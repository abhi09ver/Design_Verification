// -----------------------------------------------------------------------------
// gpio_env.svh : environment and virtual sequencer
// -----------------------------------------------------------------------------

// Handle container: virtual sequences reach both agents and the register model
// through p_sequencer.
class gpio_vsequencer extends uvm_sequencer;
  `uvm_component_utils(gpio_vsequencer)
  apb_sequencer               apb_seqr;
  pin_sequencer               pin_seqr;
  gpio_reg_block              regmodel;
  gpio_cfg                    cfg;
  virtual gpio_pin_if #(GPIO_W) pin_vif;   // for waiting on o_intr / clocks

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : gpio_vsequencer


class gpio_env extends uvm_env;
  `uvm_component_utils(gpio_env)

  gpio_cfg        cfg;
  apb_agent       apb;
  pin_agent       pins;
  gpio_reg_block  regmodel;
  apb_reg_adapter adapter;
  gpio_scoreboard sb;
  gpio_coverage   cov;
  gpio_vsequencer vseqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(gpio_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "gpio_cfg not set")

    apb   = apb_agent::type_id::create("apb", this);
    pins  = pin_agent::type_id::create("pins", this);
    sb    = gpio_scoreboard::type_id::create("sb", this);
    cov   = gpio_coverage::type_id::create("cov", this);
    vseqr = gpio_vsequencer::type_id::create("vseqr", this);

    regmodel = gpio_reg_block::type_id::create("regmodel");
    regmodel.build_model(cfg);
    regmodel.exclude_from_builtin_seqs(this);
    adapter  = apb_reg_adapter::type_id::create("adapter");
  endfunction

  function void connect_phase(uvm_phase phase);
    apb.mon.ap.connect(sb.apb_fifo.analysis_export);
    pins.mon.ap.connect(sb.pin_fifo.analysis_export);
    sb.cov = cov;

    // Stimulus convenience only: the mirror follows our own writes/reads.
    // All checking is done by the scoreboard's independent model.
    regmodel.default_map.set_sequencer(apb.seqr, adapter);
    regmodel.default_map.set_auto_predict(1);

    vseqr.apb_seqr = apb.seqr;
    vseqr.pin_seqr = pins.seqr;
    vseqr.regmodel = regmodel;
    vseqr.cfg      = cfg;
    vseqr.pin_vif  = pins.mon.vif;
  endfunction
endclass : gpio_env
