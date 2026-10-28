// hazard.sv -- stall and flush control for the 5-stage pipeline
//
// A cut-down version of cvw/src/hazard/hazard.sv. Wally's rules, which hold here too:
//   * A stage must stall if the next stage is stalled.
//   * If a stage stalls, the first stage after it that is NOT stalled must flush
//     (otherwise the same instruction would be issued twice).
//   * Flush has priority over stall.
//
// Causes:
//   LoadStallD / CSRRdStallD : the instruction in Decode needs a value that only appears
//                at the end of M (load data, CSR read). Stall F and D, bubble into E.
//   PCSrcE     : a branch is taken (or a jump) in Execute. We predicted "not taken":
//                flush the two wrong-path instructions out of D and E.
//   TrapM      : (Ch 8) exception or interrupt in M: flush D, E, M and W. The faulting
//                instruction itself must not reach W, so traps are precise.
//   RetM, CSRWriteFlushM : mret or a CSR write in M: flush D, E, M (younger instructions
//                are refetched); the mret/CSR instruction itself retires.
//   LSUStallM  : (Ch 9) a load/store is using the AHB bus (Adr and Data phases). Like Wally,
//                stall the WHOLE pipeline (StallW), so nothing moves until the bus is done.
//                A trap beats the bus stall (StallWCause & ~FlushWCause, book Fig. 9.33);
//                the busfsm only lets that happen before the transfer is committed.
module hazard (
  input  logic LoadStallD, CSRRdStallD,
  input  logic PCSrcE,
  input  logic TrapM, RetM, CSRWriteFlushM,
  input  logic LSUStallM,
  output logic StallF, StallD, StallE, StallM, StallW,
  output logic FlushD, FlushE, FlushM, FlushW
);
  logic FlushDCause, FlushECause, FlushMCause, FlushWCause;
  assign FlushWCause = TrapM;
  assign FlushMCause = TrapM | RetM | CSRWriteFlushM;
  assign FlushDCause = PCSrcE | FlushMCause;
  assign FlushECause = PCSrcE | FlushMCause;

  // stall causes, then propagate: a stage stalls if any later stage stalls
  assign StallW = LSUStallM & ~FlushWCause;
  assign StallM = StallW;
  assign StallE = StallM;
  assign StallD = StallE | ((LoadStallD | CSRRdStallD) & ~FlushDCause);   // flushes beat stalls
  assign StallF = StallD;

`ifdef BUG_NO_FLUSH_E
  // BUG: only kills PC+8. The PC+4 instruction moves into Execute and changes state.
  assign FlushD = FlushDCause;
  assign FlushE = (StallD & ~StallE) | FlushMCause;
`else
  assign FlushD = FlushDCause;
  // bubble into the first unstalled stage behind a stall, or kill a younger instruction
  assign FlushE = (StallD & ~StallE) | FlushECause;
`endif
  assign FlushM = FlushMCause;
  assign FlushW = TrapM;
endmodule
