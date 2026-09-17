# Amiga RBCP Kickstart Bootloader

Pick which Kickstart image an Amiga boots, from those held on a One ROM, or
another RBCP-capable ROM emulator, fitted in place of the Kickstart ROM.

On a cold start it boots your chosen image straight away. Hold both mouse
buttons as it starts to get a menu instead, the way the Amiga's own early
startup screen is summoned.

## What is confirmed on hardware

Tested on an Amiga A500 with a One ROM (fire-40-b, firmware 0.7.2), over the
device's own channels rather than by watching the screen: entering
command-response mode, reading the device type, version, slot counts and every
slot name, the RGB LED, the USB log, and the boot switch. Both the 256KB and
512KB builds run, and a 512KB DiagROM loads and is served correctly. The
on-screen menu and the mouse and keyboard navigation are drawn and coded but
have not all been watched on a real display yet.

## Controls

With nothing held it boots the remembered choice, or image 1 the first time.
Hold **both mouse buttons** as the machine starts to get the menu.

| Input | Action |
| --- | --- |
| left click, or cursor up/down | change the highlighted image |
| right click, or RETURN | boot the highlighted image |
| `1`-`9` | pick one of the first nine directly |

The menu appears while the buttons are still down and only starts reading
clicks once they come up, so the gesture that opened it is not read as a
choice.

## Display

The title and the highlighted image sit on full-width bars; the entries are
centred. The bottom line names the device and its version, read from the
device itself, so it says what is actually serving the ROM.

## LED

If the device has an RGB LED, it cycles colours while the menu is shown and
breathes a colour of its own per image once you boot — so the machine says
which image it is running after the bootloader has handed over.

## Logging

If the device has a pipe (USB logging on One ROM), it logs the session, and
the raw device state on any error. Read it with `onerom monitor log`.

## Remembering the choice

Where the device has writable non-volatile storage and two or more RAM slots,
picking an image records it and boots it next time. The write is staged in a
spare RAM slot, so a device with only one — which is what serving a 512KB image
leaves — cannot remember a choice and always starts on image 1.

## ROM size and the boot switch

The bootloader runs entirely from chip RAM, so replacing the served ROM does
not pull the code out from under it.

The device will only load an image into a slot whose ROM type matches the size
of what is served, so **every image in the menu must be the same ROM type as
the bootloader**. Build the bootloader at the largest size you need and store
the smaller images at that size:

- **256KB (27C200):** `make`, and program every image as `type=27c200`. On a
  device with two RAM slots this loads into the spare slot and switches to it,
  and the remembered choice works.
- **512KB (27C400):** `make ROM_KB=512`, and program every image as
  `type=27c400`, duplicating a 256KB image to fill the slot with
  `size-handling=dup`. Serving 512KB leaves one RAM slot, so it loads into the
  active slot with `LOAD_AND_EXIT` and cannot remember a choice.

Either way it then cold-starts the machine through the new image's own reset
vector.

## Building

```
make            # 256KB (27C200)
make ROM_KB=512 # 512KB (27C400)
```

Requires [vasm](http://sun.hasenbraten.de/vasm/) built with
`make CPU=m68k SYNTAX=mot`, and `font_8x8.bin` — a 2048-byte headerless 8×8
bitmap font, 256 glyphs of 8 bytes, MSB leftmost.

Output:

| File | Contents |
| --- | --- |
| `build/amiga_boot.bin` | The image in 68K byte order |
| `build/amiga_boot_swapped.bin` | The same image in device byte order |

**Write the swapped image to the device.** The 68K is big-endian and the
device stores its slot in its own byte order, so the natural image must be
byte-swapped first, which `onerom image swap-bytes` does. Kickstart images
already in device byte order are written as they are.

## Programming

512KB example — a 512KB DiagROM and a 256KB Kickstart 1.3 duplicated to fill
its slot:

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_boot_swapped.bin,type=27c400,label="Bootloader" \
    --slot file=ks-1_3.bin,type=27c400,size-handling=dup,label="Kickstart 1.3" \
    --slot file=diagrom-16bit.bin,type=27c400,label="DiagROM V2"
```

The bootloader is slot 0. The images follow, in the order the menu shows them.
To see the menu again after it has booted an image, cold-boot the device so it
serves slot 0 again — `onerom reboot`, then reset the machine.

## Files

| File | Purpose |
| --- | --- |
| `amiga_boot.s` | Boot, relocation, the RBCP session, the menu, logging and the boot switch |
| `amiga_hw.s` | ROM-section hardware init: chipset, vectors, display, keyboard, pots |
| `amiga_defs.s` | Hardware constants, the chip RAM layout and the menu layout |
| `rbcp_config.s` | RBCP configuration — ROM size, bus mapping, region placement |
