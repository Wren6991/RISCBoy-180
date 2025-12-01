#ifndef _DELAY_H
#define _DELAY_H

#include <stdint.h>

#ifndef CLK_SYS_MHZ
#define CLK_SYS_MHZ 24
#endif 

static inline void delay_ms(uint32_t ms)
{
	// This ends up fetching 3 words from memory, which cost 2 cycles each
	// over a 16-bit bus.
	uint32_t delay_count = (ms * 1000 * CLK_SYS_MHZ) / 6;
	asm volatile (
		"1:                 \n\t"
		"	addi %0, %0, -1 \n\t"
		"	bge %0, x0, 1b  \n\t"
		: "+r" (delay_count)
	);
}

static inline void delay_us(uint32_t us)
{
	uint32_t delay_count = (us * CLK_SYS_MHZ) / 6;
	asm volatile (
		"1:                 \n\t"
		"	addi %0, %0, -1 \n\t"
		"	bge %0, x0, 1b  \n\t"
		: "+r" (delay_count)
	);
}

#endif // _DELAY_H_
