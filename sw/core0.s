# core0 (processor_0) : computes x1, x2 of the 4x4 Jacobi iteration
# Reconstructed from the hand-encoded ROM in rtl/instruction_memory_0.sv.
# lw/sw offsets are BYTE offsets (the original comments use word indices).
#
# data_memory_0 map (word index : byte offset)
#   0-3  a11 a12 a13 a14     : 0-12
#   4-7  a21 a22 a23 a24     : 16-28
#   8,9  b1 b2               : 32,36
#   10   x3(k)  <- rec       : 40      11  x4(k)  <- rec     : 44
#   12   x1(k)  -> buf0_to_1[0] : 48   13  x2(k)  -> buf0_to_1[1] : 52
#   14   x1(k+1)             : 56      15  x2(k+1)           : 60
#   16   loop counter        : 64      17  loop limit (TB)   : 68

        addi $t10, $zero, 0          # counter = 0
Loop:   sw   $t10, 64($zero)         # M[16] = counter  (also the j target, see end)
        # ---- x1(k+1) = (b1 - a12*x2 - a13*x3 - a14*x4) / a11
        lw   $t0, 32($zero)          # b1
        lw   $t1, 4($zero)           # a12
        lw   $t2, 8($zero)           # a13
        lw   $t3, 12($zero)          # a14
        lw   $t4, 52($zero)          # x2(k)
        lw   $t5, 40($zero)          # x3(k)
        lw   $t6, 44($zero)          # x4(k)
        mul  $t7, $t1, $t4
        mul  $t8, $t2, $t5
        mul  $t9, $t3, $t6
        add  $t13, $t7, $t8
        add  $t13, $t13, $t9
        sub  $t14, $t0, $t13
        lw   $t1, 0($zero)           # a11
        div  $t15, $t14, $t1
        sw   $t15, 56($zero)         # x1(k+1)
        # ---- x2(k+1) = (b2 - a21*x1 - a23*x3 - a24*x4) / a22
        lw   $t0, 36($zero)          # b2
        lw   $t1, 16($zero)          # a21
        lw   $t2, 24($zero)          # a23
        lw   $t3, 28($zero)          # a24
        lw   $t4, 48($zero)          # x1(k)  (still old value: true Jacobi, not Gauss-Seidel)
        lw   $t5, 40($zero)          # x3(k)
        lw   $t6, 44($zero)          # x4(k)
        mul  $t7, $t1, $t4
        mul  $t8, $t2, $t5
        mul  $t9, $t3, $t6
        add  $t13, $t7, $t8
        add  $t13, $t13, $t9
        sub  $t14, $t0, $t13
        lw   $t1, 20($zero)          # a22
        div  $t15, $t14, $t1
        sw   $t15, 60($zero)         # x2(k+1)
        # ---- commit x(k) <- x(k+1); the sw to byte 48/52 also writes the exchange buffer
        lw   $t0, 56($zero)
        sw   $t0, 48($zero)          # x1(k) -> buf0_to_1[0]
        lw   $t1, 60($zero)
        sw   $t1, 52($zero)          # x2(k) -> buf0_to_1[1]
        rec                          # M[10..11] <- buf1_to_0 (x3, x4 from core1)
        # ---- loop control
        lw   $t10, 64($zero)
        addi $t10, $t10, 1
        sw   $t10, 64($zero)
        lw   $t11, 68($zero)         # loop limit
        beq  $t11, $t10, End
        j    Loop                    # original encoding targets byte 4, not LoopStart (8):
                                     # re-executes the counter store, +1 cycle/iteration, harmless
End:    j    End
