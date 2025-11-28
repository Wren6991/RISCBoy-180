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
#define GPIO_UART_RX 4
#define GPIO_UART_TX 5
#define GPIO_AUDIO_R 6
#define GPIO_AUDIO_L 7

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
