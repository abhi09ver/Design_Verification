`timescale 1ns/1ps
// UNIT TEST: BTB replacement policy (tree pseudo-LRU, 4 ways)
// Fill one set with 4 branches (A,B,C,D), then insert 4 NEW branches (E,F,G,H)
// into the same set. A correct LRU-ish policy must spread victims over all 4 ways.
module tb_btb_plru;
    logic clk = 0, rst = 1; always #5 clk = ~clk;
    logic [31:0] fpc [3]; logic [31:0] tgt [3]; logic hit [3];
    logic upd; logic [31:0] upc, utgt;
    btb_predictor #(.BTB_SETS(64), .BTB_WAYS(4), .FETCH_WIDTH(3)) dut (
        .clk, .rst, .fetch_pc(fpc), .btb_target(tgt), .btb_hit(hit),
        .update_en(upd), .update_pc(upc), .update_target(utgt));
    // same set (index bits [7:2] = 0), different tags (bits [31:8])
    function automatic logic [31:0] pc_of(int k); return 32'h1000_0000 + (k << 8); endfunction
    int victims[4];
    initial begin
        fpc = '{default:32'hFFFF_FFF0}; upd = 0;
        repeat (2) @(posedge clk); rst = 0;
        for (int k = 0; k < 8; k++) begin
            @(negedge clk); upd = 1; upc = pc_of(k); utgt = 32'hAAAA_0000 + k;
            @(negedge clk); upd = 0;
            if (k == 3) begin   // after 4 fills all 4 ways must be in use (no eviction while a way is free)
                int used = 0; for (int w = 0; w < 4; w++) used += dut.btb_table[0][w].valid;
                $display("after filling 4 branches: %0d of 4 ways valid %s", used, used == 4 ? "" : "  <-- BUG: evicted while a way was free");
            end
            if (k >= 4) for (int w = 0; w < 4; w++)
                if (dut.btb_table[0][w].target == 32'hAAAA_0000 + k) begin
                    victims[w]++; $display("insert #%0d (tag %0d) -> way %0d   plru=%b", k, k, w, dut.plru[0]);
                end
        end
        $display("victim histogram over ways 0..3 = %0d %0d %0d %0d", victims[0], victims[1], victims[2], victims[3]);
        if (victims[2] + victims[3] == 0) $display("RESULT: BUG - ways 2/3 are NEVER replaced (root PLRU bit is never updated)");
        else $display("RESULT: OK");
        $finish;
    end
endmodule
