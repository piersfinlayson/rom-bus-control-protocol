# VIC-20 RBCP Auxiliary I/O Tester

A ROM image for a Commodore VIC-20 that drives and reads a device's auxiliary I/O pins, showing them on screen and allowing them to be manipulated. It requires a 3K expansion.

The device requires auxiliary pins for this tester to operate.

## Controls

| Key | Action |
| --- | --- |
| cursor keys | select pin |
| `[` | previous page |
| `]` | next page |
| `L` | drive the selected pin low |
| `H` | drive the selected pin high |
| `Z` | release the selected pin |
| `B` | blink the selected pin until a key is pressed |
| `R` | reset the VIC-20 and switch to another ROM slot |

Devices expose different groups of pins that can be driven. The tester displays each group on a separate page. There is a final page showing all GPIOs, including ones that are reserved by the device and cannot be driven. The heading displays the page.

## Display

An example display is shown below:

```
RBCP I/O   PIERS.ROCKS
One ROM v0.7.2
GPIO          1 OF 4

4 OF 10 CAN BE DRIVEN

   /-----\  /-----\
   |     |  |     |
   |     |  |     |
   |     |  |     |
   \-----/  \-----/
      2        4
   /-----\  /-----\
   |     |  |     |
   |     |  |     |
   |     |  |     |
   \-----/  \-----/
      6        8

CRSR MOVES  [ ] PAGE
L LOW H HIGH Z REL
B BLINK  R RESET

```

- The selected pin's number is reversed.
- A "filled" pin means its level is high.
- The colour indicates the pin's owner:
  - Red - the VIC-20 (this program) is driving
  - White - nobody is driving
  - Blue - the device ROM is using it and it is reserved

## Wiring

Some GPIOs on your device may not be 5V tolerant. Check the board's documentation before connecting anything at 5V to a pin.

To use the program's RESET (`R`) option, wire a pin from the device to the VIC-20's /RESET line.  Then select this pin before entering the RESET option.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `vic20_auxio_pal.bin` | 8KB, 2364 | kernal | $E000 | $E100, 512 bytes |
| `vic20_auxio_ntsc.bin` | 8KB, 2364 | kernal | $E000 | $E100, 512 bytes |

## Dependencies

- [cc65](https://cc65.github.io/)

## Building

```
make
```

## Testing

Under VICE with no device fitted the program draws the screen and stops at `NO DEVICE`:

```
xvic -default -memory 3k -kernal build/vic20_auxio_pal.bin
xvic -default -ntsc -memory 3k -kernal build/vic20_auxio_ntsc.bin
```

Anything past the screen needs a One ROM running the host-control plugin, with something attached to the pins.

```
make demo
```

builds `build/vic20_auxio_demo.bin`, a PAL image that answers its own questions. Run it under VICE as above and every screen is reachable with no device fitted. `BOARD` picks which imaginary board it describes.
