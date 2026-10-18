# YARP bug hunt 3: jalr must not touch the data bus; link and target must be right
        li    x5, 16
        jalr  x1, 0(x5)        # jump to 16, x1 = 8
        li    x6, 99           # skipped
        li    x6, 98           # skipped
        addi  x7, x1, 0        # pc 16: x7 = 8
        auipc x8, 0
        jalr  x0, 12(x8)       # jump over the next instruction
        li    x9, 1            # skipped
        halt
