#!/bin/sh
# run.sh — runs the terminal on an emulated VIC-20 with the fake RBCP device
# attached.  See c64-boot/test/README.md.
#
# usage: run.sh <rom-dir> [image]
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

here=$(dirname "$0")
: "${RBCP_TARGET:=pal}"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: $0 <rom-dir> [image]" >&2
    exit 1
fi

case "$RBCP_TARGET" in
pal|ntsc) ;;
*) echo "RBCP_TARGET must be pal or ntsc" >&2; exit 1 ;;
esac

image="${2:-$here/../build/vic20_term_$RBCP_TARGET.bin}"

exec "$here/../../c64-boot/test/cbm_run.sh" "vic20-$RBCP_TARGET" "$image" \
     "$here/../build" "$1"
