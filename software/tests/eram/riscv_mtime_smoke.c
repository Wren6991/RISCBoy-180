#include "vuart.h"
#include "mtime.h"
#include "irq.h"

volatile int fired = 0;
#define PERIOD 100
#define START_TIME ((1ull << 32) - 2 * PERIOD)

void __attribute__((interrupt)) isr_machine_timer(void) {
	++fired;
	mtime_set_timecmp(mtime_get_mtimecmp() + PERIOD);
	vuart_puts(".\n");
}

int main() {
	mtime_set_enabled(false);
	mtime_set_tick_period(24);
	mtime_set_time(START_TIME);
	mtime_set_timecmp(START_TIME + PERIOD);
	mtime_set_enabled(true);

	vuart_puts("Starting timer\n");
	timer_irq_enable(true);
	while (fired < 10) {
		asm ("wfi");
	}
	timer_irq_enable(false);
	uint64_t final_time = mtime_get_time() - START_TIME;
	vuart_puts("Stopped timer\n");

	// Should be 1000 us. Print rounded to nearest 50 us.
	vuart_puthex32((((final_time + 25u) / 50u) * 50u) & 0xffffffffu);
	vuart_putc('\n');

	vuart_puts("!TPASS");
}
