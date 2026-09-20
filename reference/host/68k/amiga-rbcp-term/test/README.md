# Amiga Terminal Test Harness

Runs the built terminal on an emulated Amiga 500 against a fake RBCP device
with a far end that talks back, so both directions can be driven without
hardware.

`rbcp_dev_term.lua` watches every read in the Kickstart window, decodes the
RBCP command stream out of the addresses, and answers by substituting bytes on
reads of the back-channel region, as a real device does. It implements the
commands the terminal calls and nothing else. The
[bootloader's device](../../amiga-boot/test/README.md) covers the addressing
and the ROM files MAME needs, and both apply here.

It has two pipes, pipe 0 carrying host to device and pipe 1 device to host.
`PIPE_WRITE` on pipe 1 and `PIPE_READ` on pipe 0 are both refused. A line arriving on pipe 0 is queued back on pipe 1 as
`you said <line>`.

## Typing and reading the screen

`RBCP_TYPE` is typed through the emulated keyboard a character at a time. `\n`
is `RETURN` and `\b` is `BACKSPACE`, the terminal's rub-out key. Any other
character is looked up by the legend on a key cap, and one that is a cap's
second legend holds a shift key over the keystroke.

The terminal draws to a bitmap, so a run would otherwise leave nothing to
print. The font the image was built with is on disk, so every glyph's eight
bytes map back to the character that drew them and the whole screen comes out
as lines at the end of the run.

## Running

From this directory:

```bash
./run.sh <rom-dir>                    # the 256 KB build
RBCP_TARGET=512 ./run.sh <rom-dir>    # the 512 KB build
```

Build the image first. `make` writes `build/amiga_term.bin` and
`make ROM_KB=512` writes the same name, so `run.sh` checks the size on disk
and says which `make` to run when the wrong build is there.

`<rom-dir>` holds the A500 keyboard MCU dump under the name MAME gives it,
`6570-036`. Without it MAME will not start an `a500`. Nothing else is needed:
the terminal never switches slots, so there is no Kickstart to hand over to.

Every run prints a checksum complaint from MAME about the ROM in the Kickstart
socket. That file is the terminal, so it does not match the dump MAME expects
there.

## A passing run

`[pipe>]` is a line the terminal sent and `[pipe<]` a line the device handed
back. The screen below them is the Amiga's at the end of the run.

```
[dev] chip RAM $001000-$03FFFF dirtied with count
[dev] ENTER_CMD_RESP page=$01FF bch=$03FC00 size=512
[dev] GET_PIPE_INFO 0 flags $0D
[dev] GET_PIPE_INFO 1 flags $0E
[pipe<] from the far end\n
[pipe>] Hi2
[pipe<] you said Hi2\n
[pipe>] bye
[pipe<] you said bye\n
[screen] | RBCP TERMINAL 0.1.0        PIERS.ROCKS |
[screen] | One ROM v0.7.2              RBCP 0.1.2 |
[screen] | SENDING ON PIPE 00  READING ON PIPE 01 |
[screen] |<from the far end                       |
[screen] |>Hi2                                    |
[screen] |<you said Hi2                           |
[screen] |>bye                                    |
[screen] |<you said bye                           |
[screen] |>                                       |
[screen] | READY                          38 LEFT |
[dev] 30 commands, 0 failed, 0 lost, 2 lines typed
```

That run typed `Hi1\b2\nbye\n`.

## Settings

Everything is an environment variable:

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_TARGET` | 256 | `256` runs the 27C200 build, `512` the 27C400 build. Both on an `a500`. |
| `RBCP_FRAMES` | 900 | Frame to stop the run on. |
| `RBCP_DIRTY` | `count` | The byte chip RAM is filled with before the application sets its variables up. `count` steps `$FF` down to `$01`, a hex byte such as `FF` fills with that byte throughout, and `off` leaves chip RAM as MAME zeroes it. |
| `RBCP_TYPE` | `hello\n` | The characters the run types. `\n` is `RETURN`, `\b` is `BACKSPACE`, a shifted character holds shift. Empty types nothing. |
| `RBCP_TYPE_AT` | 240 | Frame the first key goes down on. |
| `RBCP_TYPE_GAP` | 12 | Frames between one key and the next. |
| `RBCP_TYPE_HOLD` | 6 | Frames a key is held down for. |
| `RBCP_SEND` | unset | A line the far end sends before anything has been typed at it. `\n` in it is a line feed. |
| `RBCP_ECHO` | `you said ` | The prefix the far end puts on a line it sends back. |
| `RBCP_NO_IN` | unset | Give the device no pipe carrying bytes back, so the terminal can only send. |
| `RBCP_PIPE_OUT` | 0 | The pipe carrying host to device. |
| `RBCP_PIPE_IN` | 1 | The pipe carrying device to host. |
| `RBCP_REFUSE` | unset | `GG:CC` — the command the device answers with failed. `04:03` is `PIPE_READ`. |
| `RBCP_FAIL_EVERY` | unset | One command in this many, whichever it is, answered with failed. |
| `RBCP_LOSE_EVERY` | unset | One command in this many not answered at all, so the terminal has to reset and re-enter. |
| `RBCP_SNAP` | unset | Save a screenshot at the end of the run, to `build/a500/0000.png`. MAME runs in a window when this is set. |
| `RBCP_DEBUG` | unset | Print every command byte the device sees. |

## Examples

Type two lines and have the far end speak first:

```bash
RBCP_FRAMES=1000 RBCP_TYPE='Hi1\b2\nbye\n' RBCP_SEND='from the far end\n' \
    ./run.sh <rom-dir>
```

A device with no pipe bringing bytes back, which leaves `READY - NOTHING COMES
BACK` on the bar:

```bash
RBCP_NO_IN=1 RBCP_TYPE='abc\n' ./run.sh <rom-dir>
```

A device losing one command in twelve, which the terminal resets and carries
on through:

```bash
RBCP_FRAMES=1200 RBCP_LOSE_EVERY=12 RBCP_TYPE='one\ntwo\n' ./run.sh <rom-dir>
```
