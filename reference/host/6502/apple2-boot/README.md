# Apple II RBCP Bootloader

Pick which ROM image an Apple II boots, from those held on a One ROM, or other RBCP capable ROM emulator, fitted in place of the F8 or EF boot ROM.

The 8KB build has been tested on an Apple IIe. **The [2KB build](#2kb-image) is untested on real hardware.**

## Controls

Upon boot the bootloader beeps, lists the images, and starts counting down. Any key stops the countdown.

| Key | Action |
| --- | --- |
| `1`-`9` | pick one of the first nine images |
| RETURN | boot the highlighted image |
| cursor up/down | move, on a IIe |
| cursor left/right | move, on any Apple II |

## Display

![The menu on a IIe, counting down to the image chosen last time](menu.png)

The countdown boots the image you chose last time, or image 1 the first time after One ROM is programmed.

## LED

If the device has an RGB LED:

- It cycles through colours while the menu is shown.
- It breathes a different colour for each image once you boot.

## Logging

If the device has a pipe (USB logging on One ROM), it logs:

```
-----
Apple ][ ROM Bootloader 0.1.0
One ROM v0.7.2, 5 flash ROM slots, 2 RAM slots
Stored choice: slot 2
  1 "Apple IIe Stock ROM"
  2 "Adrian's Apple ][ Deadtest ROM"
  3 "APPLE II MONITOR"
  4 "Applesoft Lite"
Auto-boot interrupted by keypress
Stored choice updated: slot 3
Switching to slot 3
  "APPLE II MONITOR"
Bootloader finished - resetting system
```

## Errors

The bootloader requires the first 4K of RAM, the stack and zero page. If it does not boot, try the [Apple II Dead Test ROM](https://github.com/misterblack1/appleII_deadtest) on its own first.

## Images

| Image | Size | Machine | Socket |
| --- | --- | --- | --- |
| `apple2_boot_f8.bin` | 2KB | [II, II+](#2kb-image) | F8, $F800-$FFFF |
| `apple2_boot_ef.bin` | 8KB | IIe | EF, $E000-$FFFF |

## Dependencies

- [cc65](https://cc65.github.io/) for `ca65`, `ld65` and `ar65`

## Building

```
make
```

| Option | Default | What it does |
| --- | --- | --- |
| `COUNTDOWN` | 3 | Seconds before it boots on its own. |
| `NV_FATAL` | unset | Stop instead of booting when the device will not remember the choice. 8KB build only. |

```
make COUNTDOWN=10 NV_FATAL=1
```

## Programming

For a IIe:

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/apple2_boot_ef.bin,type=2764,label="Bootloader" \
    --slot file=342-0134-A.bin,type=2764,label="Stock ROM" \
    --slot file=apple2dead.bin,type=2764,size=dup,label="Dead Test"
```

Images:
- `342-0134-A.bin` is the stock EF ROM from an Apple IIe.
- `apple2dead.bin` is from the [dead test releases](https://github.com/misterblack1/appleII_deadtest/releases). It is 2KB, so `size=dup` fills the socket.

## 2KB image

The F8 build for an Apple II or II+ omits the following support:
- RGB LED
- device information on screen
- most logging
- error diagnostics.

## Testing

[`test/`](test/README.md) runs either build on an emulated Apple II under MAME, against a fake RBCP device, and prints what the machine displays.

```
make test    ROMS=/path/to/apple2/roms
make test-ef ROMS=/path/to/apple2/roms
```

`ROMS` holds the machine's own ROM files, which are Apple's and not in the repository. [test/](test/README.md#where-the-rom-files-come-from) lists what each machine needs and where to get it.
