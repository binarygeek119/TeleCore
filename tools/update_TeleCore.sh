#!/bin/bash
# Update TeleCore on a MiSTer from a release zip.
# Based on the MiSTer update_all.sh launcher pattern.
# Run this script on the MiSTer itself.
#
# Usage:
#   update_TeleCore.sh
#       Downloads the latest release zip from GitHub and installs it.
#   update_TeleCore.sh /path/to/telecore-release.zip
#       Installs a release zip that was already copied to the MiSTer.
#
# Set CURL_SSL=--insecure to ignore certificate errors.
# Set DEBUG=1 to print every command as it runs.
set -e

if [ "${DEBUG:-0}" = "1" ]; then
    set -x
fi

MEDIA="/media/fat"
TMP_DIR="/tmp/telecore_update"
RELEASE_URL="https://github.com/binarygeek119/TeleCore/releases/latest/download/telecore-release.zip"

ZIP_FILE="${1:-}"

for tool in curl unzip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: required tool '$tool' is not installed on this MiSTer." >&2
        exit 1
    fi
done

download_file() {
    local DOWNLOAD_PATH="$1"
    local DOWNLOAD_URL="$2"

    set +e
    curl ${CURL_SSL:-} --silent --fail --location -o "${DOWNLOAD_PATH}" "${DOWNLOAD_URL}"
    local CMD_RET=$?
    set -e

    case ${CMD_RET} in
        0)
            return
            ;;
        6)
            echo
            echo "Could not resolve host. Check the MiSTer network connection." >&2
            exit 1
            ;;
        22)
            echo
            echo "Release zip not found at ${DOWNLOAD_URL}." >&2
            echo "The release may still be building, or the tag has no assets." >&2
            exit 1
            ;;
        60|77|35|51|58|59|82|83)
            echo
            echo "Could not establish a secure connection." >&2
            echo "There may be a problem with the certificates." >&2
            echo "Try running with CURL_SSL=--insecure" >&2
            echo "  CURL_SSL=--insecure $0" >&2
            exit 1
            ;;
        127)
            echo "Error: curl is not installed." >&2
            echo "Transfer a release zip over the debug port and run:" >&2
            echo "  $0 /path/to/telecore-release.zip" >&2
            exit 1
            ;;
        *)
            echo
            echo "Download failed (curl exit ${CMD_RET})." >&2
            echo "Check the network connection or transfer a zip manually." >&2
            exit 1
            ;;
    esac
}

validate_zip() {
    local ZIP_PATH="$1"
    if [ ! -s "${ZIP_PATH}" ]; then
        echo "Error: downloaded file is empty." >&2
        echo "The release zip may not be published yet." >&2
        exit 1
    fi
    if ! unzip -t "${ZIP_PATH}" >/dev/null 2>&1; then
        echo "Error: '${ZIP_PATH}' is not a valid zip file." >&2
        echo "First bytes:" >&2
        xxd -l 32 "${ZIP_PATH}" >&2 2>/dev/null || head -c 64 "${ZIP_PATH}" >&2
        exit 1
    fi
}

download_release() {
    rm -rf "${TMP_DIR}"
    mkdir -p "${TMP_DIR}"
    echo "Downloading latest TeleCore release..."
    download_file "${TMP_DIR}/telecore-release.zip" "${RELEASE_URL}"
    validate_zip "${TMP_DIR}/telecore-release.zip"
}

if [ -z "${ZIP_FILE}" ]; then
    download_release
    ZIP_FILE="${TMP_DIR}/telecore-release.zip"
else
    if [ ! -f "${ZIP_FILE}" ]; then
        echo "Error: zip file not found: ${ZIP_FILE}" >&2
        echo "Usage: $0 [path/to/telecore-release.zip]" >&2
        exit 1
    fi
    validate_zip "${ZIP_FILE}"
fi

echo "Extracting..."
rm -rf "${TMP_DIR}/staging"
mkdir -p "${TMP_DIR}/staging"
unzip -o "${ZIP_FILE}" -d "${TMP_DIR}/staging"

echo "Installing..."
mkdir -p "${MEDIA}/_TeleCore" "${MEDIA}/games/TeleCore"

cp "${TMP_DIR}/staging/telecore-core/output_files/TeleCore.rbf"   "${MEDIA}/_TeleCore/TeleCore.rbf"
cp "${TMP_DIR}/staging/telecore-roms/bios/boot0.rom"              "${MEDIA}/games/TeleCore/boot0.rom"
cp "${TMP_DIR}/staging/telecore-roms/bios/boot1.rom"              "${MEDIA}/games/TeleCore/boot1.rom"
cp "${TMP_DIR}/staging/telecore-roms/bios/addon.rom"              "${MEDIA}/games/TeleCore/addon.rom"
cp "${TMP_DIR}/staging/telecore-roms/rtl/fallback.hex"            "${MEDIA}/games/TeleCore/fallback.hex"
cp "${TMP_DIR}/staging/telecore-phonebook/games/phonebook.pbk"    "${MEDIA}/games/TeleCore/phonebook.pbk"
if [ -f "${TMP_DIR}/staging/telecore-settings/games/settings.nvr" ]; then
    cp "${TMP_DIR}/staging/telecore-settings/games/settings.nvr" "${MEDIA}/games/TeleCore/settings.nvr"
fi

echo "Cleaning up..."
rm -rf "${TMP_DIR}"

echo "TeleCore updated."
