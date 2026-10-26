#!/bin/sh
# run.sh — runs the built bootloader on an emulated Amiga with a fake RBCP
# device attached.  See README.md in this directory.
#
# usage: run.sh <rom-dir>
#
# <rom-dir> holds the Amiga ROM files under the names MAME gives them.  There
# is no default.  MAME will not start an a500 without the keyboard MCU dump.
# That is a real dump and this script cannot make one up.
#
# RBCP_TARGET=256 (the default) runs the 27C200 build on an A500, 512 the
# 27C400 build.  a1200, a3000, a4000 and a4000t run the 32-bit 27C200 pair on
# that machine, and a1200-512 the 32-bit 27C400 pair on an A1200.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

here=$(dirname "$0")
build="$here/../build"
roms="$build/mame-roms"
stage="$build/mame-stage"

: "${RBCP_TARGET:=256}"

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

machine=a500
kbd=6570-036                            # the keyboard MCU, a real dump
kbd_slot=
dev_kb=256

case "$RBCP_TARGET" in
256)
    bios=kick13
    socket=315093-02.u2
    bytes=262144
    # A genuine Kickstart to hand over to, under any of MAME's other names for
    # a ROM of this size.  The socket's own name is taken by the bootloader.
    stock_names=315093-01.u2
    ;;
512)
    bios=kick204
    socket=390979-01.u2
    bytes=524288
    stock_names="kick40063.u2 logica2.u2"
    ;;
# The 32-bit machines.  The high word's socket comes first in sockets.  Each
# entry in stock_pairs is a pair of halves, together one Kickstart.
a1200|a1200-512)
    # -kbd fits the A2000 keyboard in place of the A1200's, so the A1200
    # keyboard's MCU dump isn't needed.  The A2000 keyboard uses the A500's.
    machine=a1200
    kbd_slot="-kbd a2000_us"
    bios=kick31
    sockets="391773-01.u6a 391774-01.u6b"
    stock_pairs="391523-01.u6a:391524-01.u6b logica2.u6a:logica2.u6b"
    if [ "$RBCP_TARGET" = a1200-512 ]; then
        dev_kb=512
    fi
    ;;
a3000)
    machine=a3000
    bios=kick31
    sockets="kick31.u182 kick31.u183"
    stock_pairs="390629-03.u182:390630-03.u183 logica2.u182:logica2.u183"
    ;;
a4000|a4000t)
    machine=$RBCP_TARGET
    if [ "$machine" = a4000 ]; then
        bios=kick31-68
        sockets="kick40068.u175 kick40068.u176"
        stock_pairs="kick40070.u175:kick40070.u176 391513-02.u175:391514-02.u176"
    else
        bios=kick31
        sockets="391657-01.u175 391658-01.u176"
    fi
    stock_pairs="$stock_pairs logica2.u6a:logica2.u6b"
    ;;
*)
    echo "RBCP_TARGET must be 256, 512, a1200, a1200-512, a3000, a4000 or a4000t" >&2
    exit 1
    ;;
esac

if [ -n "$sockets" ]; then
    export RBCP_BUS=32 RBCP_ROM_KB=512 RBCP_DEV_KB=$dev_kb
    bytes=524288
    halves="$build/amiga_boot_32bit_${dev_kb}k_hi.bin $build/amiga_boot_32bit_${dev_kb}k_lo.bin"
    for f in $halves; do
        [ -f "$f" ] || { echo "$f not found — use make BUS=32 ROM_KB=$dev_kb to build it" >&2; exit 1; }
    done
    command -v python3 >/dev/null || { echo "python3 is not installed" >&2; exit 1; }
