# First 20 Fibonacci numbers into memory
        li    x1, 0
        li    x2, 1
        li    x3, 0            # address
        li    x4, 20
fib:    sw    x1, 0(x3)
        add   x5, x1, x2
        mv    x1, x2
        mv    x2, x5
        addi  x3, x3, 4
        addi  x4, x4, -1
        bne   x4, x0, fib
        halt
