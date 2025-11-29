#ifndef _GPIO_H
#define _GPIO_H

#include "addressmap.h"
#include "hw/gpio_regs.h"
#include "hw/padctrl_regs.h"

#define padctrl_hw ((padctrl_hw_t*)PADCTRL_BASE)
#define gpio_hw ((gpio_hw_t*)GPIO_BASE)

#define GPIO_SPI_IO0 0
#define GPIO_SPI_SCK 1
#define GPIO_SPI_CSN 2
#define GPIO_SPI_IO1 3
#define GPIO_LCD_DAT0 4
// DAT1 is also chip select in SPI mode:
#define GPIO_LCD_DAT1 5
#define GPIO_LCD_DAT2 6
#define GPIO_LCD_DAT3 7
#define GPIO_LCD_DAT4 8
#define GPIO_LCD_DAT5 9
#define GPIO_LCD_DAT6 10
#define GPIO_LCD_DAT7 11
#define GPIO_AUDIO 12

static inline void gpio_pull_down(int gpio) {
	uint32_t mask = 1u << gpio;
	padctrl_hw->gpio_pu &= ~mask;
	padctrl_hw->gpio_pd |= mask;
}

static inline void gpio_pull_up(int gpio) {
	uint32_t mask = 1u << gpio;
	padctrl_hw->gpio_pd &= ~mask;
	padctrl_hw->gpio_pu |= mask;
}

static inline void gpio_pull_none(int gpio) {
	uint32_t mask = 1u << gpio;
	padctrl_hw->gpio_pd &= ~mask;
	padctrl_hw->gpio_pu &= ~mask;
}

static inline void gpio_set_alternate(int gpio, bool alt) {
	uint32_t mask = 1u << gpio;
	if (alt) {
		gpio_hw->fsel_set = mask;
	} else {
		gpio_hw->fsel_clr = mask;
	}
}

static inline void gpio_output_enable(int gpio, bool en) {
	if (en) {
		gpio_hw->oen_set = 1u << gpio;
	} else {
		gpio_hw->oen_clr = 1u << gpio;
	}
}

static inline void gpio_put(int gpio, bool high_nlow) {
	if (high_nlow) {
		gpio_hw->out_set = 1u << gpio;
	} else {
		gpio_hw->out_clr = 1u << gpio;
	}
}

static inline void gpio_toggle(int gpio) {
	gpio_hw->out_xor = 1u << gpio;
}

static inline bool gpio_get(int gpio) {
	return gpio_hw->in & (1u << gpio);
}

#endif
