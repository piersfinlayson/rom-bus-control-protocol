# C64 RBCP Auxiliary I/O Tester

A ROM image for a Commodore 64 that drives and reads a device's auxiliary I/O pins, showing them on screen and allowing them to be manipulated.

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
| `R` | reset the C64 and switch to another ROM slot |

Devices expose different groups of pins that can be driven. The tester displays each group on a separate page. There is a final page showing all GPIOs, including ones that are reserved by the device and cannot be driven. The heading displays the page.

## Display

An example display is shown below:

```
 RBCP AUX I/O               PIERS.ROCKS
  One ROM v0.7.2             RBCP 0.1.2

  GPIO                         1 OF 4

  4 OF 10 PINS CAN BE DRIVEN

   /-----\  /-----\  /-----\  /-----\
   |     |  |     |  |     |  |     |
   |     |  |     |  |     |  |     |
   |     |  |     |  |     |  |     |
   \-----/  \-----/  \-----/  \-----/
      2        4        6        8










  CRSR MOVES  [ ] PAGE  R RESET
  L LOW  H HIGH  Z REL  B BLINK
```

- The selected pin's number is reversed.
- A "filled" pin means its level is high.
- The colour indicates the pin's owner:
  - Red - the C64 (this program) is driving
  - White - nobody is driving
  - Blue - the device ROM is using it and it is reserved

## Display blanking

The display goes off while the tester is talking to the device due to a C64 limitation.  This happens every few seconds and whenever you press a key.

## Wiring

Some GPIOs on your device may not be 5V tolerant. Check the board's documentation before connecting anything at 5V to a pin.

To use the program's RESET ('R') option, wire a pin from the device to the C64's /RESET line.  Then select this pin before entering the RESET option.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `c64_auxio_kernal.bin` | 8KB, 2364 | kernal | $E000 | $E100, 512 bytes |
| `c64_auxio_basic.bin` | 8KB, 2364 | BASIC | $A000 | $A100, 512 bytes |
| `c64_auxio_combined.bin` | 16KB, 23128 | shared BASIC/kernal | $A000 | $A100, 512 bytes |

The kernal and BASIC images are for a longboard C64. Use one or the other. The BASIC image requires a stock kernal image to be present in the kernal socket.

The combined image is for a shortboard.

## Dependencies

- [cc65](https://cc65.github.io/)

## Building

```
make
```

## Testing

Under VICE with no device fitted the program draws the screen and stops at `NO DEVICE ANSWERED THE KNOCK`:

```
x64sc -default -kernal build/c64_auxio_kernal.bin
x64sc -default -basic build/c64_auxio_basic.bin
```

The 16KB image is two 8KB halves, and VICE takes them one socket at a time:

```
dd if=build/c64_auxio_combined.bin of=basic.bin bs=8192 count=1
dd if=build/c64_auxio_combined.bin of=kernal.bin bs=8192 skip=1 count=1
x64sc -default -basic basic.bin -kernal kernal.bin
```

Anything past the screen needs a One ROM running the host-control plugin, with something attached to the pins.

```
make demo
```

builds `build/c64_auxio_demo.bin`, a kernal socket image that answers its own questions. Run it under VICE as above and every screen is reachable with no device fitted. `BOARD` picks which imaginary board it describes.
