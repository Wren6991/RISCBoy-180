#include "apu.h"

int main() {
	apu_aout_start();

	for (int i = 0; i < 8; ++i) {
		apu_aout_put_blocking(0, 0);
	}
	for (int i = 0; i < 8; ++i) {
		apu_aout_put_blocking(0, -1u);
	}
	for (int i = 0; i < 8; ++i) {
		apu_aout_put_blocking(0, 0);
	}
	apu_aout_ramp_to_midrail();
	while (true) asm ("wfi");
}
