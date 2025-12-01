#ifndef _DISPCTRL_H
#define _DISPCTRL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "addressmap.h"
#include "hw/ppu_dispctrl_rb180_regs.h"
#include "delay.h"

#define dispctrl_hw ((dispctrl_rb180_hw_t *)DISP_BASE)

// Parallel mode: drive 8 bits at a time on LCD_DAT[7:0]. Serial mode: drive 1
// bit at a time on LCD_DAT[0], and chip select on LCD_DAT[1]. LCD_DAT[7:2]
// can be used as software-controlled GPIOs. Also you can use LCD_DAT[3] as a
// UART output if you do select the display controller :)
static inline void dispctrl_set_parallel_mode(bool parallel) {
	if (parallel) {
		dispctrl_hw->csr |= DISPCTRL_RB180_CSR_LCD_BUSWIDTH_MASK;
	} else {
		dispctrl_hw->csr &= ~DISPCTRL_RB180_CSR_LCD_BUSWIDTH_MASK;
	}
}

// Generally wants to be 16 bits except when you are issuing commands.
static inline void dispctrl_set_shift_width(int width) {
	if (width == 16) {
		dispctrl_hw->csr |= DISPCTRL_RB180_CSR_LCD_SHIFTCNT_MASK;
	} else {
		dispctrl_hw->csr &= ~DISPCTRL_RB180_CSR_LCD_SHIFTCNT_MASK;
	}

}

static inline void dispctrl_set_half_rate(bool half) {
	if (half) {
		dispctrl_hw->csr |= DISPCTRL_RB180_CSR_LCD_HALFRATE_MASK;
	} else {
		dispctrl_hw->csr &= ~DISPCTRL_RB180_CSR_LCD_HALFRATE_MASK;
	}
}

static inline void dispctrl_set_xdouble_ydouble(bool xdouble, bool ydouble) {
	dispctrl_hw->csr = (dispctrl_hw->csr & ~(
		DISPCTRL_RB180_CSR_XDOUBLE_MASK |
		DISPCTRL_RB180_CSR_YDOUBLE_MASK
	)) | (
		(xdouble ? DISPCTRL_RB180_CSR_XDOUBLE_MASK : 0) |
		(ydouble ? DISPCTRL_RB180_CSR_YDOUBLE_MASK : 0)
	);
}

// Once enabled, the display controller will start to read pixels from
// scanline buffers presented by the PPU.
static inline void dispctrl_set_scan_enabled(bool en) {
	if (en) {
		dispctrl_hw->csr |= DISPCTRL_RB180_CSR_SCAN_EN_MASK;
	} else {
		dispctrl_hw->csr &= ~DISPCTRL_RB180_CSR_SCAN_EN_MASK;
	}
}

static inline void dispctrl_set_scanbuf_size(int w) {
	dispctrl_hw->scanbuf_size = w - 1;
}

// CS is ignored in parallel mode, but DC functions as normal. You should only
// call this after polling for CSR_BUSY low e.g. via dispctrl_wait_idle().
static inline void dispctrl_force_dc_cs(bool dc, bool cs) {
	dispctrl_hw->csr = (dispctrl_hw->csr
		& ~(DISPCTRL_RB180_CSR_LCD_CS_MASK | DISPCTRL_RB180_CSR_LCD_DC_MASK))
		| (!!dc << DISPCTRL_RB180_CSR_LCD_DC_LSB)
		| (!!cs << DISPCTRL_RB180_CSR_LCD_CS_LSB);
}

// Push data directly into the display controller pixel FIFO.
static inline void dispctrl_put_hword(uint16_t pixdata) {
	while (dispctrl_hw->csr & DISPCTRL_RB180_CSR_PXFIFO_FULL_MASK)
		;
	dispctrl_hw->pxfifo = pixdata;
}

// Note the shifter always outputs MSB-first, and will simply be configured to get next data
// after shifting 8 MSBs out, so we left-justify the data
static inline void dispctrl_put_byte(uint8_t pixdata) {
	while (dispctrl_hw->csr & DISPCTRL_RB180_CSR_PXFIFO_FULL_MASK)
		;
	dispctrl_hw->pxfifo = (uint16_t)pixdata << 8;
}

static inline void dispctrl_wait_idle() {
	uint32_t csr;
	do {
		csr = dispctrl_hw->csr;
	} while (csr & DISPCTRL_RB180_CSR_TX_BUSY_MASK || !(csr & DISPCTRL_RB180_CSR_PXFIFO_EMPTY_MASK));
}

