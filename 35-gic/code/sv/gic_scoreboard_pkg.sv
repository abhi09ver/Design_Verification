// gic_scoreboard_pkg.sv
// -----------------------------------------------------------------------------
// A UVM scoreboard skeleton for the GIC acknowledge path that checks against
// the SET of legal answers, not one exact answer.
//
// Why: the GIC spec lets signalling lag configuration changes, lets a Clear
// race an IAR read, and leaves 1-of-N SPI selection IMPLEMENTATION DEFINED.
// A scoreboard that predicts one INTID produces false failures. This one keeps,
// per PE, every INTID that has been a legal HPPI since the last "settle point"
// and accepts any of them (or 1023 while the window is open).
//
// Inputs come from monitors as transactions:
//   gic_cfg_item  - a config change (enable/priority/group/route/PMR)
//   gic_pend_item - an interrupt became pending / not pending
//   gic_iar_item  - a PE read IAR and got an INTID
//   gic_eoi_item  - a PE wrote EOIR
// The prediction function legal_hppi_set() is where you plug in your
// reference model (for example a DPI call into a C/Python model, or a SV port
// of Appendix B pseudocode).
// -----------------------------------------------------------------------------
package gic_scoreboard_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int SPURIOUS = 1023;

  typedef enum {CFG, PEND, IAR, EOI} gic_kind_e;

  class gic_item extends uvm_sequence_item;
    gic_kind_e kind;
    int        pe;
    int        intid;
    bit        pending;     // PEND: new pending value
    byte       prio;        // CFG/PEND: priority
    int        target_pe;   // CFG: route (-1 = 1-of-N)
    `uvm_object_utils(gic_item)
    function new(string name = "gic_item"); super.new(name); endfunction
    function string convert2string();
      return $sformatf("%s pe=%0d intid=%0d pend=%0b prio=0x%0h tgt=%0d",
                       kind.name(), pe, intid, pending, prio, target_pe);
    endfunction
  endclass

  `uvm_analysis_imp_decl(_gic)

  class gic_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(gic_scoreboard)

    uvm_analysis_imp_gic #(gic_item, gic_scoreboard) item_imp;

    int num_pes = 4;

    // Simple architectural mirror (replace with your reference model).
    byte prio_q   [int];          // intid -> priority
    bit  pending_q[int];          // intid -> pending
    int  route_q  [int];          // intid -> target PE (-1 = any)
    byte pmr_q    [int];          // pe -> PMR
    int  active_stack[int][$];    // pe -> stack of active INTIDs (for EOI order)

    // Window of legal answers per PE since the last change.
    int  legal_window[int][$];
    bit  window_open [int];       // true right after a change: 1023 also legal

    // Statistics for the end-of-test report.
    int  n_iar, n_spurious, n_errors;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      item_imp = new("item_imp", this);
    endfunction

    // Highest-priority pending interrupt(s) for one PE, under its PMR.
    // Ties return every INTID at that priority (tie-break is IMP DEF).
    function void legal_hppi_set(int pe, ref int q[$]);
      byte best = 8'hFF;
      q.delete();
      foreach (pending_q[id]) begin
        if (!pending_q[id]) continue;
        if (route_q.exists(id) && route_q[id] != -1 && route_q[id] != pe) continue;
        if (!(prio_q[id] < pmr_q[pe])) continue;
        if (prio_q[id] < best) begin best = prio_q[id]; q.delete(); end
        if (prio_q[id] == best) q.push_back(id);
      end
    endfunction

    // After any change, every PE's window gains the new legal set and stays
    // "open" (old answers and 1023 still legal) until the next IAR settles it.
    function void refresh_windows();
      int q[$];
      for (int pe = 0; pe < num_pes; pe++) begin
        legal_hppi_set(pe, q);
        foreach (q[i]) legal_window[pe].push_back(q[i]);
        window_open[pe] = 1;
      end
    endfunction

    function void write_gic(gic_item t);
      case (t.kind)
        CFG: begin
          if (t.intid == -1) pmr_q[t.pe] = t.prio;          // PMR write
          else begin prio_q[t.intid] = t.prio; route_q[t.intid] = t.target_pe; end
          refresh_windows();
        end
        PEND: begin
          pending_q[t.intid] = t.pending;
          refresh_windows();
        end
        IAR:  check_iar(t);
        EOI:  check_eoi(t);
      endcase
    endfunction

    function void check_iar(gic_item t);
      int now[$];
      bit ok;
      n_iar++;
      legal_hppi_set(t.pe, now);
      if (t.intid == SPURIOUS) begin
        n_spurious++;
        ok = window_open[t.pe] || now.size() == 0;
      end else begin
        ok = (t.intid inside {now}) || (window_open[t.pe] && (t.intid inside {legal_window[t.pe]}));
      end
      if (!ok) begin
        n_errors++;
        `uvm_error("GIC_SB", $sformatf("PE%0d IAR=%0d not legal. Now legal=%p window=%p",
                   t.pe, t.intid, now, legal_window[t.pe]))
      end
      if (t.intid != SPURIOUS) begin
        pending_q[t.intid] = 0;                 // edge model; adapt for level/LPI
        active_stack[t.pe].push_back(t.intid);
        // Another PE may no longer take this 1-of-N SPI: exactly-once check.
        for (int pe = 0; pe < num_pes; pe++)
          if (pe != t.pe) foreach (legal_window[pe][i])
            if (legal_window[pe][i] == t.intid) legal_window[pe].delete(i);
      end
      legal_window[t.pe].delete();
      window_open[t.pe] = 0;                    // settled until the next change
    endfunction

    function void check_eoi(gic_item t);
      if (active_stack[t.pe].size() == 0) begin
        `uvm_error("GIC_SB", $sformatf("PE%0d EOI %0d with nothing active", t.pe, t.intid))
        n_errors++;
        return;
      end
      if (active_stack[t.pe][$] != t.intid)
        `uvm_warning("GIC_SB", $sformatf("PE%0d EOI %0d is not the most recent ack (%0d): UNPREDICTABLE per spec, check DUT stays sane",
                     t.pe, t.intid, active_stack[t.pe][$]))
      foreach (active_stack[t.pe][i])
        if (active_stack[t.pe][i] == t.intid) begin active_stack[t.pe].delete(i); break; end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("GIC_SB", $sformatf("IAR reads=%0d spurious=%0d errors=%0d",
                n_iar, n_spurious, n_errors), UVM_LOW)
    endfunction
  endclass

endpackage
