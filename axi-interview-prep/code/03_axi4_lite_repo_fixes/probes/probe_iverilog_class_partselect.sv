// iverilog 12 limitation: variable part-select of a CLASS PROPERTY returns the
// low byte for every lane. Explains the false scoreboard mismatches (0x81818181).
// Fix: copy the property into a local reg before part-selecting.
// Run: iverilog -g2012 -o t probe_iverilog_class_partselect.sv && vvp t
module t; class C; logic [31:0] data; endclass reg [31:0] m;
initial begin C c = new(); integer b; c.data=32'h40895e81; m=0; for(b=0;b<4;b=b+1) m[b*8+:8]=c.data[b*8+:8]; $display("class part-select: %h (expect 40895e81)", m); end endmodule
