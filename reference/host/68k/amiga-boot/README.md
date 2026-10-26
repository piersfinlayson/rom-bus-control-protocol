# Amiga RBCP Kickstart Bootloader

Picks which Kickstart an Amiga boots from the images held on a One ROM or
other RBCP-capable ROM emulator fitted in the Kickstart socket(s).

## Controls

Hold **both mouse buttons** as the machine starts to get the menu. With nothing
held it boots its remembered choice, or the first non-bootloader image where
it has none.

| Input | Action |
| --- | --- |
| left click, or cursor up/down | move the highlight |
| right click, or RETURN | boot the highlighted image |
| `1`-`9`, `A`-`F` | select a ROM image |
| `I` | show One ROM info |

## LED

If the device has an RGB LED:

- It cycles through colours while the menu is shown.
- It breathes the image's colour once you boot, the colours repeating after eight.

## Logging

If the device has a pipe (USB logging on One ROM), it logs the session and the
raw device state behind any error. Read it with `onerom monitor log`.

## Errors

The screen turns red with `RBCP ERROR`, the message, and how far the command
got before the device stopped answering. On a 32-bit Amiga `WORD` is the One
ROM that failed. `HI` is the one serving the high word, in U6A on an A1200, and
`LO` the one serving the low word, in U6B.

`ROM FIRMWARE VERSIONS DIFFER`, `ROM TYPES OR BOARDS DIFFER` and
`ROM IMAGE COUNTS DIFFER` mean the two One ROMs don't match. Program both with
the same firmware, ROM type and images.

## ROM type

Every image on the device must be the same ROM type (27C200 or 27C400) as the
bootloader. Choose the type from the largest image you want in the menu, and pad
the smaller ones with `size-handling=dup` when you program them.

| Build | ROM type | For |
| --- | --- | --- |
| `make` | 27C200, 256KB | a menu of 256KB images |
| `make ROM_KB=512` | 27C400, 512KB | a menu of 512KB images |
| `make BUS=32` | 27C200, 256KB on each One ROM | an A1200, A3000, A4000 or A4000T |
| `make BUS=32 ROM_KB=512` | 27C400, 512KB on each One ROM | an A1200 |

The A1200 wires a 27C400's extra address line to the CPU. The A3000, A4000 and
A4000T leave it unconnected, so use the 27C200 build on them.

## Dependencies

[vasm and `onerom`](../README.md#requirements), and the shared Amiga routines
in [`../amiga-common/`](../amiga-common/README.md). The 32-bit build also
requires Python 3.

## Building

```
make images
```

Outputs:

- `build/amiga_boot_256k.bin`
- `build/amiga_boot_512k.bin`
- `build/amiga_boot_32bit_256k_hi.bin`
- `build/amiga_boot_32bit_256k_lo.bin`
- `build/amiga_boot_32bit_512k_hi.bin`
- `build/amiga_boot_32bit_512k_lo.bin`

## Testing

[`test/`](test/README.md) runs the built image on an emulated Amiga 500 against
a fake RBCP device, so the menu can be driven without hardware. It needs MAME
and the A500 keyboard MCU dump.

```
make
test/run.sh <rom-dir>
```

The 32-bit build runs on an emulated A1200, A3000, A4000 or A4000T against a
fake device in each socket:

```
make BUS=32
RBCP_TARGET=a1200 test/run.sh <rom-dir>
```

## Programming

You can use One ROM's stock configs to program the bootloader and the RBCP test applications.

| Config | Name |
| --- | --- |
| [`40-amiga-bootloader-256k.json`](https://images.onerom.org/configs/40-amiga-bootloader-256k.json) | Amiga Bootloader (256KB) |
| [`40l-amiga-bootloader-512k.json`](https://images.onerom.org/configs/40l-amiga-bootloader-512k.json) | Amiga Bootloader (512KB) |
| [`40-amiga-bootloader-32bit-512k-hi.json`](https://images.onerom.org/configs/40-amiga-bootloader-32bit-512k-hi.json) | Amiga 32-bit Bootloader, High Word (512KB) |
| [`40-amiga-bootloader-32bit-512k-lo.json`](https://images.onerom.org/configs/40-amiga-bootloader-32bit-512k-lo.json) | Amiga 32-bit Bootloader, Low Word (512KB) |

`40l-amiga-bootloader-512k.json` requires a size L One ROM. The 32-bit configs
are for an A1200 and contain the bootloader and DiagROM V2.

The configs don't contain a Kickstart image. To use a Kickstart image add it after the bootloader like this:

```json
{
    "type": "single",
    "chips": [
        {
            "label": "Kickstart 3.1",
            "file": "kick31.rom",
            "type": "27C400"
        }
    ]
},
```

Notes:
- A 256KB Kickstart image in the 512KB config requires `"size_handling": "duplicate"`.
- A Kickstart in a 32-bit config requires `"transform": [{"deinterleave": {"offset": 0, "stride": 2, "bytes": 2}}, "swap_bytes"]`, with `"offset": 1` for the low word, and `"size_handling": "duplicate"`.
- If `onerom` prints a warning that the Kickstart is high byte first, add `"transform": ["swap_bytes"]`.
- If using a relative `file` path with the CLI, it must start from the directory `onerom` runs in.

Program it with Studio or the CLI:

```
onerom program --config 40l-amiga-bootloader-512k.json
```

Or, without using a config file:

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_boot_512k.bin,type=27c400,label="Bootloader" \
    --slot file=ks-1_3.bin,type=27c400,size-handling=dup,label="Kickstart 1.3" \
    --slot file=diagrom-16bit.bin,type=27c400,label="DiagROM V2"
```

If `onerom` prints a warning that a ROM is high byte first, add `transform=swap_bytes` to its slot.

### 32-bit Amiga

Program the `_hi` image into the One ROM for the high word socket, U6A on an
A1200, and the `_lo` image into the one for U6B.

A Kickstart for a 32-bit Amiga is usually one 512KB file. `deinterleave`
extracts half for programming to each One ROM:

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_boot_32bit_256k_hi.bin,type=27c200,label="Bootloader" \
    --slot file=kick31.rom,type=27c200,transform=deinterleave:0/2/2+swap_bytes,label="Kickstart 3.1"
```

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_boot_32bit_256k_lo.bin,type=27c200,label="Bootloader" \
    --slot file=kick31.rom,type=27c200,transform=deinterleave:1/2/2+swap_bytes,label="Kickstart 3.1"
```

For the 27C400 pair, use the `_512k_` images and `type=27c400`, and add
`size-handling=dup` to the Kickstart's slot.

Program the images in the same order on both. The menu displays the slots configures
on the high word's One ROM.
