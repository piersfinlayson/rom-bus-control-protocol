# C64 RBCP LED Tester

A ROM image for a Commodore 64 that drives a device's LEDs and shows what each one should be doing.

**This tester is untested on real hardware.**

The device requires LEDs for this tester to operate.

## Controls

| Key | Action |
| --- | --- |
| cursor left, right | select LED |
| `F1`, `F3` | select LED 0 or 1 |
| `0`–`5` | set mode |
| cursor up, down | change colour |
| `C` | pick a colour from a list |
| `B` | change brightness |
| `P` | change period |
| `H` | change hold |
| `SPACE` | show every mode in turn |
| `A` | show everything the device reports |

In the colour list the cursor keys move, `RETURN` picks the colour and `Q` goes back.

## Display

Each LED is shown with:

- its colour
- its brightness
- its mode, for example blink, breathe or cycle

The selected LED is bracketed.

## Display blanking

The display goes off while the tester is talking to the device due to a C64 limitation. This happens once a second and whenever you change an LED.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `c64_led_kernal.bin` | 8KB, 2364 | kernal | $E000 | $E100, 512 bytes |
| `c64_led_basic.bin` | 8KB, 2364 | BASIC | $A000 | $A100, 512 bytes |
| `c64_led_combined.bin` | 16KB, 23128 | shared BASIC/kernal | $A000 | $A100, 512 bytes |

The kernal and BASIC images are for a longboard C64. Use one or the other. The BASIC image requires a stock kernal image to be present in the kernal socket.

The combined image is for a shortboard.

The 8KB images start with a black screen for about half a second.

## Dependencies

- [cc65](https://cc65.github.io/)
- Python 3

## Building

```
make
```

## Testing

Under VICE with no device fitted the program draws the screen and stops at `NO DEVICE ANSWERED THE KNOCK`:

```
x64sc -default -kernal build/c64_led_kernal.bin
x64sc -default -basic build/c64_led_basic.bin
```

The 16KB image is two 8KB halves, and VICE takes them one socket at a time:

```
dd if=build/c64_led_combined.bin of=basic.bin bs=8192 count=1
dd if=build/c64_led_combined.bin of=kernal.bin bs=8192 skip=1 count=1
x64sc -default -basic basic.bin -kernal kernal.bin
```

Anything past the screen needs a One ROM running the host-control plugin, with LEDs on it.

```
make demo
```

builds `build/c64_led_demo.bin`, a kernal socket image that answers its own questions. Run it under VICE as above and every screen is reachable with no device fitted. `BOARD` picks which imaginary board it describes.
