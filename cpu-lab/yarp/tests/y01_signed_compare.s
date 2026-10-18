# YARP bug hunt 1+2: signed vs unsigned compares (SLT/SLTI/SLTU and all 6 branches)
        li    x1, -5
        li    x2, 3
        slt   x3, x1, x2       # -5 < 3 signed      -> 1
        slt   x4, x2, x1       #  3 < -5 signed     -> 0
        sltu  x5, x1, x2       # 0xFFFFFFFB < 3 ?   -> 0
        slti  x6, x1, -1       # -5 < -1            -> 1
        li    x7, -1
        slt   x8, x7, x1       # -1 < -5            -> 0  (magnitude compare says 1)
        li    x10, 0
        blt   x1, x2, t1       # taken (signed)
        addi  x10, x10, 1
t1:     bge   x2, x1, t2       # taken
        addi  x10, x10, 2
t2:     bltu  x2, x1, t3       # 3 < 0xFFFFFFFB unsigned: taken
        addi  x10, x10, 4
t3:     bgeu  x1, x2, t4       # taken
        addi  x10, x10, 8
t4:     bltu  x7, x1, t5       # 0xFFFFFFFF < 0xFFFFFFFB ? not taken
        addi  x10, x10, 16     # executes -> x10 = 16
t5:     halt
