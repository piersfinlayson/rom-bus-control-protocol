# VIC-20 RBCP Kernal Bootloader

A custom VIC-20 kernal ROM image that acts as an RBCP-aware bootloader, allowing the user to select and boot from multiple kernal ROM images stored on a One ROM, or other RBCP capable ROM emulator, fitted in the VIC 20's kernal socket.

This is designed to be a reference implementation of an RBCP host on a real 6502-based system.  Other, better, implementations are hoped to supercede this.

## What it does

One image runs on PAL and NTSC VIC-20s.

On reset the bootloader checks whether the **Commodore (C=) key** is held:

**C= not held — auto-boot**
Loads last booted slot into the inactive RAM slot.

**C= held — menu**
Presents a selection menu listing all available kernal images (flash slots 1 and above). Use **CRSR UP/DOWN** to move and **RETURN** to boot the highlighted entry. Flash slot 0 (the bootloader itself) is never shown.

## Usage

One ROM's stock config contains:
- the bootloader
- the PAL and NTSC stock kernals
- the RBCP test applications

| Config | Name |
| --- | --- |
| [`vic20-bootloader.json`](https://images.onerom.org/configs/vic20-bootloader.json) | VIC-20 Bootloader |

To add an image of your own, copy a slot in a downloaded config updating `label` and `file`. If using a relative `file` path with the CLI, it must start from the directory `onerom` runs in.

Program it with Studio or the CLI:

```
onerom program --config vic20-bootloader.json
```

Or, without using a config file, install the built binary as the first ROM image slot, followed by the kernal images you wish to switch between.

For example, using One ROM and the pre-built bootloader binary:

```
onerom program  --plugin usb --plugin host-control \
                --slot https://images.onerom.org/roms/host-control/vic20-boot/latest/vic20_boot.bin,type=2364,cs1=0 \
                --slot kernal1.bin,type=2364,cs1=0 \
                --slot kernal2.bin,type=2364,cs1=0
```

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

Output:
- `build/vic20_boot.bin` — 8192 bytes, ready to flash as slot 0 on a One ROM or other RBCP capable ROM emulator

To clean:

```bash
make clean
```

## Debugging

When running against a One ROM with logging enabled, the bootloader will assume that One ROM has switched to a new slot before it has actually done so.  To work around this, build the bootloader with `PAUSE_BEFORE_RESET=1`:

```bash
PAUSE_BEFORE_RESET=1 make
```