else
    export RBCP_ROM_KB="$RBCP_TARGET"

    image="$build/amiga_boot.bin"
    [ -f "$image" ] || { echo "$image not found — use make to build it" >&2; exit 1; }

    # The Makefile writes the same file name whichever size it built, so the
    # size on disk is the only thing that says which build is there.
    size=$(wc -c < "$image" | tr -d ' ')
    if [ "$size" != "$bytes" ]; then
        echo "$image is $size bytes and a $RBCP_TARGET KB build is $bytes" >&2
        echo "run: make ROM_KB=$RBCP_TARGET" >&2
        exit 1
    fi
fi

command -v mame >/dev/null || { echo "mame is not installed" >&2; exit 1; }

if [ ! -f "$rom_dir/$kbd" ]; then
    echo "$rom_dir is missing: $kbd" >&2
    echo "that is the A500 keyboard MCU, and no a500 starts without it" >&2
    echo "see README.md in this directory for where it comes from" >&2
    exit 1
fi

rm -rf "$stage"
mkdir -p "$stage" "$roms"
cp "$rom_dir/$kbd" "$stage/$kbd"

# The bootloader goes in the Kickstart socket, or both sockets on a 32-bit
# machine.  MAME holds a 32-bit machine's halves in the device's byte order,
# so the halves go in as built.  A 27C400 half holds its 256 KB twice, and
# only the first copy goes in.
if [ -n "$sockets" ]; then
    set -- $halves
    for socket in $sockets; do
        head -c 262144 "$1" > "$stage/$socket"
        shift
    done
else
    cp "$image" "$stage/$socket"
fi

rm -f "$roms/$machine.zip"
(cd "$stage" && zip -q "../mame-roms/$machine.zip" ./*)

# A pair of 32-bit halves, as MAME holds them, put back together as the CPU
# reads them.
join_halves() {
    python3 -c 'import sys; h = open(sys.argv[1], "rb").read(); l = open(sys.argv[2], "rb").read(); open(sys.argv[3], "wb").write(b"".join(h[i+1:i+2] + h[i:i+1] + l[i+1:i+2] + l[i:i+1] for i in range(0, len(h), 2)))' "$@"
}

# The fake device serves this image once it has switched slots, so the
# hand-over can be followed into a real Kickstart.  Without one the bootloader
# is still the image in the socket after the switch, and the run stops there
# instead.
if [ -z "$RBCP_SWITCH_IMAGE" ]; then
    for f in $stock_names; do
        [ -f "$rom_dir/$f" ] || continue
        [ "$(wc -c < "$rom_dir/$f" | tr -d ' ')" = "$bytes" ] || continue
        RBCP_SWITCH_IMAGE="$rom_dir/$f"
        break
    done
    for pair in $stock_pairs; do
        hi="$rom_dir/${pair%%:*}"
        lo="$rom_dir/${pair#*:}"
        [ -f "$hi" ] && [ -f "$lo" ] || continue
        [ "$(wc -c < "$hi" | tr -d ' ')" = $((bytes / 2)) ] || continue
        [ "$(wc -c < "$lo" | tr -d ' ')" = $((bytes / 2)) ] || continue
        RBCP_SWITCH_IMAGE="$build/switch_32bit.bin"
        join_halves "$hi" "$lo" "$RBCP_SWITCH_IMAGE"
        break
    done
    if [ -n "$RBCP_SWITCH_IMAGE" ]; then
        export RBCP_SWITCH_IMAGE
    else
        echo "no $bytes-byte Kickstart in $rom_dir named $stock_names$stock_pairs" >&2
        echo "the run stops at the switch rather than following the hand-over" >&2
    fi
fi

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
# dump it expects.  The bootloader is in the Kickstart socket, so it never
# matches, and every run prints that complaint.
SDL_VIDEODRIVER=dummy \
mame "$machine" $kbd_slot -bios "$bios" -rompath "$roms" \
     $video -sound none -skip_gameinfo \
     -nothrottle -cfg_directory "$build/mame-cfg" -nvram_directory "$build/mame-nvram" \
     -snapshot_directory "$build" \
     -autoboot_script "$here/rbcp_dev_amiga.lua" 2>&1
