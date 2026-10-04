# C64 and VIC-20 Test Harness

Runs a built image on an emulated C64 or VIC-20 against a fake RBCP device
written in [MAME](https://mamedev.org)'s Lua, so an application can be driven
without hardware. Every C64 and VIC-20 ROM image here runs this way.

`rbcp_dev_cbm.lua` watches every read in the ROM window, decodes the RBCP
command stream out of the addresses, and answers by substituting bytes on reads
of the back-channel region, as a real device does. It implements the commands
these applications call, including the pipe and the auxiliary I/O group.

`cbm_run.sh` stages the image into the socket and starts the machine. Each
application's `run.sh` names its own image and arm and calls it. The harness
sits under the bootloader to match the Apple II one in
[`../../apple2-boot/test/`](../../apple2-boot/test/README.md).

The screen is character-mapped, so the device reads it out of screen RAM and
prints it as text at the end of a run.

## The device it pretends to be

Five flash slots, two RAM slots, one pipe, sixteen bytes of writable
non-volatile storage and two LEDs. The RGB one is the second, so a host has to
find the lowest-numbered RGB LED rather than land on zero. The slot names are
mostly mixed case, because inverse video treats the two cases differently.

A `SET_LED` is remembered and read back through `GET_LED_INFO`, which the
tester compares against what it asked for.

Three groups of auxiliary pins:

- ten GPIO, only pins 2, 4, 6 and 8 drivable
- four image-select pins, none drivable
- two pads, wired together, so driving pad 0 moves pad 1

A pin's state survives `RBCP_RESET`. A `SET_AUX` carrying a hold is answered
once the hold has elapsed.

`PIPE_WRITE` moves at most four bytes at a time, so writes are collected to the
line feed and printed whole.

## The arms

An arm is a machine and a target. Each application's `run.sh` knows its
machine and `RBCP_TARGET` picks the target, so `kernal` on a C64 application
gives `c64-kernal`. The arm sets the socket the image goes in and the screen
the device reads.

| Arm | MAME machine | Socket | For |
| --- | --- | --- | --- |
| `c64-kernal` | `c64` | `901227-03.u4` | an 8KB kernal image |
| `c64-basic` | `c64` | `901226-01.u3` | an 8KB BASIC image |
| `c64-combined` | `c64c` | `251913-01.u4` | a 16KB image over both halves |
| `vic20-pal` | `vic20p` | `901486-07.ue12` | a PAL kernal image |
| `vic20-ntsc` | `vic20` | `901486-06.ue12` | an NTSC kernal image |

A longboard C64 has two 8KB sockets and a shortboard C64C one 16KB, BASIC half
then KERNAL half. The combined image is built for the C64C's, so
`c64-combined` runs a `c64c`. The C64C's PLA and the C64's are the same 245
bytes under two part numbers, so that arm renames the file rather than asking
for a second copy.

The `c64-basic` arm needs a genuine kernal in the other socket, because the
stock kernal is what runs at reset and enters the image.

The three kernal arms serve the stock kernal after a switch. The other two
serve whatever `RBCP_SWITCH_IMAGE` names.

## Running

From an application's directory:

```bash
make test ROMS=<rom-dir>
```

or `test/run.sh <rom-dir>` from that directory. Build first. Give `ROMS` a full
path or one starting `$HOME`, because not every shell expands a leading `~` in
a make variable.

`<rom-dir>` holds the machine's ROM files under MAME's names. There is no
default. `run.sh` names a missing file and stops rather than filling the gap
with something made up.

MAME complains about the checksum of the ROM in the socket on every run. That
file is the image under test.

A `mame -verifyroms` of `c64` or `vic20` always fails. Both sets list
`901229-04.uab5`, which has no good dump.

## A passing run

```
[dev] ENTER_CMD_RESP page=$00 bch=$0100 size=512
[dev] GET_FLASH_SLOT_INFO_ALL 5 of 5
[dev] NV_PEEK = 255
[dev] LOAD_SLOT ram 1 <- flash 1 (Commodore Stock Kernal)
[pipe] SWITCHING TO SLOT $01
[dev] SWITCH_AND_EXIT ram slot 1
[dev] served 8192 bytes into :kernal
01 |    **** COMMODORE 64 BASIC V2 ****     |
03 | 64K RAM SYSTEM  38911 BASIC BYTES FREE |
05 |READY.                                  |
```

The banner is the stock kernal running. Blank rows are cut.

## The ROM files

| Save as | Contents | SHA1 |
|---------|----------|------|
| `906114-01.u17` | the C64 PLA, 245 bytes | `efb315f560b6f72444b8f0b2ca4b0ccbcd144a1b` |
| `901225-01.u5` | C64 character generator, 4096 bytes | `adc7c31e18c7c7413d54802ef2f4193da14711aa` |
| `901226-01.u3` | C64 BASIC, 8192 bytes | `79015323128650c742a3694c9429aa91f355905e` |
| `901227-03.u4` | C64 kernal, 8192 bytes | `1d503e56df85a62fee696e7618dc5b4e781df1bb` |
| `901460-03.ud7` | VIC-20 character generator, 4096 bytes | `4fd85ab6647ee2ac7ba40f729323f2472d35b9b4` |
| `901486-01.ue11` | VIC-20 BASIC, 8192 bytes | `587d1e90950675ab6b12d91248a3f0d640d02e8d` |
| `901486-06.ue12` | VIC-20 NTSC kernal, 8192 bytes | `06de7ec017a5e78bd6746d89c2ecebb646efeb19` |
| `901486-07.ue12` | VIC-20 PAL kernal, 8192 bytes | `ce0137ed69f003a299f43538fa9eee27898e621e` |

The PLA is a real dump nothing can stand in for. MAME refuses to start any C64
variant without it. The C64 files come in a MAME `c64` ROM set and the VIC-20
files in a `vic20` one.

## The 3K block

`vic20-aux-io`, `vic20-pipe-test` and `vic20-rbcp-stress` put code in the 3K
block at `$0400-$0FFF`. MAME's VIC-1210 masks the address with `$BFF` where the
cartridge decodes `$FFF`, so `$0C00-$0FFF` reads as `$0800-$0BFF` again and a
program written across both hangs. The device script holds the two kilobytes
apart with a write tap that keeps what the program stores and a read tap that
gives it back. An address nothing has written still reads MAME's own cell.
Those three applications set `RBCP_EXP=3k` themselves, which fits the
cartridge.

## Settings

Every setting is an environment variable:

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_TARGET` | `kernal`, `pal` | `kernal`, `basic` or `combined` on a C64, `pal` or `ntsc` on a VIC-20. `make test TARGET=` sets it. |
| `RBCP_EXP` | unset | The cartridge MAME fits to a VIC-20, such as `3k`. An application that needs more than the machine's 5KB sets it itself. |
| `RBCP_FRAMES` | 600 | Frame to print the screen on and stop. |
| `RBCP_KEYS` | none | Keys to press, in order. A name may list alternatives separated by `\|`, because MAME renames keyboard legends between releases. An unrecognised name stops the run. |
| `RBCP_KEY_AT` | 150 | Frame the first key is pressed on. |
| `RBCP_KEY_GAP` | 30 | Frames between presses. Both bootloaders scan the matrix in their own loop and want a clear release between two presses. |
| `RBCP_KEY_HOLD` | 8 | Frames a key is held. |
| `RBCP_HOLD` | none | A key held from reset, such as the `CBM` that asks for the menu. |
| `RBCP_HOLD_UNTIL` | 0 | Frame the held key comes up. |
| `RBCP_NV` | 255 | The slot the device has stored. 255 stands for never written. |
| `RBCP_NV_FAIL` | unset | Fail every NV write, which a bootloader carries on through. |
| `RBCP_SLOTS` | 5 | How many flash slots the device has, the ones past the fifth being filler. More than fourteen exercises the entries a C64 menu cannot show. On a VIC-20 the number is thirteen. |
| `RBCP_DEAF` | unset | `GG:CC` — the command the device ignores entirely, so the token never moves. |
| `RBCP_REFUSE` | unset | `GG:CC` — the command the device answers with failed. |
| `RBCP_LATE_RSP` | unset | `GG:CC:reads` — the command whose response byte keeps its old value for that many reads after the device has said it is complete. That is a device publishing its completion before its result. |
| `RBCP_NO_AUX` | unset | Give the device no auxiliary pins, so `GET_AUX_CAPABILITY` reports a group count of zero and every other command in the group fails. |
| `RBCP_SEND` | unset | A line the far end of the pipe sends unprompted. `\n` in it is a line feed. |
| `RBCP_SWITCH_IMAGE` | unset | A ROM image to serve once the device has switched slots, in place of the one `run.sh` finds for itself. `c64-basic` and `c64-combined` find none. |
| `RBCP_SNAP` | unset | Save a screenshot at the end of the run. MAME runs in a window when this is set. |
| `RBCP_DEBUG` | unset | Print every command byte the device sees. |
| `MAME` | `mame` | The MAME binary to run. |

## Examples

Hold `CBM` to frame 200 for the menu, move down twice, boot the highlight.
`RBCP_KEY_AT` has to fall after the hold comes up, or the presses land while
`CBM` is still down:

```bash
RBCP_HOLD=CBM RBCP_HOLD_UNTIL=200 RBCP_KEY_AT=240 RBCP_FRAMES=500 \
    RBCP_KEYS='Crsr Down Up|CRSR ↑ ↓;Crsr Down Up|CRSR ↑ ↓;Return' \
    test/run.sh <rom-dir>
```

Ignore `ENTER_CMD_RESP` and read the error screen the application draws:

```bash
RBCP_DEAF=00:01 test/run.sh <rom-dir>
```
