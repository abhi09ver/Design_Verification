// dcache.sv -- Lab 7 (book Ch 10): a write-back, write-allocate, N-way set-associative data
// cache with tree pseudo-LRU, modelled on Wally's src/cache (cache.sv, cacheway.sv,
// cachefsm.sv, cacheLRU.sv), sitting between the LSU and the AHB bus.
//
//   Cacheable (PMA): 0x9000_0000 - 0x9000_FFFF   (the bus RAM; 0x9100_xxxx is the SAME RAM, uncached)
//   Line: LINEWORDS 32-bit words. Sets: SETS. Ways: WAYS (1 = direct-mapped). Defaults: 2 x 8 x 16 B = 256 B,
//   deliberately tiny so ordinary tests evict lines.
//
//   Address (within the 64 KB region):  [15 : 2+OB+SB] tag | [2+OB+SB-1 : 2+OB] set | [2+OB-1 : 2] word | [1:0] byte
//
// Simplification vs Wally: the arrays are read combinationally (hit in the same cycle, like our
// DTIM), so there are no Address/Data stages and no store->load structural hazard. Everything
// else follows the book: FSM states Access, Writeback, Fetch, WriteLine (early return from the
// fetch buffer), Flush/FlushWriteback for fence.i; first-invalid-way then pLRU victim; bursts
// over AHB (NONSEQ + SEQ, pipelined); CacheStall stalls the whole pipeline; CacheCommitted
// holds off interrupts while the FSM is busy.
//
// Deliberate-bug switches:
//   BUG_NO_WRITEBACK      evicting a dirty line skips the writeback (the store is lost)
//   BUG_DIRTY_ON_HIT      a store HIT forgets to set the dirty bit
//   BUG_NO_MERGE          a store MISS installs the fetched line without merging the store
//   BUG_LRU_STUCK         the pLRU bits are never updated (correct but slow)
//   BUG_TAG_SHORT         the tag compare ignores the tag's most significant bit
//   BUG_FLUSH_SKIP_LAST   fence.i flush stops before the last set
//
// Lab 9 (book Ch 12): with SYNC_READ = 1 (default) the data array behaves like Wally's SRAM: a
// synchronous read. The set is presented one cycle early, in Execute, from IEUAdrE (a VIRTUAL
// address), and the line appears in DataOut at the start of Memory, where the tag compare uses
// the PHYSICAL address. That only works because the set bits sit inside the 4 KiB page offset
// (VIPT; checked below). DataOut is stale whenever something else used the port or the
// instruction in M is not the one whose set was read: a store hit or line fill wrote the array,
// the pipeline was stalled, a page walk read PTEs, a miss was serviced. SelAdr then reads M's set
// instead, and a load that finds DataOut not valid for its set spends one cycle re-reading
// (ReRead). Wally avoids most re-reads with explicit rules (StoreStallD in Decode, the HPTW's
// separate Adr and Rd states, SelAdr in cachefsm); this cache checks the read instead.
//   BUG_NO_REREAD         use DataOut without checking it is valid for this set
//   BUG_REREAD_SET_ONLY   check the set, but not whether the array was written since the read
//   BUG_FILL_NO_INVAL     a line fill (WriteLine) does not invalidate DataOut; store hits do
//   BUG_SELADR_ON_HIT     SelAdr uses Req instead of Req & ~Hit: every access re-reads M's set, so the
//                         next load always re-reads. Never wrong, just slower

