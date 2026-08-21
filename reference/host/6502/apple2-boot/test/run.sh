#!/bin/sh
# run.sh — runs the built bootloader on an emulated Apple II with a fake RBCP
# device attached.  See README.md in this directory.
#
# usage: run.sh <rom-dir>
#
# <rom-dir> holds the machine's ROM files, named as MAME names them.  There is
# no default: this needs the real ones to say anything about what the machine
# does, so it asks for them rather than making something up.
#
# RBCP_TARGET=f8 (the default) runs the 2KB build on an Apple II+.
# RBCP_TARGET=ef runs the 8KB build on an unenhanced IIe.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

here=$(dirname "$0")
build="$here/../build"
roms="$build/mame-roms"
stage="$build/mame-stage"

: "${RBCP_TARGET:=f8}"

if [ $# -ne 1 ]; then
    echo "usage: $0 <rom-dir>" >&2
    exit 1
fi
rom_dir=$1
if [ ! -d "$rom_dir" ]; then
    echo "$rom_dir: not a directory" >&2
    # A leading ~ typed into a make variable reaches this as a literal.
    case "$rom_dir" in
    "~"*) echo "a leading ~ is not expanded here — use \$HOME or a full path" >&2 ;;
    esac
    exit 1
fi

case "$RBCP_TARGET" in
f8)
    machine=apple2p
    image="$build/apple2_boot_f8.bin"
    socket=341-0020-00.f8               # the socket the bootloader goes in
    stock="$rom_dir/341-0020-00.f8"     # what it hands over to
    others="341-0036.chr 341-0011.d0 341-0012.d8 341-0013.e0 341-0014.e8 341-0015.f0"
    : "${RBCP_ROM_BASE:=0xF800}"
    ;;
ef)
    machine=apple2e
    image="$build/apple2_boot_ef.bin"
    socket=342-0134-a.64
    stock="$rom_dir/342-0134-a.64"
    others="342-0133-a.chr 342-0135-b.64 342-0132-c.e12"
    : "${RBCP_ROM_BASE:=0xE000}"
    ;;
*)
    echo "RBCP_TARGET must be f8 or ef" >&2
    exit 1
    ;;
esac

export RBCP_ROM_BASE

[ -f "$image" ] || { echo "no $image — run make first" >&2; exit 1; }
command -v mame >/dev/null || { echo "mame is not installed" >&2; exit 1; }

# The socket the bootloader goes in is the one file taken from the build rather
# than from rom_dir, and the stock ROM out of that same socket is what the fake
# device serves after the switch, so the hand-over can be followed into the
# image the user picked.
missing=
for f in $others $socket; do
    [ -f "$rom_dir/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "$rom_dir is missing:$missing" >&2
    echo "see README.md in this directory for where these come from" >&2
    exit 1
fi

rm -rf "$stage"
mkdir -p "$stage" "$roms"
for f in $others; do
    cp "$rom_dir/$f" "$stage/$f"
done

if [ -z "$RBCP_SWITCH_IMAGE" ]; then
    RBCP_SWITCH_IMAGE="$stock"
    export RBCP_SWITCH_IMAGE
fi

# The bootloader goes in the socket holding the reset vector, which is the
# point of all this.
cp "$image" "$stage/$socket"

rm -f "$roms/$machine.zip"
(cd "$stage" && zip -q "../mame-roms/$machine.zip" ./*)

# MAME hashes every ROM file it is given and says so when one differs from the
# dump it expects.  The bootloader is one of those files, and never matches.
#
# Slots 4 and 6 hold a Mockingboard and a Disk II controller by default, and
# both have ROMs of their own.  Neither is anything this test uses, so they are
# left empty and the only files needed are the machine's own.
mame "$machine" -rompath "$roms" -sl4 "" -sl6 "" \
     -video none -sound none -skip_gameinfo \
     -nothrottle -cfg_directory "$build/mame-cfg" -nvram_directory "$build/mame-nvram" \
     -snapshot_directory "$build" \
     -autoboot_script "$here/rbcp_dev.lua" 2>&1
