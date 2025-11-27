APP       := hellow
MARCH     := rv32imb_zca_zcb_zbkb_zicsr

EXTRA_SRC := ../../common/crt0_eram.S ../../common/libc.S
LDSCRIPT  := ../../ldscript/eram.ld
INCDIR    := ../../include
CROSS     := riscv32-unknown-elf-
CFLAGS    := -Wall -Os -ffunction-sections -fdata-sections -Wl,--gc-sections

.SUFFIXES:

.PHONY: all clean
all: build/$(APP).elf
clean:
	rm -rf build

build/$(APP).elf: $(APP).c $(EXTRA_SRC) $(LDSCRIPT) $(INCDIR) Makefile
	mkdir -p build
	$(CROSS)gcc $(CFLAGS) -o $@ $(addprefix -I,$(INCDIR)) $(APP).c $(EXTRA_SRC) \
		-T $(LDSCRIPT) -Wl,--no-warn-rwx -nostartfiles -march=$(MARCH)
	$(CROSS)objdump -hd $@ > $(patsubst %.elf,%.dis,$@)
	$(CROSS)objcopy -O binary $@ $(patsubst %.elf,%.bin,$@)
