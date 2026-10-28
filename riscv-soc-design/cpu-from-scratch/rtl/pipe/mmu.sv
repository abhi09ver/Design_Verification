// mmu.sv -- Lab 8 (book Ch 11): a data MMU for the pipeline, modelled on Wally's src/mmu
// (mmu.sv, tlb/*.sv, hptw.sv, pmpchecker.sv), cut down to Sv32 on RV32:
//
//   * DTLB: fully associative, TLB_ENTRIES entries, 4 KiB pages and 4 MiB megapages, "not
//     recently used" replacement (Wally tlblru), flushed by sfence.vma. No ASIDs (satp.ASID reads 0).
//   * HPTW: walks the 2-level Sv32 page table THROUGH THE LSU (DTIM, D-cache or bus), like
//     Wally; the pipeline stalls, the LSU does not (GatedStall), interrupts wait (Committed).
//   * Faults (tlbcontrol): V=0, W without R, leaf at the wrong level, misaligned megapage,
//     U-bit vs privilege, R/W permission, A=0, D=0 on a store (Svade: software manages A/D).
//   * PMP: 4 entries (pmpcfg0, pmpaddr0-3), OFF/TOR/NA4/NAPOT, lowest-numbered match wins,
//     L locks an entry and applies it to M-mode. Checked on every data access AND on the
//     walker's PTE reads. No match: M allowed, U denied.
//
// Simplification vs Wally: instruction fetch is NOT translated (no ITLB/IMMU; the IFU reads
// the IROM physically), so U-mode code runs from physical addresses. The ITLB is the same design.
//
// Deliberate-bug switches:
//   BUG_TLB_NO_FLUSH     sfence.vma does not invalidate the TLB
//   BUG_TLB_USER_IGNORED the U bit is not checked (U-mode can use supervisor/M pages)
//   BUG_MEGA_OFFSET      megapage translation takes PA[21:12] from the PPN instead of the VA
//   BUG_NO_DIRTY_FAULT   a store to a page with D=0 does not fault
//   BUG_PMP_LAST_WINS    PMP picks the highest-numbered matching entry instead of the lowest
//   BUG_WALK_NO_PMP      the walker's PTE reads are not PMP-checked
//   BUG_TLB_VICTIM0      replacement always picks entry 0 (a 1-entry TLB: slower, never wrong)

