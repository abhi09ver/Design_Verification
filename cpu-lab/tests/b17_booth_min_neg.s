# BUG HUNT 17 - Booth multiplier corner case: the most negative number (found by random test r13)
addi x1, x0, 1
slli x1, x1, 31        # x1 = 0x80000000 = -2^31
mul    x2, x1, x1      # 0
mulh   x3, x1, x1      # 0x40000000
mulhu  x4, x1, x1      # 0x40000000
addi x5, x0, -1
mulh   x6, x1, x5      # 0
mul    x7, x1, x5      # 0x80000000
