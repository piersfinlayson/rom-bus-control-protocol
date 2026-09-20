# Amiga RBCP LED Tester

A Kickstart ROM image that drives a One ROM's LEDs from an Amiga and shows what
each one should be doing, so the screen can be held against the board.

## Controls

| Key | Action |
| --- | --- |
| cursor up, down | the LED the rest of the keys land on |
| `M` | the next mode this LED reports |
| `C` | the next colour |
| `B` | the next brightness |
| `P` | the next period |
| `H` | the next hold |
| `A` | the parade |
| `RETURN` | send the same command again |
| `T`, `L` | the table and the lamps screen |

The tester opens on the lamps screen, and every key works on it and on the
table. `C` goes to the colour page and steps the list from there. Every key but
`T` and `L` sends one `SET_LED`.

## Dependencies

[vasm and `onerom`](../README.md#requirements), and the shared Amiga routines
in [`../amiga-common/`](../amiga-common/README.md).

## Building

```
make images
```

Outputs `build/amiga_led_test_256k.bin` and `build/amiga_led_test_512k.bin`.

## Testing

[`test/`](test/README.md) runs the built image on an emulated Amiga 500 against
a fake RBCP device with LEDs. It needs MAME and the A500 keyboard MCU dump.

```
make
test/run.sh <rom-dir>
```

`RBCP_LEDS` sets how many LEDs the device has, from none to more than the
screen holds, and `RBCP_LED_LIES` gives the read back something to catch.

## Programming

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_led_test_512k.bin,type=27c400,label="LED Tester"
```

Read the report with `onerom monitor log`.
