// X in a loop condition: while(!(x && 1)) evaluates to X, which a while/if
// treats as FALSE -> the loop exits immediately. This is why the original
// monitor captured a bogus transaction with addr = X at start-up.
// Fix: use === 1'b1 in handshake waits and drive VALIDs to 0 from time 0.
// Run: iverilog -g2012 -o x probe_x_in_while.sv && vvp x
module t; logic a; logic r=1; integer n=0; initial begin a='x; while(!(a&&r) && n<3) n=n+1; $display("while(!(x&&1)) loop iterations = %0d (0 means X made it exit immediately)", n); end endmodule
