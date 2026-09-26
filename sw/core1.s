# core1 (processor_1) : computes x3, x4 of the 4x4 Jacobi iteration
# Reconstructed from the hand-encoded ROM in rtl/instruction_memory_1.sv.
# lw/sw offsets are BYTE offsets (the original comments use word indices).
#
# data_memory_1 map (word index : byte offset)
#   0-3  a31 a32 a33 a34     : 0-12
#   4-7  a41 a42 a43 a44     : 16-28
#   8,9  b3 b4               : 32,36
#   10   x1(k)  <- rec       : 40      11  x2(k)  <- rec     : 44
#   12   x3(k)  -> buf1_to_0[0] : 48   13  x4(k)  -> buf1_to_0[1] : 52
#   14   x3(k+1)             : 56      15  x4(k+1)           : 60
#   16   loop counter        : 64      17  loop limit (TB)   : 68

        addi $t10, $zero, 0          # counter = 0
Loop:   sw   $t10, 64($zero)         # M[16] = counter  (also the j target, see end)
        # ---- x3(k+1) = (b3 - a31*x1 - a32*x2 - a34*x4) / a33
        lw   $t0, 32($zero)          # b3
        lw   $t1, 0($zero)           # a31
        lw   $t2, 4($zero)           # a32
        lw   $t3, 12($zero)          # a34
        lw   $t4, 40($zero)          # x1(k)
        lw   $t5, 44($zero)          # x2(k)
        lw   $t6, 52($zero)          # x4(k)
        mul  $t7, $t1, $t4
        mul  $t8, $t2, $t5
        mul  $t9, $t3, $t6
        add  $t13, $t7, $t8
        add  $t13, $t13, $t9
        sub  $t14, $t0, $t13
        lw   $t1, 8($zero)           # a33
        div  $t15, $t14, $t1
        sw   $t15, 56($zero)         # x3(k+1)
        # ---- x4(k+1) = (b4 - a41*x1 - a42*x2 - a43*x3) / a44
        lw   $t0, 36($zero)          # b4
        lw   $t1, 16($zero)          # a41
        lw   $t2, 20($zero)          # a42
        lw   $t3, 24($zero)          # a43
        lw   $t4, 40($zero)          # x1(k)
        lw   $t5, 44($zero)          # x2(k)
        lw   $t6, 48($zero)          # x3(k)  (still old value)
        mul  $t7, $t1, $t4
        mul  $t8, $t2, $t5
        mul  $t9, $t3, $t6
        add  $t13, $t7, $t8
        add  $t13, $t13, $t9
        sub  $t14, $t0, $t13
        lw   $t1, 28($zero)          # a44
        div  $t15, $t14, $t1
        sw   $t15, 60($zero)         # x4(k+1)
        # ---- commit x(k) <- x(k+1); the sw to byte 48/52 also writes the exchange buffer
        lw   $t0, 56($zero)
        sw   $t0, 48($zero)          # x3(k) -> buf1_to_0[0]
        lw   $t1, 60($zero)
        sw   $t1, 52($zero)          # x4(k) -> buf1_to_0[1]
        rec                          # M[10..11] <- buf0_to_1 (x1, x2 from core0)
        # ---- loop control
        lw   $t10, 64($zero)
        addi $t10, $t10, 1
        sw   $t10, 64($zero)
        lw   $t11, 68($zero)         # loop limit
        beq  $t11, $t10, End
        j    Loop                    # original encoding targets byte 4, not LoopStart (8)
End:    j    End
