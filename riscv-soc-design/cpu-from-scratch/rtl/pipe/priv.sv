// priv.sv -- Lab 5 (book Ch 8): a machine-mode privileged unit for the pipeline.
//
// Modelled on cvw/src/privileged (privdec.sv, csr*.sv, trap.sv), cut down to M-mode only:
//   * Zicsr: csrrw/csrrs/csrrc and the immediate forms
//   * ecall, ebreak, mret; wfi executes as a nop (legal: wfi is only a hint)
//   * CSRs: mstatus (MIE, MPIE, MPP=11), misa, mie, mip, mtvec (direct or vectored),
//     mscratch, mepc, mcause, mtval, mcycle(h), minstret(h), cycle/time/instret(h),
//     mvendorid/marchid/mimpid/mhartid (read-only 0)
//   * Exceptions: instruction address misaligned, illegal instruction, breakpoint,
//     load/store address misaligned, ecall from M
//   * Interrupts: machine software, timer, external (pins from the testbench "CLINT")
//
// Like Wally, everything happens in the Memory stage and architectural state (CSRs,
// PC) changes on the clock edge that starts Writeback. A trap flushes the instruction
// in M and everything younger, so traps are precise.
//
// Deliberate-bug switches for the verification lab:
//   BUG_MEPC_PLUS4   mepc saves PC+4 instead of the faulting PC (returns past the fault)
//   BUG_INT_BUBBLE   take interrupts even when M holds a bubble (mepc gets a stale PC)
//   BUG_CSR_NOFLUSH  a CSR write does not flush/refetch younger instructions
//   BUG_MRET_NOMIE   mret does not restore MIE from MPIE
//   BUG_NO_COMMIT    (Ch 9) take interrupts in the middle of a bus transfer (ignore Committed)
//
// Lab 8 (book Ch 11) adds what virtual memory needs from the privileged unit:
//   * U-mode: a PrivMode register, mstatus.MPP (00/11) and MPRV, mret returns to MPP,
//     ecall from U (cause 8), mret / sfence.vma / wfi / any CSR access in U are illegal
//     (mcounteren is hardwired to 0, so even cycle/time/instret trap in U).
//   * satp (0x180): MODE (bit 31, Sv32) and PPN; ASID is WARL 0 (ASIDLEN = 0).
//     NOTE: real RISC-V only has satp when S-mode exists. This core is M + U with satp, a
//     teaching cut: U-mode loads/stores are translated as if U ran under an S-mode kernel.
//   * PMP CSRs: pmpcfg0 (4 entries) and pmpaddr0-3; pmpcfg1-3 / pmpaddr4-15 read as 0.
//     L locks an entry (and the pmpaddr below a locked TOR entry) until reset.
//   * Data page faults (13, 15) and access faults (5, 7) from mmu.sv, below misaligned in priority.

