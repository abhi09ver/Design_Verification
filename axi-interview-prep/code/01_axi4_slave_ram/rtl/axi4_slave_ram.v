// =============================================================================
// axi4_slave_ram.v  -  AXI4 (full) slave RAM with FIXED / INCR / WRAP bursts
//
// Companion code for cheat sheet 08 (axi-slave-ram-verilog).
//
// Design choices (each one is an interview talking point):
//   * Separate write and read FSMs  -> a read and a write can run concurrently.
//   * One transaction in flight per direction -> always in-order, no ID queues.
//   * Write FSM waits for AW before raising WREADY. Legal for a slave; the
//     master must NOT wait for WREADY before raising AWVALID.
//   * AW / AR fields are latched at the handshake; never use AW* after it.
//   * Address of beat 2+ is ALIGNED start + 2^SIZE (handles unaligned starts).
//   * WSTRB is a per-byte write enable.
//   * Out-of-range beat or reserved burst type (2'b11) -> SLVERR. All LEN+1
//     beats are still transferred; the burst is never cut short.
//   * RDATA is driven from the current read address, which only moves on an
//     R handshake, so RDATA/RRESP/RLAST stay stable while RREADY is low.
//
// Mutation hooks: compile with -DBUG_IGNORE_WSTRB, -DBUG_WRAP_AS_INCR or
// -DBUG_RLAST_EARLY to plant a bug and prove the testbench catches it
// (make mutants). A checker you have never seen fail is not a checker.
// =============================================================================
`timescale 1ns/1ps

module axi4_slave_ram #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32,
    parameter ID_W   = 4,
    parameter DEPTH  = 1024                 // words
)(
    input  wire                ACLK,
    input  wire                ARESETn,
    // write address
    input  wire [ID_W-1:0]     AWID,
    input  wire [ADDR_W-1:0]   AWADDR,
    input  wire [7:0]          AWLEN,
    input  wire [2:0]          AWSIZE,
    input  wire [1:0]          AWBURST,
    input  wire                AWVALID,
    output wire                AWREADY,
    // write data
    input  wire [DATA_W-1:0]   WDATA,
    input  wire [DATA_W/8-1:0] WSTRB,
    input  wire                WLAST,
    input  wire                WVALID,
    output wire                WREADY,
    // write response
    output wire [ID_W-1:0]     BID,
    output wire [1:0]          BRESP,
    output wire                BVALID,
    input  wire                BREADY,
    // read address
    input  wire [ID_W-1:0]     ARID,
    input  wire [ADDR_W-1:0]   ARADDR,
    input  wire [7:0]          ARLEN,
    input  wire [2:0]          ARSIZE,
    input  wire [1:0]          ARBURST,
    input  wire                ARVALID,
    output wire                ARREADY,
    // read data
    output wire [ID_W-1:0]     RID,
    output wire [DATA_W-1:0]   RDATA,
    output wire [1:0]          RRESP,
    output wire                RLAST,
    output wire                RVALID,
    input  wire                RREADY
);
    localparam STRB_W   = DATA_W / 8;
    localparam ADDR_LSB = $clog2(STRB_W);
    localparam OKAY = 2'b00, SLVERR = 2'b10;

    reg [DATA_W-1:0] mem [0:DEPTH-1];
    integer k;
    initial for (k = 0; k < DEPTH; k = k + 1) mem[k] = {DATA_W{1'b0}};

    // ---------------------------------------------------------------------
    // Next beat address for FIXED / INCR / WRAP
    // ---------------------------------------------------------------------
    function [ADDR_W-1:0] next_addr;
        input [ADDR_W-1:0] a;
        input [7:0]        len;
        input [2:0]        size;
        input [1:0]        burst;
        reg   [ADDR_W-1:0] nb, win, inc;
        begin
            nb  = {{(ADDR_W-1){1'b0}}, 1'b1} << size;
            inc = (a & ~(nb - 1)) + nb;          // align, then step
            win = nb * (len + 1);                // WRAP window (power of 2)
            case (burst)
                2'b00:   next_addr = a;                                   // FIXED
`ifdef BUG_WRAP_AS_INCR
                2'b10:   next_addr = inc;                         // planted bug
