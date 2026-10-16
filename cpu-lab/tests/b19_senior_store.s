# BUG HUNT 19 - load right behind a store that has RETIRED but not yet DRAINED to memory
addi x1, x0, 5
addi x5, x0, 3
mul  x6, x5, x5        # 9, slow
sh   x6, 76(x0)        # store data arrives late
lw   x2, 76(x0)        # must see 9 in the low half: 0x00000009
lw   x3, 76(x0)
