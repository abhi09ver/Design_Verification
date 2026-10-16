// uart_checker — frame-level protocol rules, one message ID per check (card 09):
//   UART_BAUD  edge gap not a whole number of bits within tolerance   (card 03)
//   UART_GLITCH pulse shorter than half a bit inside a frame          (card 03/08)
//   UART_FE / UART_FE2  stop bit sampled low                          (card 04)
//   UART_PE    parity mismatch over the configured width              (card 05)
//   UART_BRK   break condition seen                                   (card 06)
//   UART_X     X/Z sampled in data                                    (card 08)
// Negative tests demote these with uart_expect_catcher, never by disabling checks.
class uart_checker extends uvm_subscriber #(uart_item);
  `uvm_component_utils(uart_checker)

  uart_cfg     cfg;
  string       dir = "RX";            // label for messages: "RX" (TB->DUT) or "TX" (DUT->TB)
  int unsigned n_frames, n_baud, n_fe, n_pe, n_brk, n_x;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "uart_checker: no uart_cfg")
  endfunction

  function void write(uart_item t);
    n_frames++;

    if (t.kind == KIND_BREAK) begin                         // card 06
      n_brk++;
      `uvm_error("UART_BRK", $sformatf("[%s] break %0.1f bit times at %0t",
                 dir, (t.t_end - t.t_start) / cfg.bit_time(), t.t_start))
      return;                                               // suppress cascades (card 09)
    end

    if ($isunknown(t.data)) begin                           // card 08
      n_x++;
      `uvm_error("UART_X", $sformatf("[%s] X/Z in data %b", dir, t.data))
    end

    if (cfg.chk_baud) check_timing(t);                      // card 03

    if (cfg.chk_framing) begin                              // card 04
      if (t.fe) begin
        n_fe++;
        `uvm_error("UART_FE", $sformatf("[%s] stop=0 after data 0x%0h at %0t",
                   dir, cfg.mask(t.data), t.t_start))
      end
      if (cfg.check_all_stops && cfg.stop_bits == 2 && t.stop[1] !== 1'b1)
        `uvm_error("UART_FE2", $sformatf("[%s] second stop bit low", dir))
    end

    if (cfg.chk_parity && cfg.parity != PAR_NONE && t.pe) begin   // card 05
      n_pe++;
      `uvm_error("UART_PE", $sformatf("[%s] data 0x%0h par %b exp %b", dir,
                 cfg.mask(t.data), t.par, cfg.exp_parity(t.data)))
    end
  endfunction

  // Every edge-to-edge gap must be n whole bits, within n * tol (card 03).
  // Long runs of equal bits are checked as one n-bit gap, so drift shows up
  // long before it corrupts data. Counting transitions in a window would not.
  protected function void check_timing(uart_item t);
    realtime bt   = cfg.bit_time();
    realtime prev = t.t_start;
    realtime gap, err;
    int      n;
    foreach (t.edges[i]) begin
      gap = t.edges[i] - prev;
      n   = $rtoi(gap / bt + 0.5);
      err = gap - n * bt;
      if (err < 0) err = -err;
      if (n == 0)
        `uvm_error("UART_GLITCH", $sformatf("[%s] %0.1f ns pulse inside frame", dir, gap))
      else if (err > n * bt * cfg.tol) begin
        n_baud++;
        `uvm_error("UART_BAUD", $sformatf("[%s] gap %0.1f ns ~ %0d bits, off %0.2f%%",
                   dir, gap, n, 100.0 * err / (n * bt)))
      end
      prev = t.edges[i];
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("UART_CHK", $sformatf("[%s] frames=%0d baud=%0d fe=%0d pe=%0d brk=%0d x=%0d",
              dir, n_frames, n_baud, n_fe, n_pe, n_brk, n_x), UVM_LOW)
  endfunction
endclass
