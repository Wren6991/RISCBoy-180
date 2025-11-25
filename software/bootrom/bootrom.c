#include "addressmap.h"
#include <stdint.h>
#include <stddef.h>

#define SECTOR_SIZE 4096

uint8_t get_spi_byte(uint32_t addr) {
	// TODO
	uint8_t x;
	asm volatile ("li %0, 0" : "=&r" (x) : "r" (addr));
	return x;
}

uint32_t checksum_adler32(const uint8_t *buf, size_t len) {
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

int __attribute__((used, noreturn)) main() {
	uint8_t *iram = (uint8_t *)IRAM_BASE;
	// Look for a 4k image with a valid checksum in either of the first two
	// flash sectors. After 10 attempts, give up. 10 is chosen arbitrarily.
	for (int i = 0; i < 10; ++i) {
		uint32_t base_addr = (i & 1) * SECTOR_SIZE;
		for (int i = 0; i < SECTOR_SIZE; ++i) {
			iram[i] = get_spi_byte(base_addr + i);
		}
		uint32_t checksum_expect = *(uint32_t*)&iram[SECTOR_SIZE - 4];
		uint32_t checksum_actual = checksum_adler32(iram, SECTOR_SIZE - 4);
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