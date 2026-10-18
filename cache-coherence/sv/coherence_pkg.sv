// coherence_pkg.sv
// Reusable testbench-side pieces for verifying a MESI/MOESI cache-coherence subsystem.
//
//   * mesi_t / coh_event_t      - common state and event encodings
//   * coherence_scoreboard      - golden memory + per-address write order + CoRR check
//   * coherence_cov             - (state x event) transition coverage and race crosses
//
// Plain SystemVerilog classes (no UVM dependency) so they drop into any environment.
// In a UVM bench, wrap coherence_scoreboard in a uvm_scoreboard and feed it from the
// core-side monitors' analysis ports (see the comments on write_observed / load_observed).
//
// Syntax-checked with slang (pyslang). Not run on a commercial simulator here.

package coherence_pkg;

  typedef enum logic [2:0] {
    ST_I = 3'd0,
    ST_S = 3'd1,
    ST_E = 3'd2,
    ST_O = 3'd3,
    ST_M = 3'd4
  } mesi_t;

  typedef enum logic [3:0] {
    EV_LOAD_HIT,
    EV_LOAD_MISS,
    EV_STORE_HIT,
    EV_STORE_UPGRADE,
    EV_STORE_MISS,
    EV_EVICT,
    EV_SNOOP_GETS,
    EV_SNOOP_GETM,
    EV_SNOOP_INV
  } coh_event_t;

  typedef logic [47:0] addr_t;   // line address (byte address >> 6)
  typedef logic [63:0] data_t;   // one word is enough for a checker

  // ---------------------------------------------------------------------------
  // Scoreboard
  //
  // Coherence order: every store to a line gets a version number when it becomes
  // globally visible (i.e. when the writer holds M and the store performs).
  // A load must return the value of SOME version that is
  //   (a) not older than the newest version this core has already observed (CoRR), and
  //   (b) not newer than the newest version that exists.
  // For an atomic-snoop/SWMR implementation, (a)+(b) collapse to "latest value".
  // For designs where a load may legally complete with an older value (e.g. a
  // load that performed just before an invalidation arrived), keep the window.
  // ---------------------------------------------------------------------------
  class coherence_scoreboard #(int N_CORES = 4);

    // per line: history of values in coherence order (index = version)
    data_t history  [addr_t][$];
    // per core, per line: newest version observed
    int    last_seen[N_CORES][addr_t];

    int unsigned n_loads, n_stores, n_errors;
    bit          strict_latest = 1;   // 1: load must see newest version

    function new();
      n_loads = 0; n_stores = 0; n_errors = 0;
    endfunction

    // Initial memory contents are version 0.
    function automatic void init_line(addr_t a, data_t v);
      history[a] = {};
      history[a].push_back(v);
    endfunction

    function automatic int latest_version(addr_t a);
      if (!history.exists(a)) init_line(a, '0);
      return history[a].size() - 1;
    endfunction

    // Call when a store performs (writer has M and updates its copy).
    function automatic void write_observed(int core, addr_t a, data_t v);
      void'(latest_version(a));
      history[a].push_back(v);
      last_seen[core][a] = history[a].size() - 1;
      n_stores++;
    endfunction

    // Call when a load returns data to the core.
    function automatic void load_observed(int core, addr_t a, data_t got);
      int newest, floor_v, match_v;
      newest  = latest_version(a);
      floor_v = last_seen[core].exists(a) ? last_seen[core][a] : 0;
      match_v = -1;
      n_loads++;

      // search newest-first inside the legal window
      for (int v = newest; v >= (strict_latest ? newest : floor_v); v--) begin
        if (history[a][v] == got) begin
          match_v = v;
          break;
        end
      end

      if (match_v < 0) begin
        n_errors++;
        $error("[SB] core%0d load line %h got %h; legal window v%0d..v%0d (latest %h)",
               core, a, got, strict_latest ? newest : floor_v, newest, history[a][newest]);
      end else begin
        last_seen[core][a] = match_v;
      end
    endfunction

    // End of test: drain caches first, then compare memory against the newest version.
    function automatic void check_memory(addr_t a, data_t mem_val);
      int newest = latest_version(a);
      if (mem_val !== history[a][newest]) begin
        n_errors++;
        $error("[SB] end-of-test line %h memory=%h expected=%h", a, mem_val, history[a][newest]);
      end
    endfunction

    function automatic void report();
      $display("[SB] loads=%0d stores=%0d errors=%0d", n_loads, n_stores, n_errors);
    endfunction

  endclass

  // ---------------------------------------------------------------------------
  // Coverage
  // Sample once per protocol event seen at a cache controller.
  // ---------------------------------------------------------------------------
  class coherence_cov;

    mesi_t      cur_state;
    mesi_t      next_state;
    coh_event_t ev;
    int         num_sharers;      // other valid copies at the time of the event
    bit         race_inflight;    // another request to the same line was in flight

    covergroup cg_transition;
      option.per_instance = 1;

      cp_state : coverpoint cur_state;
      cp_next  : coverpoint next_state;
      cp_event : coverpoint ev;

      cp_sharers : coverpoint num_sharers {
        bins none = {0};
        bins one  = {1};
        bins many = {[2:$]};
      }

      // Every (state x event) cell. Cells that the protocol says can never happen
      // are made illegal so that hitting one fails the run.
      x_state_event : cross cp_state, cp_event {
        illegal_bins load_hit_in_I  = binsof(cp_state) intersect {ST_I} &&
                                      binsof(cp_event) intersect {EV_LOAD_HIT, EV_STORE_HIT};
        illegal_bins store_hit_in_S = binsof(cp_state) intersect {ST_S} &&
                                      binsof(cp_event) intersect {EV_STORE_HIT};
        ignore_bins  miss_when_valid = binsof(cp_state) intersect {ST_S, ST_E, ST_O, ST_M} &&
                                       binsof(cp_event) intersect {EV_LOAD_MISS, EV_STORE_MISS};
      }

      // Stable transitions actually taken
      x_transition : cross cp_state, cp_next;

      // The interesting races: own request while another core's request is in flight
      x_race : cross cp_event, race_inflight {
        ignore_bins no_race = binsof(race_inflight) intersect {0};
      }

      // Upgrades and snoops with 0 / 1 / many sharers (ack-count corner cases)
      x_sharers : cross cp_event, cp_sharers {
        ignore_bins irrelevant = binsof(cp_event) intersect {EV_LOAD_HIT, EV_STORE_HIT, EV_EVICT};
      }
    endgroup

    function new();
      cg_transition = new();
    endfunction

    function automatic void sample_event(mesi_t cur, mesi_t nxt, coh_event_t e,
                                         int sharers, bit race);
      cur_state     = cur;
      next_state    = nxt;
      ev            = e;
      num_sharers   = sharers;
      race_inflight = race;
      cg_transition.sample();
    endfunction

  endclass

endpackage : coherence_pkg
