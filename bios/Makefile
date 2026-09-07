# TeleCore BIOS + ROM build
#   make            -> boot0.rom boot1.rom addon.rom ../rtl/fallback.hex
#   make font       -> regenerate font8x16.inc from the Linux console font
#   make test       -> boot boot0.rom in QEMU (serial on stdio, ESC-x to quit)

NASM   ?= nasm
QEMU   ?= qemu-system-i386
PYTHON ?= python3

all: boot0.rom boot1.rom addon.rom ../rtl/fallback.hex

boot0.rom: bios.asm rom_header.inc vga_init.inc video.inc keyboard.inc serial.inc system.inc romslots.inc sound.inc phonebook.inc setup.inc font8x16.inc
	$(NASM) -f bin $< -o $@
	@test $$(stat -c %s $@) -eq 65536 || (echo "boot0.rom must be 65536 bytes" && exit 1)

boot1.rom: term_stub.asm rom_header.inc
	$(NASM) -f bin $< -o $@

addon.rom: addon_stub.asm rom_header.inc
	$(NASM) -f bin $< -o $@

fallback.bin: fallback.asm vga_init.inc
	$(NASM) -f bin $< -o $@
	@test $$(stat -c %s $@) -eq 512 || (echo "fallback stub must be 512 bytes" && exit 1)

../rtl/fallback.hex: fallback.bin
	$(PYTHON) -c "import sys; d=open('$<','rb').read(); open('$@','w').write(''.join('%02x\n'%b for b in d))"

font: 
	$(PYTHON) ../tools/mkfont.py /usr/lib/kbd/consolefonts/default8x16.psfu.gz font8x16.inc

test: boot0.rom
	$(QEMU) -machine isapc -bios boot0.rom -vga std -serial stdio -m 4

clean:
	rm -f boot0.rom boot1.rom addon.rom fallback.bin

.PHONY: all font test clean
