#!/bin/sh
# run.sh — runs the bootloader on an emulated C64 with the fake RBCP device
# attached.  See c64-boot/test/README.md.
#
# usage: run.sh <rom-dir> [image]
#
# The menu is drawn only with RBCP_HOLD=CBM.  Otherwise flash slot 1 boots.
# RBCP_TARGET is kernal, the default, or combined.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

here=$(dirname "$0")
: "${RBCP_TARGET:=kernal}"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: $0 <rom-dir> [image]" >&2
    exit 1
fi

case "$RBCP_TARGET" in
kernal)   default="$here/../build/c64_boot.bin" ;;
combined) default="$here/../build/c64_boot_combined.bin" ;;
*) echo "RBCP_TARGET must be kernal or combined" >&2; exit 1 ;;
esac

exec "$here/cbm_run.sh" "c64-$RBCP_TARGET" "${2:-$default}" \
     "$here/../build" "$1"
