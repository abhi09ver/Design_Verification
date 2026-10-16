# DEMO for the course cycle-stepper: rename, OOO completion, in-order commit, memory RAW
addi x1, x0, 6
addi x2, x0, 7
mul  x3, x1, x2        # slow (3-stage Booth) -> 42
add  x4, x3, x1        # waits for the MUL on the CDB -> 48
addi x5, x0, 100       # independent: finishes long before the MUL
sub  x3, x5, x1        # WAW on x3 (renamed!) -> 94
sw   x4, 64(x0)        # store waits for x4
lw   x6, 64(x0)        # load must wait for / forward from the store -> 48
add  x7, x6, x3        # 48 + 94 = 142
