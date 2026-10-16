# Bubble sort 8 numbers stored at address 0..28
        li x1, 34
        sw x1, 0(x0)
        li x1, -5
        sw x1, 4(x0)
        li x1, 99
        sw x1, 8(x0)
        li x1, 0
        sw x1, 12(x0)
        li x1, 7
        sw x1, 16(x0)
        li x1, 7
        sw x1, 20(x0)
        li x1, -100
        sw x1, 24(x0)
        li x1, 12
        sw x1, 28(x0)
        li    x5, 7            # passes = n-1
outer:  li    x6, 0            # address of a[j]
        li    x7, 0            # j
inner:  lw    x8, 0(x6)
        lw    x9, 4(x6)        # load-use below!
        bge   x9, x8, noswap   # signed compare
        sw    x9, 0(x6)
        sw    x8, 4(x6)
noswap: addi  x6, x6, 4
        addi  x7, x7, 1
        blt   x7, x5, inner
        addi  x5, x5, -1
        bne   x5, x0, outer
        halt
