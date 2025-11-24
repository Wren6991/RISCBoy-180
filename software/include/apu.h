#ifndef _APU_H
#define _APU_H

#include "apu/ipc.h"
#include "apu/aout.h"

// For memcpy, memset
#include <string.h>

static inline void load_apu_ram(const uint8_t *src, int len_bytes) {
	memcpy((void*)APU_RAM_BASE, src, len_bytes);
}

#endif // _APU_H
