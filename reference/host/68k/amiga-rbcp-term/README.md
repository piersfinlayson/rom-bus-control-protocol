# Amiga RBCP Terminal

A Kickstart ROM image that sends what you type down an RBCP pipe so it arrives
in `onerom console` on the machine the device's USB is plugged into, and shows
what is typed there. It runs from reset and never hands the machine back, so
switching off is the way out.

The device requires a pipe carrying bytes from the host to it and one carrying
them back.

## Controls

| Key | Action |
| --- | --- |
| a letter, a digit, a punctuation key or `SPACE` | goes in the line |
| either `SHIFT` | the capital of a letter, or a key's second legend |
| `RETURN` | send the line |
| `BACKSPACE` | rub out the last character |

## Dependencies

[vasm and `onerom`](../README.md#requirements), and the shared Amiga routines
in [`../amiga-common/`](../amiga-common/README.md).

## Building

```
make images
```

Outputs `build/amiga_term_256k.bin` and `build/amiga_term_512k.bin`.

## Testing

[`test/`](test/README.md) runs the built image on an emulated Amiga 500
against a fake RBCP device with a far end that talks back, so both directions
can be driven without hardware. It needs MAME and the A500 keyboard MCU dump.

```
make
test/run.sh <rom-dir>
```

Use `RBCP_TYPE` and `RBCP_SEND`.

## Programming

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_term_512k.bin,type=27c400,label="RBCP Terminal"
```

Run `onerom console` on the far end.
