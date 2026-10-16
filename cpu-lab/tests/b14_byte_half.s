# SANITY 14 - sub-word loads and stores (should PASS)
addi x1, x0, 0x7F
addi x2, x0, 0x80
sb   x1, 64(x0)
sb   x2, 65(x0)
lb   x3, 65(x0)        # sign-extended 0x80 -> 0xFFFFFF80
lbu  x4, 65(x0)        # 0x80
lh   x5, 64(x0)        # 0xFFFF807F
