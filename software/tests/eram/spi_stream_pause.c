#include "vuart.h"
#include "spi_stream.h"
#include "gpio.h"

int main() {
	gpio_set_alternate(GPIO_SPI_IO0, true);
	gpio_set_alternate(GPIO_SPI_SCK, true);
	gpio_set_alternate(GPIO_SPI_CSN, true);
	gpio_set_alternate(GPIO_SPI_IO1, true);
	for (int clkdiv = 2; clkdiv <= 8; clkdiv += 6) {
		vuart_puts("Trying clkdiv: ");
		vuart_puthex8(clkdiv);
		vuart_putc('\n');
		spi_stream_set_clkdiv(clkdiv);
		spi_stream_pause();
		spi_stream_start(0, 8);
		for (int i = 0; i < 8; ++i) {
			if (!spi_stream_is_busy()) {
				vuart_puts("Shouldn't be busy\n!TFAIL");
			}
			if (!(spi_stream_hw->pause & SPI_STREAM_PAUSE_ACK_MASK)) {
				vuart_puts("Should be paused\n!TFAIL");
			}
		}
		spi_stream_unpause();
		while (!(spi_stream_hw->csr & SPI_STREAM_CSR_FVALID_MASK))
			;
		// Can't check this because the pads require !(IE && OE)
		// if (gpio_get(GPIO_SPI_CSN)) {
		// 	vuart_puts("Chip select should be low when not paused\n!TFAIL");
		// }
		spi_stream_pause();
		// if (!gpio_get(GPIO_SPI_CSN)) {
		// 	vuart_puts("Chip select should be high after re-pausing\n!TFAIL");
		// }
		spi_stream_unpause();
		// Wait for full
		while (spi_stream_get_fifo_level() != 2)
			;
		for (int i = 0; i < 8; ++i) {
			vuart_puthex32(spi_stream_get_blocking());
			vuart_putc('\n');
		}
		if (!spi_stream_is_finished()) {
			vuart_puts("Should be finished after reading 8 words\n!TFAIL");
		}
		spi_stream_clear_finished();
	}

	vuart_puts("!TPASS");
}
