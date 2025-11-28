#include "vuart.h"
#include "spi_stream.h"
#include "gpio.h"

int main() {
	gpio_set_alternate(GPIO_SPI_IO0, true);
	gpio_set_alternate(GPIO_SPI_SCK, true);
	gpio_set_alternate(GPIO_SPI_CSN, true);
	gpio_set_alternate(GPIO_SPI_IO1, true);
	for (int clkdiv = 2; clkdiv <= 16; clkdiv += 2) {
		vuart_puts("Trying clkdiv: ");
		vuart_puthex8(clkdiv);
		vuart_putc('\n');
		spi_stream_set_clkdiv(clkdiv);
		spi_stream_start(clkdiv * 2, 1);
		vuart_puthex32(spi_stream_get_blocking());
		vuart_putc('\n');
		if (!spi_stream_is_finished()) {
			vuart_puts("Expected to be finished after length-1 read\n!TFAIL");
		}
		spi_stream_clear_finished();
	}
	vuart_puts("!TPASS");
}
