# sum = 1 + 2 + ... + 100  (backward branch: predicted taken, right 99 of 100 times)
        li    x1, 0            # sum
        li    x2, 1            # i
        li    x3, 101
loop:   add   x1, x1, x2
        addi  x2, x2, 1
        bne   x2, x3, loop
        sw    x1, 0(x0)        # 5050
        halt
