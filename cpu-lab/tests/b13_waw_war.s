# SANITY 13 - WAW / WAR hazards removed by renaming (should PASS)
addi x1, x0, 5
mul  x2, x1, x1        # slow producer of x2 (25)
addi x2, x0, 9         # WAW on x2: younger write must win in the ARF
add  x3, x2, x0        # must read 9, not 25
addi x1, x0, 3         # WAR on x1 (mul read old x1=5)
add  x4, x1, x3        # 12
