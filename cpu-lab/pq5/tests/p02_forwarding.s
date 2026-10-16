# Back-to-back dependencies at distance 1, 2 and 3 (no stalls needed: forwarding)
        li    x1, 5
        add   x2, x1, x1       # distance 1: x1 forwarded from MEM stage  -> 10
        add   x3, x2, x1       # distance 1 (x2) and 2 (x1)               -> 15
        nop
        add   x4, x3, x2       # x3 distance 2, x2 distance 3            -> 25
        nop
        nop
        add   x5, x4, x0       # distance 3: register file write-through -> 25
        add   x5, x5, x5       # 50
        add   x5, x5, x5       # 100
        sub   x6, x5, x4       # 75
        sw    x6, 0(x0)        # store data forwarded too
        addi  x7, x6, 1        # 76
        sw    x7, 4(x0)
        halt
