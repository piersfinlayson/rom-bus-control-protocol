#!/bin/sh
# run.sh — runs the auxiliary I/O tester on an emulated C64 with the fake RBCP
# device attached.  See c64-boot/test/README.md.
#
# usage: run.sh <rom-dir> [image]
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
kernal|basic|combined) ;;
*) echo "RBCP_TARGET must be kernal, basic or combined" >&2; exit 1 ;;
esac

image="${2:-$here/../build/c64_auxio_$RBCP_TARGET.bin}"

exec "$here/../../c64-boot/test/cbm_run.sh" "c64-$RBCP_TARGET" "$image" \
     "$here/../build" "$1"
