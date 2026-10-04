#!/bin/sh
# run.sh — runs the bootloader on an emulated C64 with the fake RBCP device
# attached.  See c64-boot/test/README.md.
#
# usage: run.sh <rom-dir>
#
# The menu is drawn only with RBCP_HOLD=CBM.  Otherwise flash slot 1 boots.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

here=$(dirname "$0")

[ $# -eq 1 ] || { echo "usage: $0 <rom-dir>" >&2; exit 1; }

exec "$here/cbm_run.sh" c64-kernal "$here/../build/c64_boot.bin" \
     "$here/../build" "$1"
