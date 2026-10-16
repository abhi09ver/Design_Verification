// tb_smmu_queue_ptr.sv
// Random push/pop test with a reference count model. Runs on free Verilator:
//   $ verilator --binary --assert --timing -Wno-fatal sv/tb_smmu_queue_ptr.sv sv/smmu_queue_ptr.sv
//   $ ./obj_dir/Vtb_smmu_queue_ptr
`timescale 1ns/1ps
module tb_smmu_queue_ptr;
  localparam int LOG2SIZE = 3;
  localparam int SIZE = 1 << LOG2SIZE;

  logic clk = 0, rst_n = 0, push = 0, pop = 0;
  logic [LOG2SIZE:0] prod, cons;
  logic full, empty, ovflg;

  smmu_queue_ptr #(.LOG2SIZE(LOG2SIZE)) dut (.*);

  always #5 clk = ~clk;

  int model_count = 0;
  int errors = 0, saw_full = 0, saw_overflow = 0, saw_wrap = 0;

  // Reference model: plain occupancy counter. Checks DUT flags every cycle.
  always @(posedge clk) if (rst_n) begin
    automatic bit do_push = push && (model_count < SIZE);
    automatic bit do_pop  = pop  && (model_count > 0);
    if (full  != (model_count == SIZE)) begin errors++; $error("full mismatch count=%0d", model_count); end
    if (empty != (model_count == 0))    begin errors++; $error("empty mismatch count=%0d", model_count); end
    if (full) saw_full++;
    if (push && full) saw_overflow++;
    if (prod[LOG2SIZE]) saw_wrap++;
    model_count += int'(do_push) - int'(do_pop);
  end

  initial begin
    repeat (2) @(posedge clk);
    rst_n = 1;
    // Phase 1: bias to pushes so the queue fills and overflows.
    repeat (300) begin
      @(negedge clk);
      push = ($urandom_range(0, 9) < 8);
      pop  = ($urandom_range(0, 9) < 3);
    end
    // Phase 2: bias to pops so it drains and the wrap bit flips back.
    repeat (300) begin
      @(negedge clk);
      push = ($urandom_range(0, 9) < 3);
      pop  = ($urandom_range(0, 9) < 8);
    end
    @(negedge clk); push = 0; pop = 0;
    repeat (2) @(posedge clk);
    $display("cycles_full=%0d overflow_attempts=%0d wrapped_cycles=%0d errors=%0d",
             saw_full, saw_overflow, saw_wrap, errors);
    if (errors == 0 && saw_full > 0 && saw_overflow > 0 && saw_wrap > 0)
      $display("TEST PASSED");
    else
      $display("TEST FAILED");
    $finish;
  end
endmodule
