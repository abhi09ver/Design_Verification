# BUG HUNT 11 - Control flow: a single never-taken branch
addi x1, x0, 1
addi x2, x0, 2
beq  x1, x2, 8         # not taken
addi x3, x0, 3
addi x4, x0, 4
