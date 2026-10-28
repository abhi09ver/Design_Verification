// tb_periph_demo.sv -- Lab 11: two short directed scenes, printed cycle by cycle for the notes' GIF.
//   UV lines: one UART character 0x5A, 8 data bits, even parity, 1 stop, divisor 1, internal loopback
//   PV lines: book Example 20.3 on the PLIC (GPIO id 3 priority 5, UART id 10 priority 4, threshold 2)
`timescale 1ns/1ps
module tb_periph_demo;
  logic clk = 0, reset = 1;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  logic        PSEL = 0, PENABLE = 0, PWRITE = 0;
  logic [31:0] PADDR = 0, PWDATA = 0, PRDATA;
  logic        PREADY;
  logic [31:0] pins = 0, GPIOPinsOut, GPIOPinsEn;
  logic        UARTSout, SPIOut, SPISck, MTimerInt, MSwInt, MExtInt, SExtInt, GPIOIntr, UARTIntr, SPIIntr;
  logic [3:0]  SPICS;
  periph dut(.clk, .reset, .PSEL, .PENABLE, .PWRITE, .PADDR, .PWDATA, .PRDATA, .PREADY,
             .GPIOPinsIn(pins), .GPIOPinsOut, .GPIOPinsEn, .UARTSin(1'b1), .UARTSout, .SPIIn(1'b0), .SPIOut,
             .SPISck, .SPICS, .ExtSrc(32'h0), .MTimerInt, .MSwInt, .MExtInt, .SExtInt, .GPIOIntr, .UARTIntr, .SPIIntr);
  string ev = "-";
  task automatic apb(bit wr, logic [31:0] a, logic [31:0] d, output logic [31:0] q, input string what);
    @(negedge clk); PSEL = 1; PENABLE = 0; PWRITE = wr; PADDR = a; PWDATA = d;
    @(negedge clk); PENABLE = 1; #1 q = PRDATA;
    ev = wr ? $sformatf("%s<=%0d", what, d) : $sformatf("%s=%0d", what, q);
    @(posedge clk); #1 PSEL = 0; PENABLE = 0;
  endtask
  logic [31:0] q;
  bit uview = 0, pview = 0;
  // the receiver's sample strobe, as in the RTL (MID = 7)
  always @(posedge clk) begin
    #2;
    if (uview)
      $display("UV %0d %b %b %b %0d %0d %b %0d %b %s", cyc, dut.uart.txLine, dut.uart.rin, dut.uart.rbusy,
               dut.uart.rsub, dut.uart.rbit, dut.uart.rbusy & dut.uart.tick & dut.uart.rsub == 4'd8,
               dut.uart.rxn, dut.uart.rxPush, ev);
    if (pview)
      $display("PV %0d %b %b %b %b %b %b %b %0d %s", cyc, GPIOIntr, UARTIntr, dut.plic.pending[3], dut.plic.pending[10],
               dut.plic.inprog[3], dut.plic.inprog[10], MExtInt, dut.plic.best[0], ev);
    ev = "-";
  end
  initial begin
    repeat (3) @(negedge clk); reset = 0;
    // ---- UART scene ----
    apb(1, 32'h1000_0003, 8'h80, q, "LCR"); apb(1, 32'h1000_0000, 1, q, "DLL"); apb(1, 32'h1000_0001, 0, q, "DLM");
    apb(1, 32'h1000_0003, 8'h1B, q, "LCR");        // 8 bits, parity enable, even
    apb(1, 32'h1000_0002, 8'h07, q, "FCR"); apb(1, 32'h1000_0004, 8'h10, q, "MCR");
    uview = 1;
    apb(1, 32'h1000_0000, 8'h5A, q, "THR");
    repeat (200) @(negedge clk);
    apb(0, 32'h1000_0005, 0, q, "LSR"); apb(0, 32'h1000_0000, 0, q, "RBR");
    repeat (2) @(negedge clk); uview = 0;
    apb(1, 32'h1000_0004, 8'h00, q, "MCR");
    // ---- PLIC scene: book Example 20.3 ----
    apb(1, 32'h0C00_000C, 5, q, "prio3"); apb(1, 32'h0C00_0028, 4, q, "prio10");
    apb(1, 32'h0C00_2000, (1 << 3) | (1 << 10), q, "enable"); apb(1, 32'h0C20_0000, 2, q, "threshold");
    apb(1, 32'h1006_0004, 1, q, "gpio.input_en"); apb(1, 32'h1006_0028, 1, q, "gpio.high_ie");
    pview = 1;
    repeat (2) @(negedge clk);
    apb(1, 32'h1000_0001, 2, q, "uart.IER");        // THR empty: the UART requests at once
    repeat (2) @(negedge clk);
    pins = 1;                                       // a GPIO pin goes high
    repeat (4) @(negedge clk);
    apb(0, 32'h0C20_0004, 0, q, "claim");           // 3: GPIO wins (priority 5)
    repeat (2) @(negedge clk);
    apb(1, 32'h1006_0028, 0, q, "gpio.high_ie"); apb(1, 32'h1006_002C, 1, q, "gpio.high_ip");   // service: GPIO drops
    apb(1, 32'h0C20_0004, 3, q, "complete");
    repeat (2) @(negedge clk);
    apb(0, 32'h0C20_0004, 0, q, "claim");           // 10: the UART
    apb(1, 32'h1000_0001, 0, q, "uart.IER");        // service: UART drops
    apb(1, 32'h0C20_0004, 10, q, "complete");
    repeat (3) @(negedge clk);
    $finish;
  end
endmodule
