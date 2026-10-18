# YARP bug hunt 4: the first instruction after reset must execute exactly once
        addi  x1, x1, 1        # x1 = 1 (not 2)
        sw    x1, 0(x0)
        addi  x2, x1, 10
        halt
