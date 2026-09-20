# Amiga RBCP Pipe Throughput Test

A Kickstart ROM image that measures how many bytes an Amiga can push through an
RBCP pipe and shows the figure as it runs.

The device needs a pipe that carries bytes from the host to it.

## Controls

| Key | Action |
| --- | --- |
| `1` | send by `LIB4`, four bytes a command through the library |
| `2` | send by `LIB1`, one byte a command through the library |
| `3` | send by `TUNED4`, four bytes a command through hand-written code |
| `RETURN` | start a run and stop one |
| `T` | run for ten seconds |

## Dependencies

[vasm and `onerom`](../README.md#requirements), and the shared Amiga routines
in [`../amiga-common/`](../amiga-common/README.md).

## Building

```
make images
```

Outputs `build/amiga_pipe_256k.bin` and `build/amiga_pipe_512k.bin`.

## Testing

[`test/`](test/README.md) runs the built image on an emulated Amiga 500 against
a fake RBCP device, so a session can be driven without hardware. It needs MAME
and the A500 keyboard MCU dump.

```
make
test/run.sh <rom-dir>
```

`RBCP_DRAIN` gives the tester a pipe slow enough to fill and puts a
number in `REFUSALS`.

## Programming

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_pipe_512k.bin,type=27c400,label="Pipe Test"
```

## Running

Run [`pipe_rx`](../../6502/pipe/README.md#measuring-throughput) on the
machine the device's USB is plugged into, and start a run.

```
./pipe_rx /dev/ttyACM0
```

The port is `/dev/ttyACM0` on Linux and `/dev/cu.usbmodem*` on macOS.
