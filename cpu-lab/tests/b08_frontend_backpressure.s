# BUG HUNT 08 - Frontend: what happens when the back-end stalls for a long time?
# A chain of dependent DIVs fills the 4-entry Mul/Div RS -> allocation stalls
# -> decode stalls -> the 16-entry instruction queue fills up ...
addi x1, x0, 1000
addi x2, x0, 2
div  x3, x1, x2
div  x4, x3, x2
div  x5, x4, x2
div  x6, x5, x2
div  x7, x6, x2
div  x8, x7, x2
addi x10, x0, 10
addi x11, x0, 11
addi x12, x0, 12
addi x13, x0, 13
addi x14, x0, 14
addi x15, x0, 15
addi x16, x0, 16
addi x17, x0, 17
addi x18, x0, 18
addi x19, x0, 19
addi x20, x0, 20
addi x21, x0, 21
addi x22, x0, 22
addi x23, x0, 23
addi x24, x0, 24
addi x25, x0, 25
addi x26, x0, 26
addi x27, x0, 27
addi x28, x0, 28
addi x29, x0, 29
addi x30, x0, 30
addi x31, x0, 31
