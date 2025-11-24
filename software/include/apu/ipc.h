#ifndef _APU_IPC_H
#define _APU_IPC_H

#include "addressmap.h"
#include "hazard3_csr.h"
#include "hw/apu_ipc_regs.h"

#define apu_ipc_hw ((apu_ipc_hw_t *)APU_IPC_BASE)

static inline void start_apu() {
	apu_ipc_hw->start_apu = 1;
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

#endif