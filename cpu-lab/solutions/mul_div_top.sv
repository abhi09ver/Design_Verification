`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Fast Mul/Div Top Module
// This module immediately dispatches operations and clears RS entries,
// using ROB for completion tracking instead of keeping RS entries busy.
// -----------------------------------------------------------------------------

`include "mul_div.sv"
`include "fetch_pkg.sv"
`include "decoder_pkg.sv"
`include "tomasulo_pkg.sv"

import tomasulo_pkg::*;

module muldiv_top (
    input  logic clk,    // Clock
    input  logic rst,    // Reset (active high)
    input  logic flush,  // Pipeline flush
    input  logic stall,  // Stall from completion buffer
    input  MulDiv_RS_Entry_t [no_RS_muldiv-1:0] muldiv_rs_in, // Mul/Div reservation stations
    output ALU_Result_t [2*no_MulDiv_units-1:0] muldiv_out,   // Mul/Div results (2 per unit: mul + div)
    output logic [no_RS_muldiv-1:0] rs_clear                    // RS deallocation signals
);

    // Input to each muldiv unit (separate for multiply and divide slots)
    MulDiv_RS_Entry_t muldiv_in_mul[no_MulDiv_units];
    MulDiv_RS_Entry_t muldiv_in_div[no_MulDiv_units];
    
    // Valid signals for each muldiv unit (separate for multiply and divide)
    logic [no_MulDiv_units-1:0] muldiv_ex_valid_mul;
    logic [no_MulDiv_units-1:0] muldiv_ex_valid_div;
    
    // Loop variables for dispatch logic
    int muldiv, muldiv_rst, muldiv_ex, muldiv_rs_idx;
    int muldiv_min_rob, muldiv_min_idx, muldiv_rs, slot_idx;
    
    // Tracks which RS entries have been allocated this cycle
    logic [no_RS_muldiv-1:0] muldiv_allocated_this_cycle;

    // Arrays for dual-issue interface (declared outside generate block)
    MulDiv_RS_Entry_t muldiv_rs_in_array [no_MulDiv_units][2];
    logic muldiv_ex_valid_array [no_MulDiv_units][2];
    ALU_Result_t muldiv_out_array [no_MulDiv_units][2];

    // -------------------------------------------------------------------------
    // Fast Dispatch Logic: Combinational dispatch for zero-cycle latency
    // Priority is given to the lowest ROB index (oldest instruction)
    // -------------------------------------------------------------------------
    // FIX-5: issue/select rewritten.
    //  Original bug: the DIVIDE search loop ran for EVERY slot (it sat outside the
    //  'even slot' if), and wrote muldiv_in_div[slot_idx/2]. Slots 0 and 1 both map to
    //  unit 0, so a 2nd ready DIV overwrote the 1st one - whose RS entry had already been
    //  cleared (rs_clear) -> instruction silently lost -> ROB deadlock.
    //  Also only mul/mulh/div/rem were ever selected: mulhsu/mulhu/divu/remu sat in the
    //  RS forever.
    //  New structure: one MUL port + one DIV port per unit, each picks the OLDEST ready
    //  candidate of its class that nobody else picked this cycle.
    function automatic logic is_mul_class(input logic [16:0] op);
        return (op == mul) || (op == mulh) || (op == mulhsu) || (op == mulhu);
    endfunction
    function automatic logic is_div_class(input logic [16:0] op);
        return (op == div) || (op == divu) || (op == rem) || (op == remu);
    endfunction

    always_comb begin
        for (muldiv = 0; muldiv < no_MulDiv_units; muldiv++) begin
            muldiv_in_mul[muldiv] = '{default: '0};
            muldiv_in_div[muldiv] = '{default: '0};
        end
        muldiv_ex_valid_mul = '0;
        muldiv_ex_valid_div = '0;
        rs_clear = '0;
        muldiv_allocated_this_cycle = '0;
        if (!(rst || flush) && !stall) begin
            for (slot_idx = 0; slot_idx < 2*no_MulDiv_units; slot_idx++) begin
                muldiv_min_rob = {32{1'b1}};
                muldiv_min_idx = -1;
                for (muldiv_rs = 0; muldiv_rs < no_RS_muldiv; muldiv_rs++) begin
                    if (muldiv_rs_in[muldiv_rs].busy && muldiv_rs_in[muldiv_rs].ready &&
                        !muldiv_allocated_this_cycle[muldiv_rs] &&
                        (slot_idx[0] ? is_div_class(muldiv_rs_in[muldiv_rs].operation)
                                     : is_mul_class(muldiv_rs_in[muldiv_rs].operation)) &&
                        muldiv_rs_in[muldiv_rs].ROB_index < muldiv_min_rob) begin
                        // NOTE: raw ROB_index compare is NOT true age once the ROB wraps.
                        // It only affects fairness here (not correctness) - see course module 5.
                        muldiv_min_rob = muldiv_rs_in[muldiv_rs].ROB_index;
                        muldiv_min_idx = muldiv_rs;
                    end
                end
                if (muldiv_min_idx != -1) begin
                    if (slot_idx[0]) begin
                        muldiv_in_div[slot_idx/2]       = muldiv_rs_in[muldiv_min_idx];
                        muldiv_ex_valid_div[slot_idx/2] = 1'b1;
                    end else begin
                        muldiv_in_mul[slot_idx/2]       = muldiv_rs_in[muldiv_min_idx];
                        muldiv_ex_valid_mul[slot_idx/2] = 1'b1;
                    end
                    muldiv_allocated_this_cycle[muldiv_min_idx] = 1'b1;
                    rs_clear[muldiv_min_idx] = 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // MulDiv Unit Instantiation
    // Each muldiv_unit has both multiply and divide units internally
    // Slots 0,2 = multiply operations, Slots 1,3 = divide operations
    // -------------------------------------------------------------------------
    genvar muldiv_idx;
    generate
        for (muldiv_idx = 0; muldiv_idx < no_MulDiv_units; muldiv_idx++) begin : muldiv_units
            // Connect multiply and divide operations to the unit
            assign muldiv_rs_in_array[muldiv_idx][0] = muldiv_in_mul[muldiv_idx];     // Multiply slot
            assign muldiv_rs_in_array[muldiv_idx][1] = muldiv_in_div[muldiv_idx];     // Divide slot
            assign muldiv_ex_valid_array[muldiv_idx][0] = muldiv_ex_valid_mul[muldiv_idx]; // Multiply slot valid
            assign muldiv_ex_valid_array[muldiv_idx][1] = muldiv_ex_valid_div[muldiv_idx]; // Divide slot valid
            
            // Connect outputs: even indices = multiply, odd indices = divide
            assign muldiv_out[2*muldiv_idx] = muldiv_out_array[muldiv_idx][0];     // Multiply output (slot 0,2)
            assign muldiv_out[2*muldiv_idx+1] = muldiv_out_array[muldiv_idx][1];   // Divide output (slot 1,3)
            
            muldiv_unit muldiv_inst (
                .clk(clk),
                .rst(rst),
                .flush(flush),
                .rs_in(muldiv_rs_in_array[muldiv_idx]),
                .ex_valid(muldiv_ex_valid_array[muldiv_idx]),
                .out(muldiv_out_array[muldiv_idx])
            );
            // Print results from each muldiv unit
            always @(posedge clk) begin
                // Print statements removed
            end
        end
    endgenerate

endmodule