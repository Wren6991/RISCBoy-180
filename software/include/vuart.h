#ifndef _VUART_H
#define _VUART_H

#include "addressmap.h"
#include "hw/vuart_dev_regs.h"

#define vuart_dev_hw ((vuart_dev_hw_t *)VUART_DEV_BASE)

// If host is connected, put character. Otherwise bail out. linefeed is
// converted to carriage return + linefeed.
static inline void vuart_putc(char c) {
	// `status` variable is introduced to avoid redundant read of the status
	// register (costs 3 cycles for an APB read)
	uint32_t status = vuart_dev_hw->stat;
	if (!(status & VUART_DEV_STAT_HOSTCONN_MASK)) {
		return;
	}
	while (!(status & VUART_DEV_STAT_TXRDY_MASK)) {
		status = vuart_dev_hw->stat;
	}
	if (c == '\n') {
		vuart_dev_hw->fifo = (uint32_t)'\r';
		while (!(vuart_dev_hw->stat & VUART_DEV_STAT_TXRDY_MASK))
			;
	}
	vuart_dev_hw->fifo = (uint32_t)c;
}

static inline void vuart_puts(const char *s) {
	if (!(vuart_dev_hw->stat & VUART_DEV_STAT_HOSTCONN_MASK)) {
		return;
	}
	while (*s) {
		if (*s == '\n') {
			while (!(vuart_dev_hw->stat & VUART_DEV_STAT_TXRDY_MASK))
				;
			vuart_dev_hw->fifo = (uint32_t)'\r';
		}
		while (!(vuart_dev_hw->stat & VUART_DEV_STAT_TXRDY_MASK))
			;
		vuart_dev_hw->fifo = (uint32_t)*s;
		++s;
	}
}

static const char vuart_hex_table[16] = {
	'0', '1', '2', '3', '4', '5', '6', '7',
	'8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
};

static inline void vuart_puthex32(uint32_t x) {
	for (int i = 0; i < 32; i += 4) {
		vuart_putc(vuart_hex_table[(x << i) >> 28]);
	}
}

#endif // _VUART_H