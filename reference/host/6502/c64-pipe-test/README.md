# C64 RBCP Pipe Throughput Test

A ROM image for a Commodore 64 that measures how many bytes the machine can push through an RBCP pipe.

The device needs a pipe carrying bytes from the host to it. That is checked at startup and flagged on screen if it is missing.

## Controls

| Key | Action |
| --- | --- |
| `1`, `2`, `3` | pick a send path |
| `RETURN` | start/stop a run |
| `T` | run for ten seconds |

The three send paths are described with the [shared code](../pipe/README.md#send-options), which also covers `pipe_rx` and the figure to quote.

## Display Blanking

The display goes off and the border turns blue while the tester is talking to the device.  Otherwise, the VIC-II video chip fetching characters takes the bus off the processor, and around that handover the device can misread a command frame.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `c64_pipe_kernal.bin` | 8KB, 2364 | kernal | $E000 | $E100, 512 bytes |
| `c64_pipe_combined.bin` | 16KB, 23128 | shared BASIC/kernal | $A000 | $A100, 512 bytes |
| `c64_pipe_basic.bin` | 8KB, 2364 | BASIC | $A000 | $A100, 512 bytes |

The kernal and BASIC images are for a longboard C64.  Use one or other other.  The BASIC image requires a stock kernal image.

The combined image is for a shortboard, whose single socket covers both halves of the map.

## Dependencies

- [cc65](https://cc65.github.io/)

## Building

```
make
```

## Testing

Under VICE with no device fitted it draws its screen and stops at `NO DEVICE ANSWERED THE KNOCK`:

```
x64sc -default -kernal build/c64_pipe_kernal.bin
```

The 16KB image is two 8KB halves, and VICE takes them one socket at a time:

```
dd if=build/c64_pipe_combined.bin of=basic.bin bs=8192 count=1
dd if=build/c64_pipe_combined.bin of=kernal.bin bs=8192 skip=1 count=1
x64sc -default -basic basic.bin -kernal kernal.bin
```

Anything past the screen needs a One ROM running the host-control plugin, and `pipe_rx` on the machine its USB is plugged into.
