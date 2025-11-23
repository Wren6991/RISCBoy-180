// memcpy/memset are from https://github.com/raspberrypi/pico-bootrom-rp2350/blob/master/src/main/riscv/riscv_misc.S
// (Original licence BSD 3-clause, copyright Raspberry Pi Ltd)

.section .text.memcpy
.global memcpy
memcpy:
    mv a3, a0
    add a2, a2, a3
    or a4, a1, a3
    andi a4, a4, 0x3
    bnez a4, 5f

    addi a2, a2, -3
    bgeu a3, a2, 3f

    // Word loop
1:
    lw a4, (a1)
    sw a4, (a3)
    addi a1, a1, 4
    addi a3, a3, 4
2:
    bltu a3, a2, 1b
3:
    addi a2, a2, 3
    bgeu a3, a2, 6f

    // Byte loop
4:
    lbu a4, (a1)
    sb  a4, (a3)
    addi a1, a1, 1
    addi a3, a3, 1
5:
    bltu a3, a2, 4b
6:
    ret

.section .text.memset
.global memset
memset:
    mv a3, a0
    add a2, a2, a3
    andi a4, a3, 0x3
    bnez a4, 5f

    addi a2, a2, -3
    bgeu a3, a2, 3f
    // Replicate byte x4 for word loop
    packh a1, a1, a1
    pack a1, a1, a1

    // Word loop
1:
    sw a1, (a3)
    addi a3, a3, 4
2:
    bltu a3, a2, 1b
3:
    addi a2, a2, 3
    bgeu a3, a2, 6f

    // Byte loop
4:
    sb  a1, (a3)
    addi a3, a3, 1
5:
    bltu a3, a2, 4b
6:
    ret
