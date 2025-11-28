.section .init, "ax"

#include "addressmap.h"
#include "hw/clocks_regs.h"

.global _start
_start:
.option push
.option norelax
	la gp, __global_pointer$
.option pop
	la sp, __stacktop

	// wheeeee fast clock
	li a0, CLOCKS_BASE + CLOCKS_CLK_SYS_OFFS
	sw zero, (a0)

_bss_clear:
	la a0, __sbss
	la a1, __ebss
	bgeu a0, a1, 2f
	li a2, 0
1:
	sw a2, (a0)
	addi a0, a0, 4
	bltu a0, a1, 1b
2:
	// Set argc=0
	li a0, 0
	jal main
1:
	j 1b
