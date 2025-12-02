
#include "addressmap.h"
#include "hw/apu_timer_regs.h"
#include "irq.h"
#include "vuart.h"

#define apu_timer_hw ((apu_timer_hw_t *)APU_TIMER_BASE)

#define MAX_IRQS 32
volatile int seen_irqs = 0;
volatile uint8_t irq_history[MAX_IRQS] = {0};

void isr_apu_timer(void) {
	uint32_t status = apu_timer_hw->csr;
	apu_timer_hw->csr = status;
	for (int i = 0; i < APU_TIMER_CSR_IRQ_BITS; ++i) {
		if (status & (1u << (i + APU_TIMER_CSR_IRQ_LSB))) {
			irq_history[seen_irqs++] = i;
		}
		if (seen_irqs >= MAX_IRQS) {
			break;
		}
	}
}

int main() {
	apu_timer_hw->tick = 24 - 1;
	apu_timer_hw->reload0 = 10 - 1;
	apu_timer_hw->reload1 = 15 - 1;
	apu_timer_hw->reload2 = 20 - 1;

	apu_timer_hw->ctr0 = 0;
	apu_timer_hw->ctr1 = 0;
	apu_timer_hw->ctr2 = 0;

	vuart_puts("Starting timer\n");
	apu_timer_hw->csr =
		APU_TIMER_CSR_IRQ_MASK |
		APU_TIMER_CSR_RELOAD_MASK |
		APU_TIMER_CSR_EN_MASK;
	irq_set_enabled(IRQ_APU_TIMER, true);

	while (seen_irqs < MAX_IRQS)
		;
	apu_timer_hw->csr &= ~APU_TIMER_CSR_EN_MASK;
	vuart_puts("Stopped timer\n");

	for (int i = 0; i < MAX_IRQS; ++i) {
		vuart_puthex8(irq_history[i]);
		vuart_putc('\n');
	}

	vuart_puts("!TPASS");
}
