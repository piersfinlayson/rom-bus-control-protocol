# Apple IIe RBCP Reliability Meter

A ROM image for an Apple IIe that measures how reliably a One ROM answers RBCP commands. It runs a fixed set of commands in a loop and shows the failure rate as a ratio. What it counts, what it sends, how it recovers and what it says down a pipe are documented with the [shared code](../stress/README.md).

## The socket

An 8KB image for the IIe's EF socket, $E000-$FFFF, which is the one holding the reset vector. A II or II+ has a 2KB F8 socket instead and the meter does not fit in two kilobytes, so there is one build here rather than two.

The command page is $FE00 and the back-channel region is 64 bytes at $FFB0, under the 6502 vectors, which are the addresses the Apple II bootloader uses. Everything the meter runs is copied to RAM at $0800 before the first knock, so no instruction is ever fetched out of the image the device is serving.

## The screen

Forty columns and twenty-four rows. There is no colour, so the title bar and the headline band are inverse video and everything else is normal.

## Building

Needs cc65.

```
make
```

`build/apple2_meter.bin` is the 8KB image.

## Testing

Every figure this program reports comes from a device, so there is no demo build.

```
make test ROMS=/path/to/apple2/roms
```

runs the built image on an emulated unenhanced IIe against a fake RBCP device and prints the text screen at the end. See [`test/README.md`](test/README.md) for what it needs and what can be varied. The emulated device is a device: it decodes the command stream off the address bus and answers by substituting bytes on reads of the back channel, which is what a One ROM does.
