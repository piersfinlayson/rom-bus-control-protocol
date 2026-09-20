# 68K Host Reference RBCP Implementations

Examples and starting points for a 68000-family RBCP host.

## Contents

| Directory | Purpose |
| --- | --- |
| [`rbcp/`](rbcp/README.md) | Generic 68K assembly routines for talking to an RBCP device with the required bus mapping |
| [`amiga-common/`](amiga-common/README.md) | Amiga shared routines |
| [`amiga-boot/`](amiga-boot/README.md) | An Amiga Kickstart ROM image that picks which ROM the machine boots |
| [`amiga-rbcp-stress/`](amiga-rbcp-stress/README.md) | An Amiga Kickstart ROM image that measures how reliably a device answers RBCP commands |
| [`amiga-pipe-test/`](amiga-pipe-test/README.md) | An Amiga Kickstart ROM image that measures how many bytes the machine can push through an RBCP pipe |
| [`amiga-rbcp-term/`](amiga-rbcp-term/README.md) | An Amiga Kickstart ROM image that sends what you type down an RBCP pipe and displays what comes in |
| [`amiga-aux-io/`](amiga-aux-io/README.md) | An Amiga Kickstart ROM image that drives and reads a device's auxiliary I/O pins |
| [`amiga-led-test/`](amiga-led-test/README.md) | An Amiga Kickstart ROM image that drives a device's LEDs and shows what each one should be doing |

## 68K Word Size

A 6502 reads its ROM a byte at a time so an RBCP address is a CPU address. A
68K reads two bytes at a time. That moves every RBCP address somewhere else in
the CPU's address space. The two bytes of each pair arrive the opposite way
round .

`rbcp_config.s` describes how the device sits on the host's bus:

- how wide the bus is
- how wide the device is
- which lanes the device is wired to
- which way round the bytes go

See [`rbcp/README.md`](rbcp/README.md) for more details.

## Requirements

| Tool | Purpose |
| --- | --- |
| [vasm](http://sun.hasenbraten.de/vasm/) `vasmm68k_mot` | builds the ROM images |
| [One ROM](https://onerom.org) `onerom` | used to program a One ROM |

vasm ships as a source tarball. Build it with `make CPU=m68k SYNTAX=mot`.

## Building

Run the following from this directory:

```
./build.sh
```

Also supports:

```
./build.sh clean
```

To remove all build artifacts.

## Programming One ROM

A One ROM config file [`amiga.json`](amiga.json) is provided to program all
images to a single One ROM Fire 40B or later. The bootloader is installed
first, so runs at power on. Hold both mouse buttons down on boot to enter the
bootloader - otherwise the last booted slot will be loaded.

To program, run the following from this directory:

```
onerom program \
    --plugin usb \
    --plugin host-control \
    --config amiga.json
```

Optionally add `--reset-host sel_c` if you have a fly-lead attached to image
select jumper pin C and the 68K's /RESET line.  This causes One ROM to reset
the Amiga automatically after programming.


```
onerom program \
    --plugin usb \
    --plugin host-control \
    --config amiga.json \
    --reset-host sel_c
```

Image select pin D may also be used.  Pins A and B are not 5V tolerant, so
should not be used.

## Running The ROMs

Once selected and booted into, each ROM is self-documenting.  See the READMEs
in each ROM directory for more details.

The pipe throughput tester requires a PC/Mac/Linux side tool to collect bytes
streamed over the pipe.  See [its README](amiga-pipe-test/README.md#running).
