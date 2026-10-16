// coherence_assertions.sv
// SVA checkers for a cache-coherence subsystem. Bind them to the RTL.
//
//   swmr_checker          - global Single-Writer/Multiple-Reader invariant for one tracked line
//                           (instantiate per tracked line, or drive it from a "line of interest"
//                           mux in the TB; formal tools usually use a symbolic address)
//   l1_state_checker      - per-cache legal stable-state transitions (MESI)
//   miss_progress_checker - every miss completes, inv-ack counts never go negative
//
// Syntax-checked with slang (pyslang). Signal names are placeholders: map them to your
// controller's state arrays, MSHR fields and message valid/ready signals.

import coherence_pkg::*;

// -----------------------------------------------------------------------------
// 1. SWMR: at most one writable copy, and a writable copy excludes readers.
//    Also: at most one owner (M or O) so exactly one cache answers with dirty data.
// -----------------------------------------------------------------------------
module swmr_checker #(
  parameter int N_CORES = 4
) (
  input  logic  clk,
  input  logic  rst_n,
  input  mesi_t line_state [N_CORES]   // stable state of the tracked line in each L1
);

  function automatic int count_state(mesi_t s0, mesi_t s1);
    int n = 0;
    for (int i = 0; i < N_CORES; i++)
      if (line_state[i] == s0 || line_state[i] == s1) n++;
    return n;
  endfunction

  function automatic int count_valid();
    int n = 0;
    for (int i = 0; i < N_CORES; i++)
      if (line_state[i] != ST_I) n++;
    return n;
  endfunction

  // M or E: exclusive copies
  a_single_writer : assert property (@(posedge clk) disable iff (!rst_n)
    count_state(ST_M, ST_E) <= 1)
    else $error("SWMR: more than one M/E copy");

  a_writer_alone : assert property (@(posedge clk) disable iff (!rst_n)
    count_state(ST_M, ST_E) == 1 |-> count_valid() == 1)
    else $error("SWMR: M/E copy coexists with other valid copies");

  a_single_owner : assert property (@(posedge clk) disable iff (!rst_n)
    count_state(ST_M, ST_O) <= 1)
    else $error("More than one owner (M/O) for the line");

  // Coverage: make sure the checker is not vacuous
  c_two_sharers : cover property (@(posedge clk) disable iff (!rst_n)
    count_state(ST_S, ST_S) >= 2);
  c_owner_with_sharers : cover property (@(posedge clk) disable iff (!rst_n)
    count_state(ST_O, ST_O) == 1 && count_state(ST_S, ST_S) >= 1);
  c_m_to_s : cover property (@(posedge clk) disable iff (!rst_n)
    count_state(ST_M, ST_M) == 1 ##[1:$] count_state(ST_S, ST_S) >= 2);

endmodule

// -----------------------------------------------------------------------------
// 2. Per-L1 legal stable-state transitions (MESI).
//    The transient states live in the MSHR; this checks the stable state array.
// -----------------------------------------------------------------------------
module l1_state_checker (
  input logic  clk,
  input logic  rst_n,
  input mesi_t state,            // stable state of the line in this cache
  input logic  fill_valid,       // data fill completed this cycle
  input logic  fill_exclusive,   // fill granted with no other sharers
  input logic  core_store,       // core store performs this cycle
  input logic  snoop_gets,       // incoming GetS / Fwd-GetS handled
  input logic  snoop_getm,       // incoming GetM / Inv handled
  input logic  evict             // line evicted this cycle
);

  // I can only become valid via a fill
  a_i_needs_fill : assert property (@(posedge clk) disable iff (!rst_n)
    (state == ST_I) ##1 (state != ST_I) |-> $past(fill_valid))
    else $error("I -> valid without a data fill");

  // E only when the fill said 'exclusive'
  a_e_only_if_exclusive : assert property (@(posedge clk) disable iff (!rst_n)
    (state == ST_I && fill_valid && !fill_exclusive) |=> state != ST_E)
    else $error("Granted E although other sharers exist");

  // S -> M never silent: needs the upgrade fill/ack path
  a_no_silent_s_to_m : assert property (@(posedge clk) disable iff (!rst_n)
    (state == ST_S) ##1 (state == ST_M) |-> $past(fill_valid))
    else $error("S -> M without completing an upgrade");

  // Cannot store unless in M (E->M happens in the same cycle as the store)
  a_store_needs_permission : assert property (@(posedge clk) disable iff (!rst_n)
    core_store |-> (state == ST_M || state == ST_E))
    else $error("Store performed without write permission");

  // A snooped GetM must leave the line Invalid
  a_getm_invalidates : assert property (@(posedge clk) disable iff (!rst_n)
    snoop_getm |=> state == ST_I)
    else $error("Snooped GetM did not invalidate");

  // A snooped GetS must remove exclusivity
  a_gets_downgrades : assert property (@(posedge clk) disable iff (!rst_n)
    snoop_gets && state inside {ST_M, ST_E} |=> state inside {ST_S, ST_O, ST_I})
    else $error("Snooped GetS left the line exclusive");

  a_evict_to_i : assert property (@(posedge clk) disable iff (!rst_n)
    evict |=> state == ST_I);

  // Coverage of each legal transition
  c_i_e : cover property (@(posedge clk) disable iff (!rst_n) state == ST_I ##1 state == ST_E);
  c_i_s : cover property (@(posedge clk) disable iff (!rst_n) state == ST_I ##1 state == ST_S);
  c_e_m : cover property (@(posedge clk) disable iff (!rst_n) state == ST_E ##1 state == ST_M);
  c_s_m : cover property (@(posedge clk) disable iff (!rst_n) state == ST_S ##1 state == ST_M);
  c_m_s : cover property (@(posedge clk) disable iff (!rst_n) state == ST_M ##1 state == ST_S);
  c_m_i : cover property (@(posedge clk) disable iff (!rst_n) state == ST_M ##1 state == ST_I);

endmodule

// -----------------------------------------------------------------------------
// 3. Forward progress and ack accounting for one MSHR entry.
// -----------------------------------------------------------------------------
module miss_progress_checker #(
  parameter int MAX_LATENCY = 2000,   // cycles; scale for the config under test
  parameter int ACK_W       = 8
) (
  input logic             clk,
  input logic             rst_n,
  input logic             req_issue,     // GetS/GetM leaves the cache
  input logic             req_done,      // MSHR entry retires
  input logic             data_arrived,
  input logic             ack_arrived,
  input logic [ACK_W-1:0] acks_expected, // from directory / data message
  input logic signed [ACK_W:0] ack_count // controller's running counter (may go < 0 before data)
);

  // Liveness, bounded for simulation (use s_eventually in formal)
  a_miss_completes : assert property (@(posedge clk) disable iff (!rst_n)
    req_issue |-> ##[1:MAX_LATENCY] req_done)
    else $error("Miss did not complete within %0d cycles (deadlock/livelock/starvation?)", MAX_LATENCY);

  // Retire only with data present and all acks collected
  a_retire_complete : assert property (@(posedge clk) disable iff (!rst_n)
    req_done |-> ack_count == $signed({1'b0, acks_expected}))
    else $error("MSHR retired before all invalidation acks were received");

  // Counter must never exceed what was asked for
  a_ack_bound : assert property (@(posedge clk) disable iff (!rst_n)
    data_arrived |-> ack_count <= $signed({1'b0, acks_expected}))
    else $error("More acks than sharers");

  // Classic race: acks before data (counter goes negative or is pre-counted)
  c_acks_before_data : cover property (@(posedge clk) disable iff (!rst_n)
    req_issue ##[1:$] ack_arrived ##[1:$] data_arrived);
  c_zero_acks : cover property (@(posedge clk) disable iff (!rst_n)
    data_arrived && acks_expected == 0);

endmodule

// -----------------------------------------------------------------------------
// Example bind (adjust hierarchy and signal names):
//
//   bind l1_cache_ctrl l1_state_checker u_l1_chk (
//     .clk, .rst_n,
//     .state         (tag_state[dbg_set][dbg_way]),
//     .fill_valid    (fill_vld && fill_set == dbg_set),
//     .fill_exclusive(fill_excl),
//     .core_store    (st_perform && st_set == dbg_set),
//     .snoop_gets    (snp_vld && snp_type == SNP_GETS),
//     .snoop_getm    (snp_vld && snp_type inside {SNP_GETM, SNP_INV}),
//     .evict         (evict_vld && evict_set == dbg_set));
// -----------------------------------------------------------------------------
