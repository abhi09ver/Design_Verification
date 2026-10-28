// core_pipe.sv -- Lab 3: 5-stage pipelined RV32I core, written from scratch
//
//   F (Fetch) -> D (Decode) -> E (Execute) -> M (Memory) -> W (Writeback)
//
// Same units as the single-cycle core, with pipeline registers between stages.
// Signal names carry their stage as a suffix exactly like Wally: RdE, RdM, RdW are
// the destination register of three DIFFERENT instructions in flight.
//
// Hazards (book Section 7.2.2, Wally controller.sv + hazard.sv):
//   * RAW data hazards  -> forward from M or W into E; stall one cycle for load-use
//   * control hazards   -> predict not-taken, resolve in E, flush 2 instructions
//
// Deliberate-bug switches for the verification lab (compile with -D<name>):
//   BUG_FWD_PRIORITY   check W before M when both match: picks the OLDER value
//   BUG_NO_FWD_W       never forward from Writeback
//   BUG_FWD_X0         forget that x0 is never a real destination
//   BUG_NO_LOAD_STALL  no load-use stall: forwards the load ADDRESS instead of data
//   BUG_NO_FLUSH_E     (in hazard.sv) one wrong-path instruction survives a taken branch
//
// Lab 5 (book Ch 8) adds the machine-mode privileged unit (priv.sv): CSRs, ecall,
// ebreak, mret, exceptions and interrupts. Traps are taken in M, like Wally.
//
// Lab 6 (book Ch 9) adds an AHB manager port to the LSU, like Wally's ahbinterface +
// busfsm: loads and stores to the bus regions (0x1xxx_xxxx and 0x9xxx_xxxx) go out over
// AHB in three steps (Adr, Data, Mem3) while the whole pipeline stalls; everything else
// still uses the in-core memory (IROM/DTIM, answers in the same cycle).
//   BUG_BUS_NO_CANCEL  start the bus transfer even when the instruction traps
//
// Lab 7 (book Ch 10) puts a write-back data cache (dcache.sv) in front of the bus RAM:
// 0x9000_xxxx is cacheable (PMA), 0x9100_xxxx is the same RAM uncached. fence.i flushes it.
//
// Lab 8 (book Ch 11) puts a data MMU (mmu.sv) between the address adder and the LSU:
// Sv32 DTLB + hardware page-table walker + PMP. The walker borrows the LSU (DTIM, D-cache or
// bus) to read PTEs while the pipeline stalls; the LSU itself sees GatedStallW = StallW &
// ~SelHPTW so it keeps moving for the walker (Wally lsu.sv). Adds U-mode, satp, sfence.vma.
//
// Lab 10 (book Ch 13) adds a branch predictor in Fetch (bpred.sv): static or dynamic direction,
// a tagless BTB with instruction class, and a return-address stack. Execute compares the PC the
// predictor chose for the next instruction with the correct one (PCCorrectE) and flushes D and E
// only when they differ (BPWrongE replaces PCSrcE in the hazard unit).
//   BP_TYPE: 0 static not taken (the old behaviour), 1 static BTFN, 2 bimodal, 3 gshare (committed
//   history), 4 gshare with GHR forwarding (default, like Wally's BP_GSHARE)
//
// Simplifications vs Wally: no I-cache, instruction fetch never uses the bus (so no EBU
// arbitration), M-mode only, no branch predictor, no compressed instructions.

