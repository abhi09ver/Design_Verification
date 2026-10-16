// uart_monitor — passive. Turns one serial line into frame-level uart_items.
// Never drives (card 02). Records every edge inside the frame so the checker can
// measure bit timing (card 03). Classifies false starts (08) and breaks (06).
class uart_monitor extends uvm_monitor;
  `uvm_component_utils(uart_monitor)

  virtual uart_if             vif;
  uart_cfg                    cfg;
  uvm_analysis_port #(uart_item) ap;

  bit          glitch_is_error = 0;   // set for the DUT-TX monitor: a glitch there is a DUT bug
  int unsigned n_frames, n_false_starts, n_breaks;

  protected bit      in_frame;
  protected realtime edge_q[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "uart_monitor: no virtual interface")
    if (!uvm_config_db#(uart_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "uart_monitor: no uart_cfg")
  endfunction

  task run_phase(uvm_phase phase);
    wait (vif.rst_n === 1'b1);
    fork
      collect_edges();
      collect_frames();
    join
  endtask

  // Timestamps of every edge while a confirmed frame is in progress.
  protected task collect_edges();
    forever begin
      @(vif.line);
      if (in_frame) edge_q.push_back($realtime);
    end
  endtask

  protected task collect_frames();
    realtime  bt, t0;
    uart_item it;
    forever begin
      bt = cfg.bit_time();
      @(negedge vif.line);                       // candidate start edge
      t0 = $realtime;
      #(bt / 2);                                 // middle of the start bit
      if (vif.line !== 1'b0) begin               // false start: glitch rejected (card 08)
        n_false_starts++;
        if (glitch_is_error)
          `uvm_error("UART_GLITCH", $sformatf("low pulse < half bit at %0t", t0))
        else
          `uvm_info("UART_FALSE_START", $sformatf("rejected glitch at %0t", t0), UVM_HIGH)
        continue;
      end

      in_frame = 1;
      edge_q.delete();
      it = uart_item::type_id::create("it");
      it.t_start = t0;

      for (int i = 0; i < cfg.data_bits; i++) begin
        #(bt);  it.data[i] = vif.line;           // LSB first
      end
      if (cfg.parity != PAR_NONE) begin
        #(bt);  it.par = vif.line;
      end
      for (int s = 0; s < cfg.stop_bits; s++) begin
        #(bt);  it.stop[s] = vif.line;
      end
      in_frame = 0;
      it.edges = edge_q;

      // Observations only — the checker decides what to report.
      it.fe = (it.stop[0] !== 1'b1);
      it.pe = (cfg.parity != PAR_NONE) && (it.par !== cfg.exp_parity(it.data));

      // All-zero frame with low stop: break if the line stays low past one character (card 06).
      if (it.fe && cfg.mask(it.data) == 0 && (cfg.parity == PAR_NONE || it.par == 1'b0)) begin
        wait (vif.line === 1'b1);
        if ($realtime - t0 >= cfg.char_bits() * bt) begin
          it.kind = KIND_BREAK;
          n_breaks++;
        end
      end

      it.t_end = $realtime;
      n_frames++;
      ap.write(it);
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("UART_MON", $sformatf("frames=%0d breaks=%0d false_starts=%0d",
              n_frames, n_breaks, n_false_starts), UVM_LOW)
  endfunction
endclass
