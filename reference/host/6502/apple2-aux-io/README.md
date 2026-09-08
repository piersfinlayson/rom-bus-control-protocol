# Apple IIe RBCP Auxiliary I/O Tester

A ROM image for an Apple IIe that drives and reads a device's auxiliary I/O pins, showing them on screen and allowing them to be manipulated.

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
| `R` | reset the Apple and switch to another ROM slot |

Devices expose different groups of pins that can be driven. The tester displays each group on a separate page. There is a final page showing all GPIOs, including ones that are reserved by the device and cannot be driven. The heading displays the page.

## Display

An example display is shown below:

```
 RBCP AUX I/O               PIERS.ROCKS
  One ROM v0.7.2             RBCP 0.1.2

  GPIO                         1 OF 4

  4 OF 10 PINS CAN BE DRIVEN

   +-----+  +-----+  +-----+  +-----+
   |     |  |     |  |     |  |     |
   |     |  |     |  |     |  |     |
   |     |  |     |  |     |  |     |
   +-----+  +-----+  +-----+  +-----+
      2        4        6        8









  CRSR MOVES  [ ] PAGE  R RESET
  L LOW  H HIGH  Z REL  B BLINK
```

- The selected pin's number is reversed.
- A "filled" pin means its level is high.
- This screen has no colour, so the character indicates the pin's owner:
  - `#` - the Apple II (this program) is driving
  - `+` `-` `|` - nobody is driving
  - `.` - the device ROM is using it and it is reserved

## Wiring

Some GPIOs on your device may not be 5V tolerant. Check the board's documentation before connecting anything at 5V to a pin.

To use the program's RESET (`R`) option, wire a pin from the device to the Apple's /RESET line.  Then select this pin before entering the RESET option.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `apple2_auxio.bin` | 8KB | EF, $E000 | $FE00 | $FC00, 512 bytes |

II and II+ ROMs are 2KB. The tester does not fit in two kilobytes so II/II+ ROMs are not provided.

## Dependencies

- [cc65](https://cc65.github.io/)

## Building

```
make
```

## Testing

```
make test ROMS=/path/to/apple2/roms
```

runs the image on an emulated IIe against a fake RBCP device and prints the text screen at the end. `ROMS` is a directory holding the machine's own ROM files, named as MAME names them.

An example to get mame to press keys on the emulated Apple IIe, the cursor keys named by their arrows:

```
RBCP_KEYS='{↓}{↓}H' test/run.sh /path/to/apple2/roms build/apple2_auxio.bin
```

With no device to hand:

```
make demo
```

builds `build/apple2_auxio_demo.bin`, an image that answers its own questions. Run it the same way, without the fake device, and every screen is reachable. `BOARD` picks which imaginary board it describes.