module core_pipe #(parameter logic [31:0] RESET_VECTOR = 32'h8000_0000,
                   parameter int DC_WAYS = 2, parameter int DC_SETS = 8, parameter int DC_LINEWORDS = 4,
                   parameter int TLB_ENTRIES = 4, parameter bit DC_SYNC = 1,
                   parameter int BP_TYPE = 4, parameter int BHT_BITS = 10, parameter int BTB_BITS = 10,
                   parameter int RAS_SIZE = 4) (
  input  logic        clk, reset,
  output logic [31:0] PC,               // = PCF
  input  logic [31:0] Instr,            // = InstrF
  output logic        MemWrite,         // = MemWriteM
  output logic [31:0] DataAdr,
  output logic [31:0] WriteDataAligned,
  output logic [3:0]  ByteMask,
  input  logic [31:0] ReadDataWord,
  // retirement trace from the Writeback stage (like Wally's wallyTracer.sv)
  output logic        TraceValid,
  output logic [31:0] TracePC, TraceInstr,
  output logic        TraceRegWrite,
  output logic [4:0]  TraceRd,
  output logic [31:0] TraceResult,
  output logic        TraceMemWrite,
  output logic [31:0] TraceMemAdr, TraceMemData,
  output logic [3:0]  TraceMemMask,
  output logic [31:0] TracePCNext,
  output logic        TraceIllegal,
  // privileged trace: a trap taken this cycle (from M), and CSR writes retiring in W
  output logic        TraceTrap,
  output logic [31:0] TraceTrapPC, TraceCause, TraceTval,
  output logic        TraceCSRWrite,
  output logic [11:0] TraceCSRAdr,
  output logic [31:0] TraceCSRVal,
  // interrupt pins (Wally: MTimerInt/MSwInt from the CLINT, MExtInt from the PLIC)
  input  logic        MTimerInt, MSwInt, MExtInt,
  // AHB manager port of the LSU (Ch 9)
  output logic [31:0] HADDR,
  output logic        HWRITE,
  output logic [1:0]  HTRANS,
  output logic [2:0]  HSIZE,
  output logic [31:0] HWDATA,
  output logic [3:0]  HWSTRB,
  output logic [2:0]  HBURST,
  input  logic        HREADY,
  input  logic [31:0] HRDATA
);
  logic StallF, StallD, StallE, StallM, StallW, FlushD, FlushE, FlushM, FlushW;
  logic LoadStallD, CSRRdStallD, PCSrcE, LSUStallM, BusCommittedM, BPWrongE;
  logic [31:0] PCCorrectE;
  logic TrapM, InterruptM, RetM, CSRWriteFlushM;
  logic [31:0] PrivPCNextM;

  // =====================================================================
  // F: Fetch
  // =====================================================================
  logic [31:0] PCF, PCNextF, PCPlus4F, InstrF, IEUAdrE;
  assign PCPlus4F = PCF + 32'd4;
  assign PC     = PCF;
  assign InstrF = Instr;
  // ---- Lab 10: branch prediction (Wally src/ifu/bpred) ----
  localparam int RB = $clog2(RAS_SIZE);
  logic        BPTakenF, ActD, KillE, KillM, CommitM;
  logic [31:0] BPPCF, PredNextF;
  logic [1:0]  BPDirF;
  logic [BHT_BITS-1:0] BPIndexF;
  logic [2:0]  BPClassF;
  logic [RB-1:0] RASPtr, RASPtrE, RASPtrM;
  logic        CallD, ReturnD;
  logic [2:0]  ClassD, ClassE, ClassM, BPClassD, BPClassE, BPClassM;
  logic [1:0]  BPDirD, BPDirE, BPDirM;
  logic [BHT_BITS-1:0] BPIndexD, BPIndexE, BPIndexM;
  logic        BranchM, PCSrcM;
  logic [31:0] PCPlus4D_bp;
  assign PredNextF = BPTakenF ? BPPCF : PCPlus4F;
  // priority: trap / mret / CSR-write refetch (from M, oldest) > misprediction in E > prediction in F
`ifdef BUG_BP_PRIORITY
  assign PCNextF = (TrapM | RetM | CSRWriteFlushM) ? PrivPCNextM :
                   BPTakenF                        ? BPPCF       :           // BUG: younger beats older
                   BPWrongE                        ? PCCorrectE  : PCPlus4F;
`else
  assign PCNextF = (TrapM | RetM | CSRWriteFlushM) ? PrivPCNextM :
                   BPWrongE                        ? PCCorrectE  : PredNextF;
