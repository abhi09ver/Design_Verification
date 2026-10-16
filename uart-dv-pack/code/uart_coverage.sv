// uart_coverage — functional coverage on observed frames (cards 01, 05, 06, 08).
// Sample with the current config so format x error crosses are visible.
class uart_coverage extends uvm_subscriber #(uart_item);
  `uvm_component_utils(uart_coverage)

  uart_cfg cfg;

  covergroup cg with function sample(uart_item it, parity_e par_mode,
                                     int unsigned data_bits, int unsigned stop_bits);
    cp_data: coverpoint it.data[7:0] {
      bins zero    = {8'h00};
      bins ones    = {8'hFF};
      bins alt     = {8'h55, 8'hAA};
      bins walk1[] = {8'h01, 8'h02, 8'h04, 8'h08, 8'h10, 8'h20, 8'h40, 8'h80};
      bins other   = default;
    }
    cp_kind  : coverpoint it.kind;
    cp_fe    : coverpoint it.fe;
    cp_pe    : coverpoint it.pe;
    cp_par   : coverpoint par_mode;
    cp_width : coverpoint data_bits { bins w[] = {5, 6, 7, 8}; }
    cp_stops : coverpoint stop_bits { bins s[] = {1, 2}; }

    x_format     : cross cp_par, cp_width, cp_stops;
    x_par_err    : cross cp_par, cp_pe {
      ignore_bins no_par = binsof(cp_par) intersect {PAR_NONE} && binsof(cp_pe) intersect {1};
    }
    x_fe_format  : cross cp_fe, cp_width, cp_stops;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "uart_coverage: no uart_cfg")
  endfunction

  function void write(uart_item t);
    cg.sample(t, cfg.parity, cfg.data_bits, cfg.stop_bits);
  endfunction
endclass
