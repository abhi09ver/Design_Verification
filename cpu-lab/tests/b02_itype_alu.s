# BUG HUNT 02 - Execute: does the ALU implement ALL OP-IMM instructions?
addi x1, x0, 12
andi x2, x1, 5         # 12 & 5 = 4
ori  x3, x1, 3         # 15
xori x4, x1, 1         # 13
slli x5, x1, 2         # 48
srli x6, x1, 1         # 6
slti x7, x1, 20        # 1
