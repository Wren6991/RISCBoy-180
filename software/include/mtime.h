#ifndef _MTIME_H
#define _MTIME_H

#include "addressmap.h"
#include "hw/syscfg_regs.h"

typedef struct {
	volatile uint32_t ctrl;
	uint32_t _pad;
	volatile uint32_t mtime;
	volatile uint32_t mtimeh;
	volatile uint32_t mtimecmp;
	volatile uint32_t mtimecmph;
} mtime_hw_t;

#define mtime_hw ((mtime_hw_t *)TIMER_BASE)

static inline void mtime_set_tick_period(int period) {
	((syscfg_hw_t*)SYSCFG_BASE)->mtime_tick = period;
}

static inline void mtime_set_enabled(bool enabled) {
	mtime_hw->ctrl = enabled;
}

static inline void mtime_set_time(uint64_t time) {
	mtime_hw->mtime = 0;
	mtime_hw->mtimeh = time >> 32;
	mtime_hw->mtime = time & 0xffffffffu;
}

static inline uint64_t mtime_get_time(void) {
	uint32_t h0, l, h1;
	do {
		h0 = mtime_hw->mtimeh;
		l = mtime_hw->mtime;
		h1 = mtime_hw->mtimeh;
	} while (h0 != h1);
	return ((uint64_t)h0 << 32) | l;
}

static inline void mtime_set_timecmp(uint64_t timecmp) {
	mtime_hw->mtimecmp = -1u;
	mtime_hw->mtimecmph = timecmp >> 32;
	mtime_hw->mtimecmp = timecmp & 0xffffffffu;
}

static inline uint64_t mtime_get_mtimecmp(void) {
	return ((uint64_t)mtime_hw->mtimecmph << 32) | mtime_hw->mtimecmp;
}

#endif
