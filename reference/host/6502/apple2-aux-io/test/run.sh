#!/bin/sh
# run.sh — runs the auxiliary I/O tester on an emulated Apple IIe with a fake
# RBCP device attached.  See README.md one level up.
#
# usage: run.sh <rom-dir> [image]
#
# <rom-dir> holds the machine's ROM files, named as MAME names them.  There is
# no default: this needs the real ones to say anything about what the machine
# does, so it asks for them rather than making something up.
#
# What to look for is the text screen printed at the end.  RBCP_FRAMES says how
# long it runs before that, and RBCP_KEYS what to press on the way — the tester
# reads the keyboard, so every screen it has is reachable from here.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

here=$(dirname "$0")
build="$here/../build"
roms="$build/mame-roms"
stage="$build/mame-stage"

# The fake device is the one the Apple II bootloader is tested with.  It
# implements the protocol, not this program, so there is one of it.
dev="$here/../../apple2-boot/test/rbcp_dev.lua"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: $0 <rom-dir> [image]" >&2
    exit 1
fi
rom_dir=$1
if [ ! -d "$rom_dir" ]; then
    echo "$rom_dir: not a directory" >&2
    exit 1
fi

machine=apple2e
image="${2:-$build/apple2_auxio.bin}"
socket=342-0134-a.64                # the socket the tester goes in
others="342-0133-a.chr 342-0135-b.64 342-0132-c.e12"

# The tester puts 512 bytes of back channel at $FC00, where the other Apple II
# programs put 64 under the vectors, and the device has to be told which.
RBCP_ROM_BASE=0xE000
RBCP_BCH_BASE=0xFC00
RBCP_BCH_SIZE=512
export RBCP_ROM_BASE RBCP_BCH_BASE RBCP_BCH_SIZE

[ -f "$image" ] || { echo "no $image — run make first" >&2; exit 1; }
[ -f "$dev" ] || { echo "no $dev" >&2; exit 1; }
command -v mame >/dev/null || { echo "mame is not installed" >&2; exit 1; }

missing=
for f in $others $socket; do
    [ -f "$rom_dir/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "$rom_dir is missing:$missing" >&2
    exit 1
fi

rm -rf "$stage"
mkdir -p "$stage" "$roms"
for f in $others; do
    cp "$rom_dir/$f" "$stage/$f"
done

# The tester goes in the socket holding the reset vector, which is the point
# of all this.
cp "$image" "$stage/$socket"

rm -f "$roms/$machine.zip"
(cd "$stage" && zip -q "../mame-roms/$machine.zip" ./*)

# MAME hashes every ROM file it is given and says so when one differs from the
# dump it expects.  The tester is one of those files, and never matches.
#
# Slots 4 and 6 hold a Mockingboard and a Disk II controller by default, and
# both have ROMs of their own.  Neither is anything this test uses, so they are
# left empty and the only files needed are the machine's own.
mame "$machine" -rompath "$roms" -sl4 "" -sl6 "" \
     -video none -sound none -skip_gameinfo \
     -nothrottle -cfg_directory "$build/mame-cfg" -nvram_directory "$build/mame-nvram" \
     -snapshot_directory "$build" \
     -autoboot_script "$dev" 2>&1
