#!/bin/sh
# Build the TeleCore FPGA core with Quartus.
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
cd "$HERE"

QSH=$(command -v quartus_sh 2>/dev/null || true)
if [ -z "$QSH" ]; then
    echo "Error: quartus_sh not found in PATH." >&2
    echo "Add Quartus bin/ to PATH or set QUARTUS_ROOTDIR." >&2
    exit 1
fi

"$QSH" --flow compile TeleCore

ls -l "$HERE/output_files/TeleCore.rbf"
echo "Core build OK."