module dcache #(parameter int WAYS = 2, parameter int SETS = 8, parameter int LINEWORDS = 4,
                parameter bit SYNC_READ = 1) (
  input  logic        clk, reset,
  // Lab 9: the next access's address (Execute stage, virtual) and "keep reading M's set"
  input  logic [31:0] AdrE,
  input  logic        HoldM,          // MMU busy (walk, or the access is waiting for one)
  // from the LSU (Memory stage)
  input  logic [31:0] Adr,
  input  logic [1:0]  RW,             // {read, write}; already gated by PMA (cacheable) and ~TrapM
  input  logic        FlushReq,       // fence.i in M (and not trapping)
  input  logic [31:0] WriteData,      // already lane-aligned (subwordwrite)
  input  logic [3:0]  ByteMask,
  input  logic        Stall,          // StallW: the pipeline is held for another reason
  output logic [31:0] ReadDataWord,
  output logic        CacheStall,
  output logic        CacheCommitted,
  output logic        CacheBusy,      // the FSM owns the AHB port
  // AHB manager port (bursts)
  output logic [31:0] HADDR,
  output logic        HWRITE,
  output logic [1:0]  HTRANS,
  output logic [2:0]  HBURST,
  output logic [31:0] HWDATA,
  input  logic        HREADY,
  input  logic [31:0] HRDATA,
  // for the testbench's transaction monitor and performance counters
  output logic        EvAccess, EvHit,
  output logic [$clog2(WAYS > 1 ? WAYS : 2)-1:0] EvWay,
  output logic        EvVictimDirty,
  output logic [31:0] EvWbAdr,
  output logic        EvFlushWb,
  output logic        EvReRead
);
  localparam int OB  = $clog2(LINEWORDS);              // word-offset bits
  localparam int SB  = (SETS > 1) ? $clog2(SETS) : 1;  // set bits
  localparam int TW  = 16 - 2 - OB - SB;               // tag bits within the 64 KB region
  localparam int WB_ = (WAYS > 1) ? $clog2(WAYS) : 1;  // way-number bits
  localparam int LB  = (WAYS > 1) ? WAYS - 1 : 1;      // pLRU bits per set

  // ---------------- arrays (flops, like Wally's status bits; data/tag would be SRAM) ----------------
  logic [31:0]   Data  [WAYS][SETS][LINEWORDS];
  logic [TW-1:0] Tag   [WAYS][SETS];
  logic          Valid [WAYS][SETS];
  logic          Dirty [WAYS][SETS];
  logic [LB-1:0] LRU   [SETS];

  logic [SB-1:0] Set;
  logic [OB-1:0] Word;
  logic [TW-1:0] AdrTag;
  assign Word   = Adr[2 +: OB];
  assign Set    = (SETS > 1) ? Adr[2+OB +: SB] : '0;
  assign AdrTag = Adr[2+OB+SB +: TW];

  // ---------------- hit logic ----------------
  logic [WAYS-1:0] HitWay, ValidWay;
  always_comb
    for (int w = 0; w < WAYS; w++) begin
      ValidWay[w] = Valid[w][Set];
`ifdef BUG_TAG_SHORT
      HitWay[w] = Valid[w][Set] & (Tag[w][Set][TW-2:0] == AdrTag[TW-2:0]);   // BUG: drops the tag MSB
`else
      HitWay[w] = Valid[w][Set] & (Tag[w][Set] == AdrTag);
`endif
    end
  logic Hit;
  assign Hit = |HitWay;
  logic [WB_-1:0] HitWayEnc;
  always_comb begin
    HitWayEnc = '0;
    for (int w = 0; w < WAYS; w++) if (HitWay[w]) HitWayEnc = WB_'(w);
  end

  // ---------------- tree pLRU (book 10.4.4): bit index = (N-2) - heap index ----------------
  function automatic logic [WB_-1:0] plru_victim(input logic [LB-1:0] lru);
    int h = 0; logic [WB_-1:0] way = '0;
    if (WAYS == 1) return '0;
    for (int l = 0; l < WB_; l++) begin
      logic b = lru[WAYS - 2 - h];
      way = {way[WB_-2:0], b};
      h = 2 * h + 1 + int'(b);
    end
    return way;
  endfunction
  function automatic logic [LB-1:0] plru_update(input logic [LB-1:0] lru, input logic [WB_-1:0] way);
    int h = 0; logic [LB-1:0] n = lru;
    if (WAYS == 1) return lru;
    for (int l = WB_ - 1; l >= 0; l--) begin
      logic dir = way[l];
      n[WAYS - 2 - h] = ~dir;                // point AWAY from the way just used
      h = 2 * h + 1 + int'(dir);
    end
    return n;
  endfunction

  logic [WB_-1:0] VictimWay;
  always_comb begin
    VictimWay = plru_victim(LRU[Set]);
    for (int w = WAYS - 1; w >= 0; w--) if (!ValidWay[w]) VictimWay = WB_'(w);   // first invalid way wins
  end

  // ---------------- FSM (book Fig. 10.19) ----------------
  typedef enum logic [2:0] {ACCESS, WRITEBACK, FETCH, WRITELINE, FLUSH, FLUSHWB, FLUSHDONE} state_t;
  state_t State, NextState;
  logic           Req;
  assign Req = |RW;

  // miss bookkeeping, captured when leaving ACCESS
  logic [WB_-1:0] MissWay;
  logic [TW-1:0]  WbTag;
  logic [SB-1:0]  MissSet;
  // flush walk
  logic [SB-1:0]  FlushSet;
  logic [WB_-1:0] FlushWay;
  logic           FlushLast, FlushLineDirty;
`ifdef BUG_FLUSH_SKIP_LAST
  assign FlushLast = (FlushWay == WB_'(WAYS - 1)) & (FlushSet == SB'(SETS - 2 < 0 ? 0 : SETS - 2));
