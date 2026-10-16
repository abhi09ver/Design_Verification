# SANITY 12 - long back-to-back RAW chain through the CDB (should PASS)
addi x1, x0, 1
add  x2, x1, x1
add  x3, x2, x2
add  x4, x3, x3
add  x5, x4, x4
add  x6, x5, x5
add  x7, x6, x6
add  x8, x7, x7
sub  x9, x8, x1
xor  x10, x9, x8
