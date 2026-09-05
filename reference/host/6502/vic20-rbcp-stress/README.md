# VIC-20 RBCP Reliability Meter

A ROM image for a Commodore VIC-20 that measures how reliably a One ROM answers RBCP commands. It runs a fixed set of commands in a loop and shows the failure rate as a ratio. What it counts, what it sends, how it recovers and what it says down a pipe are documented with the [shared code](../stress/README.md).

## Memory

The meter is about four kilobytes of code and working storage, all of it in RAM, since no instruction may be fetched out of the image the device is serving. An unexpanded VIC-20 has 3.5KB free in one piece at $1000-$1DFF, which is not enough.

This build runs at $0400-$1DFF and needs the 3KB block at $0400-$0FFF fitted. A 3KB cartridge supplies it, as does any expansion including that block, but an 8KB or 16KB cartridge alone does not — those put their RAM at $2000 and upwards. The linker refuses to build if the meter outgrows the region, so an image that comes out is an image that fits.

## The socket

An 8KB 2364 in the kernal socket, $E000-$FFFF, with the command page at $E000 and a 64 byte back-channel region at $E100. Two images, PAL and NTSC, differing only in where the picture sits.

## The screen

Twenty-two columns by twenty-three rows, which the meter draws in its narrow layout. The sent and error counts take a row each, the command names are shortened, and the failure record is abbreviated.

```
 RBCP METER PIERS.ROCKS
 One ROM
 v0.7.2
 RBCP 0.1.2
 PIPE 00

 1 IN 2946

 SENT    2946123
   ERR       1000
  LOST          2

 CMD         SENT  ERR
 NOP       736530  250
 PROTO     736531  249
 LED INFO  736531  251
 LED MODE  736531  250

 REFUSED
 S 06 01 00 00 00 T1B
 G 06 06 T1C P BB R33

 SWITCH OFF WHEN DONE
```

A command's own counts get eight digits and five, against the ten the run's counts get, there being nothing left to give them on a 22 column screen. Past what its column holds a count fills with plus signs rather than showing a number that is not the count, and the run total above it keeps counting.

## Building

Needs cc65.

```
make
```

`build/vic20_meter_pal.bin` and `build/vic20_meter_ntsc.bin` are the two images.

## Testing

Every figure this program reports comes from a device, so there is no demo build. Under VICE with no device fitted it draws its screen and stops at `NO DEVICE`:

```
xvic -default -memory 3k -kernal build/vic20_meter_pal.bin
```

That covers the screen and the refusal path. The rest needs a One ROM in the kernal socket running the host-control plugin.
