// uart_seq — n frames with optional error injection and clock drift.
// Knobs are set by the test before start(); defaults give clean random traffic.
class uart_seq extends uvm_sequence #(uart_item);
  `uvm_object_utils(uart_seq)

  int unsigned n              = 50;
  inject_e     inj            = INJ_NONE;   // INJ_NONE = no injection at all
  int unsigned inj_every      = 5;          // inject on every Nth frame
  bit          fix_drift      = 0;
  int          drift_permille = 0;          // used when fix_drift = 1 (card 03)

  function new(string name = "uart_seq");
    super.new(name);
  endfunction

  task body();
    for (int k = 0; k < n; k++) begin
      inject_e this_inj = (inj != INJ_NONE && (k % inj_every) == inj_every - 1) ? inj : INJ_NONE;
      req = uart_item::type_id::create("req");
      start_item(req);
      if (!req.randomize() with {
            inject == this_inj;
            if (fix_drift) drift_permille == local::drift_permille;
            else           drift_permille == 0;
          })
        `uvm_fatal("RAND", "uart_item randomize failed")
      finish_item(req);
    end
  endtask
endclass
