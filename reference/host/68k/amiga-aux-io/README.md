# Amiga RBCP Auxiliary I/O Tester

A Kickstart ROM image for an Amiga that drives and reads a device's auxiliary
I/O pins, showing them on screen and allowing them to be manipulated.

The device requires auxiliary pins for this tester to operate.

## Controls

| Key | Action |
| --- | --- |
| cursor keys | select the previous or next pin |
| `[` | previous page |
| `]` | next page |
| `L` | drive the selected pin low |
| `H` | drive the selected pin high |
| `Z` | release the selected pin |
| `B` | blink the selected pin until a key is pressed |
| `R` | reset the Amiga through the selected pin |
| `T` | a screen showing RBCP timing diagnostics |

Devices expose different groups of pins. The tester shows each group on its own
page, with a final page holding every pin at once, including the ones the
device reserves.

## Wiring

Some GPIOs on your device may not be 5V tolerant. Check the board's
documentation before connecting anything at 5V to a pin.

To use `R`, wire a pin from the device to the Amiga's `_RESET` line, then
select that pin before pressing it.

## Dependencies

[vasm and `onerom`](../README.md#requirements), and the shared Amiga routines
in [`../amiga-common/`](../amiga-common/README.md).

## Building

```
make images
```

Outputs `build/amiga_auxio_256k.bin` and `build/amiga_auxio_512k.bin`.

## Testing

[`test/`](test/README.md) runs the built image on an emulated Amiga 500 against
a fake RBCP device whose pins are deliberately awkward, so the screen and the
keys can be driven without hardware. It needs MAME and the A500 keyboard MCU
dump.

```
make
test/run.sh <rom-dir>
```

`RBCP_KEYS` presses keys at named frames and `RBCP_SNAP` photographs the
result. A photograph is the only way to see the pins.

## Programming

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_auxio_512k.bin,type=27c400,label="RBCP Aux I/O"
```

Read the report with `onerom monitor log`.
