#!/bin/sh
# cbm_run.sh — runs an image in a C64 or VIC-20 ROM socket under MAME with
# the fake RBCP device attached.
#
# usage: cbm_run.sh <arm> <image> <build-dir> <rom-dir>
#
# <arm> selects one of the machine and socket cases below.
#
# <rom-dir> holds the machine's ROM files under their MAME names.  A run on
# anything but the real files proves nothing, so there is no default.
#
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

set -e

here=$(dirname "$0")
: "${MAME:=mame}"

[ $# -eq 4 ] || { echo "usage: $0 <arm> <image> <build-dir> <rom-dir>" >&2; exit 1; }
arm=$1
image=$2
build=$3
rom_dir=$4

if [ ! -d "$rom_dir" ]; then
    echo "$rom_dir: not a directory" >&2
    # A leading ~ typed into a make variable reaches this as a literal.
    case "$rom_dir" in
    "~"*) echo "a leading ~ is not expanded here — use \$HOME or a full path" >&2 ;;
    esac
    exit 1
fi

roms="$build/mame-roms"
stage="$build/mame-stage"
lua="$here/rbcp_dev_cbm.lua"

# A copies entry is <name in rom-dir>[:<name in the stage>].  The C64C's PLA
# is the C64's under another part number, so the combined arm renames it.
case "$arm" in
c64-kernal)
    machine=c64
    socket=901227-03.u4
    copies="901226-01.u3 901225-01.u5 906114-01.u17"
    stock=901227-03.u4                  # what the device serves after a switch
    : "${RBCP_ROM_BASE:=0xE000}" ; : "${RBCP_CMD_PAGE:=0xE0}"
    : "${RBCP_BCH_BASE:=0xE100}" ; : "${RBCP_ROM_SIZE:=0x2000}"
    : "${RBCP_ROM_TYPE:=2}"
    ;;
c64-basic)
    # The stock kernal enters BASIC through the word at $A000, so the BASIC
    # socket is reached only with a real kernal fitted.
    machine=c64
    socket=901226-01.u3
    copies="901227-03.u4 901225-01.u5 906114-01.u17"
    stock=
    : "${RBCP_ROM_BASE:=0xA000}" ; : "${RBCP_CMD_PAGE:=0xA0}"
    : "${RBCP_BCH_BASE:=0xA100}" ; : "${RBCP_ROM_SIZE:=0x2000}"
    : "${RBCP_ROM_TYPE:=2}"
    ;;
c64-combined)
    # The C64C's 16KB kernal socket holds BASIC then KERNAL, as the combined
    # image does.  The command page and back channel are in the BASIC half.
    machine=c64c
    socket=251913-01.u4
    copies="901225-01.u5 906114-01.u17:252715-01.u8"
    stock=
    : "${RBCP_ROM_BASE:=0xA000}" ; : "${RBCP_CMD_PAGE:=0xA0}"
    : "${RBCP_BCH_BASE:=0xA100}" ; : "${RBCP_ROM_SIZE:=0x2000}"
    : "${RBCP_ROM_TYPE:=3}"
    ;;
vic20-pal)
    machine=vic20p
    socket=901486-07.ue12
    copies="901486-01.ue11 901460-03.ud7"
    stock=901486-07.ue12
    : "${RBCP_ROM_BASE:=0xE000}" ; : "${RBCP_CMD_PAGE:=0xE0}"
    : "${RBCP_BCH_BASE:=0xE100}" ; : "${RBCP_ROM_SIZE:=0x2000}"
    : "${RBCP_ROM_TYPE:=2}"
    ;;
vic20-ntsc)
    machine=vic20
    socket=901486-06.ue12
    copies="901486-01.ue11 901460-03.ud7"
    stock=901486-06.ue12
    : "${RBCP_ROM_BASE:=0xE000}" ; : "${RBCP_CMD_PAGE:=0xE0}"
    : "${RBCP_BCH_BASE:=0xE100}" ; : "${RBCP_ROM_SIZE:=0x2000}"
    : "${RBCP_ROM_TYPE:=2}"
    ;;
