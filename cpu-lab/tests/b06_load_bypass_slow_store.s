# BUG HUNT 06 - Memory disambiguation: store DATA not ready yet
addi x1, x0, 7
mul  x2, x1, x1        # 49, multi-cycle
sw   x2, 40(x0)        # store waits for mul ...
lw   x3, 40(x0)        # ... younger load to the SAME address must wait or be replayed
add  x4, x3, x0
