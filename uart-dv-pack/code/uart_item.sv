// uart_item — one frame (or one break event).
// rand fields drive stimulus; observed fields are filled by the monitor.
class uart_item extends uvm_sequence_item;
  `uvm_object_utils(uart_item)

  // ---- stimulus ----
  rand bit [8:0]      data;
  rand inject_e       inject;
  rand int            drift_permille;   // bit time * (1 + drift/1000)  (card 03)
  rand int unsigned   break_chars;      // break length in character times (card 06)
  rand int unsigned   idle_bits;        // extra idle after the frame (card 08)

  constraint c_inject  { inject dist {INJ_NONE := 90, INJ_FE := 3, INJ_PE := 3,
                                      INJ_BREAK := 2, INJ_GLITCH := 2}; }
  constraint c_drift   { drift_permille dist {0 := 80, [-20:20] :/ 15, [-60:60] :/ 5}; }
  constraint c_break   { break_chars inside {[2:20]}; }
  constraint c_idle    { idle_bits dist {0 := 50, [1:3] :/ 40, [4:40] :/ 10}; }

  // ---- observed ----
  kind_e     kind = KIND_FRAME;
  bit        par;
  bit [1:0]  stop;
  bit        fe, pe;
  realtime   t_start, t_end;
  realtime   edges[$];                  // every line edge inside the frame (card 03)

  function new(string name = "uart_item");
    super.new(name);
  endfunction

  function string convert2string();
    if (kind == KIND_BREAK)
      return $sformatf("BREAK %0.1f..%0.1f ns", t_start, t_end);
    return $sformatf("data=0x%0h par=%b stop=%b fe=%0b pe=%0b inj=%s",
                     data, par, stop, fe, pe, inject.name());
  endfunction
endclass

// Minimal register-bus transaction seen by the scoreboard (card 07).
class uart_bus_item extends uvm_sequence_item;
  `uvm_object_utils(uart_bus_item)
  bit       is_read;
  bit [2:0] addr;
  bit [7:0] data;
  function new(string name = "uart_bus_item");
    super.new(name);
  endfunction
endclass