// Init sequences. Each record consists of:
// - A payload size (including the command byte)
// - A post-delay in units of 5 ms. 0 means no delay.
// - The command payload, including the initial command byte
// A payload size of 0 terminates the list.

static const uint8_t ili9341_init_seq[] = {
	2,  0,  0x36, 0xe8,             // For some reason the display likes to see a MADCTL *before* sw reset after a power cycle. I have no idea why

	1,  30, 0x01,                   // Software reset, 150 ms delay
	2,  24, 0xc1, 0x11,             // PWCTRL2, step up control (BT) = 1, -> VGL = -VCI * 3,  120 ms delay
	3,  0,  0xc5, 0x34, 0x3d,       // VMCTRL1, VCOMH = 4.0 V, VCOML = -0.975 V
	2,  0,  0xc7, 0xc0,             // VMCTRL2, override NVM-stored VCOM offset, and set our own offset of 0 points
	2,  0,  0x36, 0xe8,             // MADCTL, set MX+MY+MV (swap X/Y and flip both axes), set colour order to BGR
	2,  0,  0x3a, 0x55,             // COLMOD, 16 bpp pixel format for both RGB and MCU interfaces
	3,  0,  0xb1, 0x00, 0x18,       // FRMCTR1 frame rate control for normal display mode, no oscillator prescale, 79 Hz refresh
	4,  0,  0xb6, 0x08, 0x82, 0x27, // DFUNCTR: interval scan in non-display area (PTG). Crystal type normally white (REV). Set non-display scan interval (from PTG) to every 5th frame (ISC). Number of lines = 320 (NL). Do not configure external fosc divider (PCDIV).
	2,  0,  0x26, 0x01,             // GAMSET = 0x01, the only defined value for gamma curve selection
	16, 0,  0xe0, 0x0f, 0x31, 0x2b, // PGAMCTRL, positive gamma control, essentially magic as far as I'm concerned
	        0x0c, 0x0e, 0x08, 0x4e,
	        0xf1, 0x37, 0x07, 0x10,
	        0x03, 0x0e, 0x09, 0x00,
	16, 0,  0xe1, 0x00, 0x0e, 0x14, // NGAMCTRL, also magic moon runes
	        0x03, 0x11, 0x07, 0x31,
	        0xc1, 0x48, 0x08, 0x0f,
	        0x0c, 0x31, 0x36, 0x0f,
	1,  30, 0x11,                   // SLPOUT, exit sleep mode and wait 150 ms
	1,  30, 0x29,                   // DISPON, turn display on and wait 150 ms
	0                               // Terminate list
};

static const uint8_t st7789_init_seq[] = {
	1, 30,  0x01,                         // Software reset
	1, 100, 0x11,                         // Exit sleep mode
	2, 2,   0x3a, 0x55,                   // Set colour mode to 16 bit
	2, 0,   0x36, 0x00,                   // Set MADCTL: row then column, refresh is bottom to top ????
	5, 0,   0x2a, 0x00, 0x00, 0x00, 0xf0, // CASET: column addresses from 0 to 240 (f0)
	5, 0,   0x2b, 0x00, 0x00, 0x00, 0xf0, // RASET: row addresses from 0 to 240 (f0)
	1, 2,   0x21,                         // Inversion on, then 10 ms delay (supposedly a hack?)
	1, 2,   0x13,                         // Normal display on, then 10 ms delay
	1, 100, 0x29,                         // Main screen turn on, then wait 500 ms
	0                                     // Terminate list
};

static inline void dispctrl_write_cmd(const uint8_t *cmd, size_t count) {
	dispctrl_wait_idle();
	dispctrl_set_shift_width(8);
	dispctrl_force_dc_cs(0, 0);
	dispctrl_put_byte(*cmd++);
	if (count >= 2) {
		dispctrl_wait_idle();
		dispctrl_force_dc_cs(1, 0);
		for (size_t i = 0; i < count - 1; ++i)
			dispctrl_put_byte(*cmd++);
	}
	dispctrl_wait_idle();
	dispctrl_force_dc_cs(1, 1);
	dispctrl_set_shift_width(16);
}

static inline void dispctrl_init(const uint8_t *init_seq) {
	const uint8_t *cmd = init_seq;
	while (*cmd) {
		dispctrl_write_cmd(cmd + 2, *cmd);
#ifndef DISPCTRL_NO_DELAY
		delay_ms(*(cmd + 1) * 5);
#endif
		cmd += *cmd + 2;
	}
}

static inline void dispctrl_start_pixels() {
	uint8_t cmd = 0x2c;
	dispctrl_write_cmd(&cmd, 1);
	dispctrl_force_dc_cs(1, 0);
}

#endif
