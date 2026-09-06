# C64 RBCP Pipe Throughput Test

Measure the throughput a Commodore 64 achieves through an RBCP pipe.

---

In a longboard C64, the RBCP capable device should replace the 8 KB BASIC ROM — a 2364 serving $A000–$BFFF. [Other ROM Types](#other-rom-types) covers serving a combined 16KB BASIC/Kernal as used by a shortboard C64.

## Overview

The C64 sends a continuous stream of data to the host through an RBCP pipe. Each `PIPE_WRITE` command carries up to 4 bytes, so throughput depends both on how many bytes go in each command and on how fast the C64 can issue them.

Three send paths carry the same stream:

| Key | Path | Bytes per command | Displays |
| --- | --- | --- | --- |
| `1` | `LIB4` | 4, the most `PIPE_WRITE` carries | the library's rate |
| `2` | `LIB1` | 1, so four times the commands | how much of the time is protocol overhead |
| `3` | `TUNED4` | 4, hand-written in place of the library | whether the library is the limit |

## Screen During a Run

The display goes off and the border turns blue while the program is talking to the device. A VIC-II fetching characters takes the bus off the processor, and around that handover the device can misread the command frame — with the display off, the frames go out intact.

Counters carry on being written while the screen is off and are there to read the moment a run ends. `RETURN` stops a run.

## Requirements

The device needs:

- a pipe carrying data from the device to the host
- the stock BASIC image in a flash slot

Both are checked at startup, and flagged on screen if missing.

## Controls

| Key | Action |
| --- | --- |
| `1`, `2`, `3` | pick a send path |
| `RETURN` | start, stop |
| `T` | run for ten seconds |
| `Q` | quit |
| `RESTORE` | stop a run |

## Dependencies

- [cc65](https://cc65.github.io/)
- `c1541`, for the disk image. Inside the [VICE](https://vice-emu.sourceforge.io/) bundle.
- `pyserial`, for `pipe_rx`

## Building

Provide the path to `c1541` if it is not on your system's PATH.

```bash
make C1541=/Applications/vice-arm64-gtk3-3.9/bin/c1541
```

Output is `build/rbcp_pipe_test.prg` and `build/rbcp-pipe-test.d64`.

Without an RBCP capable device it reports `NO DEVICE ANSWERED THE KNOCK` and waits at the menu, to enable the screen and keys to be tested under VICE.

## Measuring Throughput

`pipe_rx` is a Python script that receives the stream. Run it on the machine the device's USB is plugged into, then `LOAD"RBCP*",8` and `RUN` on the C64.

```bash
./pipe_rx /dev/ttyACM0
```

The argument is the serial port the device presents over USB — `/dev/ttyACM0` on Linux, `/dev/cu.usbmodem*` on macOS.

It passes the stream to stdout and writes a status line to stderr each second. Redirect stdout to measure without the passthrough.

```
   99840 bps  total 1248000  lines 19500  runs 1  gaps 0 missing 0 repeats 0 bad 0
```

The script's figure is authoritative. The C64's own figure is indicative only.

## Other ROM Types

This build serves one 8 KB ROM at $A000–$BFFF. To serve a 16 KB 23128 covering BASIC and KERNAL:

| Change | In | To |
| --- | --- | --- |
| `CONFIG_ROM_SIZE` | `rbcp_config.s` | the image size |
| `ROM_TYPE_2364` | `src/pipe_defs.s` | that chip type's code, from the spec |
| `checksum_image` | `src/session.s` | walk $A000–$BFFF, then $E000–$FFFF |

A 16 KB image appears in two separate places in the C64's memory map, so the checksum must walk both, in image order.

## Technical Details

### The Stream

The C64 sends 64 byte lines continuously, numbered so a dropped one can be spotted.

```
NNNN 012345678901234567890123456789012345678901234567890123456<CR><LF>
```

Each line starts with a sequence number in hex, followed by 57 digits. One digit is replaced by `#`, one place further right on each line, so as the terminal scrolls the `#` draws a diagonal. A dropped line breaks that diagonal, which is visible without reading the numbers.

### Recovery

A device that fails to answer a command is left waiting for argument bytes that never arrive, which breaks the framing of every command after it. The run ends and the program resets RBCP communications.

`ERRORS` counts the runs that ended this way. A device that does not come back leaves the program unable to start another run.

### Clean Exit

RBCP works by replacing part of the ROM image being served by the device (BASIC here) with a data section for transmitting data from the device to the host.

When exiting, it is important this section is replaced with the original data, or BASIC will not work properly afterwards.

`Q` cleans the BASIC image on its way out.
