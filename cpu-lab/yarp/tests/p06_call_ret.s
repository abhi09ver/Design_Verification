# Function calls: jal saves the return address in ra (x1), ret = jalr x0, 0(ra)
# square(n) is called 3 times; the stack pointer (sp = x2) saves ra across a nested call.
        li    sp, 512
        li    x10, 7
        jal   ra, sum_sq       # x10 = 7*7 + 3*3 = 58 ... via nested calls
        sw    x10, 0(x0)
        halt
sum_sq: addi  sp, sp, -4
        sw    ra, 0(sp)        # save my return address (I am about to call again)
        jal   ra, square       # x11 = 49
        mv    x12, x11
        li    x10, 3
        jal   ra, square       # x11 = 9
        add   x10, x12, x11
        lw    ra, 0(sp)
        addi  sp, sp, 4
        ret
square: mv    x11, x0          # x11 = x10 * x10 by repeated addition
        mv    x13, x10
sq_lp:  beq   x13, x0, sq_end
        add   x11, x11, x10
        addi  x13, x13, -1
        j     sq_lp
sq_end: ret
