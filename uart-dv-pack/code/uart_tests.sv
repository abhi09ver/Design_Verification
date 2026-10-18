// uart_tests — base test plus negative tests that prove each check can fire (card 09).
//
//   +UVM_TESTNAME=uart_base_test                  clean random traffic, zero errors expected
//   +UVM_TESTNAME=uart_error_test +UART_INJ=FE    injected framing errors      (card 04)
//   +UVM_TESTNAME=uart_error_test +UART_INJ=PE    injected parity errors       (card 05)
//   +UVM_TESTNAME=uart_error_test +UART_INJ=BREAK injected breaks              (card 06)
//   +UVM_TESTNAME=uart_error_test +UART_INJ=GLITCH  false starts, must be rejected (card 08)
//   +UVM_TESTNAME=uart_drift_test +UART_DRIFT=40  4% slow TX clock -> UART_BAUD (card 03)
class uart_base_test extends uvm_test;
  `uvm_component_utils(uart_base_test)

  uart_env env;
  uart_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Override in derived tests to change the frame format.
  virtual function void configure(uart_cfg c);
    c.baud      = 115200.0;
    c.data_bits = 8;
    c.parity    = PAR_EVEN;
    c.stop_bits = 1;
    c.tol       = 0.02;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = uart_cfg::type_id::create("cfg");
    configure(cfg);
    uvm_config_db#(uart_cfg)::set(this, "*", "cfg", cfg);
    env = uart_env::type_id::create("env", this);
  endfunction

  virtual function void set_knobs(uart_seq s);
  endfunction

  task run_phase(uvm_phase phase);
    uart_seq seq = uart_seq::type_id::create("seq");
    set_knobs(seq);
    phase.raise_objection(this);
    seq.start(env.tb_agt.sqr);
    #(cfg.bit_time() * cfg.char_bits() * 2);    // let the last frame drain
    phase.drop_objection(this);
  endtask
endclass

class uart_error_test extends uart_base_test;
  `uvm_component_utils(uart_error_test)

  inject_e            inj = INJ_FE;
  uart_expect_catcher catcher;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    string s;
    super.build_phase(phase);
    if ($value$plusargs("UART_INJ=%s", s))
      case (s)
        "FE":     inj = INJ_FE;
        "PE":     inj = INJ_PE;
        "BREAK":  inj = INJ_BREAK;
        "GLITCH": inj = INJ_GLITCH;
        default:  `uvm_fatal("ARG", {"unknown +UART_INJ=", s})
      endcase
    catcher = uart_expect_catcher::type_id::create("catcher");
    case (inj)
      INJ_FE:    catcher.expect_id = "UART_FE";
      INJ_PE:    catcher.expect_id = "UART_PE";
      INJ_BREAK: catcher.expect_id = "UART_BRK";
      default:   catcher.expect_id = "";          // glitches are counted by the monitor
    endcase
    uvm_report_cb::add(null, catcher);
  endfunction

  function void set_knobs(uart_seq s);
    s.inj = inj;
  endfunction

  // Every injected error must be seen exactly once — a missing one fails the test.
  function void check_phase(uvm_phase phase);
    int unsigned injected = env.tb_agt.drv.n_injected.exists(inj) ? env.tb_agt.drv.n_injected[inj] : 0;
    int unsigned seen = (inj == INJ_GLITCH) ? env.tb_agt.mon.n_false_starts : catcher.seen;
    if (injected == 0)
      `uvm_error("TEST", "nothing was injected")
    else if (seen != injected)
      `uvm_error("TEST", $sformatf("%s: injected %0d, seen %0d", inj.name(), injected, seen))
    else
      `uvm_info("TEST", $sformatf("%s: all %0d injected errors seen", inj.name(), injected), UVM_LOW)
  endfunction
endclass

class uart_drift_test extends uart_base_test;
  `uvm_component_utils(uart_drift_test)

  int                 drift = 40;               // permille; 40 = TX clock 4% slow
  uart_expect_catcher catcher;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("UART_DRIFT=%d", drift));
    catcher = uart_expect_catcher::type_id::create("catcher");
    catcher.expect_id = "UART_BAUD";
    uvm_report_cb::add(null, catcher);
  endfunction

  function void set_knobs(uart_seq s);
    s.fix_drift      = 1;
    s.drift_permille = drift;
  endfunction

  // Inside tolerance: no baud errors. Outside: the checker must flag it.
  function void check_phase(uvm_phase phase);
    bit outside = ((drift < 0 ? -drift : drift) > cfg.tol * 1000.0);
    if (outside && catcher.seen == 0)
      `uvm_error("TEST", $sformatf("drift %0d permille not detected", drift))
    if (!outside && catcher.seen != 0)
      `uvm_error("TEST", $sformatf("false UART_BAUD at drift %0d permille", drift))
  endfunction
endclass
