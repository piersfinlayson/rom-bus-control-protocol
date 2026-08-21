#!/bin/sh
# make_ef_image.sh — builds an 8KB Apple IIe EF image from a stock EF ROM and
# a 2KB F8 image.
#
# A IIe has no F8 socket.  Its ROM is two 8KB parts, and the one holding the
# reset vector covers $E000-$FFFF, so anything written as a 2KB F8 image — the
# dead test ROM, an older monitor — has to be carried into a IIe inside a whole
# EF image.  This takes the top 2KB of a stock EF ROM out and puts the F8 image
# there, leaving $E000-$F7FF as it was.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

if [ $# -ne 3 ]; then
    cat >&2 <<USAGE
usage: $0 <stock-ef-rom> <f8-image> <output>

  stock-ef-rom  8192 bytes, \$E000-\$FFFF of a IIe.  342-0303-A on an enhanced
                IIe, 342-0134-A on an unenhanced one.
  f8-image      2048 bytes, \$F800-\$FFFF.
  output        8192 bytes, ready to program as one slot.
USAGE
    exit 1
fi

base=$1
f8=$2
out=$3

size() { wc -c < "$1" | tr -d ' '; }

[ -f "$base" ] || { echo "$base: not found" >&2; exit 1; }
[ -f "$f8" ]   || { echo "$f8: not found" >&2; exit 1; }

[ "$(size "$base")" = 8192 ] || { echo "$base: not 8192 bytes" >&2; exit 1; }
[ "$(size "$f8")" = 2048 ]   || { echo "$f8: not 2048 bytes" >&2; exit 1; }

dd if="$base" of="$out" bs=2048 count=3 2>/dev/null
cat "$f8" >> "$out"

echo "$out: $(size "$out") bytes — $base with $f8 at \$F800"
