#include <stdint.h>
#include <stddef.h>

#include "addressmap.h"
#include "gpio.h"
#include "spi_stream.h"

#define SECTOR_SIZE_BYTES 4096
#define BINARY_SIZE_BYTES 1024

static void spi_init() {
	gpio_hw->fsel_set =
		1u << GPIO_SPI_IO0 |
		1u << GPIO_SPI_SCK |
		1u << GPIO_SPI_CSN |
		1u << GPIO_SPI_IO1;
	// CLKDIV=4 -> 3 MHz SCK at nominal 24 MHz CLK psd input (since clk_sys is
	// divided by 2 initially)
	spi_stream_set_clkdiv(4);
}

static uint32_t checksum_adler32(const uint8_t *buf, size_t len) {
    uint32_t s1 = 1;
    uint32_t s2 = 0;
    const uint32_t PRIME = 65521;
    for (size_t i = 0; i < len; ++i) {
        s1 += buf[i];
        if (s1 >= PRIME) {
        	s1 -= PRIME;
        }
        s2 += s1;
        if (s2 >= PRIME) {
        	s2 -= PRIME;
        }
    }
    return (s2 << 16) | (s1 & 0xffff);
}

// Use of naked means prolog is omitted (GCC stacks registers even for
// noreturn). Not supposed to do this if there are C statements in the body,
// so need to review the disassembly after changes.
int __attribute__((used, noreturn, naked)) main() {
	uint8_t *iram = (uint8_t *)IRAM_BASE;
	uint32_t *iram32 = (uint32_t *)IRAM_BASE;
	// Look for a 4k image with a valid checksum in either of the first two
	// flash sectors. After 10 attempts, give up. 10 is chosen arbitrarily.
	spi_init();
	for (int i = 0; i < 10; ++i) {
		spi_stream_start((i & 1) * SECTOR_SIZE_BYTES, BINARY_SIZE_BYTES);
		for (int j = 0; j < BINARY_SIZE_BYTES / 4; ++j) {
			iram32[j] = spi_stream_get_blocking();
		}
		uint32_t checksum_expect = *(uint32_t*)&iram[BINARY_SIZE_BYTES - 4];
		uint32_t checksum_actual = checksum_adler32(iram, BINARY_SIZE_BYTES - 4);
		if (checksum_expect == checksum_actual) {
			// Here we go gamers
			((void(*)())iram)();
			__builtin_unreachable();
		}
	}
	// Well fuck. Might as well sit here
	while (true) {
		asm ("wfi");
	}
	__builtin_unreachable();
}
