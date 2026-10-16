# BUG HUNT 16 - all four multiplies with negative operands
addi x1, x0, -3
addi x2, x0, 5
mul    x3, x1, x2      # -15
mulh   x4, x1, x2      # 0xFFFFFFFF
mulhsu x5, x1, x2      # 0xFFFFFFFF
mulhu  x6, x1, x2      # 4
mulhu  x7, x1, x1      # 0xFFFFFFFA
