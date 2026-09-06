# Apple IIe RBCP Pipe Throughput Test

A ROM image for an Apple IIe that measures how many bytes the machine can push through an RBCP pipe.

The device needs a pipe carrying bytes from the host to it. That is checked at startup and flagged on screen if it is missing.

## Controls

| Key | Action |
| --- | --- |
| `1`, `2`, `3` | pick a send path |
| `RETURN` | start a run |
| any key | stop a run |
| `T` | run for ten seconds |

The three send paths are described with the [shared code](../pipe/README.md#send-options), which also covers `pipe_rx` and the figure to quote.

## Image

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `apple2_pipe_pal.bin` | 8KB | EF, $E000 | $FE00 | $FFB0, 64 bytes |
| `apple2_pipe_ntsc.bin` | 8KB | EF, $E000 | $FE00 | $FFB0, 64 bytes |

## Dependencies

- [cc65](https://cc65.github.io/)

## Building

```
make
```

## Testing

```bash
make test ROMS=/path/to/apple2/roms
```

runs the image on an emulated IIe against a fake RBCP device and prints the text screen at the end. `ROMS` is a directory holding the machine's own ROM files, named as MAME names them. `RBCP_KEYS=T` types the key that starts a ten second run.

Anything past the emulator needs a One ROM running the host-control plugin, and `pipe_rx` on the machine its USB is plugged into.
