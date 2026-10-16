# BUG HUNT 04 - Issue/select: two independent DIVs become ready in the same cycle
addi x1, x0, 100
addi x2, x0, 7
addi x3, x0, 9
div  x4, x1, x2        # 14
div  x5, x1, x3        # 11
add  x6, x4, x5        # 25
