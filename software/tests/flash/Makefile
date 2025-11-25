APP       := hellow
MARCH     := rv32imb_zca_zcb_zbkb_zicsr

EXTRA_SRC := ../../common/crt0_iram.S ../../common/libc.S
LDSCRIPT  := ../../ldscript/iram.ld
INCDIR    := ../../include
CROSS     := riscv32-unknown-elf-
CFLAGS    := -Wall -Os

.SUFFIXES:

.PHONY: all clean
all: build/$(APP).elf build/$(APP).padded.bin
clean:
	rm -rf build

build/$(APP).elf: $(APP).c $(EXTRA_SRC) $(LDSCRIPT) $(INCDIR)
	mkdir -p build
	$(CROSS)gcc $(CFLAGS) -o $@ $(addprefix -I,$(INCDIR)) $(APP).c $(EXTRA_SRC) \
		-T $(LDSCRIPT) -Wl,--no-warn-rwx -nostartfiles -march=$(MARCH)
	$(CROSS)objdump -hd $@ > $(patsubst %.elf,%.dis,$@)

build/$(APP).padded.bin: build/$(APP).elf mkflashexec
	$(CROSS)objcopy -O binary $< $(patsubst %.elf,%.bin,$<)
	./mkflashexec $(patsubst %.elf,%.bin,$<) $@