*)
    echo "$arm: not one of c64-kernal, c64-basic, c64-combined," >&2
    echo "vic20-pal, vic20-ntsc" >&2
    exit 1
    ;;
esac

case "$machine" in
c64|c64c) RBCP_CPU=":u7"    ; RBCP_SCREEN=0x0400 ; RBCP_COLS=40 ; RBCP_ROWS=25 ;;
*)        RBCP_CPU=":ue10"  ; RBCP_SCREEN=0x1E00 ; RBCP_COLS=22 ; RBCP_ROWS=23 ;;
esac

# RBCP_EXP is a MAME expansion cartridge for the VIC-20.  The 3K block leaves
# the screen at $1E00, where the device reads it.
exp=
[ -z "$RBCP_EXP" ] || exp="-exp $RBCP_EXP"

: "${RBCP_BCH_SIZE:=512}"
export RBCP_ROM_BASE RBCP_CMD_PAGE RBCP_BCH_BASE RBCP_BCH_SIZE RBCP_ROM_SIZE \
       RBCP_ROM_TYPE RBCP_CPU RBCP_SCREEN RBCP_COLS RBCP_ROWS

[ -f "$image" ] || { echo "$image not found — use make to build it" >&2; exit 1; }
[ -f "$lua" ] || { echo "no $lua" >&2; exit 1; }
command -v "$MAME" >/dev/null || { echo "$MAME is not installed" >&2; exit 1; }

missing=
for c in $copies $stock; do
    [ -f "$rom_dir/${c%%:*}" ] || missing="$missing ${c%%:*}"
done
if [ -n "$missing" ]; then
    echo "$rom_dir is missing:$missing" >&2
    exit 1
fi

rm -rf "$stage"
mkdir -p "$stage" "$roms"
for c in $copies; do
    cp "$rom_dir/${c%%:*}" "$stage/${c##*:}"
done

cp "$image" "$stage/$socket"

rm -f "$roms/$machine.zip"
(cd "$stage" && zip -q "../mame-roms/$machine.zip" ./*)

# After a switch the device serves the stock ROM for the image's socket, so the
# run continues into a real image.
if [ -z "$RBCP_SWITCH_IMAGE" ] && [ -n "$stock" ]; then
    RBCP_SWITCH_IMAGE="$rom_dir/$stock"
    export RBCP_SWITCH_IMAGE
fi

if [ -n "$RBCP_SNAP" ]; then
    video="-video soft -window -nomaximize"
else
    video="-video none"
fi

log="$build/mame.log"

# MAME's default 1541 drive requires four more ROM files and isn't used here.
#
# On macOS SDL moves the desktop to a new Space even under -video none.  The
# dummy driver prevents that, and snapshots still work.
#
# MAME reports a wrong checksum for the image, which is expected.
#
# Output goes to a file, not a pipe, to keep MAME's exit status on a /bin/sh
# without pipefail.
status=0
SDL_VIDEODRIVER=dummy \
"$MAME" "$machine" -iec8 "" -iec9 "" $exp -rompath "$roms" \
     $video -sound none -skip_gameinfo \
     -nothrottle -cfg_directory "$build/mame-cfg" -nvram_directory "$build/mame-nvram" \
     -snapshot_directory "$build" \
     -autoboot_script "$lua" > "$log" 2>&1 || status=$?
cat "$log"
[ "$status" -eq 0 ] || { echo "$MAME exited $status" >&2; exit "$status"; }

# MAME exits 0 even when the device stops on an error, so the log is checked
# for the device's fatal lines.
if grep -q '^\[dev\] fatal:' "$log"; then
    grep '^\[dev\] fatal:' "$log" >&2
    exit 1
fi
