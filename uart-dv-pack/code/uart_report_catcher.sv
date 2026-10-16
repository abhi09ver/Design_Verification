// uart_expect_catcher — demotes one expected error ID to INFO in a negative test,
// and counts how many it caught so the test can compare against what was injected.
// A missing error would otherwise pass silently (card 09).
class uart_expect_catcher extends uvm_report_catcher;
  `uvm_object_utils(uart_expect_catcher)

  string       expect_id;
  int unsigned seen;

  function new(string name = "uart_expect_catcher");
    super.new(name);
  endfunction

  function action_e catch();
    if (get_id() == expect_id && get_severity() == UVM_ERROR) begin
      set_severity(UVM_INFO);
      set_message({"[expected] ", get_message()});
      seen++;
    end
    return THROW;
  endfunction
endclass
