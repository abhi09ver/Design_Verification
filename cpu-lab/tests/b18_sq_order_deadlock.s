# BUG HUNT 18 - Store queue entry order / deadlock (found by constrained-random)
# The oldest store waits on a slow DIV; 8+ younger independent stores are ready first.
addi x1, x0, 99
addi x2, x0, 3
div  x3, x1, x2        # slow
sw   x3, 64(x0)        # OLDEST store - data not ready for ~12 cycles
sw   x2, 68(x0)
sw   x2, 72(x0)
sw   x2, 76(x0)
sw   x2, 80(x0)
sw   x2, 84(x0)
sw   x2, 88(x0)
sw   x2, 92(x0)
sw   x2, 96(x0)
sw   x2, 100(x0)
lw   x4, 64(x0)        # 33
