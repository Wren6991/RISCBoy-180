APP       := hellow

EXTRA_SRC := ../../common/crt0_eram.S ../../common/libc.S
LDSCRIPT  := ../../ldscript/eram.ld
INCDIR    := ../../include
CROSS     := riscv32-unknown-elf-
CFLAGS    := -Wall -Os -ffunction-sections -fdata-sections -Wl,--gc-sections \
	-march=rv32imb_zca_zcb_zbkb_zicsr -Wa,-march=rv32imb_zca_zcb_zbkb_zicsr_zilsd_zclsd

.SUFFIXES:

.PHONY: all clean
all: build/$(APP).elf
clean:
	rm -rf build

build/$(APP).elf: $(APP).c $(EXTRA_SRC) $(LDSCRIPT) $(INCDIR) Makefile
	mkdir -p build
	$(CROSS)gcc $(CFLAGS) -o $@ $(addprefix -I,$(INCDIR)) $(APP).c $(EXTRA_SRC) \
		-T $(LDSCRIPT) -Wl,--no-warn-rwx -nostartfiles
	$(CROSS)objdump -hd $@ > $(patsubst %.elf,%.dis,$@)
	$(CROSS)objcopy -O binary $@ $(patsubst %.elf,%.bin,$@)
