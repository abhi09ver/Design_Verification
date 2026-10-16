// =============================================================================
// core_sva.sv : white-box SystemVerilog assertions, attached with `bind`
// -----------------------------------------------------------------------------
// The ISS scoreboard (tools/run_test.py) tells you THAT something went wrong,
// often hundreds of cycles later ("HANG", "wrong value in x7").
// Assertions tell you WHERE and WHEN: they fire on the exact cycle an
// invariant breaks. A good CPU DV plan has both.
//
// `bind` attaches the checker to every instance of a design module WITHOUT
// editing the RTL. The checker sees the module's internal signals by name.
// =============================================================================
`ifndef CORE_SVA_SV
`define CORE_SVA_SV

// ----------------------------------------------------------------- core checks
module core_sva
    import tomasulo_pkg::*;
#(
    parameter int IW = 3, parameter int NROB = 48,
    parameter int NALU = 12, parameter int NMD = 4, parameter int NLSB = 16
)(
    input logic clk, rst, flush,
    input decode_entry_t   [IW-1:0]   decode_reg,
    input dispatch_entry_t [IW-1:0]   dispatch_reg,
    input logic                       alloc_d1,
    input AddSub_RS_Entry_t [NALU-1:0] alu_rs,
    input MulDiv_RS_Entry_t [NMD-1:0]  md_rs,
    input LS_Buffer_Entry_t [NLSB-1:0] lsb,
    input ALU_Result_t     [IW-1:0]   cdb,
    input rob_entry_t      [NROB-1:0] rob,
    input logic [$clog2(NROB)-1:0]    rob_tail,
    input logic [IW-1:0]              commit_next
);
    default clocking cb @(posedge clk); endclocking
    default disable iff (rst || flush);

    // A1  Decoder: every valid instruction must be classified (OTHER is only legal for branches/jumps)
    //     -> catches the op-key aliasing bug (addi x1,x0,100 classified as OTHER)
    for (genvar i = 0; i < IW; i++) begin : g_a1
        a1_known_type: assert property (
            decode_reg[i].valid |-> (decode_reg[i].instr_type != 2'b11) || is_branch(decode_reg[i].operation))
            else $error("[SVA A1] slot %0d pc=%h op=%h decoded as OTHER", i, decode_reg[i].pc, decode_reg[i].operation);
    end

    // A2  Bundle shape: valid slots must be a contiguous prefix (ROB ids are ROB_head + slot)
    for (genvar i = 1; i < IW; i++) begin : g_a2
        a2_prefix: assert property (decode_reg[i].valid |-> decode_reg[i-1].valid)
            else $error("[SVA A2] decode slot %0d valid but slot %0d empty", i, i-1);
    end

    // A3  RS allocation: the slot picked at dispatch must be FREE when it is written
    //     -> catches the shadow free-list bug the cycle it happens (instead of a hang 200 cycles later)
    for (genvar d = 0; d < IW; d++) begin : g_a3
        a3_rs_free: assert property (
            (alloc_d1 && dispatch_reg[d].valid && dispatch_reg[d].rs_allocated) |->
              ((dispatch_reg[d].instr_type == 2'b00) ? !alu_rs[dispatch_reg[d].rs_index].busy :
               (dispatch_reg[d].instr_type == 2'b10) ? !md_rs [dispatch_reg[d].rs_index].busy :
               (dispatch_reg[d].instr_type == 2'b01) ? !lsb   [dispatch_reg[d].rs_index].busy : 1'b1))
            else $error("[SVA A3] slot %0d: RS/LSB entry %0d already busy -> instruction would be dropped",
                        d, dispatch_reg[d].rs_index);
    end

    // A4  CDB: a broadcast must target a live ROB entry that has NOT completed yet
    //     (duplicate / stale broadcasts = lost or doubled instructions)
    for (genvar c = 0; c < IW; c++) begin : g_a4
        a4_cdb_tag: assert property (
            cdb[c].result_ready |-> rob[cdb[c].ROB_index].valid && !rob[cdb[c].ROB_index].ready)
            else $error("[SVA A4] CDB lane %0d broadcast to ROB[%0d] valid=%0b ready=%0b", c,
                        cdb[c].ROB_index, rob[cdb[c].ROB_index].valid, rob[cdb[c].ROB_index].ready);
    end

    // A5  Liveness (bounded): the oldest instruction must retire within 64 cycles
    int unsigned stuck_cnt;
    always_ff @(posedge clk)
        if (rst || flush || !rob[rob_tail].valid || commit_next[0]) stuck_cnt <= 0;
        else stuck_cnt <= stuck_cnt + 1;
    a5_progress: assert property (stuck_cnt < 64)
        else $error("[SVA A5] ROB head %0d (pc=%h) has not retired for 64 cycles", rob_tail, rob[rob_tail].pc);
endmodule

// ----------------------------------------------------------------- ALU checks
module alu_sva import tomasulo_pkg::*; (input logic ex_valid, input ALU_Result_t alu_out,
                                        input AddSub_RS_Entry_t rs_in);
    // A6  An ALU that accepted an instruction (its RS entry is being freed) MUST produce a result
    //     -> catches missing OP-IMM operations (andi/ori/...), which silently vanished
    always_comb
        if (ex_valid) a6_alu_result: assert (alu_out.result_ready)
            else $error("[SVA A6] ALU accepted op %h (ROB %0d) but produced no result", rs_in.operation, rs_in.ROB_index);
endmodule

// ----------------------------------------------------------------- MMU checks
module mmu_sva import tomasulo_pkg::*; #(parameter int LQD = 8)
    (input logic clk, rst, flush, input lq_entry_t lq [LQD]);
    // A7  The load queue must never hold two live entries for the same ROB tag
    //     -> catches the LSB double-consume bug (same load enqueued twice)
    always_ff @(posedge clk)
        if (!rst && !flush)
            for (int i = 0; i < LQD; i++)
                for (int j = i + 1; j < LQD; j++)
                    a7_lq_unique: assert (!(lq[i].valid && lq[j].valid && lq[i].rob_tag == lq[j].rob_tag))
                        else $error("[SVA A7] LQ[%0d] and LQ[%0d] both hold ROB tag %0d", i, j, lq[i].rob_tag);
endmodule

bind alloc_reorder_retire core_sva #(.IW(ISSUE_WIDTH), .NROB(no_ROB), .NALU(no_RS_addsublog),
                                     .NMD(no_RS_muldiv), .NLSB(no_LoadStoreBuffer)) u_core_sva (
    .clk(clk), .rst(rst), .flush(flush), .decode_reg(decode_reg), .dispatch_reg(dispatch_reg),
    .alloc_d1(alloc_resources_available_d1), .alu_rs(alu_rs_out), .md_rs(muldiv_rs_out),
    .lsb(mem_rs_out), .cdb(cdb_results_in), .rob(rob_out), .rob_tail(ROB_tail),
    .commit_next(commit_valid_next));
bind alu_unit alu_sva u_alu_sva (.ex_valid(ex_valid), .alu_out(alu_out), .rs_in(rs_in));
bind memory_management_unit mmu_sva #(.LQD(LQ_DEPTH)) u_mmu_sva (.clk(clk), .rst(rst), .flush(flush), .lq(lq));

`endif
