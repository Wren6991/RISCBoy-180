#include "vuart.h"
#include "addressmap.h"

// Make sure the APU RAM is (probably) as big as we think, by walking ones across
// the address bus.

int main() {
	vuart_puts("Writing\n");
	int j = 0;
	for (int i = 1; i < APU_RAM_END - APU_RAM_BASE; i <<= 1) {
		++j;
		((volatile uint8_t*)APU_RAM_BASE)[i] = (j * 0x21) & 0xff;
	}
	vuart_puts("Reading\n");
	j = 0;
	for (int i = 1; i < APU_RAM_END - APU_RAM_BASE; i <<= 1) {
		++j;
		uint8_t result = ((volatile uint8_t*)IRAM_BASE)[i];
		vuart_puthex8(result);
		vuart_putc('\n');
	}
	vuart_puts("!TPASS");
}

