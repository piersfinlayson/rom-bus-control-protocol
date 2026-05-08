# VIC-20 RBCP Kernal Bootloader

A custom VIC-20 kernal ROM image that acts as an RBCP-aware bootloader, allowing the user to select and boot from multiple kernal ROM images stored on a One ROM, or other RBCP capable ROM emulator, fitted in the VIC 20's kernal socket.

This is designed to be a reference implementation of an RBCP host on a real 6502-based system.  Other, better, implementations are hoped to supercede this.

## What it does

On reset the bootloader checks whether the **Commodore (C=) key** is held:

**C= not held — auto-boot**
Loads flash slot 1 into the inactive RAM slot, switches to it, and jumps through the new kernal's reset vector. No user interaction required.

**C= held — menu**
Presents a selection menu listing all available kernal images (flash slots 1 and above). Use **CRSR UP/DOWN** to move and **RETURN** to boot the highlighted entry. Flash slot 0 (the bootloader itself) is never shown.

On any RBCP error the bootloader displays a message and halts; power-cycle to recover.

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
- `build/vic20_boot_pal.bin` — PAL version, 8192 bytes, ready to flash as slot 0 on a One ROM or other RBCP capable ROM emulator
- `build/vic20_boot_ntsc.bin` — NTSC version, 8192 bytes, ready to flash as slot 0 on a One ROM or other RBCP capable ROM emulator

To clean:

```bash
make clean
```

## Debugging

When running against a One ROM with logging enabled, the bootloader will assume that One ROM has switched to a new slot before it has actually done so.  To work around this, build the bootloader with `PAUSE_BEFORE_RESET=1`:

```bash
PAUSE_BEFORE_RESET=1 make
```
