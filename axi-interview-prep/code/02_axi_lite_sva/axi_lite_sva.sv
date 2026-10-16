// =============================================================================
// axi_lite_sva.sv  -  AXI4-Lite protocol checker, attached with `bind`
//
// Companion code for cheat sheets 04 (handshake) and 14 (top-tier roadmap).
// Port names match the AXI4-Lite slave in NitishVerifies/AXI4_UVM_Verification,
// so `.*` connects everything. Needs a simulator or formal tool with
// concurrent-SVA support (VCS, Questa, Xcelium, JasperGold, SymbiYosys+Verific).
// iverilog 12 does not support concurrent assertions; see
// ../03_axi4_lite_repo_fixes/probes/probe_sva_emulation.sv for a procedural
// equivalent that was used to confirm a_b_live catches the W-before-AW bug.
// =============================================================================
module axi_lite_sva (
    input logic        aclk, aresetn,
    input logic        awvalid, awready, wvalid, wready, bvalid, bready,
    input logic        arvalid, arready, rvalid, rready,
    input logic [31:0] awaddr, araddr, wdata, rdata,
    input logic [3:0]  wstrb,
    input logic [1:0]  bresp, rresp
);
    default clocking cb @(posedge aclk); endclocking
    default disable iff (!aresetn);

    // ---- Rule 2 + 3: VALID held, payload stable until READY (5 channels)
    a_aw_hold: assert property (awvalid && !awready |=> awvalid && $stable(awaddr));
    a_w_hold : assert property (wvalid  && !wready  |=> wvalid  && $stable({wdata, wstrb}));
    a_ar_hold: assert property (arvalid && !arready |=> arvalid && $stable(araddr));
    a_b_hold : assert property (bvalid  && !bready  |=> bvalid  && $stable(bresp));
    a_r_hold : assert property (rvalid  && !rready  |=> rvalid  && $stable({rdata, rresp}));

    // ---- No X on any VALID once out of reset
    a_no_x: assert property (!$isunknown({awvalid, wvalid, bvalid, arvalid, rvalid}));

    // ---- Reset: slave VALIDs low while in reset. Overrides the default
    //      disable iff, which would otherwise make this check vacuous.
    a_rst: assert property (disable iff (1'b0) !aresetn |-> !bvalid && !rvalid);

    // ---- Response ordering: B needs AW and W accepted; R needs AR accepted
    logic [7:0] aw_n, w_n, b_n, ar_n, r_n;
    always_ff @(posedge aclk or negedge aresetn)
        if (!aresetn) {aw_n, w_n, b_n, ar_n, r_n} <= '0;
        else begin
            aw_n <= aw_n + (awvalid && awready);
            w_n  <= w_n  + (wvalid  && wready);
            b_n  <= b_n  + (bvalid  && bready);
            ar_n <= ar_n + (arvalid && arready);
            r_n  <= r_n  + (rvalid  && rready);
        end
    a_b_order: assert property (bvalid |-> aw_n != b_n && w_n != b_n);
    a_r_order: assert property (rvalid |-> ar_n != r_n);

    // ---- Bounded liveness: once both AW and W are in, B within 8 cycles
    //      (fires on the original RTL when W arrives before AW -> deadlock)
    a_b_live: assert property (aw_n != b_n && w_n != b_n |-> ##[0:8] bvalid);
    a_r_live: assert property (ar_n != r_n |-> ##[0:8] rvalid);

    // ---- Cover the interesting orderings (prove the stimulus reaches them)
    c_w_first   : cover property (wvalid && !awvalid && aw_n == b_n);
    c_same_cycle: cover property (awvalid && awready && wvalid && wready);
    c_b_stall   : cover property (bvalid && !bready ##1 bvalid && !bready);
    c_slverr    : cover property (bvalid && bready && bresp == 2'b10);
endmodule

// Attach without touching the RTL:
// bind axi4_slave_ram axi_lite_sva u_axi_lite_sva (.*);
