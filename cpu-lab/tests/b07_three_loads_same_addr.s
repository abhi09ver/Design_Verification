# BUG HUNT 07 - Load queue: 3 loads to one address, only 2 load ports
lw   x1, 48(x0)        # word 12 = 12
lw   x2, 48(x0)
lw   x3, 48(x0)
add  x4, x1, x2
add  x5, x4, x3        # 36
