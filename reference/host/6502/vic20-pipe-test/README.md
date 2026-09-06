# VIC-20 RBCP Pipe Throughput Test

A ROM image for a Commodore VIC-20 that measures how many bytes the machine can push through an RBCP pipe.  Requires a 3KB RAM expansion.

The device needs a pipe carrying bytes from the host to it. That is checked at startup and flagged on screen if it is missing.

## Controls

| Key | Action |
| --- | --- |
| `1`, `2`, `3` | pick a send path |
| `RETURN` | start/stop a run |
| `T` | run for ten seconds |

The three send paths are described with the [shared code](../pipe/README.md#send-options), which also covers `pipe_rx` and the figure to quote.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `vic20_pipe_pal.bin` | 8KB, 2364 | Kernal | $E100 | $E200, 512 bytes |
| `vic20_pipe_ntsc.bin` | 8KB, 2364 | Kernal | $E100 | $E200, 512 bytes |

## Dependencies

- [cc65](https://cc65.github.io/)

## Building

```
make
```

## Testing

Under VICE with no device fitted it draws its screen and stops at `NO DEVICE`:

```
xvic -default -memory 3k -basic build/vic20_pipe_pal.bin
xvic -default -ntsc -memory 3k -basic build/vic20_pipe_ntsc.bin
```

Anything past the screen needs a One ROM running the host-control plugin, and `pipe_rx` on the machine its USB is plugged into.