`endif
  flopenr #(32, RESET_VECTOR) pcreg(clk, reset, ~StallF, PCNextF, PCF);

  // =====================================================================
  // D: Decode -- read registers, decode, extend immediate
  // =====================================================================
  logic [31:0] InstrD, PCD, PCPlus4D, R1D, R2D, ImmExtD, ResultW;
  logic        ValidD, RegWriteW;
  logic [4:0]  Rs1D, Rs2D, RdD, RdW;

  flopenrc #(32) InstrDReg (clk, reset, FlushD, ~StallD, InstrF,   InstrD);
  flopenrc #(32) PCDReg    (clk, reset, FlushD, ~StallD, PCF,      PCD);
  flopenrc #(32) PCP4DReg  (clk, reset, FlushD, ~StallD, PCPlus4F, PCPlus4D);
  flopenrc #(1)  ValidDReg (clk, reset, FlushD, ~StallD, 1'b1,     ValidD);   // 0 = bubble
  logic [31:0] PredNextD, PredNextE;
  flopenrc #(32) PredDReg  (clk, reset, FlushD, ~StallD, PredNextF, PredNextD);  // what the predictor chose
  flopenrc #(5+BHT_BITS) BPDReg(clk, reset, FlushD, ~StallD, {BPClassF, BPDirF, BPIndexF}, {BPClassD, BPDirD, BPIndexD});

  assign Rs1D = InstrD[19:15];
  assign Rs2D = InstrD[24:20];
  assign RdD  = InstrD[11:7];

  logic       RegWriteD, ALUSrcAD, ALUSrcBD, SubArithD, ALUResultSrcD;
  logic       MemReadD, MemWriteD, BranchD, JumpD, IllegalD, BaseRegWriteD, BaseIllegalD;
  logic       SystemD, CSRD, EcallD, EbreakD, MretD, WfiD, PrivIllegalD, SfenceVmaD;
  logic [2:0] ImmSrcD, ALUSelectD;
  privdec pdec(.Instr(InstrD), .System(SystemD), .CSR(CSRD), .Ecall(EcallD), .Ebreak(EbreakD),
               .Mret(MretD), .Wfi(WfiD), .SfenceVma(SfenceVmaD), .Illegal(PrivIllegalD));
  assign RegWriteD = BaseRegWriteD | CSRD;                   // CSR instructions write rd
  assign IllegalD  = (BaseIllegalD & ~SystemD) | PrivIllegalD;
  decoder dec(.Instr(InstrD), .RegWrite(BaseRegWriteD), .ImmSrc(ImmSrcD), .ALUSrcA(ALUSrcAD),
              .ALUSrcB(ALUSrcBD), .ALUSelect(ALUSelectD), .SubArith(SubArithD),
              .ALUResultSrc(ALUResultSrcD), .MemRead(MemReadD), .MemWrite(MemWriteD),
              .Branch(BranchD), .Jump(JumpD), .Illegal(BaseIllegalD));
  // instruction class (Wally icpred): calls write x1/x5, returns are jalr x0, (x1/x5)
  assign CallD   = ValidD & JumpD & ((RdD == 5'd1) | (RdD == 5'd5));
  assign ReturnD = ValidD & JumpD & (InstrD[6:0] == 7'b1100111) & (RdD == 5'd0) & ((Rs1D == 5'd1) | (Rs1D == 5'd5));
  assign ClassD  = ~ValidD ? 3'd0 : BranchD ? 3'd1 : ReturnD ? 3'd4 : CallD ? 3'd3 : JumpD ? 3'd2 : 3'd0;
  assign PCPlus4D_bp = PCPlus4D;
  assign ActD    = ValidD & ~StallD & ~FlushE;            // leaves Decode into Execute this cycle

  // falling-edge write: W writes in the first half cycle, D reads in the second half,
  // so no W->D forwarding path is needed (book Fig. 7.15, the "and t3" instruction)
  regfile #(.NEGEDGE(1)) regf(.clk, .reset, .we3(RegWriteW), .a1(Rs1D), .a2(Rs2D), .a3(RdW),
                              .wd3(ResultW), .rd1(R1D), .rd2(R2D));
  extend ext(.Instr(InstrD[31:7]), .ImmSrc(ImmSrcD), .ImmExt(ImmExtD));

  // =====================================================================
  // E: Execute -- forward, ALU, compare, resolve branches
  // =====================================================================
  // control bits travel with the instruction; FlushE turns them all to 0 = bubble
  logic        RegWriteE, ALUSrcAE, ALUSrcBE, SubArithE, ALUResultSrcE;
  logic        MemReadE, MemWriteE, BranchE, JumpE, IllegalE, ValidE;
  logic        CSRE, EcallE, EbreakE, MretE, WfiE, SfenceVmaE;
  logic [2:0]  ALUSelectE, Funct3E;
  logic [4:0]  Rs1E, Rs2E, RdE;
  logic [31:0] R1E, R2E, ImmExtE, PCE, PCPlus4E, InstrE;

  flopenrc #(11) CtrlEReg(clk, reset, FlushE, ~StallE,
    {RegWriteD, ALUSrcAD, ALUSrcBD, SubArithD, ALUResultSrcD, MemReadD, MemWriteD, BranchD, JumpD, IllegalD, ValidD},
    {RegWriteE, ALUSrcAE, ALUSrcBE, SubArithE, ALUResultSrcE, MemReadE, MemWriteE, BranchE, JumpE, IllegalE, ValidE});
  flopenrc #(6)  PrivEReg  (clk, reset, FlushE, ~StallE, {CSRD, EcallD, EbreakD, MretD, WfiD, SfenceVmaD},
                                                           {CSRE, EcallE, EbreakE, MretE, WfiE, SfenceVmaE});
  flopenrc #(3)  ALUSelEReg(clk, reset, FlushE, ~StallE, ALUSelectD,     ALUSelectE);
  flopenrc #(3)  F3EReg    (clk, reset, FlushE, ~StallE, InstrD[14:12],  Funct3E);
  flopenrc #(15) RegsEReg  (clk, reset, FlushE, ~StallE, {Rs1D, Rs2D, RdD}, {Rs1E, Rs2E, RdE});
  flopenrc #(32) R1EReg    (clk, reset, FlushE, ~StallE, R1D,      R1E);
  flopenrc #(32) R2EReg    (clk, reset, FlushE, ~StallE, R2D,      R2E);
  flopenrc #(32) ImmEReg   (clk, reset, FlushE, ~StallE, ImmExtD,  ImmExtE);
  flopenrc #(32) PCEReg    (clk, reset, FlushE, ~StallE, PCD,      PCE);
  flopenrc #(32) PCP4EReg  (clk, reset, FlushE, ~StallE, PCPlus4D, PCPlus4E);
  flopenrc #(32) InstrEReg (clk, reset, FlushE, ~StallE, InstrD,   InstrE);
  flopenrc #(32) PredEReg  (clk, reset, FlushE, ~StallE, PredNextD, PredNextE);
  flopenrc #(8+BHT_BITS+RB) BPEReg(clk, reset, FlushE, ~StallE, {ClassD, BPClassD, BPDirD, BPIndexD, RASPtr},
                                                            {ClassE, BPClassE, BPDirE, BPIndexE, RASPtrE});

  // ---- forwarding (Wally controller.sv lines ~469-477) ----
  // 10 = from Memory stage (newest), 01 = from Writeback, 00 = register file value
  logic [1:0]  ForwardAE, ForwardBE;
  logic [4:0]  RdM;
  logic        RegWriteM;
  logic [31:0] IEUResultM;

  function automatic logic [1:0] fwd(input logic [4:0] RsE, RdM_, RdW_, input logic RegWriteM_, RegWriteW_);
    logic MatchM, MatchW;
`ifdef BUG_FWD_X0
    MatchM = RegWriteM_ & (RsE == RdM_);                      // BUG: x0 "matches"
    MatchW = RegWriteW_ & (RsE == RdW_);
