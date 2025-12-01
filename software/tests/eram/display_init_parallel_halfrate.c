#include "vuart.h"
#include "gpio.h"
#define DISPCTRL_NO_DELAY
#include "dispctrl.h"

int main() {
	gpio_hw->fsel_set = 0xffu << GPIO_LCD_DAT0;
	dispctrl_set_parallel_mode(true);
	dispctrl_set_half_rate(true);
	dispctrl_init(st7789_init_seq);
	vuart_puts("!TPASS");
}
