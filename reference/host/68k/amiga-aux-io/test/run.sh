#!/bin/sh
# run.sh — runs the built tester on an emulated Amiga 500 with a fake RBCP
# device attached.  See README.md in this directory.
#
# usage: run.sh <rom-dir>
#
# <rom-dir> holds the Amiga ROM files under the names MAME gives them.  There
# is no default.  MAME will not start an a500 without the keyboard MCU dump.
# That is a real dump and this script cannot make one up.
#
# RBCP_TARGET=256 (the default) runs the 27C200 build, 512 the 27C400 build.
#
# The tester reads the pins every field and redraws what moved, so a run that
# presses nothing still shows the first page working.  RBCP_KEYS is how a run
# drives a pin.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

here=$(dirname "$0")
build="$here/../build"
roms="$build/mame-roms"
stage="$build/mame-stage"
lua="$here/rbcp_dev_auxio.lua"

: "${RBCP_TARGET:=256}"

if [ $# -ne 1 ]; then
    echo "usage: $0 <rom-dir>" >&2
    exit 1
fi
rom_dir=$1
if [ ! -d "$rom_dir" ]; then
    echo "$rom_dir: not a directory" >&2
    # A leading ~ passed through a variable reaches this as a literal.
    case "$rom_dir" in
    "~"*) echo "a leading ~ is not expanded here — use \$HOME or a full path" >&2 ;;
    esac
    exit 1
fi

machine=a500
kbd=6570-036                            # the keyboard MCU, a real dump

case "$RBCP_TARGET" in
256)
    bios=kick13
    socket=315093-02.u2
    bytes=262144
    ;;
512)
    bios=kick204
    socket=390979-01.u2
    bytes=524288
    ;;
*)
    echo "RBCP_TARGET must be 256 or 512" >&2
    exit 1
    ;;
esac

export RBCP_ROM_KB="$RBCP_TARGET"

image="$build/amiga_auxio.bin"
[ -f "$image" ] || { echo "no $image — run make first" >&2; exit 1; }

# The Makefile writes the same file name whichever size it built, so the size
# on disk is the only thing that says which build is there.
size=$(wc -c < "$image" | tr -d ' ')
if [ "$size" != "$bytes" ]; then
    echo "$image is $size bytes and a $RBCP_TARGET KB build is $bytes" >&2
    echo "run: make ROM_KB=$RBCP_TARGET" >&2
    exit 1
fi

command -v mame >/dev/null || { echo "mame is not installed" >&2; exit 1; }
[ -f "$lua" ] || { echo "no $lua" >&2; exit 1; }

if [ ! -f "$rom_dir/$kbd" ]; then
    echo "$rom_dir is missing: $kbd" >&2
    echo "that is the A500 keyboard MCU, and no a500 starts without it" >&2
    echo "see README.md in this directory for where it comes from" >&2
    exit 1
fi

rm -rf "$stage"
mkdir -p "$stage" "$roms"
cp "$rom_dir/$kbd" "$stage/$kbd"

# The tester goes in the Kickstart socket.  It runs from reset and only the
# reset screen hands the machine on, so there is no second image here unless
# RBCP_SWITCH_IMAGE names one.
cp "$image" "$stage/$socket"

rm -f "$roms/$machine.zip"
(cd "$stage" && zip -q "../mame-roms/$machine.zip" ./*)

# A snapshot needs a render target and -video none gives none.  In a window
# MAME stops on the ROM hash warning screen and waits for a keypress the
# script cannot send.  A -seconds_to_run under 300 skips that screen.
if [ -n "$RBCP_SNAP" ]; then
    video="-video soft -window -nomaximize -seconds_to_run 60"
else
    video="-video none"
fi

# On macOS -video none does not stop SDL bringing the real video subsystem up,
# which pulls the desktop across to a new Space.  SDL_VIDEODRIVER=dummy stops
# that, and a snapshot still comes out under it.
#
# MAME hashes every ROM file it is given and reports when one differs from the
# dump it expects.  The tester is in the Kickstart socket, so it never matches,
# and every run prints that complaint.
SDL_VIDEODRIVER=dummy \
mame "$machine" -bios "$bios" -rompath "$roms" \
     $video -sound none -skip_gameinfo \
     -nothrottle -cfg_directory "$build/mame-cfg" -nvram_directory "$build/mame-nvram" \
     -snapshot_directory "$build" \
     -autoboot_script "$lua" 2>&1
