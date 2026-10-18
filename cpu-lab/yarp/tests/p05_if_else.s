# max and absolute value with forward branches (predicted NOT taken)
        li    x1, -17
        li    x2, 9
        blt   x1, x2, x1_small
        mv    x3, x1           # skipped
        j     done_max
x1_small:
        mv    x3, x2           # max = 9
done_max:
        bge   x1, x0, positive
        sub   x4, x0, x1       # abs(-17) = 17
        j     done_abs
positive:
        mv    x4, x1
done_abs:
        sw    x3, 0(x0)
        sw    x4, 4(x0)
        halt
