// uart_cfg — one config object shared by driver, monitor, checker, scoreboard.
// Set by the test, distributed with uvm_config_db (card 02).
class uart_cfg extends uvm_object;
  `uvm_object_utils(uart_cfg)

  // ---- frame format (card 01) ----
  real         baud       = 115200.0;
  int unsigned data_bits  = 8;          // 5..8
  parity_e     parity     = PAR_NONE;
  int unsigned stop_bits  = 1;          // 1 or 2

  // ---- checking (cards 03, 04, 05, 06) ----
  real         tol        = 0.02;       // allowed bit-time error per edge gap (2%)
  bit          chk_baud    = 1;
  bit          chk_framing = 1;
  bit          chk_parity  = 1;
  bit          check_all_stops = 0;     // TX-side rule: both stop bits must be 1

  // ---- DUT receive path model (card 07) ----
  int unsigned fifo_depth = 16;         // 1 = FIFO disabled

  function new(string name = "uart_cfg");
    super.new(name);
  endfunction

  // Bit period in the current timeunit (ns with `timescale 1ns/1ps).
  function realtime bit_time();
    return 1.0e9 / baud;
  endfunction

  // start + data + parity + stop
  function int unsigned char_bits();
    return 1 + data_bits + (parity != PAR_NONE) + stop_bits;
  endfunction

  // Expected parity over the CONFIGURED width only (card 05 width bug).
  function bit exp_parity(bit [8:0] d);
    bit x = 1'b0;
    for (int i = 0; i < data_bits; i++) x ^= d[i];
    case (parity)
      PAR_EVEN : return x;
      PAR_ODD  : return ~x;
      PAR_MARK : return 1'b1;
      PAR_SPACE: return 1'b0;
      default  : return 1'b0;
    endcase
  endfunction

  function bit [8:0] mask(bit [8:0] d);
    return d & ((9'h1 << data_bits) - 1);
  endfunction
endclass
