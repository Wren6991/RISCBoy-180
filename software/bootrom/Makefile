APP       := bootrom
MARCH     := rv32imb_zca_zcb_zbkb_zicsr

EXTRA_SRC := crt0_bootrom.S ../common/libc.S
LDSCRIPT  := rom.ld
INCDIR    := ../include
CROSS     := riscv32-unknown-elf-
CFLAGS    := -Wall -Os --save-temps -ffunction-sections -fdata-sections -Wl,--gc-sections
.SUFFIXES:

.PHONY: all clean
all: build/$(APP).elf ../../hdl/mem/ahb_rom_boot.v
clean:
	rm -rf build

build/$(APP).elf: $(APP).c $(EXTRA_SRC) $(LDSCRIPT) $(INCDIR) $(lastword $(MAKEFILE_LIST))
	mkdir -p build
	$(CROSS)gcc $(CFLAGS) -o $@ $(addprefix -I,$(INCDIR)) $(APP).c $(EXTRA_SRC) \
		-T $(LDSCRIPT) -Wl,--no-warn-rwx -nostartfiles -march=$(MARCH)
	$(CROSS)objdump -hd $@ > $(patsubst %.elf,%.dis,$@)
	$(CROSS)objcopy -O binary $@ $(patsubst %.elf,%.bin,$@)

../../hdl/mem/ahb_rom_boot.v: build/$(APP).elf ../../scripts/bin2rom
	../../scripts/bin2rom -a 20 --outreg $(patsubst %.elf,%.bin,$<) ../../hdl/mem/ahb_rom_boot.v
