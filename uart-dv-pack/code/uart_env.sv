// uart_env — the complete environment from card 09.
//   tb_agt  (active)  drives the DUT RX pin;      its monitor feeds rx_chk, scoreboard, coverage
//   dut_agt (passive) observes the DUT TX pin;    its monitor feeds tx_chk, coverage
//   sb.bus_export     connect your register-bus monitor / RAL predictor here (card 07)
class uart_env extends uvm_env;
  `uvm_component_utils(uart_env)

  uart_agent      tb_agt, dut_agt;
  uart_checker    rx_chk, tx_chk;
  uart_scoreboard sb;
  uart_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "tb_agt",  "is_active", UVM_ACTIVE);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "dut_agt", "is_active", UVM_PASSIVE);
    tb_agt  = uart_agent     ::type_id::create("tb_agt",  this);
    dut_agt = uart_agent     ::type_id::create("dut_agt", this);
    rx_chk  = uart_checker   ::type_id::create("rx_chk",  this);
    tx_chk  = uart_checker   ::type_id::create("tx_chk",  this);
    sb      = uart_scoreboard::type_id::create("sb",      this);
    cov     = uart_coverage  ::type_id::create("cov",     this);
    rx_chk.dir = "RX";
    tx_chk.dir = "TX";
  endfunction

  function void connect_phase(uvm_phase phase);
    tb_agt.mon.ap.connect(rx_chk.analysis_export);
    tb_agt.mon.ap.connect(sb.line_export);
    tb_agt.mon.ap.connect(cov.analysis_export);
    dut_agt.mon.ap.connect(tx_chk.analysis_export);
    dut_agt.mon.ap.connect(cov.analysis_export);
    dut_agt.mon.glitch_is_error = 1;            // a glitch on DUT TX is a design bug (card 08)
  endfunction
endclass
