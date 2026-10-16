# The one hazard forwarding cannot fix: use a loaded value immediately
        li    x1, 42
        sw    x1, 8(x0)
        lw    x2, 8(x0)
        addi  x3, x2, 1        # needs x2 NOW -> 1 bubble (load-use stall)   -> 43
        lw    x4, 8(x0)
        nop                    # one independent instruction in between: no stall
        addi  x5, x4, 2        # 44
        lw    x6, 8(x0)
        sw    x6, 12(x0)       # store data from a load: also a stall here
        lw    x7, 12(x0)
        lw    x8, 0(x7)        # load-use on the ADDRESS: x7 = 42 -> word 10 = 0
        halt