`else
                2'b10:   next_addr = (a & ~(win - 1)) | (inc & (win - 1)); // WRAP
`endif
                default: next_addr = inc;                                 // INCR
            endcase
        end
    endfunction

    function in_range;
        input [ADDR_W-1:0] a;
        in_range = ((a >> ADDR_LSB) < DEPTH);
    endfunction

    // =====================================================================
    // Write channel: W_IDLE -> W_DATA -> W_RESP
    // =====================================================================
    localparam W_IDLE = 2'd0, W_DATA = 2'd1, W_RESP = 2'd2;
    reg [1:0]        wstate;
    reg [ID_W-1:0]   aw_id;
    reg [ADDR_W-1:0] w_addr;
    reg [7:0]        aw_len;
    reg [2:0]        aw_size;
    reg [1:0]        aw_burst;
    reg              w_err;
    integer          i;
    wire [ADDR_W-1:0] w_idx = w_addr >> ADDR_LSB;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            wstate <= W_IDLE;
            w_err  <= 1'b0;
        end else begin
            case (wstate)
                W_IDLE: if (AWVALID) begin               // AWREADY = 1 here
                    aw_id    <= AWID;    w_addr  <= AWADDR;
                    aw_len   <= AWLEN;   aw_size <= AWSIZE;
                    aw_burst <= AWBURST;
                    w_err    <= (AWBURST == 2'b11);
                    wstate   <= W_DATA;
                end
                W_DATA: if (WVALID) begin                // WREADY = 1 here
                    if (in_range(w_addr)) begin
                        for (i = 0; i < STRB_W; i = i + 1)
`ifdef BUG_IGNORE_WSTRB
                            mem[w_idx][8*i +: 8] <= WDATA[8*i +: 8];
`else
                            if (WSTRB[i]) mem[w_idx][8*i +: 8] <= WDATA[8*i +: 8];
`endif
                    end else
                        w_err <= 1'b1;
                    w_addr <= next_addr(w_addr, aw_len, aw_size, aw_burst);
                    if (WLAST) wstate <= W_RESP;
                end
                W_RESP: if (BREADY) wstate <= W_IDLE;    // BVALID = 1 here
                default: wstate <= W_IDLE;
            endcase
        end
    end

    assign AWREADY = (wstate == W_IDLE);
    assign WREADY  = (wstate == W_DATA);
    assign BVALID  = (wstate == W_RESP);
    assign BID     = aw_id;
    assign BRESP   = w_err ? SLVERR : OKAY;

    // =====================================================================
    // Read channel: R_IDLE -> R_DATA
    // =====================================================================
    localparam R_IDLE = 1'b0, R_DATA = 1'b1;
    reg              rstate;
    reg [ID_W-1:0]   ar_id;
    reg [ADDR_W-1:0] r_addr;
    reg [7:0]        ar_len, r_cnt;
    reg [2:0]        ar_size;
    reg [1:0]        ar_burst;
    wire [ADDR_W-1:0] r_idx = r_addr >> ADDR_LSB;
    wire              r_ok  = in_range(r_addr) && (ar_burst != 2'b11);

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rstate <= R_IDLE;
            r_cnt  <= 8'd0;
        end else begin
            case (rstate)
                R_IDLE: if (ARVALID) begin               // ARREADY = 1 here
                    ar_id    <= ARID;    r_addr  <= ARADDR;
                    ar_len   <= ARLEN;   ar_size <= ARSIZE;
                    ar_burst <= ARBURST; r_cnt   <= 8'd0;
                    rstate   <= R_DATA;
                end
                R_DATA: if (RREADY) begin                // RVALID = 1 here
                    r_addr <= next_addr(r_addr, ar_len, ar_size, ar_burst);
                    r_cnt  <= r_cnt + 8'd1;
                    if (RLAST) rstate <= R_IDLE;
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

    assign ARREADY = (rstate == R_IDLE);
    assign RVALID  = (rstate == R_DATA);
    assign RID     = ar_id;
    assign RDATA   = r_ok ? mem[r_idx] : {DATA_W{1'b0}};
    assign RRESP   = r_ok ? OKAY : SLVERR;
`ifdef BUG_RLAST_EARLY
    assign RLAST   = (r_cnt + 8'd1 == ar_len);            // planted off-by-one
`else
    assign RLAST   = (r_cnt == ar_len);
`endif

endmodule
