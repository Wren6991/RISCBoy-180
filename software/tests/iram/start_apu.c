#include "apu.h"
#include "vuart.h"

// Hack to embed APU binary in IRAM binary
void __attribute__((noreturn, used)) apu_main(void) {
	apu_ipc_hw->softirq_set = 1;
	while (true) {
		asm volatile ("wfi");
	}
}

int main() {
	load_apu_ram((const uint8_t*)&apu_main, 64);
	vuart_puts("Starting APU\n");
	start_apu();
	while (!softirq_status())
		;
	vuart_puts("Received IRQ\n");
}