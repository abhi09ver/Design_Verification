# Every ALU operation once, including the U-type ones
        li    x1, 100
        li    x2, -7
        add   x3, x1, x2       # 93
        sub   x4, x1, x2       # 107
        and   x5, x1, x2
        or    x6, x1, x2
        xor   x7, x1, x2
        slt   x8, x2, x1       # 1  (-7 < 100 signed)
        sltu  x9, x2, x1       # 0  (0xFFFFFFF9 > 100 unsigned)
        sll   x10, x1, x2      # shift amount = low 5 bits of -7 = 25
        srl   x11, x2, x1      # 100 & 31 = 4
        sra   x12, x2, x1
        slti  x13, x2, 0
        sltiu x14, x1, 101
        xori  x15, x1, -1      # NOT
        ori   x16, x1, 0x700
        andi  x17, x2, 0xF0
        slli  x18, x1, 20
        srli  x19, x2, 28
        srai  x20, x2, 1
        lui   x21, 0xABCDE
        auipc x22, 0x10
        addi  x23, x21, -1
        halt
