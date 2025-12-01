#include "vuart.h"
#include "gpio.h"
#include "dispctrl.h"
#include "ppu.h"

// Check PPU can execute and fetch texels from the full range of ERAM
// addresses.

// From 256k down to 4k, halving:
#define LINKS 7
static_assert((4096 << (LINKS - 1)) == ERAM_END - ERAM_BASE, "");

void write_link(uint32_t *at, int y, const uint32_t *next) {
	ppu_instr_t *p = (ppu_instr_t *)at;
	// 4 words in size:
	p += cproc_blit(p, 0, y, PPU_SIZE_8, 0, PPU_FORMAT_ARGB1555, &at[8]);
	p += cproc_sync(p);
	p += cproc_jump(p, next);
	// Some space before the data because why not:
	at[8] = 0x8000 + y;
}

static inline uintptr_t link_addr(int step) {
	return ERAM_BASE + ((ERAM_END - ERAM_BASE) >> step) - 64u;
}

int main() {
	gpio_hw->fsel_set = 0xffu << GPIO_LCD_DAT0;
	dispctrl_set_parallel_mode(true);
	dispctrl_set_half_rate(false);
	dispctrl_set_shift_width(16);
	dispctrl_set_scanbuf_size(1);
	dispctrl_force_dc_cs(1, 0);
	dispctrl_set_scan_enabled(true);

	vuart_puts("Generating PPU program\n");
	for (int i = 0; i < LINKS; ++i) {
		write_link((uint32_t*)link_addr(i), i, (const uint32_t*)link_addr(i + 1));
	}
	// The last jump is dangling but that's fine because the PPU is set to
	// stop execution on the last SYNC instruction.

	vuart_puts("Starting PPU\n");
	cproc_put_pc((const uint32_t*)link_addr(0));
	ppu_set_display_w_h(1, LINKS);
	ppu_start(true);

	while (ppu_is_running())
		;
	dispctrl_wait_idle();

	vuart_puts("Done\n");
	vuart_puts("!TPASS");
}
