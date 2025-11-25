#include "apu.h"

int main() {
	apu_aout_start();
	apu_aout_ramp_to_midrail();
	while (true) asm ("wfi");
}