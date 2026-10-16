# BUG HUNT 05 - Memory ordering (RAW through memory)
# word 10 (addr 40) is pre-initialised to 10 by data_mem reset.
addi x1, x0, 77
nop
nop
sw   x1, 40(x0)        # older store
lw   x2, 40(x0)        # younger load, same address -> MUST see 77
add  x3, x2, x0
