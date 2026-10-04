#!/bin/sh
# run.sh — runs the bootloader on an emulated VIC-20 with the fake RBCP device
# attached.  See c64-boot/test/README.md.
#
# usage: run.sh <rom-dir>
#
# The menu is drawn only with RBCP_HOLD=CBM.  Otherwise flash slot 1 boots.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

here=$(dirname "$0")
: "${RBCP_TARGET:=pal}"

[ $# -eq 1 ] || { echo "usage: $0 <rom-dir>" >&2; exit 1; }

case "$RBCP_TARGET" in
pal|ntsc) ;;
*) echo "RBCP_TARGET must be pal or ntsc" >&2; exit 1 ;;
esac

exec "$here/../../c64-boot/test/cbm_run.sh" "vic20-$RBCP_TARGET" \
     "$here/../build/vic20_boot_$RBCP_TARGET.bin" "$here/../build" "$1"