module mmu #(parameter int TLB_ENTRIES = 4) (
  input  logic        clk, reset,
  // the access in the Memory stage
  input  logic [31:0] VAdrM,
  input  logic        ReadM, WriteM,          // load / store in M (not trapping for other reasons)
  input  logic        MisalignedM,            // an older exception wins: no translation fault
  input  logic        SfenceVmaM,
  // privilege and CSRs
  input  logic [1:0]  PrivMode, MPP,
  input  logic        MPRV,
  input  logic [31:0] SATP,
  input  logic [7:0]  PMPCfg [4],
  input  logic [31:0] PMPAdr [4],
  input  logic        TrapM,                  // anything traps this cycle: do not start a walk
  // LSU side
  input  logic [31:0] ReadDataWordM,          // what the LSU returns (for the walker)
  input  logic        LSUMemStall,            // cache / bus still busy with the current read
  output logic [31:0] PAdrM,                  // physical address the LSU uses
  output logic        SelHPTW,                // the walker owns the LSU
  output logic        MMUStall,               // TLB miss being walked
  output logic        BlockAccess,            // the program's own access must not happen yet
  // faults for the trap unit (all with tval = VAdrM)
  output logic        LoadPageFault, StorePageFault, LoadAccessFault, StoreAccessFault,
  // for the testbench
  output logic        EvTLBMiss, EvTLBWrite, EvWalkFault
);
  localparam logic [1:0] U_MODE = 2'b00, M_MODE = 2'b11;

  // ---------------- effective privilege and translation enable (tlbcontrol) ----------------
  logic [1:0] EffMode;
  logic       Translate, Access;
  assign EffMode   = MPRV ? MPP : PrivMode;                   // mstatus.MPRV: loads/stores as MPP
  assign Translate = SATP[31] & (EffMode != M_MODE);          // Sv32 only below M
  assign Access    = (ReadM | WriteM) & ~MisalignedM;

  // ---------------- TLB: CAM + RAM, flops ----------------
  logic        TV   [TLB_ENTRIES];                            // valid
  logic [19:0] TVPN [TLB_ENTRIES];
  logic        TMega[TLB_ENTRIES];
  logic [21:0] TPPN [TLB_ENTRIES];
  logic [7:0]  TFlags[TLB_ENTRIES];                           // D A G U X W R V
  logic [TLB_ENTRIES-1:0] Match, RU;                           // matches, recently-used bits
  always_comb
    for (int i = 0; i < TLB_ENTRIES; i++)
      Match[i] = TV[i] & (TVPN[i][19:10] == VAdrM[31:22]) & (TMega[i] | (TVPN[i][9:0] == VAdrM[21:12]));
  logic        CAMHit;
  logic [21:0] HitPPN;
  logic [7:0]  HitFlags;
  logic        HitMega;
  always_comb begin                                           // distributed AND-OR read mux
    HitPPN = '0; HitFlags = '0; HitMega = 1'b0;
    for (int i = 0; i < TLB_ENTRIES; i++) if (Match[i]) begin
      HitPPN |= TPPN[i]; HitFlags |= TFlags[i]; HitMega |= TMega[i];
    end
  end
  assign CAMHit = |Match;

  // permission checks on a hit (Svade: A/D are the OS's job, so A=0 / D=0 fault)
  logic PermFault, R, W, U, A, D;
  assign {D, A, U, W, R} = {HitFlags[7], HitFlags[6], HitFlags[4], HitFlags[2], HitFlags[1]};
  always_comb begin
    PermFault = 1'b0;
`ifndef BUG_TLB_USER_IGNORED
    if (EffMode == U_MODE && !U) PermFault = 1'b1;            // (no S-mode: SUM is not needed)
`endif
    if (ReadM  && !R) PermFault = 1'b1;
    if (WriteM && !W) PermFault = 1'b1;
    if (!A) PermFault = 1'b1;
`ifndef BUG_NO_DIRTY_FAULT
    if (WriteM && !D) PermFault = 1'b1;
`endif
  end

  // ---------------- tlbmixer: physical address ----------------
  logic [33:0] TLBPAdr;
`ifdef BUG_MEGA_OFFSET
  assign TLBPAdr = {HitPPN, VAdrM[11:0]};                     // BUG: ignores the megapage case
`else
  assign TLBPAdr = HitMega ? {HitPPN[21:10], VAdrM[21:0]} : {HitPPN, VAdrM[11:0]};
