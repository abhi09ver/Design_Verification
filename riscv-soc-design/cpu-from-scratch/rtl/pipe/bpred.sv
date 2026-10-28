// bpred.sv -- Lab 10 (book Ch 13): a branch predictor for the Fetch stage, modelled on Wally's
// src/ifu/bpred (bpred.sv, btb.sv, icpred.sv, gshare.sv, twoBitPredictor.sv, RASPredictor.sv).
//
//   TYPE 0  static not taken (Lab 3's behaviour: every taken branch or jump costs 2 cycles)
//   TYPE 1  static BTFN: decode the instruction in Fetch; backward branches and jal are predicted
//           taken with their PC-relative target (no tables; jalr is never predicted)
//   TYPE 2  bimodal: 2^BHT_BITS x 2-bit saturating counters indexed by PC, + BTB + RAS
//   TYPE 3  gshare, "basic" (book Fig. 13.16): the same table indexed by PC xor GHR, where the GHR
//           holds COMMITTED branches only, + BTB + RAS
//   TYPE 4  gshare with GHR forwarding (book Fig. 13.17): the lookup history also shifts in the
//           branches still in flight -- Memory and Execute with their real outcome, Decode with its
//           predicted one. Without it a tight loop indexes different counters depending on whether
//           its previous iteration was predicted right (the history then lags one branch more).
//           (Wally also forwards in-flight PHT counters on an index match; that is not done here.)
//
// Like Wally:
//   * BTB: 2^BTB_BITS entries, TAGLESS, each {target, instruction class}. The class (branch, jump,
//     call, return, or none) is what lets Fetch decide before the instruction is decoded.
//   * Calls are jal/jalr with rd = x1 or x5; returns are jalr x0, 0(x1 or x5).
//   * Every table is updated when the instruction COMMITS (leaves Memory without trapping), so
//     flushed branches never train the predictor; the GHR is the committed history ("simple gshare",
//     book Fig. 13.16, without the forwarding of Fig. 13.17), so it lags the fetch stream.
//   * The PHT update uses the counter value read at Fetch time and carried down the pipeline
//     (NewBPDir from BPDir), not a fresh read.
// Different from Wally:
//   * The RAS acts in DECODE on the real decoded call/return (push PCD+4 / pop), with the stack top
//     forwarded to Fetch. Each instruction carries a snapshot of the RAS pointer; when an instruction
//     that already acted is killed (flushed from Execute, or trapping in Memory) the pointer is
//     restored. Wally pops in Fetch on a predicted return and repairs on flushes and class errors.
//   * The arrays are flops read combinationally from PCF (Wally: SRAM read from PCNextF).
//
// Deliberate-bug switches:
//   BUG_BP_PRIORITY    a Fetch prediction beats a misprediction redirect from Execute (wrong path)
//   BUG_BP_CFI_ONLY    mispredictions are only checked for branches and jumps; a non-control
//                      instruction the BTB thinks is taken is never corrected (tagless aliasing)
//   BUG_BP_DIR_ONLY    a branch/jump is checked for direction only, not for its target address
//   BUG_RAS_NO_REPAIR  killed calls/returns are not undone in the RAS (performance only)
//   BUG_PHT_NO_SAT     2-bit counters wrap (11 + 1 = 00) instead of saturating (performance only)

