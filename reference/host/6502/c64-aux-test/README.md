# RBCP Auxiliary I/O Tester

Drive a device's auxiliary pins from a Commodore 64.

---

**Untested on hardware.**

In a longboard C64, the RBCP capable device should replace the 8 KB BASIC ROM — a 2364 serving $A000–$BFFF. [Other ROM Types](#other-rom-types) covers serving a combined 16KB BASIC/Kernal as used by a shortboard C64.

## Overview

Each pin is shown with:

- its level, high or low
- whether the C64 is driving it, it is free, or the ROM is using it

The information shown comes from RBCP's `GET_AUX_PIN_INFO` command, so directly from the device.

## Controls

| Key | Selects |
| --- | --- |
| cursor left, right | the pin |
| cursor up, down | the group |

| Key | Action |
| --- | --- |
| `L` | drive low |
| `H` | drive high |
| `Z` | release |
| `B` | blink |
| `T` | move test |
| `A` | show every pin |
| `R` | reset the C64 |
| `Q` | quit |

## Wiring

Auxiliary pins are whatever the device exposes, and the protocol says nothing about what is attached to one. On One ROM:

| Attach | Where | Purpose |
| --- | --- | --- |
| an LED, through a resistor to ground | any drivable pin | visual feedback |
| a loopback pair, with a 10k pull-up on the net | two drivable pins | the move test (`T`) |
| the C64 reset line | a 5V tolerant pin | resetting the C64 (`R`) |

Which pins are 5V tolerant varies by One ROM model. Check the board's documentation before connecting anything at 5V.

## Dependencies

- [cc65](https://cc65.github.io/)
- `c1541`, for the disk image. Inside the [VICE](https://vice-emu.sourceforge.io/) bundle.

## Building

Provide the path to `c1541` if it is not on your system's PATH.

```bash
make C1541=/Applications/vice-arm64-gtk3-3.9/bin/c1541
```

## Demo Build

For testing under VICE, where there is no device. `make demo` builds `rbcp_aux_demo.prg`, which answers its own questions. Separate binary, not linked into the one that talks to hardware.

`BOARD` picks the imaginary board:

| BOARD | Board |
|-------|-------|
| `0` | Three groups: 30 GPIO of which 14 drivable, 4 image select, 2 X pads with a loopback between them. |
| `1` | Two groups, no X pads, nothing in the GPIO group drivable. |
| `2` | One group of 48 GPIO, 30 drivable. Cannot time holds. |

`SCRIPT` reaches one screen at startup, through the dispatch the keyboard uses.

With VICE:

```bash
make BOARD=0 SCRIPT=2 demo
x64sc -warp -limitcycles 90000000 -exitscreenshot shot.png -autostart build/rbcp_aux_demo.prg
```

Notes:

- `-keybuf` cannot reach this program, which reads the keyboard matrix directly with interrupts masked.

## Other ROM Types

This build serves one 8 KB ROM at $A000–$BFFF. To serve a 16 KB 23128 covering BASIC and KERNAL:

| Change | In | To |
| --- | --- | --- |
| `CONFIG_ROM_SIZE` | `rbcp_config.s` | the image size |
| `ROM_TYPE_2364` | `src/aux_defs.s` | that chip type's code, from the spec |
| `checksum_image` | `src/pins_dev.s` | walk $A000–$BFFF, then $E000–$FFFF |

A 16 KB image appears in two separate places in the C64's memory map, so the checksum must walk both, in image order.

## Technical Details

### Move Test

`T` checks that a pin actually drives a wire. It drives the selected pin low, then high, then releases it, and reports whether any other pin moved with it. This needs the loopback pair fitted.

Reading the pin back instead would prove nothing, because that answer comes from the device rather than from the wire.

### Clean Exit

RBCP works by replacing part of the ROM image being served by the device (BASIC here) with a data section for transmitting data from the device to the host.

When exiting, it is important this section is replaced with the original data, or BASIC will not work properly afterwards.

`Q` cleans the BASIC image on its way out.

This is [`../common/rbcp_session.s`](../common/rbcp_session.s), shared with the LED tester.