`else
    MatchM = RegWriteM_ & (RsE == RdM_) & (RsE != 5'd0);      // x0 is never forwarded
    MatchW = RegWriteW_ & (RsE == RdW_) & (RsE != 5'd0);
`endif
`ifdef BUG_NO_FWD_W
    MatchW = 1'b0;                                            // BUG: no W forwarding path
`endif
`ifdef BUG_FWD_PRIORITY
    if      (MatchW) fwd = 2'b01;                            // BUG: older result wins
    else if (MatchM) fwd = 2'b10;
`else
    if      (MatchM) fwd = 2'b10;                            // newest result wins
    else if (MatchW) fwd = 2'b01;
`endif
    else             fwd = 2'b00;
  endfunction

  assign ForwardAE = fwd(Rs1E, RdM, RdW, RegWriteM, RegWriteW);
  assign ForwardBE = fwd(Rs2E, RdM, RdW, RegWriteM, RegWriteW);

  logic [31:0] ForwardedSrcAE, ForwardedSrcBE, SrcAE, SrcBE, ALUResultE, SumE;
  logic [31:0] AltResultE, IEUResultE, PCNextE;
  logic        BranchTakenE;

  mux3 faemux(R1E, ResultW, IEUResultM, ForwardAE, ForwardedSrcAE);
  mux3 fbemux(R2E, ResultW, IEUResultM, ForwardBE, ForwardedSrcBE);
  comparator cmp(.a(ForwardedSrcAE), .b(ForwardedSrcBE), .Funct3(Funct3E), .BranchTaken(BranchTakenE));
  mux2 srcamux(ForwardedSrcAE, PCE, ALUSrcAE, SrcAE);
  mux2 srcbmux(ForwardedSrcBE, ImmExtE, ALUSrcBE, SrcBE);
  alu  alu(.A(SrcAE), .B(SrcBE), .ALUSelect(ALUSelectE), .SubArith(SubArithE),
           .ALUResult(ALUResultE), .Sum(SumE));
  assign IEUAdrE = {SumE[31:1], SumE[0] & ~JumpE};
  mux2 altmux(ImmExtE, PCPlus4E, JumpE, AltResultE);
  mux2 ieuresmux(ALUResultE, AltResultE, ALUResultSrcE, IEUResultE);

  assign PCSrcE  = JumpE | (BranchE & BranchTakenE);        // redirect fetch, flush wrong path
  logic InstrMisalignedE;                                    // no C extension: targets must be word aligned
  assign InstrMisalignedE = PCSrcE & IEUAdrE[1];
  assign PCNextE = PCSrcE ? IEUAdrE : PCPlus4E;             // for the trace
  // ---- Lab 10: was the instruction behind this one fetched from the right PC? (Wally Table 13.1) ----
  assign PCCorrectE = PCNextE;
`ifdef BUG_BP_CFI_ONLY
  assign BPWrongE = ValidE & (BranchE | JumpE) & (PredNextE != PCCorrectE);   // BUG: aliased non-CFIs never fixed
`elsif BUG_BP_DIR_ONLY
  assign BPWrongE = ValidE & ((PredNextE != PCPlus4E) != PCSrcE);             // BUG: target never checked
`else
  assign BPWrongE = ValidE & (PredNextE != PCCorrectE);
