# RV32I has no multiply: shift-and-add. 123 * 45 = 5535, then 6! = 720
        li    x10, 123
        li    x11, 45
        jal   ra, mul
        sw    x12, 0(x0)
        li    x20, 6           # factorial
        li    x21, 1
fact:   mv    x10, x21
        mv    x11, x20
        jal   ra, mul
        mv    x21, x12
        addi  x20, x20, -1
        bne   x20, x0, fact
        sw    x21, 4(x0)
        halt
mul:    li    x12, 0           # x12 = x10 * x11
mlp:    andi  x13, x11, 1
        beq   x13, x0, mskip
        add   x12, x12, x10
mskip:  slli  x10, x10, 1
        srli  x11, x11, 1
        bne   x11, x0, mlp
        ret
