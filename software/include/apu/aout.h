#ifndef _APU_AOUT_H
#define _APU_AOUT_H

// Low-level accessors for APU audio output pipeline

#include "addressmap.h"
#include "hw/apu_aout_regs.h"

#define apu_aout_hw ((apu_aout_hw_t*)APU_AOUT_BASE)

static inline void apu_aout_start() {
	apu_aout_hw->csr |= APU_AOUT_CSR_ENABLE_MASK;
	while (!(apu_aout_hw->csr & APU_AOUT_CSR_RUNNING_MASK))
		;
}

static inline void apu_aout_set_signed(bool sgn) {
	if (sgn) {
		apu_aout_hw->csr |= APU_AOUT_CSR_SIGNED_MASK;
	} else {
		apu_aout_hw->csr &= ~APU_AOUT_CSR_SIGNED_MASK;
	}
}

static inline void apu_aout_put_blocking(uint16_t l, uint16_t r) {
	uint32_t fifo_data = (uint32_t)l << 16 | (uint32_t)r;
	// RDY is sign bit
	while ((int32_t)apu_aout_hw->csr >= 0)
		;
	apu_aout_hw->fifo = fifo_data;
}

// This process takes 4k samples, or ~80 ms.
static inline void apu_aout_ramp_to_midrail() {
	bool sgn = apu_aout_hw->csr & APU_AOUT_CSR_SIGNED_MASK;
	for (int i = 0; i <= (1 << 15); i += 8) {
		uint16_t lr = (uint16_t)i ^ (sgn ? 0x8000u : 0x0000u);
		apu_aout_put_blocking(lr, lr);
	}
}

static inline void apu_aout_ramp_to_ground() {
	bool sgn = apu_aout_hw->csr & APU_AOUT_CSR_SIGNED_MASK;
	for (int i = (1 << 15); i >= 0; i -= 8) {
		uint16_t lr = (uint16_t)i ^ (sgn ? 0x8000u : 0x0000u);
		apu_aout_put_blocking(lr, lr);
	}
}

static inline void apu_aout_stop() {
	if (!(apu_aout_hw->csr & APU_AOUT_CSR_ENABLE_MASK)) {
		return;
	}
	while (!(apu_aout_hw->csr & APU_AOUT_CSR_RUNNING_MASK))
		;
	apu_aout_hw->csr &= ~APU_AOUT_CSR_ENABLE_MASK;
	while (apu_aout_hw->csr & APU_AOUT_CSR_RUNNING_MASK)
		;
}

#endif