`endif

  // =====================================================================
  // M: Memory
  // =====================================================================
  logic        MemReadM, MemWriteM, IllegalM, ValidM;
  logic        CSRM, EcallM, EbreakM, MretM, WfiM, SfenceVmaM, InstrMisalignedM;
  logic [2:0]  Funct3M;
  logic [31:0] IEUAdrM, WriteDataM, PCM, InstrM, PCNextM, ReadDataM, SrcAM;

  // FlushM clears the instruction entering M (a trap, mret or CSR write in M kills it)
  flopenrc #(10) CtrlMReg(clk, reset, FlushM, ~StallM, {RegWriteE, MemReadE, MemWriteE, IllegalE, ValidE, RdE},
                                   {RegWriteM, MemReadM, MemWriteM, IllegalM, ValidM, RdM});
  flopenrc #(7)  PrivMReg(clk, reset, FlushM, ~StallM, {CSRE, EcallE, EbreakE, MretE, WfiE, SfenceVmaE, InstrMisalignedE},
                                   {CSRM, EcallM, EbreakM, MretM, WfiM, SfenceVmaM, InstrMisalignedM});
  flopenr #(32) SrcAMReg(clk, reset, ~StallM, ForwardedSrcAE, SrcAM);   // rs1 value for CSR writes
  flopenr #(3)  F3MReg  (clk, reset, ~StallM, Funct3E,        Funct3M);
  flopenr #(32) IEURMReg(clk, reset, ~StallM, IEUResultE,     IEUResultM);
  flopenr #(32) AdrMReg (clk, reset, ~StallM, IEUAdrE,        IEUAdrM);
  flopenr #(32) WDMReg  (clk, reset, ~StallM, ForwardedSrcBE, WriteDataM);  // store data is forwarded too
  flopenr #(32) PCMReg  (clk, reset, ~StallM, PCE,            PCM);
  flopenrc #(10+BHT_BITS+RB) BPMReg(clk, reset, FlushM, ~StallM, {BranchE, PCSrcE, ClassE, BPClassE, BPDirE, BPIndexE, RASPtrE},
                                                              {BranchM, PCSrcM, ClassM, BPClassM, BPDirM, BPIndexM, RASPtrM});
  assign KillE   = ValidE & FlushM & ~StallM;      // Execute's instruction is flushed (it already acted in D)
  assign KillM   = ValidM & TrapM;                 // Memory's instruction traps: it never commits
  assign CommitM = ValidM & ~TrapM & ~StallM;      // commits: train the predictor
  bpred #(.TYPE(BP_TYPE), .BHT_BITS(BHT_BITS), .BTB_BITS(BTB_BITS), .RAS_SIZE(RAS_SIZE)) bp(
    .clk, .reset, .PCF, .InstrF, .BPTakenF, .BPPCF, .BPDirF, .BPIndexF, .BPClassF, .RASPtr,
    .ValidD, .CallD, .ReturnD, .ActD, .PCPlus4D(PCPlus4D_bp),
    .BranchD(ValidD & BranchD), .BranchE(ValidE & BranchE), .BranchM_ff(ValidM & BranchM), .PCSrcE, .PCSrcM_ff(PCSrcM),
    .BPDirD_ff(BPDirD), .KillE, .KillM, .RASPtrE, .RASPtrM,
    .CommitM, .PCM, .TargetM(IEUAdrM), .BranchM, .TakenM(PCSrcM), .ClassM, .PredClassM(BPClassM),
    .DirM(BPDirM), .IndexM(BPIndexM));
  flopenr #(32) InsMReg (clk, reset, ~StallM, InstrE,         InstrM);
  flopenr #(32) PCNMReg (clk, reset, ~StallM, PCNextE,        PCNextM);

  // ---- Ch 9: the LSU's AHB interface (Wally lsu.sv / ahbinterface.sv / busfsm.sv) ----
  // A tiny PMA: which addresses live on the bus. Everything else is the in-core DTIM.
  logic        SelBusM, SelCacheM, CaptureEnM, WBufEnM, BusStallM, BusCommittedOnlyM;
  logic [1:0]  BusRWM, CacheRWM;
  logic [31:0] FetchBufferM, WriteBufferM, DTIMReadWordM, ReadDataWordM, CacheReadWordM;
  logic [3:0]  WriteStrbM;
  // ---- Ch 11: MMU. PAdrM is what every memory below sees; the walker can own the LSU ----
  logic [31:0] PAdrM;
  logic        SelHPTW, MMUStallM, BlockAccessM, LSUReadM, LSUWriteM, GatedStallW;
  logic        LoadPageFaultM, StorePageFaultM, LoadAccessFaultM, StoreAccessFaultM, LSMisalignedM;
  logic [1:0]  PrivModeM, MPPM;
  logic        MPRVM;
  logic [31:0] SATPM;
  logic [7:0]  PMPCfgM [4];
  logic [31:0] PMPAdrM [4];
  mmu #(.TLB_ENTRIES(TLB_ENTRIES)) dmmu(.clk, .reset, .VAdrM(IEUAdrM), .ReadM(MemReadM), .WriteM(MemWriteM),
    .MisalignedM(LSMisalignedM), .SfenceVmaM(SfenceVmaM & ValidM & ~TrapM), .PrivMode(PrivModeM), .MPP(MPPM),
    .MPRV(MPRVM), .SATP(SATPM), .PMPCfg(PMPCfgM), .PMPAdr(PMPAdrM), .TrapM(InterruptM),
    .ReadDataWordM, .LSUMemStall(BusStallM | CacheStallM), .PAdrM, .SelHPTW, .MMUStall(MMUStallM),
    .BlockAccess(BlockAccessM), .LoadPageFault(LoadPageFaultM), .StorePageFault(StorePageFaultM),
    .LoadAccessFault(LoadAccessFaultM), .StoreAccessFault(StoreAccessFaultM),
    .EvTLBMiss(), .EvTLBWrite(), .EvWalkFault());
  // the walker reads words; the program's own access waits for a walk and never runs after a fault
  assign LSUReadM  = SelHPTW | (MemReadM  & ~BlockAccessM);
  assign LSUWriteM = ~SelHPTW & MemWriteM & ~BlockAccessM;
  assign GatedStallW = StallW & ~SelHPTW;       // Wally: the LSU must keep moving for the walker

  assign SelCacheM = (PAdrM[31:16] == 16'h9000);                                    // cacheable RAM
  assign SelBusM   = ((PAdrM[31:28] == 4'h1) | (PAdrM[31:28] == 4'h9)) & ~SelCacheM;  // uncached bus
`ifdef BUG_BUS_NO_CANCEL
  assign BusRWM  = {LSUReadM, LSUWriteM} & {2{SelBusM}};             // BUG: trapping access still goes out