`else
  assign FlushLast = (FlushWay == WB_'(WAYS - 1)) & (FlushSet == SB'(SETS - 1));
`endif
  assign FlushLineDirty = Valid[FlushWay][FlushSet] & Dirty[FlushWay][FlushSet];

  // ---------------- burst engine (Wally ahbcacheinterface + EBU burst support) ----------------
  logic [OB:0]    AdrBeat, DataBeat;           // address phases accepted, data phases completed
  logic           BurstWrite, BurstDone;
  logic [31:0]    BurstBase;
  logic [31:0]    FetchBuffer [LINEWORDS];
  logic           InBurst;
  assign InBurst   = (State == WRITEBACK) | (State == FETCH) | (State == FLUSHWB);
  assign BurstDone = InBurst & HREADY & (DataBeat == (OB+1)'(LINEWORDS - 1)) & (AdrBeat == (OB+1)'(LINEWORDS));

  always_comb begin
    BurstWrite = (State == WRITEBACK) | (State == FLUSHWB);
    case (State)
      WRITEBACK: BurstBase = {16'h9000, WbTag, MissSet, {(OB+2){1'b0}}};
      FLUSHWB:   BurstBase = {16'h9000, Tag[FlushWay][FlushSet], FlushSet, {(OB+2){1'b0}}};
      default:   BurstBase = {Adr[31:2+OB], {(OB+2){1'b0}}};
    endcase
  end
  logic [WB_-1:0] BurstWay;
  logic [SB-1:0]  BurstSet;
  assign BurstWay = (State == FLUSHWB) ? FlushWay : MissWay;
  assign BurstSet = (State == FLUSHWB) ? FlushSet : MissSet;
  assign CacheBusy = InBurst;
  assign HTRANS  = (InBurst & (AdrBeat < (OB+1)'(LINEWORDS))) ? ((AdrBeat == 0) ? 2'b10 : 2'b11) : 2'b00;
  assign HADDR   = BurstBase + {AdrBeat[OB-1:0], 2'b00};
  assign HWRITE  = BurstWrite;
  assign HBURST  = (LINEWORDS == 4) ? 3'b011 : (LINEWORDS == 8) ? 3'b101 : 3'b001;   // INCR4 / INCR8 / INCR
  assign HWDATA  = Data[BurstWay][BurstSet][DataBeat[OB-1:0]];
  logic DataPhase;
  assign DataPhase = InBurst & (DataBeat < AdrBeat);

  always_ff @(posedge clk)
    begin
      if (HREADY & DataPhase & ~BurstWrite) FetchBuffer[DataBeat[OB-1:0]] <= HRDATA;   // incl. the last beat
      if (reset | ~InBurst | BurstDone) begin AdrBeat <= '0; DataBeat <= '0; end   // each burst starts at beat 0
      else if (HREADY) begin
        if (AdrBeat < (OB+1)'(LINEWORDS)) AdrBeat <= AdrBeat + 1'b1;
        if (DataPhase) DataBeat <= DataBeat + 1'b1;
      end
    end

  // ---------------- next state ----------------
  logic VictimDirty;
  assign VictimDirty = Valid[VictimWay][Set] & Dirty[VictimWay][Set];
  always_comb begin
    NextState = State;
    case (State)
      ACCESS:    if (FlushReq) NextState = FLUSH;
                 else if (Req & ~Hit)
`ifdef BUG_NO_WRITEBACK
                   NextState = FETCH;                                       // BUG: dirty victim dropped
`else
                   NextState = VictimDirty ? WRITEBACK : FETCH;
`endif
      WRITEBACK: if (BurstDone) NextState = FETCH;
      FETCH:     if (BurstDone) NextState = WRITELINE;
      WRITELINE: NextState = ACCESS;
      FLUSH:     if (FlushLineDirty) NextState = FLUSHWB;
                 else if (FlushLast) NextState = FLUSHDONE;
      FLUSHWB:   if (BurstDone) NextState = FlushLast ? FLUSHDONE : FLUSH;
      FLUSHDONE: NextState = ACCESS;
      default:   NextState = ACCESS;
    endcase
  end
  always_ff @(posedge clk) if (reset) State <= ACCESS; else State <= NextState;

  // CacheStall: everything except a hit in ACCESS, and the one-cycle WRITELINE/FLUSHDONE where the
  // instruction finally leaves M (early return from the fetch buffer, as in Wally)
  assign CacheStall     = (State == ACCESS & ((Req & ~Hit) | FlushReq | ReRead)) |
                          (State == WRITEBACK) | (State == FETCH) | (State == FLUSH) | (State == FLUSHWB);
  assign CacheCommitted = (State != ACCESS);

  // ---------------- Lab 9: data SRAM with a synchronous read port ----------------
  initial if (2 + OB + SB > 12) $error("dcache: set + offset bits exceed the 4 KiB page offset: not VIPT-safe");
  logic [SB-1:0] SetE, RdSet, DataOutSet;
  logic          SelAdr, DataOutOK, ArrayWrite, StoreWrite, DataReady, ReRead;
  logic [31:0]   DataOut [WAYS][LINEWORDS];
  assign SetE       = (SETS > 1) ? AdrE[2+OB +: SB] : '0;
  assign StoreWrite = (State == ACCESS) & ~FlushReq & Req & Hit & ~Stall & RW[0];
  assign ArrayWrite = StoreWrite | (State == WRITELINE);
`ifdef BUG_SELADR_ON_HIT
  assign SelAdr = HoldM | Stall | (State != ACCESS) | FlushReq | Req | ReRead;              // BUG: Req, not Req & ~Hit
`else
  assign SelAdr = HoldM | Stall | (State != ACCESS) | FlushReq | (Req & ~Hit) | ReRead;
`endif
  assign RdSet = SelAdr ? Set : SetE;          // Wally: CacheSet = SelAdr ? PAdrM : IEUAdrE (set bits)
  always_ff @(posedge clk) begin
    for (int w = 0; w < WAYS; w++) for (int i = 0; i < LINEWORDS; i++)
      DataOut[w][i] <= Data[w][RdSet][i];      // a write in the same cycle is not seen (read-before-write)
    DataOutSet <= RdSet;
`ifdef BUG_FILL_NO_INVAL
    DataOutOK  <= ~reset & ~StoreWrite;        // BUG: forgets that a line fill also used the port
`else
    DataOutOK  <= ~reset & ~ArrayWrite;        // single-port SRAM: a write cycle reads nothing useful
`endif
  end
`ifdef BUG_NO_REREAD
  assign DataReady = 1'b1;
`elsif BUG_REREAD_SET_ONLY
  assign DataReady = (DataOutSet == Set);
`else
  assign DataReady = DataOutOK & (DataOutSet == Set);
`endif
  // only a load hit needs the data; a store hit only needs the tags (flops here)
  assign ReRead   = SYNC_READ & (State == ACCESS) & ~FlushReq & Req & Hit & RW[1] & ~DataReady;
  assign EvReRead = ReRead;

  // ---------------- read data ----------------
  logic [31:0] HitWord;
  always_comb begin
    HitWord = '0;
    for (int w = 0; w < WAYS; w++)
      if (HitWay[w]) HitWord |= SYNC_READ ? DataOut[w][Word] : Data[w][Set][Word];   // AND-OR mux
  end
  assign ReadDataWord = (State == WRITELINE) ? FetchBuffer[Word] : HitWord;

  // ---------------- array updates ----------------
  function automatic logic [31:0] merge(input logic [31:0] old, input logic [31:0] d, input logic [3:0] m);
    for (int b = 0; b < 4; b++) if (m[b]) old[8*b +: 8] = d[8*b +: 8];
    return old;
  endfunction

  always_ff @(posedge clk)
    if (reset) begin
      for (int w = 0; w < WAYS; w++) for (int s = 0; s < SETS; s++) begin Valid[w][s] <= 1'b0; Dirty[w][s] <= 1'b0; end
      for (int s = 0; s < SETS; s++) LRU[s] <= '0;
      FlushSet <= '0; FlushWay <= '0; MissWay <= '0; WbTag <= '0; MissSet <= '0;
    end else begin
      case (State)
        ACCESS: begin
          if (!FlushReq && Req && Hit && !Stall && !ReRead) begin
`ifndef BUG_LRU_STUCK
            LRU[Set] <= plru_update(LRU[Set], HitWayEnc);
`endif
            if (RW[0]) begin
              Data[HitWayEnc][Set][Word] <= merge(Data[HitWayEnc][Set][Word], WriteData, ByteMask);
`ifndef BUG_DIRTY_ON_HIT
              Dirty[HitWayEnc][Set] <= 1'b1;
`endif
            end
          end
          if (!FlushReq && Req && !Hit) begin                       // remember the miss
            MissWay <= VictimWay; MissSet <= Set; WbTag <= Tag[VictimWay][Set];
          end
          FlushSet <= '0; FlushWay <= '0;
        end
        WRITELINE: begin                                            // install the line (+ merge a store)
          for (int i = 0; i < LINEWORDS; i++)
            Data[MissWay][MissSet][i] <= FetchBuffer[i];
`ifndef BUG_NO_MERGE
          if (RW[0]) Data[MissWay][MissSet][Word] <= merge(FetchBuffer[Word], WriteData, ByteMask);
`endif
          Tag[MissWay][MissSet]   <= AdrTag;
          Valid[MissWay][MissSet] <= 1'b1;
          Dirty[MissWay][MissSet] <= RW[0];
`ifndef BUG_LRU_STUCK
          LRU[MissSet] <= plru_update(LRU[MissSet], MissWay);
`endif
        end
        FLUSH: if (!FlushLineDirty && !FlushLast) begin             // clean line: next way / set
          if (FlushWay == WB_'(WAYS - 1)) begin FlushWay <= '0; FlushSet <= FlushSet + 1'b1; end
          else FlushWay <= FlushWay + 1'b1;
        end
        FLUSHWB: if (BurstDone) begin
          Dirty[FlushWay][FlushSet] <= 1'b0;                        // cleared after the writeback
          if (!FlushLast) begin
            if (FlushWay == WB_'(WAYS - 1)) begin FlushWay <= '0; FlushSet <= FlushSet + 1'b1; end
            else FlushWay <= FlushWay + 1'b1;
          end
        end
        default: ;
      endcase
    end

  // ---------------- monitor outputs ----------------
  assign EvAccess      = (State == ACCESS) & Req & ~FlushReq & (Hit ? (~Stall & ~ReRead) : 1'b1);
  assign EvHit         = Hit;
  assign EvWay         = Hit ? HitWayEnc : VictimWay;
  assign EvVictimDirty = ~Hit & VictimDirty;
  assign EvWbAdr       = {16'h9000, Tag[VictimWay][Set], Set, {(OB+2){1'b0}}};
  assign EvFlushWb     = (State == FLUSHWB) & BurstDone;
endmodule