`endif

  // ---------------- HPTW (book Fig. 11.26, Sv32: L1 then L0) ----------------
  typedef enum logic [1:0] {IDLE, L1, L0, DONE} walk_t;
  walk_t       WState;
  logic [33:0] HPTWAdr;
  logic [31:0] PTE;
  logic        StartWalk, PTEValidNow, WalkFault, WalkPMPFault, LeafPTE, BadPTE;
  logic        TLBWrite;
  logic [21:0] NextBase;
  assign PTE         = ReadDataWordM;
  assign PTEValidNow = (WState == L1 | WState == L0) & ~LSUMemStall;   // the LSU delivered the PTE
  assign LeafPTE     = PTE[1] | PTE[3];                                 // R or X
  // malformed PTEs (RISC-V privileged spec 4.3.2): V=0, W without R; non-leaf with D/A/U set;
  // a pointer at level 0; a megapage whose PPN[9:0] is not zero
  always_comb begin
    BadPTE = ~PTE[0] | (PTE[2] & ~PTE[1]);
    if (!LeafPTE && (PTE[7] | PTE[6] | PTE[4])) BadPTE = 1'b1;
    if (WState == L0 && !LeafPTE) BadPTE = 1'b1;
    if (WState == L1 && LeafPTE && PTE[19:10] != 10'b0) BadPTE = 1'b1;
  end
  assign StartWalk = (WState == IDLE) & Translate & Access & ~CAMHit & ~TrapM;
  assign HPTWAdr   = (WState == L1) ? {SATP[21:0], VAdrM[31:22], 2'b00} : {NextBase, VAdrM[21:12], 2'b00};
  assign SelHPTW   = (WState == L1) | (WState == L0);

  always_ff @(posedge clk)
    if (reset) begin WState <= IDLE; NextBase <= '0; end
    else case (WState)
      IDLE: if (StartWalk) WState <= L1;
      L1:   if (WalkPMPFault)            WState <= DONE;
            else if (PTEValidNow) begin
              if (BadPTE | LeafPTE)       WState <= DONE;       // megapage leaf or fault: done
              else begin NextBase <= PTE[31:10]; WState <= L0; end
            end
      L0:   if (WalkPMPFault | PTEValidNow) WState <= DONE;
      DONE: WState <= IDLE;                                     // the access replays (hits or faults)
    endcase

  // remember a walk fault for the replay cycle; write good leaves into the TLB
  logic WalkFaultR, WalkAccFaultR;
  assign TLBWrite  = PTEValidNow & ~WalkPMPFault & ~BadPTE & LeafPTE;
  assign WalkFault = PTEValidNow & ~WalkPMPFault & BadPTE;
  always_ff @(posedge clk)
    if (reset | (WState == IDLE)) begin WalkFaultR <= 1'b0; WalkAccFaultR <= 1'b0; end
    else begin
      if (WalkFault)    WalkFaultR    <= 1'b1;
      if (WalkPMPFault) WalkAccFaultR <= 1'b1;
    end

  // tlblru: first entry not recently used; clear all RU bits when all are used
  logic [TLB_ENTRIES-1:0] Victim, RUNext, RUSet;
  logic                   HitUse;
  always_comb begin
    Victim = '0;
    for (int i = TLB_ENTRIES - 1; i >= 0; i--) if (!RU[i]) begin Victim = '0; Victim[i] = 1'b1; end
    if (Victim == '0) Victim[0] = 1'b1;
`ifdef BUG_TLB_VICTIM0
    Victim = '0; Victim[0] = 1'b1;                            // BUG: always replaces entry 0
`endif
  end
  assign HitUse = Translate & Access & CAMHit & ~SelHPTW;
  assign RUSet  = (HitUse ? Match : '0) | (TLBWrite ? Victim : '0);
  assign RUNext = ((&(RU | RUSet)) ? '0 : RU) | RUSet;          // all used: start over with this one
  always_ff @(posedge clk)
    if (reset) begin
      for (int i = 0; i < TLB_ENTRIES; i++) TV[i] <= 1'b0;
      RU <= '0;
    end else begin
      // (sfence.vma also clears the RU bits so replacement restarts from entry 0)
`ifndef BUG_TLB_NO_FLUSH
      if (SfenceVmaM) for (int i = 0; i < TLB_ENTRIES; i++) TV[i] <= 1'b0;
