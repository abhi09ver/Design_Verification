// uart_scoreboard — predicts the DUT receive FIFO from two sides (card 07):
//   write_line : frames the TB sent on the DUT RX pin (from the line monitor)
//   write_bus  : register reads seen on the CPU bus (from your bus monitor / RAL predictor)
// Overrun is invisible on the wire, so it can only be checked here.
//
// Spec-specific choices are marked SPEC: change them to match your DUT.
`uvm_analysis_imp_decl(_line)
`uvm_analysis_imp_decl(_bus)

class uart_scoreboard extends uvm_component;
  `uvm_component_utils(uart_scoreboard)

  typedef struct {
    bit [7:0] data;
    bit       fe, pe, bi;
  } rx_entry_t;

  uvm_analysis_imp_line #(uart_item,     uart_scoreboard) line_export;
  uvm_analysis_imp_bus  #(uart_bus_item, uart_scoreboard) bus_export;

  uart_cfg     cfg;
  rx_entry_t   rx_q[$];         // model of the DUT RX FIFO
  bit          exp_oe;
  int unsigned n_pushed, n_lost, n_matched, n_mismatch;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    line_export = new("line_export", this);
    bus_export  = new("bus_export",  this);
    if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "uart_scoreboard: no uart_cfg")
  endfunction

  // A complete character (or a break) arrived at the DUT.
  function void write_line(uart_item t);
    rx_entry_t e;
    e.data = cfg.mask(t.data);
    e.fe   = t.fe;                                  // SPEC: break usually sets FE too
    e.pe   = t.pe;
    e.bi   = (t.kind == KIND_BREAK);
    if (e.bi) e.data = 8'h00;                       // one 0x00 per break (card 06)

    if (rx_q.size() < cfg.fifo_depth) begin
      rx_q.push_back(e);
      n_pushed++;
    end else begin
      exp_oe = 1;                                   // SPEC: FIFO mode drops the newest char
      n_lost++;
      `uvm_info("UART_SB", $sformatf("overrun predicted, char 0x%0h lost", e.data), UVM_MEDIUM)
    end
  endfunction

  // CPU-side register access.
  function void write_bus(uart_bus_item b);
    if (!b.is_read) return;

    if (b.addr == RBR) begin
      rx_entry_t e;
      if (rx_q.size() == 0) begin
        `uvm_error("UART_SB", "RBR read with model FIFO empty (DR should be 0)")
        return;
      end
      e = rx_q.pop_front();
      if (b.data !== e.data) begin
        n_mismatch++;
        `uvm_error("UART_SB", $sformatf("RBR 0x%0h exp 0x%0h", b.data, e.data))
      end else n_matched++;
    end

    if (b.addr == LSR) begin
      bit [7:0] exp = '0;
      exp[LSR_DR] = (rx_q.size() != 0);
      exp[LSR_OE] = exp_oe;
      if (rx_q.size() != 0) begin                   // error bits describe the char at the head
        exp[LSR_PE] = rx_q[0].pe;
        exp[LSR_FE] = rx_q[0].fe;
        exp[LSR_BI] = rx_q[0].bi;
      end
      foreach (exp[i]) if (i inside {LSR_DR, LSR_OE, LSR_PE, LSR_FE, LSR_BI} && b.data[i] !== exp[i])
        `uvm_error("UART_LSR", $sformatf("LSR[%0d]=%b exp %b (LSR=0x%0h)", i, b.data[i], exp[i], b.data))
      exp_oe = 0;                                   // OE clears on LSR read
    end
  endfunction

  function void check_phase(uvm_phase phase);
    if (rx_q.size() != 0)
      `uvm_info("UART_SB", $sformatf("%0d chars still in model FIFO at end of test", rx_q.size()), UVM_LOW)
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("UART_SB", $sformatf("pushed=%0d lost=%0d matched=%0d mismatched=%0d",
              n_pushed, n_lost, n_matched, n_mismatch), UVM_LOW)
  endfunction
endclass
