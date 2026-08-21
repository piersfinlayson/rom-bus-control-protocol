# Apple II RBCP Bootloader

An Apple II ROM image that acts as an RBCP-aware bootloader, letting the user pick which image to boot from those held on a One ROM, or other RBCP capable ROM emulator, fitted in the socket holding the reset vector.

**Untested on hardware.** It has run only under emulation, against the fake device described in [test/](test/README.md). It has never been in front of a real Apple II or a real RBCP device.

That socket differs by machine, so there are two builds from the same source:

| Build | Machine | Socket | Image |
|-------|---------|--------|-------|
| `apple2_boot_f8.bin` | II, II+ | F8, $F800-$FFFF | 2KB |
| `apple2_boot_ef.bin` | IIe | EF, $E000-$FFFF | 8KB |

On a II or II+ the F8 socket holds the reset vector and the monitor, and it is the socket [Adrian Black's dead test ROM](https://github.com/misterblack1/appleII_deadtest) replaces. So a One ROM there can hold the stock autostart monitor, the older monitor, a dead test image and whatever else, and this picks between them.

A IIe has no F8 socket. Its ROM is two 8KB parts, and the one holding the reset vector covers $E000-$FFFF, so the images a IIe switches between are whole 8KB EF images. See [Putting an F8 image into a IIe](#putting-an-f8-image-into-a-iie) below.

Both images end at $FFFF, so the command page and the back-channel region are at the same addresses in both and the two builds run the same code. The 8KB build has around 6KB spare.

## What it does

On reset it draws the list of images and starts a three second countdown under it, naming the one it is about to boot:

**Countdown left alone**
Boots the image the device has stored as the choice, or image 1 where it has stored nothing. No key needed.

**Any key**
Stops the countdown and leaves the list up. **CURSOR LEFT/RIGHT** move, **SPACE** moves down, **1** to **9** pick directly, **RETURN** boots. On a IIe the up and down arrows work too. The choice is written to the device's non-volatile storage first, so the next boot takes it without asking.

Flash slot 0 is the bootloader itself and is never listed. Nine images are listed, which is what one digit picks between.

On any RBCP error it says what failed and stops. Power cycling starts again.

## The device's LED

The 8KB build drives an RGB LED on the device, where it has one. The LED cycles through the hues for as long as the bootloader is up, and settles to breathing a colour of its own for each image at the moment that image is booted — green for slot 1, blue for 2, red for 3, and so on. An LED's state outlives the command-response session, so the colour is still showing long after the bootloader has handed over, and a device still cycling is one that never got that far.

It looks for the lowest-numbered LED of type RGB rather than assuming LED 0, since LEDs are numbered per device. A device with no LEDs, or one whose protocol version predates the LEDs group, is asked once and left alone.

The 2KB build leaves all of this out. There is no room in an F8 ROM for the capability query, the search and a table of colours.

Where the device has a pipe, two lines go out through it: one naming the bootloader as the session opens, and `SWITCHING TO SLOT $XX` immediately before the switch. The second is last because the switch ends the command-response session, and the image that follows need not have a back-channel at all. A device with no pipe, or one whose protocol version predates the Pipes group, is asked once and sent nothing.

## Working RAM is needed

The bootloader copies itself to $0800 and runs from there, because a ROM address read is how a command reaches the device. It therefore needs working RAM at $0800-$0FFF, the stack, and zero page — the first 4K bank, and nothing above it.

A machine too broken to run that cannot reach the menu, and cannot reach the countdown either. Booting a dead test image on such a machine means setting the device's own boot slot over USB rather than using this.

## Image layout

2KB has to hold the RBCP library, the bootloader and the two regions the protocol needs, so the image is laid out to waste none of it:

This is the 2KB image, which is the one with no room to spare:

| Address | Contents |
|---------|----------|
| $F800-$F854 | Reset entry, hardware setup and the copy to RAM. Runs from ROM. |
| $F855-$FFAF | Everything else, copied to RAM at $0800 before the session opens. |
| $FE00-$FEFF | The command page. Ordinary code — see below. |
| $FFB0-$FFEF | The back-channel region, 64 bytes. |
| $FFFA-$FFFF | 6502 vectors. |

The command page holds code rather than padding. A command page only has to be a page the host never reads while the session is open, and every byte the bootloader reads has been copied to RAM before it opens. The back-channel is 64 bytes, the smallest region `GET_FLASH_SLOT_INFO` works in, which is why image names are read one command at a time rather than as a list.

The 8KB image is the same, moved down to $E000 and with the space between the end of the code and the back-channel unused. The command page falls in that unused space.

The RBCP library is linked as an `ar65` archive, so only the fourteen command modules this bootloader calls end up in the image.

## Usage

Install the built binary as the first ROM image slot, followed by the F8 images to switch between.

For example, using One ROM:

```
onerom program  --plugin usb --plugin host-control \
                --slot build/apple2_boot_f8.bin,type=2316,cs1=0 \
                --slot apple2_autostart.bin,type=2316,cs1=0 \
                --slot apple2dead.bin,type=2316,cs1=0
```

On a IIe the images are 8KB EF images instead, `build/apple2_boot_ef.bin` first.

## Putting an F8 image into a IIe

A 2KB F8 image such as the dead test ROM has to be carried into a IIe inside a whole 8KB EF image:

```bash
tools/make_ef_image.sh 342-0134-a.64 apple2dead.bin deadtest_ef.bin
```

That takes $E000-$F7FF from the stock EF ROM and puts the F8 image at $F800. Use the EF ROM out of the machine it is going back into: **342-0134-A** on an unenhanced IIe, **342-0303-A** on an enhanced one. The enhanced firmware expects a 65C02 and the enhanced CD ROM alongside it, so the two are not interchangeable.

## Dependencies

- [cc65](https://cc65.github.io/) — provides `ca65` (assembler) and `ld65` (linker).

On Debian/Ubuntu:

```bash
sudo apt install cc65
```

On macOS with Homebrew:

```zsh
brew install cc65
```

## Building

```bash
make
```

Outputs, both ready to flash as slot 0 on a One ROM or other RBCP capable ROM emulator:

- `build/apple2_boot_f8.bin` — 2048 bytes, for the F8 socket of a II or II+
- `build/apple2_boot_ef.bin` — 8192 bytes, for the EF socket of a IIe

To clean:

```bash
make clean
```

## Testing without hardware

[`test/`](test/README.md) holds a fake RBCP device written in MAME's Lua, which watches the F8 address range, answers as a device would, and prints what comes out of the pipe. It runs the real binary against an emulated Apple II+, drives the menu from a key list, and prints the text screen.

```bash
make test    ROMS=/path/to/apple2/roms    # the 2KB build, on an Apple II+
make test-ef ROMS=/path/to/apple2/roms    # the 8KB build, on a IIe
```

`<rom-dir>` holds the machine's own ROM files. There is no default, and without them the test stops rather than making something up and reporting a pass.
