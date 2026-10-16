// Directed protocol probe for NitishVerifies/AXI4_UVM_Verification rtl/axi4_slave_ram.sv
// Case 1: W before AW (legal)  -> original RTL deadlocks (no BVALID)
// Case 2: out-of-range address -> original RTL returns OKAY and aliases word 0
// Case 3: BREADY held low      -> BVALID must stay high
// Run: iverilog -g2012 -o p probe_protocol.sv <repo>/rtl/axi4_slave_ram.sv && vvp p
`timescale 1ns/1ps
module tb; logic aclk=0, aresetn=0; always #5 aclk=~aclk;
logic [31:0] awaddr=0,wdata=0,araddr=0; logic [3:0] wstrb=4'hF; logic awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
wire awready,wready,bvalid,arready,rvalid; wire [1:0] bresp,rresp; wire [31:0] rdata;
axi4_slave_ram dut(.aclk,.aresetn,.awaddr,.awprot(3'b0),.awvalid,.awready,.wdata,.wstrb,.wvalid,.wready,.bresp,.bvalid,.bready,
 .araddr,.arprot(3'b0),.arvalid,.arready,.rdata,.rresp,.rvalid,.rready);
initial begin
 repeat(3) @(posedge aclk); aresetn<=1; repeat(3) @(posedge aclk);
 // ---- Case 1: W before AW (legal for a master)
 wvalid<=1; wdata<=32'h1111_2222; @(posedge aclk); while(!wready) @(posedge aclk); wvalid<=0;
 $display("%0t W handshake done (slave in WR_ADDR)", $time);
 awvalid<=1; awaddr<=32'h10; @(posedge aclk); while(!awready) @(posedge aclk); awvalid<=0; bready<=1;
 fork begin repeat(50) @(posedge aclk); $display("Case1: NO BVALID after 50 cycles -> DEADLOCK (W-before-AW dropped)"); end
      begin @(posedge aclk); while(!bvalid) @(posedge aclk); $display("Case1: got BVALID"); end join_any
 disable fork;
 // reset and test out of range
 aresetn<=0; bready<=0; repeat(2) @(posedge aclk); aresetn<=1; repeat(3) @(posedge aclk);
 awvalid<=1; wvalid<=1; awaddr<=32'h400; wdata<=32'hDEAD_BEEF; @(posedge aclk); while(!(awready)) @(posedge aclk); awvalid<=0; wvalid<=0; bready<=1;
 @(posedge aclk); while(!bvalid) @(posedge aclk); $display("Case2: write 0x400 (out of range) BRESP=%b (expect 10 SLVERR)", bresp); bready<=0;
 arvalid<=1; araddr<=32'h0; @(posedge aclk); while(!arready) @(posedge aclk); arvalid<=0; rready<=1; @(posedge aclk); while(!rvalid) @(posedge aclk);
 $display("Case2: read 0x000 = %h  (aliasing if DEADBEEF)", rdata); rready<=0;
 // Case 3: hold BREADY low, check BVALID stays
 awvalid<=1; wvalid<=1; awaddr<=32'h20; @(posedge aclk); while(!awready) @(posedge aclk); awvalid<=0; wvalid<=0;
 repeat(5) @(posedge aclk); $display("Case3: BVALID held while BREADY low = %b", bvalid); bready<=1; @(posedge aclk); bready<=0;
 $finish; end endmodule
