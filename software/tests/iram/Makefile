APP       := hellow
MARCH     := rv32imb_zca_zcb_zbkb

EXTRA_SRC := ../../common/crt0_iram.S ../../common/libc.S
LDSCRIPT  := ../../ldscript/iram.ld
INCDIR    := ../../include
CROSS     := riscv32-unknown-elf-

.SUFFIXES:

.PHONY: all clean
all: build/$(APP).elf
clean:
	rm -rf build

build/$(APP).elf: $(APP).c $(EXTRA_SRC) $(LDSCRIPT) $(INCDIR)
	mkdir -p build
	$(CROSS)gcc -o $@ $(addprefix -I,$(INCDIR)) $(APP).c $(EXTRA_SRC) \
		-T $(LDSCRIPT) -Wl,--no-warn-rwx -nostartfiles -march=$(MARCH) -Os
	$(CROSS)objdump -hd $@ > $(patsubst %.elf,%.dis,$@)
	$(CROSS)objcopy -O binary $@ $(patsubst %.elf,%.bin,$@)
