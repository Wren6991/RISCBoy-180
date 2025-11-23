#ifndef _APU_H
#define _APU_H

#include "addressmap.h"
#include "hazard3_csr.h"
#include "hw/apu_ipc_regs.h"

// For memcpy, memset
#include <string.h>

#define apu_ipc_hw ((apu_ipc_hw_t *)APU_IPC_BASE)

static inline void load_apu_ram(const uint8_t *src, int len_bytes) {
	memcpy((void*)APU_RAM_BASE, src, len_bytes);
}

static inline void start_apu() {
	apu_ipc_hw->start_apu = 1;
	apu_ipc_hw->start_apu = 0;
}

static inline void softirq_post_other_core(void) {
	apu_ipc_hw->softirq_set = 1u << !read_csr(mhartid);
}

static inline void softirq_clear_current_core(void) {
	apu_ipc_hw->softirq_clr = 1u << read_csr(mhartid);
}

static inline bool softirq_status(void) {
	return read_csr(mip) & 0x8;
}

#endif // _APU_H