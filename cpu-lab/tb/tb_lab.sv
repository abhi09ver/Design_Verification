`timescale 1ns/1ps
// =============================================================================
// tb_lab : self-checking-ready lab testbench for the Tomasulo core
// -----------------------------------------------------------------------------
//  * Loads any program with +PROG=<hex file>     (default = built-in program)
//  * Prints a COMMIT TRACE (pc, rd, value) for every retired instruction
//  * Watchdog: declares HANG if nothing retires for HANG_CYCLES cycles
//  * At the end dumps ARF + first 64 data-memory words
//  The python script tools/run_test.py compares all of this against a golden ISS.
//  This is the same pattern real CPU DV teams use: "commit-trace vs ISS".
// =============================================================================
module tb_lab;
    import fetch_types_pkg::*;
    import decoder_pkg::*;
    import tomasulo_pkg::*;

    localparam int ISSUE_WIDTH = 3;
    localparam int NO_INSTR    = 33;
    localparam int HANG_CYCLES = 200;
    localparam int MAX_CYCLES  = 3000;

    logic clk, rst, flush;
    logic [31:0] pc_in;
    logic update_en, update_taken;
    logic [31:0] update_pc, update_target;

    // ---------------------------------------------------------------- DUT
    top_module #(
        .ISSUE_WIDTH(ISSUE_WIDTH), .CDB_WIDTH(3), .no_ARF(32), .no_RAT(32),
        .no_instr(NO_INSTR), .no_RS_addsublog(12), .no_RS_muldiv(4),
        .no_LoadStoreBuffer(16), .no_ALU_units(3), .no_MulDiv_units(2),
        .no_ROB(48), .NUM_LD_PORTS(2), .NUM_ST_PORTS(1), .IQ_DEPTH(16),
        .INSTRUCTION_MEMORY_SIZE(64), .BTB_SETS(64), .BTB_WAYS(4),
        .GSHARE_TABLE_BITS(10), .RAS_DEPTH(16), .BPQ_DEPTH(16),
        .LQ_DEPTH(8), .SQ_DEPTH(8), .MEM_DEPTH(1024), .DATA_WIDTH(32),
        .ADDR_WIDTH(32), .SAFETY_MARGIN(5)
    ) dut (
        .clk(clk), .rst(rst), .flush(flush), .pc_in(pc_in),
        .fetch_stall(), .alloc_stall(), .decode_reg(), .dec_rdy(), .decoder_error(),
        .update_en(update_en), .update_pc(update_pc), .update_taken(update_taken),
        .update_target(update_target), .predicted_pc(), .predict_valid(),
        .ras_sp_out(), .bpq_count_out(), .debug_pc(), .debug_cycle_count(),
        .init_done(), .init_done_pulse(), .fetch_stage_stall(), .decode_stage_stall(),
        .dispatch_stage_stall(), .instruction_queue_full(), .instruction_queue_empty(),
        .instruction_queue_count(), .commit_valid(), .commit_rob_id(), .commit_id_0(),
        .commit_id_1(), .commit_id_2(), .rob_out(), .violation_detected(),
        .violation_rob_index(), .violation_pc()
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------- commit monitor
    // Sample at negedge: commit_valid_next / retire_info_current are the
    // combinational "what retires at the coming posedge" signals.
    int commits, cyc, last_commit_cyc;
    bit started;
    always @(negedge clk) begin
        if (!rst) begin
            cyc++;
            for (int i = 0; i < ISSUE_WIDTH; i++) begin
                if (dut.tomasulo_core.commit_valid_next[i]) begin
                    automatic int id = dut.tomasulo_core.commit_rob_id_next[i];
                    $display("COMMIT cyc=%0d slot=%0d rob=%0d pc=%08h rd=%0d val=%08h",
                             cyc, i, id, dut.tomasulo_core.ROB[id].pc,
                             dut.tomasulo_core.ROB[id].dest,
                             dut.tomasulo_core.retire_info_current[i].result);
                    commits++;
                    last_commit_cyc = cyc;
                end
            end
        end
    end

    // ------------------------------------------------------------ +TRACE : per-cycle machine state
    //  One "TR" line per structure per cycle (sampled at negedge = stable state for this cycle).
    //  tools/trace2json.py turns this into the data for the course's cycle stepper.
    bit trace_on;
    initial trace_on = $test$plusargs("TRACE");
    always @(negedge clk) if (trace_on && !rst && cyc <= 60) begin
        for (int e = 0; e < 48; e++)
            if (dut.tomasulo_core.ROB[e].valid)
                $display("TR %0d ROB %0d %08h %0b %0d %08h", cyc, e, dut.tomasulo_core.ROB[e].pc,
                         dut.tomasulo_core.ROB[e].ready, dut.tomasulo_core.ROB[e].dest, dut.tomasulo_core.ROB[e].value);
        for (int r = 1; r < 32; r++)
            if (dut.tomasulo_core.RAT_valid[r])
                $display("TR %0d RAT %0d %0d", cyc, r, dut.tomasulo_core.RAT_tag[r]);
        for (int k = 0; k < 12; k++) if (dut.tomasulo_core.AS_RS[k].busy)
            $display("TR %0d RS ALU %0d %0d %0b %0b %0d %0b %0d", cyc, k, dut.tomasulo_core.AS_RS[k].ROB_index,
                     dut.tomasulo_core.AS_RS[k].ready, dut.tomasulo_core.AS_RS[k].src1_valid, dut.tomasulo_core.AS_RS[k].src1_tag,
                     dut.tomasulo_core.AS_RS[k].src2_valid, dut.tomasulo_core.AS_RS[k].src2_tag);
        for (int k = 0; k < 4; k++) if (dut.tomasulo_core.MD_RS[k].busy)
            $display("TR %0d RS MD %0d %0d %0b %0b %0d %0b %0d", cyc, k, dut.tomasulo_core.MD_RS[k].ROB_index,
                     dut.tomasulo_core.MD_RS[k].ready, dut.tomasulo_core.MD_RS[k].src1_valid, dut.tomasulo_core.MD_RS[k].src1_tag,
                     dut.tomasulo_core.MD_RS[k].src2_valid, dut.tomasulo_core.MD_RS[k].src2_tag);
        for (int k = 0; k < 16; k++) if (dut.tomasulo_core.LS_buffer[k].busy)
            $display("TR %0d RS LSB %0d %0d %0b %0b %0d %0b %0d", cyc, k, dut.tomasulo_core.LS_buffer[k].ROB_index,
                     dut.tomasulo_core.LS_buffer[k].ready, dut.tomasulo_core.LS_buffer[k].src_valid, dut.tomasulo_core.LS_buffer[k].src_tag,
                     dut.tomasulo_core.LS_buffer[k].store_data_valid, dut.tomasulo_core.LS_buffer[k].store_data_tag);
        for (int c = 0; c < 3; c++) if (dut.tomasulo_core.cdb_results_in[c].result_ready)
            $display("TR %0d CDB %0d %0d %08h", cyc, c, dut.tomasulo_core.cdb_results_in[c].ROB_index,
                     dut.tomasulo_core.cdb_results_in[c].result);
        for (int d = 0; d < 3; d++) if (dut.tomasulo_core.decode_reg[d].valid)
            $display("TR %0d DEC %0d %08h", cyc, d, dut.tomasulo_core.decode_reg[d].pc);
        $display("TR %0d PTR %0d %0d %0b", cyc, dut.tomasulo_core.ROB_tail, dut.tomasulo_core.ROB_head,
                 dut.tomasulo_core.alloc_stall);
    end

    task automatic dump_state(string why);
        $display("STATUS %s cycles=%0d commits=%0d", why, cyc, commits);
        for (int r = 0; r < 32; r++) $display("ARF x%0d=%08h", r, dut.tomasulo_core.ARF[r]);
        for (int m = 0; m < 64; m++) $display("MEM %0d=%08h", m, dut.mem_subsystem.dmem.mem[m]);
        if (why != "DONE") begin
            $display("---- ROB entries still valid (the 'who is stuck' view) ----");
            for (int e = 0; e < 48; e++)
                if (dut.tomasulo_core.ROB[e].valid)
                    $display("STUCK rob=%0d pc=%08h ready=%0b dest=x%0d", e,
                             dut.tomasulo_core.ROB[e].pc, dut.tomasulo_core.ROB[e].ready,
                             dut.tomasulo_core.ROB[e].dest);
            $display("ROB tail(commit ptr)=%0d head(alloc ptr)=%0d",
                     dut.tomasulo_core.ROB_tail, dut.tomasulo_core.ROB_head);
        end
    endtask

    initial begin
        rst = 1; flush = 0; pc_in = 0;
        update_en = 0; update_pc = 0; update_taken = 0; update_target = 0;
        // silence the design's own verbose prints + hard-coded checker
        dut.tomasulo_core.debug_print    = $test$plusargs("DEBUG");
        dut.tomasulo_core.result_checker = 1'b0;
        dut.mem_subsystem.mmu.mmu_debug  = $test$plusargs("MMUDBG");
        #20 rst = 0;
        forever begin
            @(posedge clk);
            // let the pipeline drain a few cycles after the last commit
            if (commits >= NO_INSTR && cyc > last_commit_cyc + 5) begin dump_state("DONE"); $finish; end
            if (cyc > 20 && cyc - last_commit_cyc > HANG_CYCLES) begin dump_state("HANG"); $finish; end
            if (cyc > MAX_CYCLES) begin dump_state("TIMEOUT"); $finish; end
        end
    end
endmodule
