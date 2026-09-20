# Amiga Bootloader Test Harness

Runs the built bootloader on an emulated Amiga 500 against a fake RBCP device
written in [MAME](https://mamedev.org)'s Lua, so the menu can be driven without
hardware.

`rbcp_dev_amiga.lua` watches every read in the Kickstart window, decodes the
RBCP command stream out of the addresses, and answers by substituting bytes on
reads of the back-channel region, as a real device does. It implements the
commands the bootloader calls, the pipe and the auxiliary I/O group, and
nothing else. The
[reliability meter](../../amiga-rbcp-stress/test/README.md) drives the same
device from its own `run.sh`.

A 68000 reads its ROM as words, so the tap sees the even CPU address of a word
and never a byte address. One command byte is two CPU address bytes. Region
byte N sits at CPU address `BCH_ABS + (N xor 1)`, so a word read answers with
region bytes `rel+1` and `rel` high byte first, which covers both lanes without
looking at the mask.

The device it pretends to be has five flash slots, two RAM slots, one pipe,
sixteen bytes of writable non-volatile storage and two LEDs of which the second
is the RGB one — so the search for the lowest-numbered RGB LED is exercised
rather than assumed to land on zero. One slot name is mixed case and another is
twenty-nine characters, one short of the most a record holds.

The device carries three groups of auxiliary pins for the harnesses that drive
them. The bootloader drives none.

Pipe writes are collected until the line feed that ends a line and printed
whole because `PIPE_WRITE` moves at most four bytes at a time. The bootloader's
own session log is therefore readable as it runs, and so is the raw device
state behind an error.

## Running

From this directory:

```bash
./run.sh <rom-dir>                    # the 256 KB build, a 27C200 menu
RBCP_TARGET=512 ./run.sh <rom-dir>    # the 512 KB build, a 27C400 menu
```

Build first. `make` writes `build/amiga_boot.bin` and `make ROM_KB=512` writes
the same name, so `run.sh` checks the size on disk and names the `make` to run
when the wrong build is there.

`<rom-dir>` holds the Amiga ROM files, named as MAME names them — see the table
below. There is no default and nothing is read from the environment. Without
the keyboard MCU dump MAME will not start an `a500` at all. `run.sh` names what
is missing and stops rather than filling that gap with something made up.

Every run prints a checksum complaint from MAME about the ROM in the Kickstart
socket. That file is the bootloader, so it does not match the dump MAME expects
there.

## A passing run

With nothing held the bootloader boots its remembered choice, or the first
image where it has none. The run ends at the switch:

```
[dev] chip RAM $001000-$03FFFF dirtied with count
[dev] ENTER_CMD_RESP page=$01FF bch=$03FC00 size=512
[pipe] Amiga RBCP Bootloader 0.1.2
[dev] GET_LED_INFO 0 = monochrome
[dev] GET_LED_INFO 1 = RGB
[pipe] One ROM v0.7.2, 5 flash ROM slots, 2 RAM slots
[dev] NV_PEEK = 0
[pipe] Stored choice: none
[pipe] Booting the stored choice
[dev] SET_LED 1 breathe rgb 00FF00
[pipe] Switching to slot 1
[dev] GET_FLASH_SLOT_INFO 1 = Kickstart 1.3
[pipe]   "Kickstart 1.3"
[pipe] Bootloader finished - resetting system
[dev] LOAD_SLOT ram 1 <- flash 1 (Kickstart 1.3)
[dev] SWITCH_AND_EXIT ram slot 1
[dev] switched, and nothing to switch to — stopping at frame 9
[dev] 82 commands, 0 failed, 0 lost
```

The last line is the device's own tally. A host that draws to a bitmap gives
no other sign of it.

`SWITCH_AND_EXIT` is the end of it. Without a Kickstart to hand over, the
script stops there. With one, the device serves it and the machine runs it, and
the tap ends with the session.

The screen is a bitmap, so there is nothing to print as text. `RBCP_SNAP` saves
it as a PNG instead.

## The ROM files

| Save as | Contents | SHA1 |
|---------|------------|------|
| `6570-036` | the A500 keyboard MCU, 2048 bytes | `83b21d0c8b93fc9b9b3b287fde4ec8f3badac5a2` |
| `315093-01.u2` | Kickstart 1.2, 262144 bytes | `11f9e62cf299f72184835b7b2a70a16333fc0d88` |
| `kick40063.u2` | Kickstart 3.1, 524288 bytes | `3b7f1493b27e212830f989f26ca76c02049f09ca` |
| `logica2.u2` | Logica Diagnostic 2.0, 524288 bytes | `ba10d16166b2e2d6177c979c99edf8462b21651e` |

Only `6570-036` is needed. It is a real dump nothing can stand in for. MAME
looks for it in `a500kbd_us`, `a2000kbd_us` and `a500`, and without it says
`Required files are missing, the machine cannot be run`. It comes with a MAME
ROM set for the Amiga 500. Every SHA1 above is the one MAME expects, so a
downloaded file can be checked with `shasum` before it is used.

The other three are optional. Each is a Kickstart for the device to serve after
the switch so the hand-over can be followed. `RBCP_TARGET=256` looks for
`315093-01.u2` and `RBCP_TARGET=512` for `kick40063.u2` then `logica2.u2` —
MAME's names for Kickstarts of the right size. The socket's own name is taken
by the bootloader. `run.sh` checks the size of what it finds and says when it
finds nothing. MAME never sees these files, so it does not hash them, and
`RBCP_SWITCH_IMAGE` names one directly.

## Settings

Everything is an environment variable:

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_TARGET` | 256 | `256` runs the 27C200 build, `512` the 27C400 build. Both on an `a500`. |
| `RBCP_FRAMES` | 600 | Frame to stop the run on. |
| `RBCP_DIRTY` | `count` | The byte chip RAM is filled with before the application sets its variables up. `count` steps `$FF` down to `$01`, a hex byte such as `FF` fills with that byte throughout, and `off` leaves chip RAM as MAME zeroes it. |
| `RBCP_MOUSE` | unset | Frame the held mouse buttons come up. They are held from the first frame, the gesture that asks for the menu. |
| `RBCP_RCLICK` | unset | Frame of a right click, which boots the highlighted entry. |
| `RBCP_KEYS` | unset | `frame:Key;frame:Key`, each key held for six frames. A key is named by its cap or by any legend on it — `Cursor Up`, `Cursor Down`, `Enter`, `1`, `S` — and otherwise by the start of a cap. |
| `RBCP_SLOTS` | 5 | How many flash slots the device has, the ones past the fifth being filler. More than eight exercises the entries the menu cannot show. |
| `RBCP_RAM_SLOTS` | 2 | One makes the bootloader boot with `LOAD_AND_EXIT` and store its choice without a staging slot. Two make it stage the load in the spare and `SWITCH_AND_EXIT` to it. |
| `RBCP_NV` | 0 | The slot the device has stored. 0 stands for never written. |
| `RBCP_NV_FAIL` | unset | Fail every NV write, which the bootloader carries on through. |
| `RBCP_DEAF` | unset | `GG:CC` — the command the device ignores entirely, so the token never moves. |
| `RBCP_REFUSE` | unset | `GG:CC` — the command the device answers with failed. |
| `RBCP_LATE_RSP` | unset | `GG:CC:reads` — the command whose response byte keeps its old value for that many reads after the device has said the command is complete. That is a device publishing the two out of order. |
| `RBCP_FAIL_EVERY` | unset | One command in this many, whichever it is, answered with failed. |
| `RBCP_LOSE_EVERY` | unset | One command in this many not answered at all, so the host has to reset and re-enter. |
| `RBCP_NO_AUX` | unset | Give the device no auxiliary pins, so `GET_AUX_CAPABILITY` reports a group count of zero and every other command in the group fails. |
| `RBCP_SEND` | unset | A line the far end sends unprompted. `\n` in it is a line feed. |
| `RBCP_SWITCH_IMAGE` | unset | A ROM image to serve once the device has switched slots, in place of the one `run.sh` finds for itself. |
| `RBCP_SNAP` | unset | Save a screenshot at the end of the run, to `build/a500/0000.png`. MAME runs in a window when this is set. |
| `RBCP_DEBUG` | unset | Print every command byte the device sees. |

The progress byte and the response byte share a word, and a 68000 cannot read
one without the other crossing the bus. `RBCP_LATE_RSP` counts word reads, so
the poll that sees the command complete spends the first of them and a count of
2 is the smallest that reaches the host's read of the response.

## Examples

Boot what is stored, with nothing held:

```bash
./run.sh <rom-dir>
```

Hold both buttons to frame 200 for the menu, move down twice, boot the
highlight:

```bash
RBCP_MOUSE=200 RBCP_KEYS='240:Cursor Down;265:Cursor Down;290:Enter' ./run.sh <rom-dir>
```

Refuse `GET_FLASH_SLOT_COUNT` and photograph the error screen:

```bash
RBCP_REFUSE=01:00 RBCP_SNAP=1 RBCP_FRAMES=400 ./run.sh <rom-dir>
```
