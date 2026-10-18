// uart_agent — active (sequencer + driver + monitor) or passive (monitor only), card 02.
// Active drives the DUT RX pin; passive observes the DUT TX pin.
typedef uvm_sequencer #(uart_item) uart_sequencer;

class uart_agent extends uvm_agent;
  `uvm_component_utils(uart_agent)

  uart_sequencer sqr;
  uart_driver    drv;
  uart_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);                   // picks up is_active from config_db
    mon = uart_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = uart_sequencer::type_id::create("sqr", this);
      drv = uart_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
