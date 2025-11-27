#include "vuart.h"
#include "addressmap.h"

// Make sure the IRAM is (probably) as big as we think, by walking ones across
// the address bus. This *probably* doesn't collide with anything important
// like our stack. If it does we will find out, so there's no issue really.

int main() {
	vuart_puts("Writing\n");
	int j = 0;
	for (int i = 1; i < IRAM_END - IRAM_BASE; i <<= 1) {
		++j;
		((volatile uint8_t*)IRAM_BASE)[i] = (j * 0x21) & 0xff;
	}
	vuart_puts("Reading\n");
	j = 0;
	for (int i = 1; i < IRAM_END - IRAM_BASE; i <<= 1) {
		++j;
		uint8_t result = ((volatile uint8_t*)IRAM_BASE)[i];
		vuart_puthex8(result);
		vuart_putc('\n');
	}
	vuart_puts("!TPASS");
}

