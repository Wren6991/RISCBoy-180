#include "vuart.h"
#include "gpio.h"
#define DISPCTRL_NO_DELAY
#include "dispctrl.h"

int main() {
	gpio_hw->fsel_set = 0x3u << GPIO_LCD_DAT0;
	dispctrl_set_parallel_mode(false);
	dispctrl_set_half_rate(false);
	dispctrl_init(st7789_init_seq);
	vuart_puts("!TPASS");
}
