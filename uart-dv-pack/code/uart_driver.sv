// uart_driver — drives one serial line (the DUT's RX input).
// Error knobs come from the item: drift (03), framing (04), parity (05), break (06), glitch (08).
// Counts what it injected so tests can prove every injected error was seen (card 09).
class uart_driver extends uvm_driver #(uart_item);
  `uvm_component_utils(uart_driver)

  virtual uart_if vif;
  uart_cfg        cfg;
  int unsigned    n_injected[inject_e];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "uart_driver: no virtual interface")
    if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "uart_driver: no uart_cfg")
  endfunction

  task run_phase(uvm_phase phase);
    vif.line <= 1'b1;                          // idle = mark, also during reset
    wait (vif.rst_n === 1'b1);
    forever begin
      seq_item_port.get_next_item(req);
      drive(req);
      seq_item_port.item_done();
    end
  endtask

  task drive(uart_item it);
    realtime t = cfg.bit_time() * (1.0 + it.drift_permille / 1000.0);
    bit p;

    if (it.inject != INJ_NONE) n_injected[it.inject]++;

    case (it.inject)
      INJ_BREAK: begin                         // low for longer than a whole character
        vif.line <= 1'b0;  #(t * cfg.char_bits() * it.break_chars);
        vif.line <= 1'b1;  #(t * 2);           // mark before the next start
        return;
      end
      INJ_GLITCH: begin                        // shorter than half a bit -> must be rejected
        vif.line <= 1'b0;  #(t * 0.25);
        vif.line <= 1'b1;  #(t * 2);
        return;
      end
      default: ;
    endcase

    // start
    vif.line <= 1'b0;  #(t);
    // data, LSB first, configured width only
    for (int i = 0; i < cfg.data_bits; i++) begin
      vif.line <= it.data[i];  #(t);
    end
    // parity
    if (cfg.parity != PAR_NONE) begin
      p = cfg.exp_parity(it.data);
      if (it.inject == INJ_PE) p = ~p;
      vif.line <= p;  #(t);
    end
    // stop bit(s); INJ_FE forces the first one low
    for (int s = 0; s < cfg.stop_bits; s++) begin
      vif.line <= (it.inject == INJ_FE && s == 0) ? 1'b0 : 1'b1;  #(t);
    end
    vif.line <= 1'b1;
    if (it.idle_bits) #(t * it.idle_bits);
  endtask
endclass