`endif
      if (TLBWrite) for (int i = 0; i < TLB_ENTRIES; i++) if (Victim[i]) begin
        TV[i] <= 1'b1; TVPN[i] <= VAdrM[31:12]; TMega[i] <= (WState == L1);
        TPPN[i] <= PTE[31:10]; TFlags[i] <= PTE[7:0];
      end
      RU <= SfenceVmaM ? '0 : RUNext;       // recently-used bits (Wally tlblru)
    end

  // ---------------- physical address seen by the LSU ----------------
  logic [33:0] PAdr34;
  assign PAdr34 = SelHPTW ? HPTWAdr : Translate ? TLBPAdr : {2'b00, VAdrM};
  assign PAdrM  = PAdr34[31:0];               // our bus is 32-bit; PA[33:32] != 0 is an access fault

  // ---------------- PMP checker (book Fig. 11.18) ----------------
  function automatic logic [3:0] pmp_check(input logic [33:0] pa, input logic [1:0] mode,
                                           input logic [7:0] cfg [4], input logic [31:0] adr [4]);
    // returns {matched, R, W, enforce}; X is irrelevant for data accesses
    logic [31:0] pw;  logic hit [4];  int first;  logic [31:0] m;
    pw = pa[33:2];
    for (int i = 0; i < 4; i++) begin
      case (cfg[i][4:3])
        2'b01:   hit[i] = ((i == 0) ? 1'b1 : (pw >= adr[i - 1])) & (pw < adr[i]);   // TOR
        2'b10:   hit[i] = (pw == adr[i]);                                           // NA4
        2'b11:   begin m = adr[i] ^ (adr[i] + 32'd1); hit[i] = ((pw & ~m) == (adr[i] & ~m)); end  // NAPOT
        default: hit[i] = 1'b0;                                                     // OFF
      endcase
    end
    first = -1;
`ifdef BUG_PMP_LAST_WINS
    for (int i = 0; i < 4; i++) if (hit[i]) first = i;                 // BUG: last match wins
`else
    for (int i = 3; i >= 0; i--) if (hit[i]) first = i;                // lowest-numbered match wins
`endif
    if (first < 0) return {1'b0, 1'b0, 1'b0, (mode != M_MODE)};        // no match: deny below M
    return {1'b1, cfg[first][0], cfg[first][1], (mode != M_MODE) | cfg[first][7]};
  endfunction

  logic [3:0] PMPRes;
  logic       PMPDeny, OutOfRange;
  logic [1:0] CheckMode;
  // the walker's implicit reads are checked like supervisor accesses (not M), i.e. enforced
  assign CheckMode  = SelHPTW ? U_MODE : EffMode;
  assign PMPRes     = pmp_check(PAdr34, CheckMode, PMPCfg, PMPAdr);
  assign OutOfRange = (PAdr34[33:32] != 2'b00);
  always_comb begin
    PMPDeny = 1'b0;
    if (PMPRes[0]) begin                                               // enforced
      if (!PMPRes[3]) PMPDeny = 1'b1;                                  // no match below M
      else if (SelHPTW ? !PMPRes[2] : ((ReadM & !PMPRes[2]) | (WriteM & !PMPRes[1]))) PMPDeny = 1'b1;
    end
    if (OutOfRange) PMPDeny = 1'b1;
  end
`ifdef BUG_WALK_NO_PMP
  assign WalkPMPFault = 1'b0;
`else
  assign WalkPMPFault = SelHPTW & PMPDeny;
`endif

  // ---------------- what the pipeline sees ----------------
  logic TLBPageFault, ProgAccessFault;
  assign TLBPageFault    = Translate & Access & CAMHit & PermFault & ~SelHPTW;      // IDLE or replay (DONE)
  assign ProgAccessFault = Access & ~SelHPTW & (~Translate | CAMHit) & PMPDeny;
  // a walk that ended in a fault reports it on the replay cycle (DONE)
  logic PF, AF;
  assign PF = TLBPageFault | ((WState == DONE) & WalkFaultR);
  assign AF = (ProgAccessFault & ~TLBPageFault) | ((WState == DONE) & WalkAccFaultR);
  assign LoadPageFault    = PF & ReadM;
  assign StorePageFault   = PF & WriteM;
  assign LoadAccessFault  = AF & ReadM;
  assign StoreAccessFault = AF & WriteM;

  assign MMUStall    = StartWalk | (WState != IDLE & WState != DONE);
  // the program's own access waits during a walk, and never happens after a fault
  assign BlockAccess = (Translate & Access & ~CAMHit) | SelHPTW;

  assign EvTLBMiss   = StartWalk;
  assign EvTLBWrite  = TLBWrite;
  assign EvWalkFault = WalkFault | WalkPMPFault;
endmodule
