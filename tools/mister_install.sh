#!/bin/sh
# Install the latest TeleCore release on a MiSTer.
# Run this script on the MiSTer itself (e.g. via SSH).
set -e

MEDIA="/media/fat"
TMP_DIR="/tmp/telecore_update"
RELEASE_URL="https://github.com/binarygeek119/TeleCore/releases/latest/download/telecore-release.zip"

echo "Downloading latest TeleCore release..."
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
curl -L -o "$TMP_DIR/telecore-release.zip" "$RELEASE_URL"

echo "Extracting..."
unzip -o "$TMP_DIR/telecore-release.zip" -d "$TMP_DIR/staging"

echo "Installing..."
mkdir -p "$MEDIA/_TeleCore" "$MEDIA/games/TeleCore"

cp "$TMP_DIR/staging/telecore-core/output_files/TeleCore.rbf" "$MEDIA/_TeleCore/TeleCore.rbf"
cp "$TMP_DIR/staging/telecore-roms/bios/boot0.rom" "$MEDIA/games/TeleCore/boot0.rom"
cp "$TMP_DIR/staging/telecore-roms/bios/boot1.rom" "$MEDIA/games/TeleCore/boot1.rom"
cp "$TMP_DIR/staging/telecore-roms/bios/addon.rom" "$MEDIA/games/TeleCore/addon.rom"
cp "$TMP_DIR/staging/telecore-roms/rtl/fallback.hex" "$MEDIA/games/TeleCore/fallback.hex"
cp "$TMP_DIR/staging/telecore-phonebook/games/telecore.nvr" "$MEDIA/games/TeleCore/telecore.nvr"

echo "Cleaning up..."
rm -rf "$TMP_DIR"

echo "TeleCore installed from latest release."
