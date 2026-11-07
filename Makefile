# Pick the cross-toolchain prefix for this OS
ifeq ($(shell uname -s),Darwin)
    CROSS ?= aarch64-elf-
    GDB   ?= aarch64-elf-gdb
else
    CROSS ?= aarch64-linux-gnu-
    GDB   ?= gdb-multiarch
endif

AS   = $(CROSS)as
LD   = $(CROSS)ld
QEMU = qemu-system-aarch64 -M virt -cpu cortex-a72 -nographic -kernel forth.elf

forth.elf: forth.S link.ld forth/core.fs
	$(AS) -g forth.S -o forth.o
	$(LD) -T link.ld forth.o -o forth.elf

run: forth.elf
	$(QEMU)

debug: forth.elf
	$(QEMU) -s -S

gdb:
	$(GDB) forth.elf -ex "target remote :1234"

clean:
	rm -f forth.o forth.elf

.PHONY: run debug gdb clean
