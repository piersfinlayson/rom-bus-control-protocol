# Amiga Pipe Test Harness

Runs the built tester on an emulated Amiga 500 against a fake RBCP device
written in [MAME](https://mamedev.org)'s Lua.

The device is `rbcp_dev_pipe.lua` in this directory. It counts the pipe lines
and checks each against the format the tester sends, where the shared device
prints every line and a run here sends hundreds a second. It also gives the
pipe a size and a drain rate, so the tester can be made to meet a full one.

It implements the knock, `ENTER_CMD_RESP`, `RBCP_RESET`, the three identity
commands and the three pipe commands, and nothing else.

## The ROM files

`<rom-dir>` holds the A500 keyboard MCU dump under the name MAME gives it,
`6570-036`. Without it MAME will not start an `a500`. It is a real dump and
this harness cannot make one up. The
[bootloader's harness](../../amiga-boot/test/README.md#the-rom-files) has where
it comes from and its SHA1. Nothing else is needed: the tester never switches
slots, so there is no Kickstart to hand over to.

Every run prints a checksum complaint from MAME about the ROM in the Kickstart
socket. That file is the tester, so it does not match the dump MAME expects
there.

## Running

From this directory:

```bash
./run.sh <rom-dir>                    # the 256 KB build
RBCP_TARGET=512 ./run.sh <rom-dir>    # the 512 KB build
```

Build the image first. `make` writes `build/amiga_pipe.bin` and
`make ROM_KB=512` writes the same name, so `run.sh` checks the size on disk and
says which `make` to run when the wrong build is there.

Nothing is sent until somebody starts a run, so `RBCP_KEYS` defaults to
pressing `RETURN` at frame 200.

## A passing run

The tester draws to a bitmap, so the screen is a picture and `RBCP_SNAP` is how
to read it. The text is the device's own tally:

```
[dev] chip RAM $001000-$03FFFF dirtied with count
[dev] ENTER_CMD_RESP page=$01FF bch=$03FC00 size=512
[dev] key 'Enter' at frame 200
[dev] 77824 commands, 0 failed, 0 lost
[dev] 311268 bytes, 4863 lines, 1 runs
[dev] paths LIB4
[dev] gaps 0 missing 0 repeats 0 stripe 0 malformed 0
[dev] 178128 bits per second over 13.98 emulated seconds sending
```

`gaps`, `repeats` and `stripe` all zero says the stream arrived as the tester
built it, and the rate is worked out from MAME's own clock where the tester
works its own out from the CIA-B counter. The two agree when the one-second
window really is a second.

`paths` names the send path each run took, read off the banner. It is the only
sign down the pipe of which key the menu took, so a run driven by `1`, `2` or
`3` is checked on it.

Neither figure is a machine's throughput. A fake device answers a `PIPE_WRITE`
the instant it sees one, and no real device does.

## Settings

Everything is an environment variable:

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_TARGET` | 256 | `256` runs the 27C200 build, `512` the 27C400 build. Both on an `a500`. |
| `RBCP_FRAMES` | 900 | Frame to stop the run on. A frame is a fiftieth of an emulated second. |
| `RBCP_DIRTY` | `count` | The byte chip RAM is filled with before the application sets its variables up. `count` steps `$FF` down to `$01`, a hex byte such as `FF` fills with that byte throughout, and `off` leaves chip RAM as MAME zeroes it. |
| `RBCP_KEYS` | `200:Enter` | `frame:Key;frame:Key`. A key is named by any legend on its cap. `Enter`, `1`, `2`, `3` and `T` are the ones the tester reads. |
| `RBCP_DRAIN` | unset | Bytes the far end takes off the pipe each frame. Unset is a far end that keeps up with anything. Set it below what the machine sends and the tester meets a full pipe and counts refusals. |
| `RBCP_FAIL_EVERY` | unset | One command in this many answered with failure. A refused write is retried and counted as a refusal, so the run carries on. |
| `RBCP_LOSE_EVERY` | unset | One command in this many not answered at all, which ends the run and sends the tester through its recovery. |
| `RBCP_ECHO` | unset | Print every line the pipe receives. A run is hundreds a second. |
| `RBCP_SNAP` | unset | Save a screenshot at the end of the run, to `build/a500/0000.png`. MAME runs in a window when this is set. |
| `RBCP_DEBUG` | unset | Print every command byte the device sees. |

## Examples

Six seconds of sending on the four-byte path, photographed:

```bash
RBCP_FRAMES=500 RBCP_SNAP=1 ./run.sh <rom-dir>
```

A pipe that takes 10000 bytes a second, which the machine outruns:

```bash
RBCP_FRAMES=500 RBCP_DRAIN=200 RBCP_SNAP=1 ./run.sh <rom-dir>
```

The one-byte path on a ten second run, on the 512 KB build:

```bash
RBCP_TARGET=512 RBCP_FRAMES=820 RBCP_KEYS='200:2;260:T' RBCP_SNAP=1 \
    ./run.sh <rom-dir>
```
