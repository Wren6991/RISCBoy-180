#include "vuart.h"

// 16 bytes: enough to cover each byte lane of each RAM bank for the
// 4 x 4 x 512 x 8-bit macro array.
volatile __attribute__((aligned(4))) uint8_t buf[16];

int main() {
	volatile uint32_t *buf32 = (volatile uint32_t*)buf;
	volatile uint16_t *buf16 = (volatile uint16_t*)buf;
	vuart_puts("Zero init\n");
	for (int i = 0; i < 4; ++i) {
		vuart_puthex32(buf32[i]);
		vuart_putc('\n');
	}
	vuart_puts("Byte write\n");
	for (int i = 0; i < 16; ++i) {
		buf[i] = 0xa0 + i;
	}
	for (int i = 0; i < 4; ++i) {
		vuart_puthex32(buf32[i]);
		vuart_putc('\n');
	}
	vuart_puts("Byte write, one per word\n");
	for (int i = 0; i < 4; ++i) {
		buf32[i] = 0;
	}
	for (int i = 0; i < 4; ++i) {
		buf[i * 5] = 0xe0 + i;
	}
	for (int i = 0; i < 4; ++i) {
		vuart_puthex32(buf32[i]);
		vuart_putc('\n');
	}
	vuart_puts("Halfword write\n");
	for (int i = 0; i < 8; ++i) {
		buf16[i] = 0xb1b0 + 2 * i * 0x0101;
	}
	for (int i = 0; i < 4; ++i) {
		vuart_puthex32(buf32[i]);
		vuart_putc('\n');
	}
	vuart_puts("Word write\n");
	for (int i = 0; i < 4; ++i) {
		buf32[i] = 0xc3c2c1c0 + 4 * i * 0x01010101;
	}
	for (int i = 0; i < 4; ++i) {
		vuart_puthex32(buf32[i]);
		vuart_putc('\n');
	}
	vuart_puts("!TPASS");
}
