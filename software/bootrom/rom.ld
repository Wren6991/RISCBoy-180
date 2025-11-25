/* We load into the lower half of IRAM, but the upper half is available for the ROM to use. */

MEMORY {
	ROM  (rx)   : ORIGIN = 0xa0000, LENGTH = 256
	IRAM (rwx)  : ORIGIN = 0x80000 + 7K, LENGTH = 1K
}

OUTPUT_FORMAT("elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS {
	.text : {
		KEEP(*(.init))
		/* fall through: */
		KEEP(*(.text.startup.main))
		*(*.text *.text.*)
		. = ALIGN(4);
	} > ROM

	.rodata : {
		*(.rodata .rodata.*)
		*(.srodata*)
		. = ALIGN(4);
	} > ROM

	.data : {
		__sdata = .;
		*(.data .data.*)
		*(.sdata*)
		. = ALIGN(4);
		__edata = .;
	} > IRAM
	ASSERT(__sdata == __edata, "Initialised static data is not supported in the bootrom.")

	.bss : {
		PROVIDE(__sbss = .);
		*(.bss .bss.*)
		*(.sbss*)
		. = ALIGN(4);
		PROVIDE(__ebss = .);
	} > IRAM


	PROVIDE(__stacktop = ORIGIN(IRAM) + LENGTH(IRAM));
}
