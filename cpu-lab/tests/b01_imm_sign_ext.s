# BUG HUNT 01 - Decoder: is the I-type immediate sign-extended?
# RISC-V: imm[11:0] is ALWAYS sign-extended to 32 bits.
addi x1, x0, -1        # expect 0xFFFFFFFF
addi x2, x0, 100
addi x3, x2, -40       # expect 60
lw   x4, -4(x5)        # x5=0 -> addr -4 = 0xFFFFFFFC -> word 1023 % 1024
