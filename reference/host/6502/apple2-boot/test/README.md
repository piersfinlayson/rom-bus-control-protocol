# Testing the Apple II bootloader without hardware

A fake RBCP device in [MAME](https://mamedev.org)'s Lua. The real binary runs
on an emulated Apple II and is driven through the menu.

`rbcp_dev.lua` watches every read in the ROM's address range, decodes the
command stream out of the addresses, and answers by substituting bytes on reads
of the back channel. It implements the commands the Apple II programs here
call, plus the auxiliary I/O group. Pipe writes are printed.

The device has five flash slots, two RAM slots, one pipe, one byte of
non-volatile storage and two LEDs. The RGB one is the second, so a host has to
find the lowest-numbered RGB LED rather than land on zero. One slot name is
mixed case, because inverse video treats the two cases differently.

Three groups of auxiliary pins, shaped to catch a host that assumed an easy
board:

- ten GPIO, only the even ones from 2 upwards drivable
- four image-select pins, none drivable
- two pads, wired together, so driving pad 0 moves pad 1

A pin's state survives `RBCP_RESET`. A `SET_AUX` carrying a hold is answered
once the hold has elapsed.

## Running

```bash
make test    ROMS=/path/to/apple2/roms    # 2KB build, Apple II+
make test-ef ROMS=/path/to/apple2/roms    # 8KB build, unenhanced IIe
```

Or `./run.sh <rom-dir>` and `RBCP_TARGET=ef ./run.sh <rom-dir>` from this
directory. Give `ROMS` a full path or one starting `$HOME`, because not every
shell expands a leading `~` in a make variable.

`<rom-dir>` holds the machine's ROM files under MAME's names. There is no
default. The character generator is what makes the screen readable, and the
stock image is what the device serves after the slot switch, so `run.sh` names
a missing file and stops.

MAME complains about the checksum of the ROM in the bootloader's socket on
every run. That file is the bootloader.

## ROM files

[`Abdess/retrobios`](https://github.com/Abdess/retrobios), under
`bios/Apple/Apple II/`. `apple2p.zip` and `apple2e.zip` unpack into one
directory. CI takes them from commit `13c5618`.

Apple ][+, from `apple2p.zip`:

| Save as | SHA1 |
|---------|------|
| `341-0011.d0` | `0287ebcef2c1ce11dc71be15a99d2d7e0e128b1e` |
| `341-0012.d8` | `a75ce5aab6401355bf1ab01b04e4946a424879b5` |
| `341-0013.e0` | `8d82a1da63224859bd619005fab62c4714b25dd7` |
| `341-0014.e8` | `37501be96d36d041667c15d63e0c1eff2f7dd4e9` |
| `341-0015.f0` | `e6bf91ed28464f42b807f798fc6422e5948bf581` |
| `341-0020-00.f8` | `a28852ff997b4790e53d8d0352112c4b1a395098` |
| `341-0036.chr` | `f9d312f128c9557d9d6ac03bfad6c3ddf83e5659` |

Unenhanced IIe, MAME's `apple2e`, which `RBCP_TARGET=ef` runs on, from
`apple2e.zip`:

| Save as | SHA1 |
|---------|------|
| `342-0134-a.64` | `8895a4b703f2184b673078f411f4089889b61c54` |
| `342-0135-b.64` | `523838c19c79f481fa02df56856da1ec3816d16e` |
| `342-0132-c.e12` | `12a2e718f5f4acd69b6c33a45a4a940b1440a481` |
| `342-0133-a.chr` | `7060de104046736529c1e8a687a0dd7b84f8c51b` |

MAME fits a Mockingboard in slot 4 and a Disk II controller in slot 6, and
neither source carries their ROMs. `run.sh` leaves both slots empty. With no
disk to boot after the hand-over, the monitor falls through to BASIC.

## Settings

Environment variables.

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_TARGET` | f8 | `f8` runs the 2KB build on an `apple2p`, `ef` the 8KB build on an `apple2e`. |
| `RBCP_NV` | 255 | The slot the device has stored. 255 stands for never written. |
| `RBCP_SLOTS` | 5 | Flash slots the device has, the ones past the fifth being filler. More than eleven exercises the entries a digit cannot pick. |
| `RBCP_KEYS` | none | Keys to press, in order, one every 20 frames. A key in braces is an input port field held for three frames, such as `{Cursor Right}`. |
| `RBCP_KEY_AT` | 150 | Frame the first key is pressed on. |
| `RBCP_FRAMES` | 600 | Frame to print the text screen on and stop. |
| `RBCP_NV_FAIL` | unset | Fail every NV write. The bootloader carries on through it. |
| `RBCP_DEAF` | unset | `GG:CC` — the command the device ignores, so the token never moves. |
| `RBCP_REFUSE` | unset | `GG:CC` — the command the device answers with failed. |
| `RBCP_LATE_RSP` | unset | `GG:CC:reads` — the command whose response byte keeps its old value for that many reads after the device has said it is complete. A device publishing the two out of order. |
| `RBCP_NO_AUX` | unset | Give the device no auxiliary pins. `GET_AUX_CAPABILITY` reports zero groups and every other command in the group fails. |
| `RBCP_SWITCH_IMAGE` | unset | A ROM image to serve once the device has switched slots, so the machine boots something other than the bootloader. |
| `RBCP_SNAP` | unset | Save a screenshot to `build/<machine>/0000.png` at MAME's native 560x192. MAME runs in a window. |
| `RBCP_DEBUG` | unset | Print every command byte the device sees. |

The screen prints as 24 rows of 40 columns. Lower case marks inverse video,
which is how the highlighted line and the title show up.

## Examples

Let the countdown run out, with nothing stored:

```bash
make test
```

Stop the countdown, move down twice, boot what is highlighted:

```bash
RBCP_KEYS='x{Cursor Right}{Cursor Right}
' ./run.sh
```

Boot the stored choice, showing the menu part way through the countdown:

```bash
RBCP_NV=3 RBCP_FRAMES=120 ./run.sh
```
