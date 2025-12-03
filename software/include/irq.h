#ifndef _IRQ_H
#define _IRQ_H

#include "hazard3_csr.h"
#ifndef __ASSEMBLER__
#include "stdint.h"
#include "stdbool.h"
#endif

// mip.meip mapping:
// APU and CPU:
#define IRQ_APU_AOUT   0
#define IRQ_SPI_STREAM 1
// CPU only (APU timer is mtip on APU):
#define IRQ_PPU        2
#define IRQ_VUART      3
#define IRQ_APU_TIMER  4
#define IRQ_UART       5
#define NUM_IRQS       6

#ifndef __ASSEMBLER__
extern uintptr_t _external_irq_table[NUM_IRQS];

#define h3irq_array_read(csr, index) (read_set_csr(csr, (index)) >> 16)

#define h3irq_array_write(csr, index, data) (write_csr(csr, (index) | ((uint32_t)(data) << 16)))
#define h3irq_array_set(csr, index, data) (set_csr(csr, (index) | ((uint32_t)(data) << 16)))
#define h3irq_array_clear(csr, index, data) (clear_csr(csr, (index) | ((uint32_t)(data) << 16)))

static inline void irq_set_enabled(unsigned int irq, bool enable) {
	if (enable) {
		h3irq_array_set(hazard3_csr_meiea, irq >> 4, 1u << (irq & 0xfu));
	}
	else {
		h3irq_array_clear(hazard3_csr_meiea, irq >> 4, 1u << (irq & 0xfu));
	}
}

static inline bool irq_is_pending(unsigned int irq) {
	return h3irq_array_read(hazard3_csr_meipa, irq >> 4) & (1u << (irq & 0xfu));
}

static inline void irq_force_pending(unsigned int irq, bool force) {
	if (force) {
		h3irq_array_set(hazard3_csr_meifa, irq >> 4, 1u << (irq & 0xfu));
	}
	else {
		h3irq_array_clear(hazard3_csr_meifa, irq >> 4, 1u << (irq & 0xfu));
	}
}

static inline bool irq_is_forced(unsigned int irq) {
	return h3irq_array_read(hazard3_csr_meifa, irq >> 4) & (1u << (irq & 0xfu));
}

// -1 for no IRQ
static inline int get_current_irq() {
	uint32_t meicontext = read_csr(hazard3_csr_meicontext);
	return meicontext & 0x8000u ? -1 : (meicontext >> 4) & 0x1ffu;
}

static inline void irq_set_handler(unsigned int irq, void (*handler)(void)) {
	_external_irq_table[irq] = (uintptr_t)handler;
}

static inline void global_irq_enable(bool en) {
	// mstatus.mie
	if (en) {
		set_csr(mstatus, 0x8);
	}
	else {
		clear_csr(mstatus, 0x8);
	}
}

static inline void external_irq_enable(bool en) {
	// mie.meie
	if (en) {
		set_csr(mie, 0x800);
	}
	else {
		clear_csr(mie, 0x800);
	}
}

static inline void timer_irq_enable(bool en) {
	// mie.mtie
	if (en) {
		set_csr(mie, 0x080);
	}
	else {
		clear_csr(mie, 0x080);
	}
}

static inline void soft_irq_enable(bool en) {
	// mie.msie
	if (en) {
		set_csr(mie, 0x008);
	}
	else {
		clear_csr(mie, 0x008);
	}
}

#endif // !__ASSEMBLER__

#endif
