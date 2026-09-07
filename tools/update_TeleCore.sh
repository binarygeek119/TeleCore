#!/bin/sh
# Update TeleCore on a MiSTer from a release zip.
# Run this script on the MiSTer itself (e.g. via SSH or the debug serial port).
#
# Usage:
#   update_TeleCore.sh
#       Downloads the latest release zip from GitHub and installs it.
#   update_TeleCore.sh /path/to/telecore-release.zip
#       Installs a release zip that was already copied to the MiSTer
#       (e.g. over the debug port/serial).
set -e

MEDIA="/media/fat"
TMP_DIR="/tmp/telecore_update"
RELEASE_URL="https://github.com/binarygeek119/TeleCore/releases/latest/download/telecore-release.zip"

ZIP_FILE="$1"

download_release() {
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"

    if command -v curl >/dev/null 2>&1; then
        echo "Downloading latest TeleCore release (curl)..."
        set +e
        curl --location -o "$TMP_DIR/telecore-release.zip" "$RELEASE_URL"
        RET=$?
        set -e
        if [ $RET -ne 0 ]; then
            echo "curl failed, retrying with --insecure..."
            set +e
            curl --insecure --location -o "$TMP_DIR/telecore-release.zip" "$RELEASE_URL"
            RET=$?
            set -e
            if [ $RET -ne 0 ]; then
                echo "Error: failed to download release with curl." >&2
                return $RET
            fi
        fi
    elif command -v wget >/dev/null 2>&1; then
        echo "Downloading latest TeleCore release (wget)..."
        wget --no-check-certificate -O "$TMP_DIR/telecore-release.zip" "$RELEASE_URL"
    else
        echo "Error: curl and wget are both missing. Transfer a release zip" >&2
        echo "over the debug port and run: $0 /path/to/telecore-release.zip" >&2
        return 1
    fi
}

if [ -z "$ZIP_FILE" ]; then
    download_release
    ZIP_FILE="$TMP_DIR/telecore-release.zip"
else
    if [ ! -f "$ZIP_FILE" ]; then
        echo "Error: zip file not found: $ZIP_FILE" >&2
        echo "Usage: $0 [path/to/telecore-release.zip]" >&2
        exit 1
    fi
fi

echo "Extracting..."
rm -rf "$TMP_DIR/staging"
mkdir -p "$TMP_DIR/staging"
unzip -o "$ZIP_FILE" -d "$TMP_DIR/staging"

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

echo "TeleCore updated."
