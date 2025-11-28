#ifndef _SPI_STREAM_H
#define _SPI_STREAM_H

#include "addressmap.h"
#include "hw/spi_stream_regs.h"

#include <stdint.h>
#include <stddef.h>

#define spi_stream_hw ((spi_stream_hw_t *)APU_SPI_STREAM_BASE)

static inline void spi_stream_start(uint32_t addr, size_t count) {
	spi_stream_hw->addr = addr;
	spi_stream_hw->count = count - 1;
	spi_stream_hw->csr |= SPI_STREAM_CSR_START_MASK;
}

static inline uint32_t spi_stream_get_blocking(void) {
	while (!(spi_stream_hw->csr & SPI_STREAM_CSR_FVALID_MASK))
		;
	return spi_stream_hw->fifo;
}

// FIFO level ranges from 0 to 2. IRQ is raised when FIFO level is greater
// than IRQLEVEL, or when the FINISHED flag is raised (count decrements
// through 0).
static inline void spi_stream_set_irq_level(int level) {
	spi_stream_hw->csr = (spi_stream_hw->csr & ~SPI_STREAM_CSR_IRQLEVEL_MASK) |
		((level << SPI_STREAM_CSR_IRQLEVEL_LSB) & SPI_STREAM_CSR_IRQLEVEL_MASK);
}

// Even values are truncated. Range is 2 through 14. Divisor of 0 means
// division by 16.
static inline void spi_stream_set_clkdiv(int clkdiv) {
	spi_stream_hw->clkdiv = clkdiv;
}

// Really for debugging -- you should know whether more data is coming :)
static inline bool spi_stream_is_busy(void) {
	return spi_stream_hw->csr & SPI_STREAM_CSR_BUSY_MASK;
}

static inline bool spi_stream_is_finished(void) {
	return spi_stream_hw->csr & SPI_STREAM_CSR_FINISHED_MASK;
}

static inline void spi_stream_clear_finished(void) {
	spi_stream_hw->csr = spi_stream_hw->csr;
}

// When the CPU needs to interrupt the SPI stream to borrow the GPIOs, e.g.
// for accessing button shift register:
static inline void spi_stream_pause(void) {
	spi_stream_hw->pause = SPI_STREAM_PAUSE_REQ_MASK;
	while (!(spi_stream_hw->pause & SPI_STREAM_PAUSE_ACK_MASK))
		;
}

static inline void spi_stream_unpause(void) {
	spi_stream_hw->pause = 0;
	while (spi_stream_hw->pause & SPI_STREAM_PAUSE_ACK_MASK)
		;
}

#endif
