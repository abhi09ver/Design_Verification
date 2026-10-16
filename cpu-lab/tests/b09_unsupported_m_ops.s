# BUG HUNT 09 - Decode/issue: unsigned M-extension ops
addi x1, x0, 100
addi x2, x0, 7
divu x3, x1, x2        # 14
remu x4, x1, x2        # 2
