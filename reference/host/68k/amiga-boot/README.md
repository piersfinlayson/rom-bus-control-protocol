# Amiga RBCP Kickstart Bootloader

Picks which Kickstart an Amiga boots from the images held on a One ROM or
other RBCP-capable ROM emulator fitted in the Kickstart socket.

## Controls

Hold **both mouse buttons** as the machine starts to get the menu. With nothing
held it boots its remembered choice, or the first non-bootloader image where
it has none.

| Input | Action |
| --- | --- |
| left click, or cursor up/down | move the highlight |
| right click, or RETURN | boot the highlighted image |
| `1`-`8` | select a ROM image |

## LED

If the device has an RGB LED:

- It cycles through colours while the menu is shown.
- It breathes a different colour for each image once you boot.

## Logging

If the device has a pipe (USB logging on One ROM), it logs the session and the
raw device state behind any error. Read it with `onerom monitor log`.

## Errors

The screen turns red with `RBCP ERROR`, the message, and how far the command
got before the device stopped answering.

## ROM type

Every image on the device must be the same ROM type (27C200 or 27C400) as the
bootloader. Choose the type from the largest image you want in the menu, and pad
the smaller ones with `size-handling=dup` when you program them.

| Build | ROM type | For |
| --- | --- | --- |
| `make` | 27C200, 256KB | a menu of 256KB images |
| `make ROM_KB=512` | 27C400, 512KB | a menu of 512KB images |

## Dependencies

[vasm and `onerom`](../README.md#requirements), and the shared Amiga routines
in [`../amiga-common/`](../amiga-common/README.md).

## Building

```
make images
```

Outputs `build/amiga_boot_256k.bin` and `build/amiga_boot_512k.bin`.

## Testing

[`test/`](test/README.md) runs the built image on an emulated Amiga 500 against
a fake RBCP device, so the menu can be driven without hardware. It needs MAME
and the A500 keyboard MCU dump.

```
make
test/run.sh <rom-dir>
```

## Programming

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_boot_512k.bin,type=27c400,label="Bootloader" \
    --slot file=ks-1_3.bin,type=27c400,size-handling=dup,label="Kickstart 1.3" \
    --slot file=diagrom-16bit.bin,type=27c400,label="DiagROM V2"
```

If `onerom` says a ROM is high byte first, add `transform=swap_bytes` to its slot.
