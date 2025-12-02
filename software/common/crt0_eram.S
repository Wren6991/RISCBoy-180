#include "hazard3_csr.h"

// GAS supports Zilsd but GCC does not, so the preprocessor macro isn't set.
// FIXME this will break non-Zilsd builds.
#define __riscv_zilsd 1

.section .init, "ax"

.global _start
_start:
.option push
.option norelax
	la gp, __global_pointer$
.option pop
	la sp, __stacktop

	// Disable all sources of IRQs, then set global IRQ enable
	csrw hazard3_csr_meiea, zero
	li a0, 0x800
	// (set mie.meie as all per-source enables are clear)
	csrw mie, a0
	csrs mstatus, 0x8

	la a0, __vector_table + 1
	csrw mtvec, a0	

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

// ----------------------------------------------------------------------------
// Default handler loops

.macro default_handler name
.weak \name
\name:
1:
	j 1b
.endm

// If you're here it's probably because of a bug in your code. Check mepc and
// mcause for the source of the exception. mcause values:
// Fetch fault         0x1
// Illegal instruction 0x2
// Soft breakpoint     0x3
// Misaligned load     0x4
// Load fault          0x5
// Misaligned store    0x6
// Store fault         0x7
// ecall from M-mode   0xb
default_handler __exception_handler

// If you're here it's because the APU interrupted the CPU and no interrupt
// handler was installed.
default_handler isr_machine_softirq

// If you're here it's because you enabled timer IRQs with no interrupt
// handler installed
default_handler isr_machine_timer

default_handler isr_apu_aout
default_handler isr_spi_stream
default_handler isr_ppu
default_handler isr_vuart
default_handler isr_apu_timer
default_handler isr_uart

// ----------------------------------------------------------------------------
// Vector table and IRQ dispatch

.p2align 6
__vector_table:
.option push
.option norelax
.option norvc
j __exception_handler
.word 0
.word 0
j isr_machine_softirq
.word 0
.word 0
.word 0
j isr_machine_timer
.word 0
.word 0
.word 0
.option pop
// Dispatch for external IRQs is inlined into the table:
isr_machine_external:
#if __riscv_i
	addi sp, sp, -64
#else
	addi sp, sp, -40
#endif
	sw ra,  0(sp)
	sw t0,  4(sp)
#if __riscv_zilsd
	sd t1,  8(sp)
	sd a0, 16(sp)
	sd a2, 24(sp)
	sd a4, 32(sp)
#else
	sw t1,  8(sp)
	sw t2, 12(sp)
	sw a0, 16(sp)
	sw a1, 20(sp)
	sw a2, 24(sp)
	sw a3, 28(sp)
	sw a4, 32(sp)
	sw a5, 36(sp)
#endif
#if __riscv_i
#if __riscv_zilsd
	sd a6, 40(sp)
	sd t3, 48(sp)
	sd t5, 56(sp)
#else
	sw a6, 40(sp)
	sw a7, 44(sp)
	sw t3, 48(sp)
	sw t4, 52(sp)
	sw t5, 56(sp)
	sw t6, 60(sp)
#endif
#endif

	// No preemption, just handle the IRQs in ascending order. Try not to take
	// exceptions in your IRQ handlers!

	csrrsi a0, hazard3_csr_meinext, 0x1
	bltz a0, no_more_irqs
dispatch_irq:
	csrsi mstatus, 0x8
	// meinext is pre-shifted by 2, so only an add is required to index table
	la a1, _external_irq_table
	add a1, a1, a0
	lw a1, (a1)
	jalr ra, a1
get_next_irq:
	// Sample the current highest-priority active IRQ (left-shifted by 2) from
	// meinext, and write 1 to the LSB to tell hardware to tell hw to update
	// meicontext with the preemption priority (and IRQ number) of this IRQ
	csrrsi a0, hazard3_csr_meinext, 0x1
	// MSB will be set if there is no active IRQ at the current priority level
	bgez a0, dispatch_irq

no_more_irqs:
	lw ra,  0(sp)
	lw t0,  4(sp)
#if __riscv_zilsd
	ld t1,  8(sp)
	ld a0, 16(sp)
	ld a2, 24(sp)
	ld a4, 32(sp)
#else
	lw t1,  8(sp)
	lw t2, 12(sp)
	lw a0, 16(sp)
	lw a1, 20(sp)
	lw a2, 24(sp)
	lw a3, 28(sp)
	lw a4, 32(sp)
	lw a5, 36(sp)
#endif
#if __riscv_i
#if __riscv_zilsd
	ld a6, 40(sp)
	ld t3, 48(sp)
	ld t5, 56(sp)
#else
	lw a6, 40(sp)
	lw a7, 44(sp)
	lw t3, 48(sp)
	lw t4, 52(sp)
	lw t5, 56(sp)
	lw t6, 60(sp)
#endif
#endif
#if __riscv_i
	addi sp, sp, 64
#else
	addi sp, sp, 40
#endif

	mret

.section .data
.global _external_irq_table
_external_irq_table:
.word isr_apu_aout
.word isr_spi_stream
.word isr_ppu
.word isr_vuart
.word isr_apu_timer
.word isr_uart
