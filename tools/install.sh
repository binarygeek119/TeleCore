#!/bin/sh
# TeleCore installer - run on the PC, copies files to a MiSTer over the network
# or to a mounted SD card.
#
#   tools/install.sh mister            # scp to root@mister (default password "1")
#   tools/install.sh /run/media/$USER/MISTER   # SD card mounted locally
#
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
DEST=${1:-mister}

RBF=$(ls -t "$HERE"/output_files/TeleCore.rbf "$HERE"/releases/*.rbf 2>/dev/null | head -1)
[ -n "$RBF" ] || { echo "no TeleCore.rbf found - build first"; exit 1; }

FILES_CORE="$RBF"
FILES_GAMES="$HERE/bios/boot0.rom $HERE/bios/boot1.rom"
[ -f "$HERE/games/phonebook.pbk" ] && FILES_GAMES="$FILES_GAMES $HERE/games/phonebook.pbk"
[ -f "$HERE/games/settings.nvr" ] && FILES_GAMES="$FILES_GAMES $HERE/games/settings.nvr"

case "$DEST" in
  /*)
    mkdir -p "$DEST/_TeleCore" "$DEST/games/TeleCore/A Drive"
    cp $FILES_CORE  "$DEST/_TeleCore/TeleCore.rbf"
    cp $FILES_GAMES "$DEST/games/TeleCore/"
    [ -f "$HERE/tools/adrive-sync" ] && mkdir -p "$DEST/linux/telecore" && cp "$HERE/tools/adrive-sync" "$DEST/linux/telecore/"
    ;;
  *)
    HOST=$DEST
    ssh "root@$HOST" 'mkdir -p /media/fat/_TeleCore "/media/fat/games/TeleCore/A Drive" /media/fat/linux/telecore'
    scp $FILES_CORE  "root@$HOST:/media/fat/_TeleCore/TeleCore.rbf"
    scp $FILES_GAMES "root@$HOST:/media/fat/games/TeleCore/"
    [ -f "$HERE/tools/adrive-sync" ] && scp "$HERE/tools/adrive-sync" "root@$HOST:/media/fat/linux/telecore/" && \
        ssh "root@$HOST" 'chmod +x /media/fat/linux/telecore/adrive-sync; \
            grep -q telecore/adrive-sync /media/fat/linux/user-startup.sh 2>/dev/null || \
            printf "\n# TeleCore A: drive folder sync\n/media/fat/linux/telecore/adrive-sync &\n" >> /media/fat/linux/user-startup.sh'
    ;;
esac
echo "installed: $(basename "$RBF") + $(echo $FILES_GAMES | wc -w) support files -> $DEST"
