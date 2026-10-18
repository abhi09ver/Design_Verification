// gic_cpu_if_sva.sv
// -----------------------------------------------------------------------------
// Example SystemVerilog assertions for a GICv3 CPU interface / Redistributor
// boundary. Bind this checker to your design and map the ports onto the
// signals your RTL actually has (names here are generic, not from any real IP).
//
// The GIC architecture deliberately does NOT define signalling latency, so
// every "must happen" property is written as "within MAX_LAT cycles" and every
// "must not happen" property waits for config to be stable for SETTLE cycles.
// Tune both per design; a property that fires at cycle 0 after a config write
// is usually a checker bug, not an RTL bug.
//
// Reference: Arm IHI 0069H.b (GICv3.3 / GICv4.2), Chapters 4, 11, 12.
// -----------------------------------------------------------------------------
module gic_cpu_if_sva #(
  parameter int MAX_LAT = 64,   // bound for "eventually" properties
  parameter int SETTLE  = 8,    // cycles a config must be stable before we judge
  parameter int SPURIOUS = 1023
) (
  input logic        clk,
  input logic        rst_n,

  // ---- core-facing outputs of the CPU interface ----
  input logic        irq,
  input logic        fiq,

  // ---- CPU interface state (from sysregs) ----
  input logic        igrpen0,       // ICC_IGRPEN0_EL1.Enable
  input logic        igrpen1,       // ICC_IGRPEN1_EL1.Enable (current Security state)
  input logic [7:0]  pmr,           // ICC_PMR_EL1.Priority
  input logic [7:0]  rpr,           // running priority (0xFF when idle)

  // ---- HPPI offered by the Redistributor (Set packet / internal bus) ----
  input logic        hppi_valid,
  input logic [7:0]  hppi_prio,     // already group-priority masked by BPR
  input logic [1:0]  hppi_grp,      // 0 = G0, 1 = G1S, 2 = G1NS

  // ---- acknowledge (ICC_IAR1_EL1 read) ----
  input logic        iar_rd,        // one-cycle pulse when the read retires
  input logic [23:0] iar_intid,
  input logic [7:0]  iar_prio,      // priority of the INTID returned (sideband)

  // ---- power handshake (GICR_WAKER) ----
  input logic        processor_sleep,
  input logic        children_asleep,
  input logic        wake_request,

  // ---- ITS command queue pointers (GITS_CREADR / GITS_CWRITER offsets) ----
  input logic [19:0] its_creadr,
  input logic [19:0] its_cwriter,
  input logic        its_stalled
);

  // "Could the CPU interface legally signal right now?" (simplified: ignores
  // the IRQ/FIQ group-to-signal mapping, which is checked separately).
  wire grp_enabled = (hppi_grp == 2'd0) ? igrpen0 : igrpen1;
  wire eligible    = hppi_valid && grp_enabled && (hppi_prio < pmr) && (hppi_prio < rpr);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // ---------------------------------------------------------------------------
  // 1. No interrupt is signalled while both groups are disabled (after settle).
  // ---------------------------------------------------------------------------
  a_no_signal_when_groups_off: assert property (
    (!igrpen0 && !igrpen1) [*SETTLE] |-> (!irq && !fiq)
  ) else $error("IRQ/FIQ asserted with both group enables clear");

  // ---------------------------------------------------------------------------
  // 2. Masking: once nothing is eligible for SETTLE cycles, the line drops.
  //    (PMR raised, RPR raised by an ack, or HPPI withdrawn.)
  // ---------------------------------------------------------------------------
  a_irq_drops_when_masked: assert property (
    (!eligible) [*SETTLE] |-> !irq
  ) else $error("IRQ still asserted though no pending interrupt passes PMR/RPR");

  // ---------------------------------------------------------------------------
  // 3. Liveness: an eligible interrupt that stays eligible is signalled
  //    within MAX_LAT cycles. (Bounded, so it works in simulation and formal.)
  // ---------------------------------------------------------------------------
  a_eligible_gets_signalled: assert property (
    $rose(eligible) ##0 eligible [*MAX_LAT] |-> (irq || fiq)
  ) else $error("Eligible HPPI not signalled within MAX_LAT cycles");

  // ---------------------------------------------------------------------------
  // 4. IAR never returns an interrupt that is masked by PMR.
  //    LPIs/SPIs/etc. all carry a priority; 1020-1023 are special values.
  // ---------------------------------------------------------------------------
  a_iar_respects_pmr: assert property (
    (iar_rd && iar_intid < 1020) |-> (iar_prio < pmr)
  ) else $error("IAR returned INTID %0d with priority 0x%0h >= PMR 0x%0h",
                iar_intid, iar_prio, pmr);

  // ---------------------------------------------------------------------------
  // 5. IAR returns spurious when nothing has been eligible for SETTLE cycles.
  //    We do NOT check the reverse (eligible => real INTID): a Clear can race
  //    the read and 1023 is then legal.
  // ---------------------------------------------------------------------------
  a_iar_spurious_when_idle: assert property (
    (!eligible) [*SETTLE] ##1 iar_rd |-> (iar_intid == SPURIOUS)
  ) else $error("IAR returned %0d when nothing was eligible", iar_intid);

  // ---------------------------------------------------------------------------
  // 6. GICR_WAKER handshake ordering.
  // ---------------------------------------------------------------------------
  a_asleep_only_after_request: assert property (
    $rose(children_asleep) |-> processor_sleep
  ) else $error("ChildrenAsleep set without ProcessorSleep");

  a_sleep_completes: assert property (
    $rose(processor_sleep) |-> ##[1:MAX_LAT] children_asleep or !processor_sleep
  ) else $error("ChildrenAsleep did not follow ProcessorSleep within MAX_LAT");

  a_no_irq_while_asleep: assert property (
    children_asleep |-> (!irq && !fiq)
  ) else $error("IRQ/FIQ asserted to a quiesced CPU interface");

  // An interrupt that would have been signalled while asleep must raise a wake request.
  a_wake_on_pending: assert property (
    (children_asleep && hppi_valid && grp_enabled) [*SETTLE] |-> ##[0:MAX_LAT] wake_request
  ) else $error("Pending interrupt for a sleeping PE did not raise wake_request");

  // ---------------------------------------------------------------------------
  // 7. ITS command queue: CREADR only moves when the queue is non-empty and the
  //    ITS is not stalled; it never moves when CREADR == CWRITER.
  // ---------------------------------------------------------------------------
  a_creadr_moves_only_when_work: assert property (
    $changed(its_creadr) |-> ($past(its_creadr) != $past(its_cwriter)) && !$past(its_stalled)
  ) else $error("GITS_CREADR advanced with an empty or stalled queue");

  a_creadr_32byte_aligned: assert property (
    its_creadr[4:0] == 5'd0
  ) else $error("GITS_CREADR not aligned to a 32-byte command");

  // ---------------------------------------------------------------------------
  // Coverage: make sure the interesting situations actually happened.
  // ---------------------------------------------------------------------------
  c_preempt:       cover property (rpr != 8'hFF && eligible && irq);   // nested interrupt
  c_pmr_mask:      cover property (hppi_valid && grp_enabled && hppi_prio >= pmr);
  c_spurious_read: cover property (iar_rd && iar_intid == SPURIOUS);
  c_sleep_wake:    cover property ($rose(children_asleep) ##[1:$] $rose(wake_request));
  c_its_wrap:      cover property ($changed(its_creadr) && its_creadr == 20'd0);

endmodule

// Example bind (adjust hierarchy and signal names to your RTL):
// bind gic_cpu_if gic_cpu_if_sva #(.MAX_LAT(64)) u_sva (
//   .clk(clk), .rst_n(rst_n), .irq(o_irq), .fiq(o_fiq),
//   .igrpen0(r_igrpen0), .igrpen1(r_igrpen1), .pmr(r_pmr), .rpr(w_rpr),
//   .hppi_valid(set_vld), .hppi_prio(set_gprio), .hppi_grp(set_grp),
//   .iar_rd(iar_ret), .iar_intid(iar_id), .iar_prio(iar_pri),
//   .processor_sleep(waker_ps), .children_asleep(waker_ca), .wake_request(o_wake),
//   .its_creadr(creadr), .its_cwriter(cwriter), .its_stalled(creadr_stalled));
