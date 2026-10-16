# BUG HUNT 03 - Wakeup: can an instruction wait on ROB entry #0?
# mul lives in ROB[0] (first instruction ever) and takes several cycles.
# add/sub depend on it and arrive in the same bundle -> they MUST be woken by the CDB.
mul  x1, x2, x3        # ROB[0]  (x2*x3 = 0, value doesn't matter, the TAG does)
add  x4, x1, x1        # ROB[1]  waits on tag 0
sub  x5, x1, x4        # ROB[2]
