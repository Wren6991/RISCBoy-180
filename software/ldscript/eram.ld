MEMORY {
	ERAM (rwx)  : ORIGIN = 0x00000, LENGTH = 512K
	IRAM (rwx)  : ORIGIN = 0x80000, LENGTH = 8K
}

OUTPUT_FORMAT("elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS {
	.text : {
		KEEP(*(.init))
		*(*.text *.text.*)
		. = ALIGN(4);
	} > ERAM

	.rodata : {
		*(.rodata .rodata.*)
		. = ALIGN(4);
	} > ERAM

	.data : {
		*(.data .data.*)
		. = ALIGN(4);
	} > ERAM

	.sdata : {
		__global_pointer$ = . + 2K;
		*(.srodata*)
		*(.sdata*)
		*(.sbss*)
		. = ALIGN(4);
	} > ERAM

	.bss : {
		PROVIDE(__sbss = .);
		*(.bss .bss.*)
		. = ALIGN(4);
		PROVIDE(__ebss = .);
	} > ERAM

	PROVIDE(__stacktop = ORIGIN(IRAM) + LENGTH(IRAM));
}
