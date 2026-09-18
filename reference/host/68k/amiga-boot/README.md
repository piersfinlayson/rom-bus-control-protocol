# Amiga RBCP Kickstart Bootloader

Pick which Kickstart an Amiga boots, from those held on a One ROM, or other
RBCP capable ROM emulator, fitted in the Kickstart socket.

## Controls

Hold **both mouse buttons** as the machine starts to get the menu. With nothing
held it boots either the first non-bootloader image, or last booted image.

| Input | Action |
| --- | --- |
| left click, or cursor up/down | move the highlight |
| right click, or RETURN | boot the highlighted image |
| `1`-`8` | pick a ROM image |

## LED

If the device has an RGB LED:

- It cycles through colours while the menu is shown.
- It breathes a different colour for each image once you boot.

## Logging

If the device has a pipe (USB logging on One ROM), it logs the session, and the
raw device state behind any error. Read it with `onerom monitor log`.

## Errors

The screen turns red with `RBCP ERROR`, the message, and how far the command
got before the device stopped answering.

## ROM type

Every image on the device must be the same ROM type (27C200 or 27C400) as the
bootloader. Pick the type from the largest image you want in the menu, and pad
the smaller ones with `size-handling=dup` when you program them.

| Build | ROM type | For |
| --- | --- | --- |
| `make` | 27C200, 256KB | a menu of 256KB images |
| `make ROM_KB=512` | 27C400, 512KB | a menu of 512KB images |

On One ROM Fire 40A and on later models using 27C400, the last booted image is
not stored (as there is insufficient RAM on One ROM to modify NV storage).

## Dependencies

[vasm and `onerom`](../README.md#requirements)

## Building

```
make
```

`make` writes `build/amiga_boot_swapped.bin`, the image in the device's byte
order. Program this file.

## Programming

For a 512KB menu, with a 256KB Kickstart padded out to fill its slot:

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_boot_swapped.bin,type=27c400,label="Bootloader" \
    --slot file=ks-1_3.bin,type=27c400,size-handling=dup,label="Kickstart 1.3" \
    --slot file=diagrom-16bit.bin,type=27c400,label="DiagROM V2"
```

If `onerom` says a Kickstart dump is high byte first, add `transform=swap_bytes`
to its slot.
