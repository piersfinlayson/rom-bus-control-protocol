# C64 RBCP Pipe Throughput Test

Measures how fast a Commodore 64 can push bytes through an RBCP pipe, and prints the stream to a terminal on the other end.

Build with `make`. Output is `build/rbcp_pipe_test.prg` and `build/rbcp-pipe-test.d64`.

Run `./pipe_rx <port>` on the machine the device's USB is plugged into, then `LOAD"RBCP*",8` and `RUN` on the C64. Keys: `1` `2` `3` pick a send path, `RETURN` starts and stops, `T` runs for ten seconds, `Q` quits. RUN/STOP-RESTORE also stops a run.

---

**Breadbin C64 only.** The device replaces the 8 KB BASIC ROM, a 2364 serving $A000–$BFFF. A combined 16 KB BASIC+KERNAL ROM needs the changes under [Other ROM types](#other-rom-types).

Device also needs a pipe taking host-to-device, two RAM slots, and the stock BASIC image in a flash slot. All checked at startup and named on screen if missing.

## Send paths

All three send the same stream. They differ in how much data each RBCP command carries, and in what builds it.

| Key | Path | What it does |
|-----|------|--------------|
| `1` | `LIB4` | Four bytes per command, the most `PIPE_WRITE` carries, sent through the shared 6502 library. |
| `2` | `LIB1` | One byte per command, so four times as many commands for the same data. Shows how much of the time is protocol overhead rather than payload. |
| `3` | `TUNED4` | Four bytes again, but hand-written send code in place of the library. Shows whether the library is what limits the rate. |

Switching path is a keypress — the RBCP session stays open from startup to quit.

## The stream

64-byte lines.

```
NNNN 012345678901234567890123456789012345678901234567890123456<CR><LF>
```

Sequence in hex, then a digit ruler with one cell replaced by `#` at column `sequence mod 57` — a diagonal scrolling up the terminal. A dropped line jumps the counter and breaks the diagonal. Each run starts with a `####` line naming the run and path.

## Measuring

`pipe_rx` passes the stream to stdout and writes a status line to stderr each second. Redirect stdout to measure without the passthrough. Needs `pyserial`.

```
  12480 B/s  total 1248000  lines 19500  runs 1  gaps 0 missing 0 repeats 0 bad 0
```

This is the authoritative figure. The C64 shows its own alongside, which includes its bookkeeping — under 5%.

PAL only has been tested.

## Building

Needs [cc65](https://cc65.github.io/), and `c1541` from [VICE](https://vice-emu.sourceforge.io/) for the disk image. `c1541` is inside the VICE bundle, not on a stock macOS PATH:

```bash
make C1541=/Applications/vice-arm64-gtk3-3.9/bin/c1541
```

With no device it reports `NO DEVICE ANSWERED THE KNOCK` and waits at the menu, so screen and keys can be exercised under an emulator. Nothing past the knock can be.

## Other ROM types

A flash slot is only offered as a clean exit if it reports type 2364, and the served image is assumed to be the 8 KB at $A000–$BFFF. For another 8-bit ROM — a 23128 combined BASIC+KERNAL, say:

- `rbcp_config.s`: `CONFIG_ROM_SIZE` to the image size.
- `src/pipe_defs.s`: `ROM_TYPE_2364` to that type's code from the spec.
- `src/session.s`: `checksum_image` walks up from `CONFIG_ROM_BASE_HI`. A 16 KB image is not contiguous — $A000–$BFFF then $E000–$FFFF — so it must walk both halves in image order.
