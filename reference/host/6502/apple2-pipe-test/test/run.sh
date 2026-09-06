#!/bin/sh
# run.sh — runs the built tester on an emulated Apple IIe with a fake RBCP
# device attached.  See README.md one level up.
#
# usage: run.sh <rom-dir>
#
# <rom-dir> holds the machine's ROM files, named as MAME names them.  There is
# no default: this needs the real ones to say anything about what the machine
# does, so it asks for them rather than making something up.
#
# RBCP_KEYS picks what is typed once the tester is up, and RBCP_FRAMES how long
# it runs before the text screen is printed.  Both belong to the fake device.
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

if [ $# -ne 1 ]; then
    echo "usage: $0 <rom-dir>" >&2
    exit 1
fi
rom_dir=$1
if [ ! -d "$rom_dir" ]; then
    echo "$rom_dir: not a directory" >&2
    exit 1
fi

machine=apple2e
image="${2:-$build/apple2_pipe_pal.bin}"
socket=342-0134-a.64                # the socket the tester goes in
others="342-0133-a.chr 342-0135-b.64 342-0132-c.e12"

RBCP_ROM_BASE=0xE000
export RBCP_ROM_BASE

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

# The tester goes in the socket holding the reset vector, which is the point of
# all this.
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