`else
  assign BusRWM  = {LSUReadM, LSUWriteM} & {2{SelBusM & ~TrapM}};    // traps cancel in the Adr phase
`endif
  logic [1:0]  BusHTRANS, CacheHTRANS;
  logic [31:0] CacheHADDR, CacheHWDATA;
  logic        CacheHWRITE, CacheStallM, CacheCommittedM, CacheBusyM, FenceIM;
  logic [2:0]  CacheHBURST;
  busfsm bfsm(.clk, .reset, .RW(BusRWM), .HREADY, .Stall(GatedStallW), .HTRANS(BusHTRANS),
              .BusStall(BusStallM), .BusCommitted(BusCommittedOnlyM), .CaptureEn(CaptureEnM), .WBufEn(WBufEnM));

  // ---- Ch 10: data cache for the cacheable region ----
  assign CacheRWM = {LSUReadM, LSUWriteM} & {2{SelCacheM & ~TrapM}};
  assign FenceIM  = ValidM & (InstrM == 32'h0000_100F) & ~TrapM;     // fence.i: flush the D-cache
  dcache #(.WAYS(DC_WAYS), .SETS(DC_SETS), .LINEWORDS(DC_LINEWORDS), .SYNC_READ(DC_SYNC)) dc(
    .clk, .reset, .AdrE(IEUAdrE), .HoldM(MMUStallM | SelHPTW), .Adr(PAdrM), .RW(CacheRWM), .FlushReq(FenceIM), .WriteData(WriteDataAligned), .ByteMask,
    .Stall(GatedStallW), .ReadDataWord(CacheReadWordM), .CacheStall(CacheStallM), .CacheCommitted(CacheCommittedM),
    .CacheBusy(CacheBusyM), .HADDR(CacheHADDR), .HWRITE(CacheHWRITE), .HTRANS(CacheHTRANS), .HBURST(CacheHBURST),
    .HWDATA(CacheHWDATA), .HREADY, .HRDATA,
    .EvAccess(), .EvHit(), .EvWay(), .EvVictimDirty(), .EvWbAdr(), .EvFlushWb(), .EvReRead());
  assign LSUStallM     = BusStallM | CacheStallM | MMUStallM;
  // Wally: CommittedM = bus | cache; a page-table walk in progress is committed too
  assign BusCommittedM = BusCommittedOnlyM | CacheCommittedM | SelHPTW;

  // one AHB port: the cache's bursts or the uncached single transfers
  assign HTRANS = CacheBusyM ? CacheHTRANS : BusHTRANS;
  assign HADDR  = CacheBusyM ? CacheHADDR  : PAdrM;                  // byte address; lane = HADDR[1:0]
  assign HWRITE = CacheBusyM ? CacheHWRITE : LSUWriteM;
  assign HSIZE  = (CacheBusyM | SelHPTW) ? 3'b010 : {1'b0, Funct3M[1:0]};
  assign HBURST = CacheBusyM ? CacheHBURST : 3'b000;
  // write buffer: loaded when the Adr phase is accepted, drives HWDATA in the Data phase
  flopenr #(36) wbuf(clk, reset, WBufEnM,
                     {ByteMask, WriteDataAligned}, {WriteStrbM, WriteBufferM});
  assign HWDATA = CacheBusyM ? CacheHWDATA : WriteBufferM;
  assign HWSTRB = CacheBusyM ? 4'b1111     : WriteStrbM;
  // fetch buffer: HRDATA captured at the end of the Data phase, used in Mem3
  flopenr #(32) fbuf(clk, reset, CaptureEnM, HRDATA, FetchBufferM);

  assign MemWrite = LSUWriteM & ~TrapM & ~SelBusM & ~SelCacheM;   // DTIM write; trapping stores never write

  // ---- privileged unit (Ch 8): CSRs, exceptions, interrupts, mret -- all in M ----
  logic [31:0] CSRReadValM, CSRWriteValM, CauseM, TvalM;
  logic        CSRWriteM;
  logic [11:0] CSRAdrM;
  priv pu(.clk, .reset, .ValidM, .PCM, .InstrM, .CSRM, .EcallM, .EbreakM, .MretM, .WfiM, .SfenceVmaM,
          .IllegalInstrM(IllegalM), .InstrMisalignedM, .InstrMisalignedAdrM(IEUAdrM),
          .MemReadM, .MemWriteM, .Funct3M, .IEUAdrM, .SrcAM,
          .MTimerInt, .MSwInt, .MExtInt, .StallM, .Committed(BusCommittedM),
          .LoadPageFaultM, .StorePageFaultM, .LoadAccessFaultM, .StoreAccessFaultM,
          .PrivMode(PrivModeM), .MPP(MPPM), .MPRV(MPRVM), .SATP(SATPM), .PMPCfg(PMPCfgM), .PMPAdr(PMPAdrM),
          .LoadStoreMisalignedM(LSMisalignedM),
          .TrapM, .InterruptM, .RetM, .CSRWriteFlushM, .PrivPCNextM, .CSRReadValM,
          .CSRWriteM, .CSRAdrM, .CSRWriteValM, .CauseM, .TvalM);
  assign DataAdr  = {PAdrM[31:2], 2'b00};          // physical (the trace records physical store addresses)
  subwordwrite sww(.WriteData(WriteDataM), .Size(Funct3M[1:0]), .Offset(IEUAdrM[1:0]),
                   .WriteDataAligned, .ByteMask);
  assign DTIMReadWordM = ReadDataWord;
  assign ReadDataWordM = SelCacheM ? CacheReadWordM : SelBusM ? FetchBufferM : DTIMReadWordM;
  subwordread  swr(.ReadDataWord(ReadDataWordM), .Funct3(Funct3M), .Offset(IEUAdrM[1:0]), .ReadData(ReadDataM));

  // ---- load-use hazard detection (Wally controller.sv ~line 482) ----
  // The load's data appears at the END of M; the dependent instruction needs it
  // at the START of E. One cycle too late -> stall it in D for one cycle, after
  // which the value is forwarded from W.
`ifdef BUG_NO_LOAD_STALL
  assign LoadStallD = 1'b0;
`elsif PERF_LOADSTALL_X0
  // the book's text version: no RdE != 0 term. Functionally correct, but a load
  // to x0 followed by any instruction that reads x0 stalls for nothing.
  assign LoadStallD = MemReadE & ((Rs1D == RdE) | (Rs2D == RdE));
`else
  assign LoadStallD = MemReadE & (RdE != 5'd0) & ((Rs1D == RdE) | (Rs2D == RdE));
`endif
  // A CSR is read in M, so like a load its value is not ready for the next instruction
  // in E (Wally controller.sv: CSRRdStallD = CSRReadE & MatchDE).
  assign CSRRdStallD = CSRE & (RdE != 5'd0) & ((Rs1D == RdE) | (Rs2D == RdE));

  hazard hzu(.LoadStallD, .CSRRdStallD, .PCSrcE(BPWrongE), .TrapM, .RetM, .CSRWriteFlushM, .LSUStallM,
             .StallF, .StallD, .StallE, .StallM, .StallW, .FlushD, .FlushE, .FlushM, .FlushW);

  // =====================================================================
  // W: Writeback
  // =====================================================================
  logic        MemReadW, MemWriteW, IllegalW, ValidW;
  logic [31:0] IEUResultW, ReadDataW, PCW, InstrW, PCNextW, DataAdrW, WDAlignW;
  logic [3:0]  ByteMaskW;

  logic        CSRW, CSRWriteW;
  logic [11:0] CSRAdrW;
  logic [31:0] CSRReadValW, CSRWriteValW;
  // FlushW = TrapM: the trapping instruction never reaches W, so it changes no state
  flopenrc #(10) CtrlWReg(clk, reset, FlushW, ~StallW, {RegWriteM, MemReadM, MemWriteM, IllegalM, ValidM, RdM},
                                   {RegWriteW, MemReadW, MemWriteW, IllegalW, ValidW, RdW});
  flopenrc #(2)  CSRWReg (clk, reset, FlushW, ~StallW, {CSRM, CSRWriteM}, {CSRW, CSRWriteW});
  flopenr #(12) CSRAWReg(clk, reset, ~StallW, CSRAdrM,      CSRAdrW);
  flopenr #(32) CSRRWReg(clk, reset, ~StallW, CSRReadValM,  CSRReadValW);
  flopenr #(32) CSRVWReg(clk, reset, ~StallW, CSRWriteValM, CSRWriteValW);
  flopenr #(32) IEURWReg(clk, reset, ~StallW, IEUResultM, IEUResultW);
  flopenr #(32) RDWReg  (clk, reset, ~StallW, ReadDataM,  ReadDataW);
  flopenr #(32) PCWReg  (clk, reset, ~StallW, PCM,        PCW);
  flopenr #(32) InsWReg (clk, reset, ~StallW, InstrM,     InstrW);
  flopenr #(32) PCNWReg (clk, reset, ~StallW, PCNextM,    PCNextW);
  flopenr #(32) AdrWReg (clk, reset, ~StallW, DataAdr,    DataAdrW);
  flopenr #(32) WDWReg  (clk, reset, ~StallW, WriteDataAligned, WDAlignW);
  flopenr #(4)  BMWReg  (clk, reset, ~StallW, ByteMask,   ByteMaskW);

  assign ResultW = MemReadW ? ReadDataW : CSRW ? CSRReadValW : IEUResultW;

  // =====================================================================
  // Trace: one record per instruction leaving W (bubbles have ValidW = 0)
  // =====================================================================
  assign TraceValid    = ValidW & ~StallW;     // W holds an instruction during a bus stall: report it once
  assign TracePC       = PCW;
  assign TraceInstr    = InstrW;
  assign TraceRegWrite = RegWriteW & (RdW != 5'd0);
  assign TraceRd       = RdW;
  assign TraceResult   = ResultW;
  assign TraceMemWrite = MemWriteW;
  assign TraceMemAdr   = DataAdrW;
  assign TraceMemData  = WDAlignW;
  assign TraceMemMask  = ByteMaskW;
  assign TracePCNext   = PCNextW;
  assign TraceIllegal  = 1'b0;            // illegal instructions now trap (cause 2) instead
  assign TraceTrap     = TrapM;
  assign TraceTrapPC   = PCM;
  assign TraceCause    = CauseM;
  assign TraceTval     = TvalM;
  assign TraceCSRWrite = CSRWriteW & ValidW;
  assign TraceCSRAdr   = CSRAdrW;
  assign TraceCSRVal   = CSRWriteValW;
endmodule

// ---------------------------------------------------------------------------
// busfsm (book Fig. 9.23, Wally src/ebu/busfsm.sv): sequences one AHB transfer.
//   Adr : drive HTRANS = NONSEQ while a read/write is requested; stall the pipeline.
//         Move on when HREADY says the bus accepted the address.
//   Data: the device reads/writes; keep stalling until HREADY. Committed from here on:
//         interrupts must wait. On a read, capture HRDATA as the phase ends.
//   Mem3: pipeline moves on using the fetch buffer; stay here while something else stalls.
// ---------------------------------------------------------------------------
module busfsm (
  input  logic       clk, reset,
  input  logic [1:0] RW,              // {read, write} requested by the instruction in M
  input  logic       HREADY,
  input  logic       Stall,           // StallW: pipeline still held for another reason
  output logic [1:0] HTRANS,
  output logic       BusStall, BusCommitted, CaptureEn, WBufEn
);
  localparam logic [1:0] ADR = 2'd0, DATA = 2'd1, MEM3 = 2'd2;
  logic [1:0] CurrState, NextState;
  always_ff @(posedge clk)
    if (reset) CurrState <= ADR;
    else       CurrState <= NextState;
  always_comb
    case (CurrState)
      ADR:     NextState = (HREADY & |RW) ? DATA : ADR;
      DATA:    NextState = HREADY ? MEM3 : DATA;
      MEM3:    NextState = Stall ? MEM3 : ADR;
      default: NextState = ADR;
    endcase
  assign HTRANS       = (CurrState == ADR & |RW) ? 2'b10 : 2'b00;   // NONSEQ or IDLE
  assign BusStall     = (CurrState == ADR & |RW) | (CurrState == DATA);
  assign BusCommitted = (CurrState != ADR);
  assign CaptureEn    = (CurrState == DATA) & HREADY & RW[1];
  assign WBufEn       = (CurrState == ADR) & HREADY & RW[0];      // store data for the Data phase
endmodule
