.section .init, "ax"

#include "addressmap.h"

.global _start
_start:
	// This is the first instruction that executes after the chip powers up.
	// Spin in a delay loop for a few thousand cycles before touching RAM.
	// Why? It just makes me feel better. Also this happens to zero s0/s1,
	// which are the registers used by the testbench debug host.
	li s0, 31
1:
	li s1, 31
2:
	addi s1, s1, -1
	bnez s1, 2b
	addi s0, s0, -1
	bnez s0, 1b

// Extreme pro gamer move: by inspection the C program does not use any stack
// or .bss, so save space (gates) by skipping stack init and .bss clear
#if 0

	// Stack pointer: `li` is just one 32-bit lui here as it's 4k-aligned.
	li sp, IRAM_END

	// Just unconditionally clear the top 1k of RAM. This includes the boot
	// stack and .bss. The linker script only allocates this 1k.
_bss_clear:
	addi a1, sp, -1024
	li a0, 0
1:
	sw a0, (a1)
	addi a1, a1, 4
	bltu a1, sp, 1b
2:
	// The above loop initialised argc=0 and argv to top of stack.
#endif
	// Fall through into `main` via linker script fuckery:
