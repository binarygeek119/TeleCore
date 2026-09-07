#!/bin/sh
# Build the TeleCore BIOS ROMs and fallback hex file.
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

make -C bios "$@"

ls -l "$HERE/bios/boot0.rom" "$HERE/bios/boot1.rom" "$HERE/bios/addon.rom" "$HERE/rtl/fallback.hex"

echo "BIOS build OK."