module bpred #(parameter int TYPE = 4, parameter int BHT_BITS = 10, parameter int BTB_BITS = 10,
               parameter int RAS_SIZE = 4) (
  input  logic        clk, reset,
  // Fetch: what to fetch next if this instruction is a taken control-flow instruction
  input  logic [31:0] PCF, InstrF,
  output logic        BPTakenF,            // fetch BPPCF next instead of PCF + 4
  output logic [31:0] BPPCF,
  output logic [1:0]  BPDirF,              // counter read at Fetch, carried to Memory
  output logic [BHT_BITS-1:0] BPIndexF,
  output logic [2:0]  BPClassF,            // predicted class, carried to Memory
  output logic [$clog2(RAS_SIZE)-1:0] RASPtr,    // current RAS pointer: the core snapshots it as an
                                                 // instruction leaves Decode (before its own action)
  // Decode: the real class, for the RAS
  input  logic        ValidD, CallD, ReturnD, ActD,    // ActD: the instruction leaves Decode this cycle
  input  logic [31:0] PCPlus4D,
  input  logic        BranchD, BranchE, BranchM_ff, PCSrcE, PCSrcM_ff,   // for GHR forwarding (TYPE 4)
  input  logic [1:0]  BPDirD_ff,
  input  logic        KillE, KillM,                    // an instruction that already acted is killed
  input  logic [$clog2(RAS_SIZE)-1:0] RASPtrE, RASPtrM,
  // Memory: commit (update the tables)
  input  logic        CommitM,
  input  logic [31:0] PCM, TargetM,
  input  logic        BranchM, TakenM,
  input  logic [2:0]  ClassM, PredClassM,
  input  logic [1:0]  DirM,
  input  logic [BHT_BITS-1:0] IndexM
);
  localparam logic [2:0] C_NONE = 3'd0, C_BRANCH = 3'd1, C_JUMP = 3'd2, C_CALL = 3'd3, C_RET = 3'd4;
  localparam int RB = $clog2(RAS_SIZE);

  // ---------------- tables ----------------
  logic [1:0]  PHT [2**BHT_BITS];
  logic [31:0] BTBTarget [2**BTB_BITS];
  logic [2:0]  BTBClass  [2**BTB_BITS];
  logic [BHT_BITS-1:0] GHR;
  logic [31:0] RAS [RAS_SIZE];
  logic [RB-1:0] Ptr;
  initial for (int i = 0; i < RAS_SIZE; i++) RAS[i] = '0;

  // ---------------- Fetch: look up ----------------
  logic [BTB_BITS-1:0] BTBIdx;
  assign BTBIdx   = PCF[BTB_BITS+1:2];
  // speculative history for the lookup: committed GHR + in-flight branches (oldest first)
  logic [BHT_BITS-1:0] GHRF;
  always_comb begin
    GHRF = GHR;
    if (TYPE == 4) begin
      if (BranchM_ff) GHRF = {PCSrcM_ff, GHRF[BHT_BITS-1:1]};
      if (BranchE)    GHRF = {PCSrcE,    GHRF[BHT_BITS-1:1]};
      if (BranchD)    GHRF = {BPDirD_ff[1], GHRF[BHT_BITS-1:1]};
    end
  end
  assign BPIndexF = (TYPE >= 3) ? (PCF[BHT_BITS+1:2] ^ GHRF) : PCF[BHT_BITS+1:2];
  assign BPDirF   = PHT[BPIndexF];

  // RAS top for Fetch, with Decode's action this cycle forwarded (a return right behind a return)
  logic [31:0] RASTop;
  always_comb
    if (ActD & ReturnD)    RASTop = RAS[Ptr - 1'b1];
    else if (ActD & CallD) RASTop = PCPlus4D;
    else                   RASTop = RAS[Ptr];
  assign RASPtr = Ptr;

  // static BTFN: partial decode in Fetch
  logic [31:0] ImmBF, ImmJF;
  logic        IsBranchF, IsJalF;
  assign IsBranchF = (InstrF[6:0] == 7'b1100011);
  assign IsJalF    = (InstrF[6:0] == 7'b1101111);
  assign ImmBF = {{20{InstrF[31]}}, InstrF[7], InstrF[30:25], InstrF[11:8], 1'b0};
  assign ImmJF = {{12{InstrF[31]}}, InstrF[19:12], InstrF[20], InstrF[30:21], 1'b0};

  always_comb begin
    BPTakenF = 1'b0; BPPCF = PCF + 32'd4; BPClassF = C_NONE;
    case (TYPE)
      0: ;
      1: begin
        if (IsJalF) begin BPTakenF = 1'b1; BPPCF = PCF + ImmJF; BPClassF = C_JUMP; end
        else if (IsBranchF) begin BPClassF = C_BRANCH; BPTakenF = InstrF[31]; BPPCF = PCF + ImmBF; end
      end
      default: begin
        BPClassF = BTBClass[BTBIdx];
        case (BPClassF)
          C_BRANCH:       begin BPTakenF = BPDirF[1]; BPPCF = BTBTarget[BTBIdx]; end
          C_JUMP, C_CALL: begin BPTakenF = 1'b1;      BPPCF = BTBTarget[BTBIdx]; end
          C_RET:          begin BPTakenF = 1'b1;      BPPCF = RASTop; end
          default: ;
        endcase
      end
    endcase
    if (!BPTakenF) BPPCF = PCF + 32'd4;
  end

  // ---------------- 2-bit saturating counter (book Fig. 13.2) ----------------
  function automatic logic [1:0] sat(input logic [1:0] s, input logic t);
`ifdef BUG_PHT_NO_SAT
    return t ? s + 2'd1 : s - 2'd1;                      // BUG: wraps around
`else
    if (t) return (s == 2'b11) ? 2'b11 : s + 2'd1;
    else   return (s == 2'b00) ? 2'b00 : s - 2'd1;
`endif
  endfunction

  // ---------------- update at commit (end of Memory) ----------------
  logic [BTB_BITS-1:0] BTBIdxM;
  assign BTBIdxM = PCM[BTB_BITS+1:2];
  // Like Wally (book 13.3.5) the prediction arrays are not reset: in silicon they are SRAMs and power
  // up random, which only costs accuracy. In simulation they start as weakly-not-taken / no class.
  initial begin
    for (int i = 0; i < 2**BHT_BITS; i++) PHT[i] = 2'b01;             // weakly not taken (Example 13.2)
    for (int i = 0; i < 2**BTB_BITS; i++) begin BTBClass[i] = C_NONE; BTBTarget[i] = '0; end
  end
  always_ff @(posedge clk)
    if (reset) begin
      GHR <= '0;
    end else if (CommitM && TYPE >= 2) begin  // (TYPE 4 commits exactly like TYPE 3)
      if (BranchM) begin
        PHT[IndexM] <= sat(DirM, TakenM);
        GHR <= {TakenM, GHR[BHT_BITS-1:1]};                             // newest outcome at the MSB
      end
      if (ClassM != C_NONE) begin BTBClass[BTBIdxM] <= ClassM; BTBTarget[BTBIdxM] <= TargetM; end
      else if (PredClassM != C_NONE) BTBClass[BTBIdxM] <= C_NONE;     // forget a wrong class
    end

  // ---------------- RAS: act in Decode, restore on kill ----------------
  always_ff @(posedge clk)
    if (reset) begin
      Ptr <= '0;
`ifndef BUG_RAS_NO_REPAIR
    end else if (KillM) begin
      Ptr <= RASPtrM;                       // the instruction in Memory traps: undo it and younger
    end else if (KillE) begin
      Ptr <= RASPtrE;                       // the instruction in Execute is flushed
`endif
    end else if (ActD & CallD) begin
      RAS[Ptr + 1'b1] <= PCPlus4D;          // push
      Ptr <= Ptr + 1'b1;
    end else if (ActD & ReturnD) begin
      Ptr <= Ptr - 1'b1;                    // pop
    end
endmodule
