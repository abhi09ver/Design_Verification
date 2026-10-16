// smmu_dv_pkg.sv
// Interview-sized UVM pieces for SMMU verification:
//   smmu_txn          - one upstream transaction as seen at ingress + egress
//   smmu_maint_item   - a software action seen by the env (PTE write, TLBI, CFGI, SYNC done)
//   smmu_scoreboard   - INVALIDATION-AWARE checker: accepts any PA that was legal
//                       for this transaction given caching rules (old or new mapping
//                       until the CMD_SYNC that covers the change completes)
//   smmu_coverage     - functional coverage crosses that find SMMU bugs
//
// This is a teaching skeleton: page-table formats are abstracted into a
// "mapping table" kept by the predictor. Compiles against Accellera UVM 1.2/2020.

package smmu_dv_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum {CFG_ABORT, CFG_BYPASS, CFG_S1, CFG_S2, CFG_NESTED} ste_cfg_e;
  typedef enum {RES_OK, RES_TERMINATED, RES_STALLED} result_e;
  typedef enum {F_NONE, F_TRANSLATION, F_ADDR_SIZE, F_ACCESS, F_PERMISSION, F_WALK_EABT,
                C_BAD_STREAMID, C_BAD_STE, C_BAD_SUBSTREAMID, C_BAD_CD} fault_e;
  typedef enum {M_PTE_WRITE, M_PTE_CLEAR, M_TLBI_VA, M_TLBI_ASID, M_TLBI_VMALL,
                M_CFGI_STE, M_SYNC_DONE} maint_e;

  // ------------------------------------------------------------------------
  class smmu_txn extends uvm_sequence_item;
    rand bit [31:0]  sid;
    rand bit [19:0]  ssid;
    rand bit         ssv;
    rand bit [63:0]  va;
    rand bit         write;
    rand bit         priv;
    rand bit         instr;
    // Filled by the monitor at egress / event queue:
    bit [63:0]       pa;
    result_e         result;
    fault_e          fault;
    int unsigned     fault_stage;
    longint unsigned t_ingress;   // time of arrival (sim time or cycle)
    longint unsigned t_egress;

    constraint c_va_canonical { va[63:48] inside {16'h0000, 16'hFFFF}; }

    `uvm_object_utils_begin(smmu_txn)
      `uvm_field_int(sid,   UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(ssid,  UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(ssv,   UVM_ALL_ON)
      `uvm_field_int(va,    UVM_ALL_ON | UVM_HEX)
      `uvm_field_int(write, UVM_ALL_ON)
      `uvm_field_int(pa,    UVM_ALL_ON | UVM_HEX)
      `uvm_field_enum(result_e, result, UVM_ALL_ON)
      `uvm_field_enum(fault_e,  fault,  UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "smmu_txn");
      super.new(name);
    endfunction
  endclass

  // ------------------------------------------------------------------------
  class smmu_maint_item extends uvm_sequence_item;
    maint_e          kind;
    bit [15:0]       asid;
    bit [15:0]       vmid;
    bit [63:0]       va_page;     // page-aligned VA for PTE writes / TLBI_VA
    bit [63:0]       pa_page;
    bit              writable;
    longint unsigned t;           // when the env observed this action
    `uvm_object_utils(smmu_maint_item)
    function new(string name = "smmu_maint_item");
      super.new(name);
    endfunction
  endclass

  // ------------------------------------------------------------------------
  // One mapping version. A page can have several versions alive at once:
  // the newest one, plus older ones that the DUT may still legally use until
  // an invalidation covering them has been completed by CMD_SYNC.
  class map_version;
    bit [63:0]       pa_page;
    bit              valid;
    bit              writable;
    longint unsigned t_written;
    longint unsigned t_dead = '1;   // time the SYNC completed after a covering TLBI
    bit              inv_pending;   // covered by a TLBI that is not yet synced
  endclass

  `uvm_analysis_imp_decl(_txn)
  `uvm_analysis_imp_decl(_maint)

  class smmu_scoreboard extends uvm_component;
    `uvm_component_utils(smmu_scoreboard)

    uvm_analysis_imp_txn   #(smmu_txn,        smmu_scoreboard) txn_export;
    uvm_analysis_imp_maint #(smmu_maint_item, smmu_scoreboard) maint_export;

    // Context the predictor needs; a real env reads it from the STE/CD model.
    bit [15:0] asid_of_sid[bit [31:0]];
    bit [15:0] vmid_of_sid[bit [31:0]];

    // History: key = {vmid, asid, va_page}
    typedef bit [95:0] key_t;
    map_version history[key_t][$];

    int unsigned n_checked, n_errors, n_old_mapping_used;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      txn_export   = new("txn_export", this);
      maint_export = new("maint_export", this);
    endfunction

    function key_t mk(bit [15:0] vmid, bit [15:0] asid, bit [63:0] va_page);
      return {vmid, asid, va_page};
    endfunction

    // --- software actions --------------------------------------------------
    function void write_maint(smmu_maint_item m);
      key_t k;
      map_version v;
      case (m.kind)
        M_PTE_WRITE, M_PTE_CLEAR: begin
          k = mk(m.vmid, m.asid, m.va_page);
          v = new();
          v.pa_page   = m.pa_page;
          v.valid     = (m.kind == M_PTE_WRITE);
          v.writable  = m.writable;
          v.t_written = m.t;
          history[k].push_back(v);
        end
        M_TLBI_VA:    mark_pending(m.vmid, m.asid, m.va_page, 1'b1, 1'b1);
        M_TLBI_ASID:  mark_pending(m.vmid, m.asid, '0, 1'b1, 1'b0);
        M_TLBI_VMALL: mark_pending(m.vmid, '0, '0, 1'b0, 1'b0);
        M_SYNC_DONE:  retire_pending(m.t);
        default: ;
      endcase
    endfunction

    // A TLBI makes every version except the newest one "pending death".
    function void mark_pending(bit [15:0] vmid, bit [15:0] asid, bit [63:0] va_page,
                               bit match_asid, bit match_va);
      foreach (history[k]) begin
        if (k[95:80] != vmid) continue;
        if (match_asid && k[79:64] != asid) continue;
        if (match_va && k[63:0] != va_page) continue;
        for (int i = 0; i < history[k].size() - 1; i++)
          history[k][i].inv_pending = 1'b1;
      end
    endfunction

    // When CMD_SYNC completes, pending versions die at that time.
    function void retire_pending(longint unsigned t);
      foreach (history[k, i])
          if (history[k][i].inv_pending && history[k][i].t_dead == '1) begin
            history[k][i].t_dead      = t;
            history[k][i].inv_pending = 1'b0;
          end
    endfunction

    // --- transactions -------------------------------------------------------
    // Legal if SOME version was alive between ingress and egress and allows
    // this access and PA; or if a fault is consistent with some alive version.
    function void write_txn(smmu_txn t);
      key_t k;
      bit   ok = 0;
      bit   used_old = 0;
      bit [63:0] page = {t.va[63:12], 12'h000};
      n_checked++;
      if (!asid_of_sid.exists(t.sid)) begin
        expect_that(t.result == RES_TERMINATED && t.fault == C_BAD_STREAMID, t, "unknown SID must give C_BAD_STREAMID");
        return;
      end
      k = mk(vmid_of_sid[t.sid], asid_of_sid[t.sid], page);
      if (!history.exists(k)) begin
        expect_that(t.fault == F_TRANSLATION, t, "never-mapped page must fault F_TRANSLATION");
        return;
      end
      for (int i = 0; i < history[k].size(); i++) begin
        map_version v = history[k][i];
        bit alive = (v.t_written <= t.t_egress) && (v.t_dead > t.t_ingress);
        if (!alive) continue;
        if (t.result == RES_OK && v.valid && (v.writable || !t.write)
            && {v.pa_page[63:12], t.va[11:0]} == t.pa) begin
          ok = 1;
          used_old = (i != history[k].size() - 1);
        end
        if (t.result != RES_OK && !v.valid && t.fault == F_TRANSLATION) ok = 1;
        if (t.result != RES_OK && v.valid && t.write && !v.writable && t.fault == F_PERMISSION) ok = 1;
      end
      if (used_old) n_old_mapping_used++;
      expect_that(ok, t, "result not explained by any mapping alive between ingress and egress");
    endfunction

    function void expect_that(bit cond, smmu_txn t, string msg);
      if (!cond) begin
        n_errors++;
        `uvm_error("SMMU_SB", $sformatf("%s\n%s", msg, t.sprint()))
      end
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("SMMU_SB", $sformatf("checked=%0d errors=%0d stale-but-legal=%0d",
                n_checked, n_errors, n_old_mapping_used), UVM_LOW)
      if (n_checked == 0) `uvm_error("SMMU_SB", "scoreboard checked nothing")
    endfunction
  endclass

  // ------------------------------------------------------------------------
  class smmu_coverage extends uvm_subscriber #(smmu_txn);
    `uvm_component_utils(smmu_coverage)

    // Context set by the env before sampling (from the STE/CD/ID-register model).
    ste_cfg_e  cfg;
    bit        secure;
    bit        stall_en;
    int        granule_kb;   // 4, 16, 64
    int        leaf_level;   // 1..3 (block or page)
    bit        tlb_hit;
    bit        inv_in_flight; // a TLBI for this page was pending while txn was in flight
    smmu_txn   tr;

    covergroup cg_txn;
      option.per_instance = 1;
      cp_cfg:     coverpoint cfg;
      cp_sec:     coverpoint secure;
      cp_gran:    coverpoint granule_kb { bins g4 = {4}; bins g16 = {16}; bins g64 = {64}; }
      cp_level:   coverpoint leaf_level { bins block_l1 = {1}; bins block_l2 = {2}; bins page_l3 = {3}; }
      cp_dir:     coverpoint tr.write;
      cp_ssv:     coverpoint tr.ssv;
      cp_result:  coverpoint tr.result;
      cp_fault:   coverpoint tr.fault;
      cp_stage:   coverpoint tr.fault_stage { bins s1 = {1}; bins s2 = {2}; }
      cp_hit:     coverpoint tlb_hit;
      cp_race:    coverpoint inv_in_flight;

      x_cfg_sec:     cross cp_cfg, cp_sec;
      x_gran_level:  cross cp_gran, cp_level;
      x_fault_stage: cross cp_fault, cp_stage, cp_result {
        ignore_bins none = binsof(cp_fault) intersect {F_NONE};
      }
      // Stale-TLB races: a hit while an invalidation was in flight, both directions.
      x_race:        cross cp_hit, cp_race, cp_dir;
      x_cfg_ssv:     cross cp_cfg, cp_ssv;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_txn = new();
    endfunction

    function void write(smmu_txn t);
      tr = t;
      cg_txn.sample();
    endfunction
  endclass

endpackage
