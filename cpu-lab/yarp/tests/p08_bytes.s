# Sub-word memory: little-endian bytes and halves, sign vs zero extension
        lui   x1, 0x80FF0
        addi  x1, x1, 0x17F    # x1 = 0x80FF017F
        sw    x1, 16(x0)
        lb    x2, 16(x0)       # 0x7F        -> 127
        lb    x3, 17(x0)       # 0x01
        lb    x4, 18(x0)       # 0xFF        -> -1
        lbu   x5, 18(x0)       # 0xFF        -> 255
        lh    x6, 18(x0)       # 0x80FF      -> negative
        lhu   x7, 18(x0)       # 0x80FF      -> 33023
        li    x8, -2
        sb    x8, 21(x0)       # write one byte in the middle of word 5
        sh    x8, 26(x0)       # upper half of word 6
        lw    x9, 20(x0)
        lw    x10, 24(x0)
        halt