// ---------------------------------------------------------------------------
// privdec: decode SYSTEM instructions in Decode (Wally privdec.sv + controller)
// ---------------------------------------------------------------------------
module privdec (
  input  logic [31:0] Instr,
  output logic        System,     // opcode 1110011: the main decoder must not call it illegal
  output logic        CSR,        // csrr*
  output logic        Ecall, Ebreak, Mret, Wfi,
  output logic        SfenceVma,  // sfence.vma rs1, rs2 (Ch 11)
  output logic        Illegal     // reserved SYSTEM encodings
);
  logic [2:0] f3;
  assign f3     = Instr[14:12];
  assign System = (Instr[6:0] == 7'b1110011);
  assign CSR    = System & (f3 != 3'b000) & (f3 != 3'b100);
  // the funct3 = 000 forms need rd = rs1 = 0 and an exact funct12
  logic zeroRegs;
  assign zeroRegs = (Instr[19:15] == 5'd0) & (Instr[11:7] == 5'd0);
  assign Ecall  = System & (f3 == 3'b000) & zeroRegs & (Instr[31:20] == 12'h000);
  assign Ebreak = System & (f3 == 3'b000) & zeroRegs & (Instr[31:20] == 12'h001);
  assign Mret   = System & (f3 == 3'b000) & zeroRegs & (Instr[31:20] == 12'h302);
  assign Wfi    = System & (f3 == 3'b000) & zeroRegs & (Instr[31:20] == 12'h105);
  assign SfenceVma = System & (f3 == 3'b000) & (Instr[11:7] == 5'd0) & (Instr[31:25] == 7'b0001001);
  assign Illegal = System & ~(CSR | Ecall | Ebreak | Mret | Wfi | SfenceVma);
endmodule

// ---------------------------------------------------------------------------
// priv: CSR file + trap unit + next-PC for traps/mret/CSR-write refetch (all in M)
// ---------------------------------------------------------------------------
module priv (
  input  logic        clk, reset,
  // instruction in the Memory stage
  input  logic        ValidM,                     // not a bubble
  input  logic [31:0] PCM, InstrM,
  input  logic        CSRM, EcallM, EbreakM, MretM, WfiM, SfenceVmaM,
  input  logic        IllegalInstrM,              // from the decoders
  input  logic        InstrMisalignedM,           // taken branch/jump to a non-word address
  input  logic [31:0] InstrMisalignedAdrM,        // ... that target
  input  logic        MemReadM, MemWriteM,
  input  logic [2:0]  Funct3M,
  input  logic [31:0] IEUAdrM,                    // load/store address
  input  logic [31:0] SrcAM,                      // rs1 value (forwarded) for CSR writes
  // interrupt pins (from the testbench's CLINT-like block)
  input  logic        MTimerInt, MSwInt, MExtInt,
  // Ch 9: the pipeline is stalled by the bus; a bus transfer has passed its Adr phase
  input  logic        StallM, Committed,
  // Ch 11: faults from the MMU (tval = the virtual address)
  input  logic        LoadPageFaultM, StorePageFaultM, LoadAccessFaultM, StoreAccessFaultM,
  output logic [1:0]  PrivMode, MPP,
  output logic        MPRV,
  output logic [31:0] SATP,
  output logic [7:0]  PMPCfg [4],
  output logic [31:0] PMPAdr [4],
  output logic        LoadStoreMisalignedM,
  // outputs
  output logic        TrapM, InterruptM, RetM, CSRWriteFlushM,
  output logic [31:0] PrivPCNextM,                // where to fetch next when any of the above
  output logic [31:0] CSRReadValM,
  output logic        CSRWriteM,                  // a CSR is actually written (for the trace)
  output logic [11:0] CSRAdrM,
  output logic [31:0] CSRWriteValM,
  output logic [31:0] CauseM, TvalM               // for the trace
);
  // ---------------- CSR addresses ----------------
  localparam MSTATUS = 12'h300, MISA = 12'h301, MIE = 12'h304, MTVEC = 12'h305,
             MSCRATCH = 12'h340, MEPC = 12'h341, MCAUSE = 12'h342, MTVAL = 12'h343, MIP = 12'h344,
             MCYCLE = 12'hB00, MINSTRET = 12'hB02, MCYCLEH = 12'hB80, MINSTRETH = 12'hB82,
             CYCLE = 12'hC00, TIME = 12'hC01, INSTRET = 12'hC02,
             CYCLEH = 12'hC80, TIMEH = 12'hC81, INSTRETH = 12'hC82,
             MVENDORID = 12'hF11, MARCHID = 12'hF12, MIMPID = 12'hF13, MHARTID = 12'hF14,
             SATP_A = 12'h180, MCOUNTEREN = 12'h306, PMPCFG0 = 12'h3A0, PMPADDR0 = 12'h3B0;
  localparam logic [1:0] U_MODE = 2'b00, M_MODE = 2'b11;

  // ---------------- architectural CSR state ----------------
  logic        MIE_bit, MPIE_bit;                 // mstatus.MIE (bit 3), mstatus.MPIE (bit 7)
  logic [31:0] MIE_REG, MTVEC_REG, MSCRATCH_REG, MEPC_REG, MCAUSE_REG, MTVAL_REG;
  logic [63:0] MCYCLE_REG, MINSTRET_REG;
  logic [31:0] MSTATUS_REG, MIP_REG;
  logic        MPRV_bit;
  logic [1:0]  MPP_REG, PrivModeReg;
  logic [31:0] SATP_REG;
  assign MSTATUS_REG = {14'b0, MPRV_bit, 4'b0, MPP_REG, 3'b0, MPIE_bit, 3'b0, MIE_bit, 3'b0};
  assign PrivMode = PrivModeReg;
  assign MPP      = MPP_REG;
  assign MPRV     = MPRV_bit;
  assign SATP     = SATP_REG;
  assign MIP_REG     = {20'b0, MExtInt, 3'b0, MTimerInt, 3'b0, MSwInt, 3'b0};

  // ---------------- CSR read (combinational, in M) ----------------
  logic        CSRLegalM, CSRReadOnly;
  assign CSRAdrM     = InstrM[31:20];
  assign CSRReadOnly = (CSRAdrM[11:10] == 2'b11);
  always_comb begin
    CSRLegalM = 1'b1;
    case (CSRAdrM)
      MSTATUS:   CSRReadValM = MSTATUS_REG;
      MISA:      CSRReadValM = 32'h4010_0100;     // MXL = 32, I, U
      MCOUNTEREN: CSRReadValM = 32'b0;            // U-mode may not read the counters
      SATP_A:    CSRReadValM = SATP_REG;
      PMPCFG0:   CSRReadValM = {PMPCfg[3], PMPCfg[2], PMPCfg[1], PMPCfg[0]};
      PMPADDR0, PMPADDR0 + 12'd1, PMPADDR0 + 12'd2, PMPADDR0 + 12'd3: CSRReadValM = PMPAdr[CSRAdrM[1:0]];
      PMPCFG0 + 12'd1, PMPCFG0 + 12'd2, PMPCFG0 + 12'd3: CSRReadValM = 32'b0;   // entries 4-15 absent
      12'h3B4, 12'h3B5, 12'h3B6, 12'h3B7, 12'h3B8, 12'h3B9, 12'h3BA, 12'h3BB,
      12'h3BC, 12'h3BD, 12'h3BE, 12'h3BF: CSRReadValM = 32'b0;
      MIE:       CSRReadValM = MIE_REG;
      MTVEC:     CSRReadValM = MTVEC_REG;
      MSCRATCH:  CSRReadValM = MSCRATCH_REG;
      MEPC:      CSRReadValM = MEPC_REG;
      MCAUSE:    CSRReadValM = MCAUSE_REG;
      MTVAL:     CSRReadValM = MTVAL_REG;
      MIP:       CSRReadValM = MIP_REG;
      MCYCLE, CYCLE, TIME:          CSRReadValM = MCYCLE_REG[31:0];   // time = cycles here
      MCYCLEH, CYCLEH, TIMEH:       CSRReadValM = MCYCLE_REG[63:32];
      MINSTRET, INSTRET:            CSRReadValM = MINSTRET_REG[31:0];
      MINSTRETH, INSTRETH:          CSRReadValM = MINSTRET_REG[63:32];
      MVENDORID, MARCHID, MIMPID, MHARTID: CSRReadValM = 32'b0;
      default: begin CSRReadValM = 32'b0; CSRLegalM = 1'b0; end
    endcase
  end

  // ---------------- CSR write value ----------------
  // csrrw: write src. csrrs/csrrc: set/clear bits; they do NOT write when rs1 (or zimm) = 0,
  // so reading a read-only CSR with csrr (= csrrs rd, csr, x0) is legal.
  logic [31:0] CSRSrcM;
  logic        CSRWantsWriteM;
  assign CSRSrcM = Funct3M[2] ? {27'b0, InstrM[19:15]} : SrcAM;
  always_comb
    case (Funct3M[1:0])
      2'b01:   CSRWriteValM = CSRSrcM;                    // csrrw(i)
      2'b10:   CSRWriteValM = CSRReadValM | CSRSrcM;      // csrrs(i)
      default: CSRWriteValM = CSRReadValM & ~CSRSrcM;     // csrrc(i)
    endcase
  assign CSRWantsWriteM = CSRM & ((Funct3M[1:0] == 2'b01) | (InstrM[19:15] != 5'd0));

  // ---------------- exceptions (priority order, privileged spec Table 3.7) ----------------
  logic IllegalCSRM, IllegalM, LoadMisalignedM, StoreMisalignedM, ExceptionM;
  // U-mode: every CSR here is M- or S-level, or a counter gated off by mcounteren = 0
  logic UModeM, IllegalPrivM;
  assign UModeM           = (PrivModeReg == U_MODE);
  assign IllegalCSRM      = CSRM & (~CSRLegalM | (CSRWantsWriteM & CSRReadOnly) | UModeM);
  assign IllegalPrivM     = UModeM & (MretM | SfenceVmaM | WfiM);
  assign IllegalM         = IllegalInstrM | IllegalCSRM | IllegalPrivM;
  assign LoadMisalignedM  = MemReadM  & ((Funct3M[1:0] == 2'b01 & IEUAdrM[0]) | (Funct3M[1:0] == 2'b10 & IEUAdrM[1:0] != 2'b00));
  assign StoreMisalignedM = MemWriteM & ((Funct3M[1:0] == 2'b01 & IEUAdrM[0]) | (Funct3M[1:0] == 2'b10 & IEUAdrM[1:0] != 2'b00));
  assign LoadStoreMisalignedM = LoadMisalignedM | StoreMisalignedM;
  assign ExceptionM = ValidM & (InstrMisalignedM | IllegalM | EcallM | EbreakM | LoadMisalignedM | StoreMisalignedM |
                                LoadPageFaultM | StorePageFaultM | LoadAccessFaultM | StoreAccessFaultM);

  // ---------------- interrupts (Wally trap.sv, M-mode only) ----------------
  // In M-mode, interrupts need mstatus.MIE; each source also needs its mie bit.
  // Interrupts are taken only on a real instruction in M, so mepc is a real PC.
  logic [11:0] ValidIntsM;
  assign ValidIntsM = MIP_REG[11:0] & MIE_REG[11:0] & {12{MIE_bit}};
  // Ch 9 (book Fig. 9.35): once a bus transfer is past its Adr phase it must finish, so
  // interrupts wait (Committed). Otherwise a load from a device with read side effects
  // (a UART receive buffer) would be flushed after the device had already acted, and
  // re-executed after mret.
`ifdef BUG_INT_BUBBLE
  assign InterruptM = |ValidIntsM & ~Committed;        // BUG: also on bubbles
`elsif BUG_NO_COMMIT
  assign InterruptM = (|ValidIntsM) & ValidM;          // BUG: ignores Committed
`else
  assign InterruptM = (|ValidIntsM) & ValidM & ~Committed;
`endif
  assign TrapM = ExceptionM | InterruptM;

  always_comb begin
    TvalM = 32'b0;
    if      (ValidIntsM[11]) CauseM = 32'h8000_000B;  // machine external
    else if (ValidIntsM[3])  CauseM = 32'h8000_0003;  // machine software
    else if (ValidIntsM[7])  CauseM = 32'h8000_0007;  // machine timer
    else if (InstrMisalignedM) begin CauseM = 32'd0; TvalM = InstrMisalignedAdrM; end
    else if (IllegalM)         begin CauseM = 32'd2; TvalM = InstrM; end
    else if (EbreakM)          begin CauseM = 32'd3; TvalM = PCM; end
    else if (EcallM)                 CauseM = UModeM ? 32'd8 : 32'd11;   // ecall from U / M
    else if (StoreMisalignedM) begin CauseM = 32'd6; TvalM = IEUAdrM; end
    else if (LoadMisalignedM)  begin CauseM = 32'd4; TvalM = IEUAdrM; end
    else if (StorePageFaultM)  begin CauseM = 32'd15; TvalM = IEUAdrM; end   // Ch 11, spec Table 3.7
    else if (LoadPageFaultM)   begin CauseM = 32'd13; TvalM = IEUAdrM; end
    else if (StoreAccessFaultM) begin CauseM = 32'd7; TvalM = IEUAdrM; end
    else if (LoadAccessFaultM) begin CauseM = 32'd5; TvalM = IEUAdrM; end
    else                             CauseM = 32'd0;
  end

  // ---------------- what the pipeline does next ----------------
  assign RetM      = ValidM & MretM & ~TrapM;
  assign CSRWriteM = ValidM & CSRWantsWriteM & ~TrapM;
`ifdef BUG_CSR_NOFLUSH
  assign CSRWriteFlushM = 1'b0;
`else
  assign CSRWriteFlushM = CSRWriteM;                  // refetch younger instructions: they may
`endif                                                // depend on the new CSR value (e.g. MIE)
  logic [31:0] TrapVectorM;
  assign TrapVectorM = (MTVEC_REG[0] & InterruptM) ? {MTVEC_REG[31:2], 2'b00} + {CauseM[29:0], 2'b00}
                                                   : {MTVEC_REG[31:2], 2'b00};
  assign PrivPCNextM = TrapM ? TrapVectorM : RetM ? MEPC_REG : PCM + 32'd4;

  // ---------------- state updates at the M->W clock edge ----------------
  logic RetireM;
  assign RetireM = ValidM & ~TrapM;                   // this instruction will reach Writeback
  always_ff @(posedge clk)
    if (reset) begin
      MIE_bit <= 1'b0; MPIE_bit <= 1'b0;
      MIE_REG <= '0; MTVEC_REG <= '0; MSCRATCH_REG <= '0; MEPC_REG <= '0;
      MCAUSE_REG <= '0; MTVAL_REG <= '0; MCYCLE_REG <= '0; MINSTRET_REG <= '0;
      PrivModeReg <= M_MODE; MPP_REG <= M_MODE; MPRV_bit <= 1'b0; SATP_REG <= '0;
      for (int i = 0; i < 4; i++) begin PMPCfg[i] <= '0; PMPAdr[i] <= '0; end
    end else begin
      MCYCLE_REG <= MCYCLE_REG + 64'd1;
      if (RetireM & ~StallM) MINSTRET_REG <= MINSTRET_REG + 64'd1;   // count once, not per stall cycle
      if (TrapM) begin
`ifdef BUG_MEPC_PLUS4
        MEPC_REG   <= PCM + 32'd4;                    // BUG
`else
        MEPC_REG   <= PCM;
`endif
        MCAUSE_REG <= CauseM;
        MTVAL_REG  <= TvalM;
        MPIE_bit   <= MIE_bit;
        MIE_bit    <= 1'b0;
        MPP_REG    <= PrivModeReg;                    // traps go to M and remember where from
        PrivModeReg <= M_MODE;
      end else if (StallM) begin
        // instruction held in M by the bus: architectural state waits too
      end else if (RetM) begin
`ifndef BUG_MRET_NOMIE
        MIE_bit  <= MPIE_bit;
`endif
        MPIE_bit <= 1'b1;
        PrivModeReg <= MPP_REG;                       // return to the mode in MPP
        MPP_REG     <= U_MODE;                        // least-privileged supported mode
        if (MPP_REG != M_MODE) MPRV_bit <= 1'b0;      // leaving M clears MPRV
      end else if (CSRWriteM) begin
        case (CSRAdrM)
          MSTATUS:  begin MIE_bit <= CSRWriteValM[3]; MPIE_bit <= CSRWriteValM[7];
                          MPRV_bit <= CSRWriteValM[17];
                          MPP_REG  <= (CSRWriteValM[12:11] == M_MODE) ? M_MODE : U_MODE;  // WARL: no S, H
                    end
          SATP_A:   SATP_REG     <= {CSRWriteValM[31], 9'b0, CSRWriteValM[21:0]};   // ASID WARL 0
          PMPCFG0:  for (int i = 0; i < 4; i++)
                      if (!PMPCfg[i][7]) begin                         // locked entries ignore writes
                        PMPCfg[i] <= CSRWriteValM[8*i +: 8] & 8'h9F;  // bits 6:5 reserved
                        if (!CSRWriteValM[8*i]) PMPCfg[i][1] <= 1'b0; // R=0,W=1 reserved: drop W
                      end
          PMPADDR0, PMPADDR0 + 12'd1, PMPADDR0 + 12'd2, PMPADDR0 + 12'd3:
                    if (!PMPCfg[CSRAdrM[1:0]][7] &&
                        !(CSRAdrM[1:0] != 2'd3 && PMPCfg[CSRAdrM[1:0] + 2'd1][7] &&
                          PMPCfg[CSRAdrM[1:0] + 2'd1][4:3] == 2'b01))      // base of a locked TOR
                      PMPAdr[CSRAdrM[1:0]] <= CSRWriteValM;
          MIE:      MIE_REG      <= CSRWriteValM & 32'h0000_0888;   // only MEIE, MTIE, MSIE exist
          MTVEC:    MTVEC_REG    <= {CSRWriteValM[31:2], 1'b0, CSRWriteValM[0]};  // mode 0 or 1
          MSCRATCH: MSCRATCH_REG <= CSRWriteValM;
          MEPC:     MEPC_REG     <= {CSRWriteValM[31:2], 2'b00};   // IALIGN = 32
          MCAUSE:   MCAUSE_REG   <= CSRWriteValM;
          MTVAL:    MTVAL_REG    <= CSRWriteValM;
          MCYCLE:   MCYCLE_REG[31:0]    <= CSRWriteValM;
          MCYCLEH:  MCYCLE_REG[63:32]   <= CSRWriteValM;
          MINSTRET: MINSTRET_REG[31:0]  <= CSRWriteValM;
          MINSTRETH: MINSTRET_REG[63:32] <= CSRWriteValM;
          default: ;                                   // misa, mip: writes ignored (WARL)
        endcase
      end
    end
endmodule
