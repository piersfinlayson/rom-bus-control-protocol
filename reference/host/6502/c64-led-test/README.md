# RBCP LED Tester

Drive a device's LEDs from a Commodore 64.

---

In a longboard C64, the RBCP capable device should replace the 8 KB BASIC ROM — a 2364 serving $A000–$BFFF. [Other ROM types](#other-rom-types) covers serving a combined 16KB BASIC/Kernal as used by a shortboard C64.

## Overview

Each LED is shown with:

- the colour it is showing
- how brightly it is lit
- the mode it is using (e.g. blink, cycle, breathe)

The selected LED is bracketed.

The information shown comes from RBCP's `GET_LED_INFO` command, so directly from the device.

## Controls

| Key | Selects |
| --- | --- |
| `F1`, `F3` | an LED |
| `0`–`5` | a mode |
| cursor left, right | the LED |
| cursor up, down | the colour |

| Key | Action |
| --- | --- |
| `C` | colour list |
| `B` | brightness |
| `P` | period |
| `H` | hold |
| `SPACE` | steps all supported LED modes |
| `A` | displays the device's LED data |
| `Q` | quit |

## Dependencies

- [cc65](https://cc65.github.io/)
- `c1541`, for the disk image. Inside the [VICE](https://vice-emu.sourceforge.io/) bundle.

## Building

Provide the path to `c1541` if it is not on your system's PATH, e.g.

```bash
make C1541=/Applications/vice-arm64-gtk3-3.9/bin/c1541
```

`make LED_DIAGS=1` adds two rows showing internal diagnostics.

## Demo Build

For testing under VICE without a device:

```bash
make demo
```

Builds `rbcp_led_demo.prg`, which runs standalone emulating the device. This is a separate binary to the one designed for real hardware.

`BOARD` picks the imaginary device:

| BOARD | Device |
|-------|--------|
| `0` | Mono status LED and an RGB one. Times a period and a hold. |
| `1` | One RGB LED. No period, no hold. |
| `2` | No LEDs. |
| `3` | Three LEDs, and LED 0 reports its own brightness whatever it is given. |

`SCRIPT` reaches one screen at startup, through the dispatch the keyboard uses:

| SCRIPT | Screen |
|--------|--------|
| `1` | RGB LED lit, in a colour it was given. |
| `2` | Breathing, half brightness, with a period. |
| `3` | The colour list. |
| `4` | Every byte the device reported. |
| `5` | A mode this LED does not have, refused. |
| `6` | A parade, run to the end. |
| `7` | Half brightness, dithered. On board 3, the read back catching the device out. |
| `8` | A hold on a device that times none. |
| `9` | A beacon. |

For example with VICE:

```bash
make BOARD=0 SCRIPT=2 demo
x64sc -warp -limitcycles 90000000 -exitscreenshot shot.png -autostart build/rbcp_led_demo.prg
```

Notes:

- `-keybuf` cannot reach this program, which reads the keyboard matrix directly with interrupts masked.

## Other ROM Types

This build serves one 8 KB ROM at $A000–$BFFF. To serve a 16 KB 23128 covering BASIC and KERNAL:

| Change | In | To |
| --- | --- | --- |
| `CONFIG_ROM_SIZE` | `rbcp_config.s` | the image size |
| `CONFIG_ROM_TYPE` | `rbcp_config.s` | that chip type's code, from the spec |
| `checksum_image` | `../common/rbcp_session.s` | walk $A000–$BFFF, then $E000–$FFFF |

A 16 KB image appears in two separate places in the C64's memory map, so the checksum must walk both, in image order.

## Technical Details

### Display Blanking

With the display on, some commands come back wrong. The VIC-II takes the bus for 40+ cycles on every eighth raster line, and across that handover a device can:

- see a phantom access
- see one access as two
- miss one

Each slips the command frame by a byte.

| Display | Commands wrong |
| --- | --- |
| on | 1 in 500 to 1 in 20,000, by board |
| off | none |

So the program clears bit 4 of `$D011` to disable the device around every exchange. The idle refresh runs once a second rather than every pass, which strobed the screen hard enough to be a hazard.

### Recovery

If the device fails to answer an RBCP command, RBCP framing breaks for every subsequent command, because the device is left waiting for argument bytes that never arrive. When detected, the program resets RBCP communications using [`../common/rbcp_recover.s`](../common/rbcp_recover.s), shared with the reliability meter implementation.

### Clean Exit

RBCP works by replacing part of the ROM image being served by the device (BASIC here) with a data section for transmitting data from the device to the host.

When exiting, it is important this section is replaced with the original data, or BASIC will not work properly, subsequently.

Exiting uses `Q` cleans the BASIC image on its way out.

This is [`../common/rbcp_session.s`](../common/rbcp_session.s), shared with the auxiliary I/O tester.
