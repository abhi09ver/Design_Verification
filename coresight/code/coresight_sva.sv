// =============================================================================
// coresight_sva.sv
// Bind-able SystemVerilog checkers for CoreSight interfaces (ARM IHI 0029E v3.0)
// plus a reference model for the authentication equations.
//
//   cs_atb_checker        ATB valid/ready stability, legal IDs, flush completion
//   cs_channel_checker    Async channel 4-phase handshake (spec C4.3)
//   cs_apb_pwr_checker    Debug APB: no hang, PSLVERR when component is powered off
//   cs_auth_checker       AUTHSTATUS and gating vs. spec Tables C5-2..C5-4
//   cs_cti_checker        No reflection of channel input to channel output (C4.4)
//
// ATB signal names follow the AMBA ATB spec. Parameters such as MAX_* are
// design-specific bounds that you agree with the micro-architect.
// =============================================================================

// -----------------------------------------------------------------------------
// ATB
// -----------------------------------------------------------------------------
module cs_atb_checker #(
  parameter int DW            = 32,
  parameter int BW            = $clog2(DW/8),
  parameter int MAX_FLUSH_CYC = 4096          // bound for AFVALID -> AFREADY
)(
  input logic          atclk,
  input logic          atresetn,
  input logic          atvalid,
  input logic          atready,
  input logic [6:0]    atid,
  input logic [DW-1:0] atdata,
  input logic [BW-1:0] atbytes,
  input logic          afvalid,               // flush request (slave -> master)
  input logic          afready                // flush done    (master -> slave)
);
  default clocking cb @(posedge atclk); endclocking
  default disable iff (!atresetn);

  // Once offered, a beat must not change or be withdrawn until accepted.
  a_atb_stable: assert property (
    atvalid && !atready |=> atvalid && $stable({atid, atdata, atbytes}))
    else $error("ATB: payload changed or valid dropped while stalled");

  // Source IDs 0x00 and 0x70-0x7F are special/reserved; 0x7B (flush response)
  // and 0x7D (trigger) are permitted on ATB with defined payload.
  a_atid_legal: assert property (
    atvalid |-> (atid inside {[7'h01:7'h6F]} || atid == 7'h7B || atid == 7'h7D))
    else $error("ATB: illegal ATID %0h", atid);

  // Flush request is held until acknowledged, and is acknowledged in bounded time.
  a_flush_hold: assert property (afvalid && !afready |=> afvalid)
    else $error("ATB: AFVALID dropped before AFREADY");
  a_flush_done: assert property (
    $rose(afvalid) |-> ##[0:MAX_FLUSH_CYC] afready)
    else $error("ATB: flush did not complete within %0d cycles", MAX_FLUSH_CYC);

  // No X on control while out of reset.
  a_no_x: assert property (!$isunknown({atvalid, atready, afvalid, afready}));

  // Coverage: stalls, back-to-back, flush while busy, special IDs.
  c_stall:        cover property (atvalid && !atready ##1 atvalid && !atready ##1 atvalid && atready);
  c_b2b:          cover property (atvalid && atready ##1 atvalid && atready);
  c_flush_busy:   cover property (afvalid && atvalid && !atready);
  c_flush_resp:   cover property (atvalid && atready && atid == 7'h7B);
  c_trigger_id:   cover property (atvalid && atready && atid == 7'h7D);
endmodule


// -----------------------------------------------------------------------------
// Asynchronous channel interface: CHIN / CHINACK 4-phase handshake (spec C4.3)
// Sampled on a fast reference clock in simulation.
// -----------------------------------------------------------------------------
module cs_channel_checker #(
  parameter int N       = 4,
  parameter int MAX_LAT = 16                    // cycles of sample clock
)(
  input logic         clk,
  input logic         resetn,
  input logic [N-1:0] chin,
  input logic [N-1:0] chinack
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!resetn);

  for (genvar m = 0; m < N; m++) begin : g_ch
    // 1: req up -> ack up      2: ack up -> req down     3: req down -> ack down
    a_ack_rise:  assert property ($rose(chin[m])  |-> ##[0:MAX_LAT] chinack[m]);
    a_req_hold:  assert property (chin[m] && !chinack[m] |=> chin[m]);
    a_ack_fall:  assert property ($fell(chin[m])  |-> ##[0:MAX_LAT] !chinack[m]);
    a_ack_hold:  assert property (!chin[m] && chinack[m] |=> chinack[m]);
    a_no_spur:   assert property ($rose(chinack[m]) |-> chin[m]);
    c_full_hs:   cover  property ($rose(chin[m]) ##[1:$] $rose(chinack[m])
                                   ##[1:$] $fell(chin[m]) ##[1:$] $fell(chinack[m]));
  end
endmodule


// -----------------------------------------------------------------------------
// Debug APB: a powered-down component must answer with PSLVERR, never hang.
// pwr_on comes from the power intent (UPF supply state) or the PPU model.
// -----------------------------------------------------------------------------
module cs_apb_pwr_checker #(
  parameter int MAX_WAIT = 64
)(
  input logic pclkdbg,
  input logic presetdbgn,
  input logic pseldbg,
  input logic penabledbg,
  input logic preadydbg,
  input logic pslverrdbg,
  input logic pwr_on
);
  default clocking cb @(posedge pclkdbg); endclocking
  default disable iff (!presetdbgn);

  wire access = pseldbg && penabledbg;

  a_no_hang: assert property ($rose(access) |-> ##[0:MAX_WAIT] preadydbg)
    else $error("Debug APB: transfer not completed in %0d cycles", MAX_WAIT);

  a_err_when_off: assert property (access && preadydbg && !pwr_on |-> pslverrdbg)
    else $error("Debug APB: access to powered-down component without PSLVERR");

  c_access_off: cover property (access && preadydbg && !pwr_on);
  c_access_on:  cover property (access && preadydbg && pwr_on && !pslverrdbg);
endmodule


// -----------------------------------------------------------------------------
// Authentication reference model (Tables C5-2, C5-3, C5-4) and AUTHSTATUS
// -----------------------------------------------------------------------------
package cs_auth_pkg;
  typedef struct packed {
    logic ns_inv, ns_ninv, s_inv, s_ninv, h_inv, h_ninv;
  } cs_perm_t;

  function automatic cs_perm_t cs_auth_perm(logic dbgen, niden, spiden, spniden, hiden, hniden);
    cs_perm_t p;
    p.ns_inv  = dbgen;
    p.ns_ninv = dbgen | niden;
    p.s_inv   = dbgen & spiden;
    p.s_ninv  = (spiden | spniden) & (dbgen | niden);
    p.h_inv   = dbgen & hiden;
    p.h_ninv  = (hiden | hniden) & (dbgen | niden);
    return p;
  endfunction

  // Component that supports every level: field = 2'b11 enabled, 2'b10 disabled.
  function automatic logic [31:0] cs_authstatus(cs_perm_t p);
    logic [31:0] a = '0;
    a[1:0]   = {1'b1, p.ns_inv};
    a[3:2]   = {1'b1, p.ns_ninv};
    a[5:4]   = {1'b1, p.s_inv};
    a[7:6]   = {1'b1, p.s_ninv};
    a[9:8]   = {1'b1, p.h_inv};
    a[11:10] = {1'b1, p.h_ninv};
    return a;
  endfunction
endpackage

module cs_auth_checker
  import cs_auth_pkg::*;
#(
  parameter int SYNC_CYC = 4                    // allowed latency for a change to take effect
)(
  input logic        clk,
  input logic        resetn,
  input logic        dbgen, niden, spiden, spniden, hiden, hniden,
  input logic [31:0] authstatus,                // value the component returns at 0xFB8
  input logic        secure_trace_active,       // DUT emitting trace of Secure state
  input logic        ns_trace_active            // DUT emitting trace of Non-secure state
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!resetn);

  cs_perm_t p;
  assign p = cs_auth_perm(dbgen, niden, spiden, spniden, hiden, hniden);

  // AUTHSTATUS must match the model once inputs have been stable for SYNC_CYC.
  a_authstatus: assert property (
    $stable({dbgen, niden, spiden, spniden, hiden, hniden})[*SYNC_CYC] |-> authstatus[11:0] == cs_authstatus(p)[11:0])
    else $error("AUTHSTATUS %h != model %h", authstatus[11:0], cs_authstatus(p)[11:0]);

  // No Secure trace when Secure non-invasive debug is not permitted (after sync).
  a_no_s_leak:  assert property (!p.s_ninv [*SYNC_CYC] |-> !secure_trace_active);
  a_no_ns_leak: assert property (!p.ns_ninv[*SYNC_CYC] |-> !ns_trace_active);

  // Cover every one of the 16 SPIDEN/DBGEN/SPNIDEN/NIDEN combinations.
  for (genvar k = 0; k < 16; k++) begin : g_combo
    c_combo: cover property ({spiden, dbgen, spniden, niden} == k[3:0]);
  end
  c_drop_mid_trace: cover property (secure_trace_active ##1 $fell(spniden | spiden));
endmodule


// -----------------------------------------------------------------------------
// CTI: an event on channel input m must not be reflected on channel output m
// by the same CTI unless software/trigger logic asserted it (spec C4.4).
// local_drive[m] = this CTI's own trigger-in mapping or APPSET/APPPULSE for m.
// -----------------------------------------------------------------------------
module cs_cti_checker #(parameter int N = 4)(
  input logic         clk,
  input logic         resetn,
  input logic [N-1:0] chin,
  input logic [N-1:0] chout,
  input logic [N-1:0] local_drive
);
  default clocking cb @(posedge clk); endclocking
  default disable iff (!resetn);
  for (genvar m = 0; m < N; m++) begin : g_ch
    a_no_reflect: assert property ($rose(chout[m]) |-> $past(local_drive[m]) || local_drive[m])
      else $error("CTI: channel %0d output without a local source (reflection?)", m);
    c_in_out: cover property (chin[m] && local_drive[m]);
  end
endmodule


// -----------------------------------------------------------------------------
// Example binds (adjust instance and signal names to your RTL)
// -----------------------------------------------------------------------------
// bind cs_funnel  cs_atb_checker   #(.DW(32)) u_atb_m (.atclk(clk), .atresetn(resetn),
//      .atvalid(atvalid_m), .atready(atready_m), .atid(atid_m), .atdata(atdata_m),
//      .atbytes(atbytes_m), .afvalid(afvalid_m), .afready(afready_m));
// bind cs_cti     cs_cti_checker   #(.N(4)) u_cti (.clk(clk), .resetn(resetn),
//      .chin(chin), .chout(chout), .local_drive(dbg_local_drive));
