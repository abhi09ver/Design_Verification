# The original 33-instruction program shipped with the design
addi x1, x0, 1
addi x2, x0, 2
addi x3, x0, 3
sw x1, 4(x0)
sw x2, 8(x0)
sw x3, 12(x0)
sw x3, 16(x0)
mul x3, x1, x2
add x4, x2, x3
add x7, x3, x1
add x8, x8, x9
lb x1, 4(x0)
lbu x9, 8(x0)
lw x9, 12(x0)
xor x15, x9, x10
add x10, x10, x11
xor x11, x10, x9   # NOTE: original comment said "add" but the hex 0x009545B3 is XOR (funct3=100)
sll x12, x9, x1
srl x13, x9, x1
sub x10, x12, x11
and x13, x18, x19
slt x14, x10, x12
add x11, x9, x10
div x6, x2, x1
lb x18, 16(x0)
lb x19, 20(x0)
sw x25, 20(x19)
add x1, x9, x10
add x2, x9, x11
add x3, x1, x2
mul x8, x1, x3
or x7, x1, x2
add x29, x7, x1
