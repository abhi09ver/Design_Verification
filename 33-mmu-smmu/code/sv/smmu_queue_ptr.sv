// smmu_queue_ptr.sv
// SMMUv3-style circular queue index logic with a wrap bit, plus the SVA you
// would bind to it. Index = {WRAP, IDX[LOG2SIZE-1:0]}.
//   empty : prod == cons
//   full  : IDX equal, WRAP different  -> all 2**LOG2SIZE slots usable
// Interview use: "Write assertions for the Command/Event queue pointers."

module smmu_queue_ptr #(
  parameter int LOG2SIZE = 3
) (
  input  logic              clk,
  input  logic              rst_n,
  input  logic              push,      // producer writes one entry
  input  logic              pop,       // consumer reads one entry
  output logic [LOG2SIZE:0] prod,
  output logic [LOG2SIZE:0] cons,
  output logic              full,
  output logic              empty,
  output logic              ovflg      // toggles once per overflow episode
);
  localparam int SIZE = 1 << LOG2SIZE;

  logic ovackflg;  // software acknowledge (modelled as "ack on next pop")

  assign empty = (prod == cons);
`ifdef BUG_NO_WRAP_BIT
  // Injected bug for "prove your checker can fail": ignores the wrap bit,
  // so an empty queue also looks full.
  assign full  = (prod[LOG2SIZE-1:0] == cons[LOG2SIZE-1:0]);
`else
  assign full  = (prod[LOG2SIZE-1:0] == cons[LOG2SIZE-1:0]) &&
                 (prod[LOG2SIZE] != cons[LOG2SIZE]);
`endif

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prod     <= '0;
      cons     <= '0;
      ovflg    <= 1'b0;
      ovackflg <= 1'b0;
    end else begin
      if (push && !full)                     prod  <= prod + 1'b1;  // wraps naturally
      if (push && full && ovflg == ovackflg) ovflg <= ~ovflg;       // new overflow episode
      if (pop && !empty) begin
        cons     <= cons + 1'b1;
        ovackflg <= ovflg;
      end
    end
  end

  // ------------------------------------------------------------------ SVA
`ifndef SYNTHESIS
  function automatic int occupancy(logic [LOG2SIZE:0] p, logic [LOG2SIZE:0] c);
    return int'((p - c) & ((2 * SIZE) - 1));
  endfunction

  default clocking cb @(posedge clk); endclocking
  // Each property carries its own disable iff (some tools lack 'default disable iff').

  // Occupancy can never exceed the queue size.
  a_occupancy_bound: assert property (disable iff (!rst_n) occupancy(prod, cons) <= SIZE);

  // full and empty are mutually exclusive.
  a_full_empty_excl: assert property (disable iff (!rst_n) !(full && empty));

  // Producer moves by exactly one (or not at all) and never past a full queue.
  a_prod_step:   assert property (disable iff (!rst_n) prod == $past(prod) || prod == $past(prod) + 1'b1);
  a_no_push_full: assert property (disable iff (!rst_n) $past(full) && !$past(pop) |-> prod == $past(prod));

  // Consumer moves by one and never reads an empty queue.
  a_cons_step:    assert property (disable iff (!rst_n) cons == $past(cons) || cons == $past(cons) + 1'b1);
  a_no_pop_empty: assert property (disable iff (!rst_n) $past(empty) |-> cons == $past(cons));

  // A push that is dropped while full must raise (toggle) the overflow flag
  // unless an unacknowledged episode is already open.
  a_ovf_toggle: assert property (disable iff (!rst_n) 
    push && full && (ovflg == ovackflg) |=> ovflg != $past(ovflg));

  // Reset value.
  a_reset_empty: assert property (@(posedge clk) !rst_n |=> empty);

  // Coverage: reach full, wrap the index, overflow, and simultaneous push+pop.
  c_full:      cover property (disable iff (!rst_n) full);
  c_wrap:      cover property (disable iff (!rst_n) prod[LOG2SIZE] && !$past(prod[LOG2SIZE]));
  c_overflow:  cover property (disable iff (!rst_n) push && full);
  c_push_pop:  cover property (disable iff (!rst_n) push && pop && !full && !empty);
`endif
endmodule
