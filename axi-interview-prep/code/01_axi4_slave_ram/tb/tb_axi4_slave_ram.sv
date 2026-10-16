// =============================================================================
// tb_axi4_slave_ram.sv  -  self-checking testbench for axi4_slave_ram
//
// Companion code for cheat sheets 09 (write TB), 10 (read TB) and 11 (full env).
// Runs on free iverilog (-g2012). Structure mirrors a UVM env in plain tasks:
//
//   axi_write() / axi_read()   driver: AW and W forked, handshakes sampled at
//                              the clock edge, NBA drives, per-beat checks
//   model[] + tb_beat_addr()   reference model, written INDEPENDENTLY of the
//                              RTL next_addr() (shared logic hides shared bugs)
//   stability checkers         VALID held + payload stable while READY is low
//   directed tests             the read-after-write table from sheet 10
//   random test                N constrained-random bursts vs the model
//   end of test                $fatal on any error OR if nothing was checked
//
// Knobs:  +SEED=<n>  +NRAND=<n>  +BP (random READY back-pressure on B and R)
// =============================================================================
`timescale 1ns/1ps

module tb_axi4_slave_ram;
    localparam ADDR_W = 32, DATA_W = 32, ID_W = 4, DEPTH = 1024;
    localparam MEM_BYTES = DEPTH * 4;
    localparam FIXED = 2'b00, INCR = 2'b01, WRAP = 2'b10;
    localparam OKAY = 2'b00, SLVERR = 2'b10;

    // ---------------------------------------------------------------- clock
    reg ACLK = 0, ARESETn = 0;
    always #5 ACLK = ~ACLK;

    // ------------------------------------------------------------- signals
    reg  [ID_W-1:0]   AWID = 0;    reg [ADDR_W-1:0] AWADDR = 0;
    reg  [7:0]        AWLEN = 0;   reg [2:0] AWSIZE = 0;  reg [1:0] AWBURST = 0;
    reg               AWVALID = 0; wire AWREADY;
    reg  [DATA_W-1:0] WDATA = 0;   reg [3:0] WSTRB = 0;   reg WLAST = 0;
    reg               WVALID = 0;  wire WREADY;
    wire [ID_W-1:0]   BID;         wire [1:0] BRESP;      wire BVALID;
    reg               BREADY = 0;
    reg  [ID_W-1:0]   ARID = 0;    reg [ADDR_W-1:0] ARADDR = 0;
    reg  [7:0]        ARLEN = 0;   reg [2:0] ARSIZE = 0;  reg [1:0] ARBURST = 0;
    reg               ARVALID = 0; wire ARREADY;
    wire [ID_W-1:0]   RID;         wire [DATA_W-1:0] RDATA;
    wire [1:0]        RRESP;       wire RLAST, RVALID;
    reg               RREADY = 0;

    axi4_slave_ram #(.ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .DEPTH(DEPTH)) dut (.*);

    // ------------------------------------------------------- bookkeeping
    integer errors = 0, checks = 0;
    integer seed = 1, nrand = 300;
    reg     bp = 0;                                // random back-pressure

    task automatic fail(input [8*96-1:0] msg);
        begin errors = errors + 1; $display("[%0t] ERROR: %0s", $time, msg); end
    endtask

    // --------------------------------------------- reference model (bytes)
    reg [7:0] model [0:MEM_BYTES-1];
    integer m;
    initial for (m = 0; m < MEM_BYTES; m = m + 1) model[m] = 8'h00;

    // Beat address, written differently from the RTL on purpose
    function automatic [31:0] tb_beat_addr(input [31:0] start, input [7:0] len,
                                           input [2:0] size, input [1:0] burst,
                                           input integer n);
        reg [31:0] nb, aligned, win, lower, a;
        begin
            nb      = 32'd1 << size;
            aligned = (start / nb) * nb;
            case (burst)
                FIXED: tb_beat_addr = start;
                WRAP: begin
                    win   = nb * (len + 1);
                    lower = (start / win) * win;
                    a     = start + n * nb;
                    if (a >= lower + win) a = a - win;
                    tb_beat_addr = a;
                end
                default: tb_beat_addr = (n == 0) ? start : aligned + n * nb;
            endcase
        end
    endfunction

    function automatic [31:0] model_word(input [31:0] addr);
        reg [31:0] b;
        begin
            b = addr & ~32'h3;
            model_word = {model[b+3], model[b+2], model[b+1], model[b]};
        end
    endfunction

    // Active byte lanes of one beat (narrow / unaligned aware)
    function automatic [3:0] active_lanes(input [31:0] a, input [2:0] size);
        reg [31:0] nb, lo, hi; integer l;
        begin
            nb = 32'd1 << size;
            lo = a % 4;
            hi = ((a / nb) * nb) % 4 + nb - 1;
            active_lanes = 4'b0000;
            for (l = 0; l < 4; l = l + 1)
                if (l >= lo && l <= hi) active_lanes[l] = 1'b1;
        end
    endfunction

    // ------------------------------------------------ per-burst stimulus
    reg [31:0] wbuf [0:255];          // write data per beat
    reg [3:0]  sbuf [0:255];          // write strobes per beat
    reg [31:0] rbuf [0:255];          // captured read data per beat

    // ======================================================== DRIVER: write
    // skew > 0 raises WVALID that many cycles BEFORE AWVALID (legal W-first).
    task automatic axi_write(input [ID_W-1:0] id, input [31:0] addr, input [7:0] len,
                             input [2:0] size, input [1:0] burst, input integer skew,
                             input [1:0] exp_resp);
        integer i, b, delay; reg [31:0] a;
        begin
            fork
                begin : aw_ch
                    repeat (skew) @(posedge ACLK);
                    AWID <= id; AWADDR <= addr; AWLEN <= len;
                    AWSIZE <= size; AWBURST <= burst; AWVALID <= 1'b1;
                    @(posedge ACLK); while (!AWREADY) @(posedge ACLK);
                    AWVALID <= 1'b0;
                end
                begin : w_ch
                    for (i = 0; i <= len; i = i + 1) begin
                        WDATA <= wbuf[i]; WSTRB <= sbuf[i];
                        WLAST <= (i == len); WVALID <= 1'b1;
                        @(posedge ACLK); while (!WREADY) @(posedge ACLK);
                    end
                    WVALID <= 1'b0; WLAST <= 1'b0;
                end
            join
            delay = bp ? ($urandom % 5) : 0;
            repeat (delay) @(posedge ACLK);
            BREADY <= 1'b1;
            @(posedge ACLK); while (!BVALID) @(posedge ACLK);
            BREADY <= 1'b0;
            checks = checks + 1;
            if (BID !== id)        fail("BID does not match AWID");
            if (BRESP !== exp_resp) begin
                $display("        addr=%h burst=%0d len=%0d BRESP=%b exp=%b", addr, burst, len, BRESP, exp_resp);
                fail("BRESP mismatch");
            end
            // update the model only for accepted (OKAY) writes
            if (exp_resp == OKAY)
                for (i = 0; i <= len; i = i + 1) begin
                    a = tb_beat_addr(addr, len, size, burst, i);
                    for (b = 0; b < 4; b = b + 1)
                        if (sbuf[i][b]) model[(a & ~32'h3) + b] = wbuf[i][8*b +: 8];
                end
        end
    endtask

    // ========================================================= DRIVER: read
    task automatic axi_read(input [ID_W-1:0] id, input [31:0] addr, input [7:0] len,
                            input [2:0] size, input [1:0] burst, input [1:0] exp_resp);
        integer i; reg [31:0] a, exp_d;
        begin
            ARID <= id; ARADDR <= addr; ARLEN <= len;
            ARSIZE <= size; ARBURST <= burst; ARVALID <= 1'b1;
            @(posedge ACLK); while (!ARREADY) @(posedge ACLK);
            ARVALID <= 1'b0;
            for (i = 0; i <= len; i = i + 1) begin
                RREADY <= bp ? ($urandom % 2) : 1'b1;
                @(posedge ACLK);
                while (!(RVALID === 1'b1 && RREADY === 1'b1)) begin
                    RREADY <= bp ? ($urandom % 2) : 1'b1;
                    @(posedge ACLK);
                end
                rbuf[i] = RDATA;
                checks = checks + 1;
                if (RID !== id)            fail("RID does not match ARID");
                if (RRESP !== exp_resp)    fail("RRESP mismatch");
                if (RLAST !== (i == len))  fail("RLAST on wrong beat");
                if (exp_resp == OKAY) begin
                    a     = tb_beat_addr(addr, len, size, burst, i);
                    exp_d = model_word(a);
                    if (RDATA !== exp_d) begin
                        $display("        beat %0d addr=%h got=%h exp=%h", i, a, RDATA, exp_d);
                        fail("RDATA mismatch vs model");
                    end
                end
            end
            RREADY <= 1'b0;
        end
    endtask

    // ------------------------------------- protocol stability checkers (slave)
    reg        b_hold = 0, r_hold = 0;
    reg [1:0]  b_resp_q;
    reg [31:0] r_data_q; reg [1:0] r_resp_q; reg r_last_q;
    always @(posedge ACLK) if (ARESETn) begin
        if (b_hold && !(BVALID === 1'b1 && BRESP === b_resp_q))
            fail("BVALID dropped or BRESP changed while BREADY low");
        if (r_hold && !(RVALID === 1'b1 && RDATA === r_data_q && RRESP === r_resp_q && RLAST === r_last_q))
            fail("RVALID dropped or R payload changed while RREADY low");
        b_hold   <= BVALID && !BREADY;   b_resp_q <= BRESP;
        r_hold   <= RVALID && !RREADY;   r_data_q <= RDATA;
        r_resp_q <= RRESP;               r_last_q <= RLAST;
        // XOR-reduction is X if any bit is X/Z ($isunknown on a concatenation
        // is mis-evaluated by iverilog 12, so use the portable idiom)
        if ((^{AWREADY, WREADY, BVALID, ARREADY, RVALID}) === 1'bx)
            fail("X on slave handshake output after reset");
    end

    // ---------------------------------------------- expected-value helpers
    task automatic expect_rbuf(input integer n, input [31:0] v0, input [31:0] v1,
                               input [31:0] v2, input [31:0] v3, input [8*40-1:0] name);
        reg [31:0] v [0:3]; integer i;
        begin
            v[0] = v0; v[1] = v1; v[2] = v2; v[3] = v3;
            for (i = 0; i < n; i = i + 1) begin
                checks = checks + 1;
                if (rbuf[i] !== v[i]) begin
                    $display("        %0s beat %0d got=%h exp=%h", name, i, rbuf[i], v[i]);
                    fail("directed expected value mismatch");
                end
            end
        end
    endtask

    task automatic fill4(input [31:0] a, input [31:0] b, input [31:0] c, input [31:0] d);
        begin
            wbuf[0] = a; wbuf[1] = b; wbuf[2] = c; wbuf[3] = d;
            sbuf[0] = 4'hF; sbuf[1] = 4'hF; sbuf[2] = 4'hF; sbuf[3] = 4'hF;
        end
    endtask

    // ================================================================ TESTS
    integer t, i, len_i, nb, total;
    reg [31:0] addr; reg [7:0] len; reg [2:0] size; reg [1:0] burst;
    reg [3:0] lanes, st;

    initial begin
        if ($value$plusargs("SEED=%d", seed))  ; else seed = 1;
        if ($value$plusargs("NRAND=%d", nrand)) ; else nrand = 300;
        if ($test$plusargs("BP")) bp = 1;
        $display(" seed=%0d  random bursts=%0d  back-pressure=%0d", seed, nrand, bp);
        t = $urandom(seed);                     // seeds the generator
        $dumpfile("tb_axi4_slave_ram.vcd");
        $dumpvars(0, tb_axi4_slave_ram);

        repeat (5) @(posedge ACLK);
        ARESETn <= 1'b1;
        repeat (2) @(posedge ACLK);

        // T1 INCR 4 beats, read back
        fill4(1, 2, 3, 4);
        axi_write(1, 32'h10, 3, 3'd2, INCR, 0, OKAY);
        axi_read (1, 32'h10, 3, 3'd2, INCR, OKAY);
        expect_rbuf(4, 1, 2, 3, 4, "T1 INCR");

        // T2 write WRAP from 0x38, read INCR from 0x30 -> C D A B
        fill4(32'hA, 32'hB, 32'hC, 32'hD);
        axi_write(2, 32'h38, 3, 3'd2, WRAP, 0, OKAY);
        axi_read (2, 32'h30, 3, 3'd2, INCR, OKAY);
        expect_rbuf(4, 32'hC, 32'hD, 32'hA, 32'hB, "T2 WRAP->INCR");

        // T3 write INCR from 0x30, read WRAP from 0x38 -> R S P Q
        fill4(32'h50, 32'h51, 32'h52, 32'h53);           // P Q R S
        axi_write(3, 32'h30, 3, 3'd2, INCR, 0, OKAY);
        axi_read (3, 32'h38, 3, 3'd2, WRAP, OKAY);
        expect_rbuf(4, 32'h52, 32'h53, 32'h50, 32'h51, "T3 INCR->WRAP");

        // T4 FIXED 3 beats to 0x40 -> last one wins
        fill4(32'h1111, 32'h2222, 32'h3333, 0);
        axi_write(4, 32'h40, 2, 3'd2, FIXED, 0, OKAY);
        axi_read (4, 32'h40, 2, 3'd2, FIXED, OKAY);
        expect_rbuf(3, 32'h3333, 32'h3333, 32'h3333, 0, "T4 FIXED");

        // T5 partial strobe merge -> 0x11BB33DD
        wbuf[0] = 32'h11223344; sbuf[0] = 4'hF;
        axi_write(5, 32'h20, 0, 3'd2, INCR, 0, OKAY);
        wbuf[0] = 32'hAABBCCDD; sbuf[0] = 4'b0101;
        axi_write(5, 32'h20, 0, 3'd2, INCR, 0, OKAY);
        axi_read (5, 32'h20, 0, 3'd2, INCR, OKAY);
        expect_rbuf(1, 32'h11BB33DD, 0, 0, 0, "T5 WSTRB merge");

        // T6 unaligned start 0x51, 2 beats: strobes 1110 then 1111
        wbuf[0] = 32'hA1A2A3A4; sbuf[0] = 4'b1110;
        wbuf[1] = 32'hB1B2B3B4; sbuf[1] = 4'b1111;
        axi_write(6, 32'h51, 1, 3'd2, INCR, 0, OKAY);
        axi_read (6, 32'h50, 1, 3'd2, INCR, OKAY);
        expect_rbuf(2, 32'hA1A2A300, 32'hB1B2B3B4, 0, 0, "T6 unaligned");

        // T7 narrow: 1-byte beats INCR from 0x60, lanes walk 0..3
        wbuf[0] = 32'h000000E0; sbuf[0] = 4'b0001;
        wbuf[1] = 32'h0000E100; sbuf[1] = 4'b0010;
        wbuf[2] = 32'h00E20000; sbuf[2] = 4'b0100;
        wbuf[3] = 32'hE3000000; sbuf[3] = 4'b1000;
        axi_write(7, 32'h60, 3, 3'd0, INCR, 0, OKAY);
        axi_read (7, 32'h60, 0, 3'd2, INCR, OKAY);
        expect_rbuf(1, 32'hE3E2E1E0, 0, 0, 0, "T7 narrow");

        // T8 W before AW (legal for a master): WVALID 3 cycles early
        fill4(32'hFEED0001, 0, 0, 0);
        axi_write(8, 32'h80, 0, 3'd2, INCR, 3, OKAY);
        axi_read (8, 32'h80, 0, 3'd2, INCR, OKAY);
        expect_rbuf(1, 32'hFEED0001, 0, 0, 0, "T8 W-first");

        // T9 out of range -> SLVERR, model untouched
        fill4(32'hDEADBEEF, 0, 0, 0);
        axi_write(9, MEM_BYTES, 0, 3'd2, INCR, 0, SLVERR);
        axi_read (9, MEM_BYTES, 0, 3'd2, INCR, SLVERR);
        axi_read (9, 32'h0, 0, 3'd2, INCR, OKAY);        // word 0 not aliased

        // T10 16-beat INCR with back-pressure on B and R
        bp = 1;
        for (i = 0; i < 16; i = i + 1) begin wbuf[i] = 32'hC0DE0000 + i; sbuf[i] = 4'hF; end
        axi_write(10, 32'h100, 15, 3'd2, INCR, 0, OKAY);
        axi_read (10, 32'h100, 15, 3'd2, INCR, OKAY);
        if (!$test$plusargs("BP")) bp = 0;

        // T11 read and write at the same time (independent FSMs)
        for (i = 0; i < 8; i = i + 1) begin wbuf[i] = 32'h77770000 + i; sbuf[i] = 4'hF; end
        fork
            axi_write(11, 32'h200, 7, 3'd2, INCR, 0, OKAY);
            axi_read (12, 32'h100, 7, 3'd2, INCR, OKAY);
        join

        // T12 constrained-random bursts checked against the model
        for (t = 0; t < nrand; t = t + 1) begin
            burst = $urandom % 3;
            size  = $urandom % 3;                 // 1, 2 or 4 bytes
            nb    = 1 << size;
            case (burst)
                WRAP:  len = (8'd1 << (1 + $urandom % 4)) - 1;      // 1,3,7,15
                FIXED: len = $urandom % 16;
                default: len = ($urandom % 4 == 0) ? ($urandom % 256) : ($urandom % 16);
            endcase
            addr = $urandom % MEM_BYTES;
            if (burst == WRAP) addr = (addr / nb) * nb;
            if (burst == INCR) begin                // stay inside memory (= one 4 KB page)
                total = (len + 1) * nb - (addr % nb);
                while (addr + total > MEM_BYTES) begin
                    len = len / 2;
                    total = (len + 1) * nb - (addr % nb);
                end
            end
            for (i = 0; i <= len; i = i + 1) begin
                lanes   = active_lanes(tb_beat_addr(addr, len, size, burst, i), size);
                st      = ($urandom % 4 == 0) ? ($urandom % 16) : 4'hF;
                sbuf[i] = lanes & st;
                wbuf[i] = $urandom;
            end
            if ($urandom % 2)
                axi_write($urandom % 16, addr, len, size, burst, $urandom % 3, OKAY);
            else
                axi_read ($urandom % 16, addr, len, size, burst, OKAY);
        end

        // ------------------------------------------------------- verdict
        repeat (5) @(posedge ACLK);
        $display("==================================================");
        $display(" checks=%0d  errors=%0d", checks, errors);
        if (errors == 0 && checks > 0) $display(" *** TEST PASSED ***");
        else begin
            $display(" *** TEST FAILED ***");
            $fatal(1, "testbench detected errors");
        end
        $display("==================================================");
        $finish;
    end

    initial begin #20_000_000; $fatal(1, "TIMEOUT - possible deadlock"); end
endmodule
