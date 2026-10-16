// Same stimulus as probe_protocol.sv plus a procedural emulation of the
// a_b_live / a_b_order properties from ../../02_axi_lite_sva/axi_lite_sva.sv
// (iverilog 12 has no concurrent SVA). Original RTL: a_b_live fires; fixed RTL: 0.
// Run: iverilog -g2012 -o s probe_sva_emulation.sv <repo>/rtl/axi4_slave_ram.sv && vvp s
`timescale 1ns/1ps
module tb; logic aclk=0, aresetn=0; always #5 aclk=~aclk;
logic [31:0] awaddr=0,wdata=0,araddr=0; logic [3:0] wstrb=4'hF; logic awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
wire awready,wready,bvalid,arready,rvalid; wire [1:0] bresp,rresp; wire [31:0] rdata;
axi4_slave_ram dut(.aclk,.aresetn,.awaddr,.awprot(3'b0),.awvalid,.awready,.wdata,.wstrb,.wvalid,.wready,.bresp,.bvalid,.bready,
 .araddr,.arprot(3'b0),.arvalid,.arready,.rdata,.rresp,.rvalid,.rready);

logic [7:0] aw_n=0,w_n=0,b_n=0; integer pend=0, viol=0, ordv=0;
always @(posedge aclk) if (aresetn) begin
  if (bvalid && !(aw_n!=b_n && w_n!=b_n)) ordv=ordv+1;
  if (aw_n!=b_n && w_n!=b_n && !bvalid) begin pend=pend+1; if (pend>8) viol=viol+1; end else pend=0;
  aw_n <= aw_n + (awvalid&&awready); w_n <= w_n + (wvalid&&wready); b_n <= b_n + (bvalid&&bready);
end
final $display("SVA-emulation: a_b_live violations=%0d  a_b_order violations=%0d", viol, ordv);
initial begin
 repeat(3) @(posedge aclk); aresetn<=1; repeat(3) @(posedge aclk);
 // ---- Case 1: W before AW (legal for a master)
 wvalid<=1; wdata<=32'h1111_2222; @(posedge aclk); while(!wready) @(posedge aclk); wvalid<=0;
 $display("%0t W handshake done (slave in WR_ADDR)", $time);
 awvalid<=1; awaddr<=32'h10; @(posedge aclk); while(!awready) @(posedge aclk); awvalid<=0; bready<=1;
 fork begin repeat(50) @(posedge aclk); $display("Case1: NO BVALID after 50 cycles -> DEADLOCK (W-before-AW dropped)"); end
      begin @(posedge aclk); while(!bvalid) @(posedge aclk); $display("Case1: got BVALID"); end join_any
 disable fork;
 $display("after case1: live viol so far=%0d", viol);
 aw_n=0; w_n=0; b_n=0; pend=0;
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
