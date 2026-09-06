# RBCP Pipe Throughput Test

The tester measures how many bytes a machine can push through an RBCP pipe.

See also:
- [C64 RBCP Pipe Throughput Test](../c64-pipe-test/README.md)
- [VIC-20 RBCP Pipe Throughput Test](../vic20-pipe-test/README.md)
- [Apple II RBCP Pipe Throughput Test](../apple2-pipe-test/README.md)

## Send Options

Three code paths carry the same stream. Two of them use the [RBCP library](../rbcp/), and one replaces it with hand-written code.

| Key | Path | Bytes per command | Sent by |
| --- | --- | --- | --- |
| `1` | `LIB4` | 4 | the library |
| `2` | `LIB1` | 1 | the library |
| `3` | `TUNED4` | 4 | hand-written code |

## Stream

The machine sends 64 byte lines, numbered so a dropped one can be spotted.

```
NNNN 012345678901234567890123456789012345678901234567890123456<CR><LF>
```

A sequence number in hex, then 57 digits with one replaced by `#`, one place further right on each line. As the terminal scrolls the `#` draws a diagonal, and a dropped line breaks it without anyone reading the numbers.

## Measuring Throughput

`pipe_rx` receives the stream. It needs `pyserial`. Run it on the machine the device's USB is plugged into, then start a run.

```bash
./pipe_rx /dev/ttyACM0
```

The argument is the serial port the device presents over USB — `/dev/ttyACM0` on Linux, `/dev/cu.usbmodem*` on macOS.

It passes the stream to stdout and writes a status line to stderr each second. Redirect stdout to measure without the passthrough.

```
   99840 bps  total 1248000  lines 19500  runs 1  gaps 0 missing 0 repeats 0 bad 0
```

Quote its figure. The machine's own is produced by the thing under measurement.

## Refusals and Errors

`REFUSALS` counts writes the pipe had no room for. They are retried, and a run ends only if the pipe stays full.

`ERRORS` counts runs ended by a device that stopped answering. One that does not come back leaves the tester unable to start another run.
