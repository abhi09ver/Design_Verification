# BUG HUNT 15 - unsigned sub-word loads (lbu / lhu) - found while debugging b14
addi x1, x0, -1        # 0xFFFFFFFF
sw   x1, 72(x0)        # word 18 = 0xFFFFFFFF
nop
nop
nop
nop
lbu  x2, 72(x0)        # 0x000000FF
lhu  x3, 74(x0)        # 0x0000FFFF
lb   x4, 73(x0)        # 0xFFFFFFFF
lh   x5, 72(x0)        # 0xFFFFFFFF
