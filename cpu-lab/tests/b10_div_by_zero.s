# BUG HUNT 10 - Divider corner cases (RISC-V spec table 13.1)
addi x1, x0, 7
sub  x2, x0, x1        # x2 = -7
div  x3, x1, x0        #  7 / 0 -> -1 (0xFFFFFFFF)
div  x4, x2, x0        # -7 / 0 -> -1 (0xFFFFFFFF)
rem  x5, x2, x0        # -7 % 0 -> -7 (dividend)
rem  x6, x2, x1        # -7 % 7 ->  0
