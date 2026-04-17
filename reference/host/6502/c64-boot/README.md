# C64 RBCP Kernal Bootloader

A custom Commodore 64 kernal ROM image that acts as an RBCP-aware bootloader, allowing the user to select and boot from multiple kernal ROM images stored on a One ROM, or other RBCP capable ROM emulator, fitted in the C64's kernal socket.

This is designed to be a reference implementation of an RBCP host on a real 6502-based system.

This code was mostly written by an LLM (Claude).

## What it does

On reset the bootloader checks whether the **Commodore (C=) key** is held:

**C= not held — auto-boot**
Loads flash slot 1 into the inactive RAM slot, switches to it, and jumps through the new kernal's reset vector. No user interaction required.

**C= held — menu**
Presents a selection menu listing all available kernal images (flash slots 1 and above). Use **CRSR UP/DOWN** to move and **RETURN** to boot the highlighted entry. Flash slot 0 (the bootloader itself) is never shown.

On any RBCP error the bootloader displays a message and halts; power-cycle to recover.

## Dependencies

- [cc65](https://cc65.github.io/) — provides `ca65` (assembler) and `ld65` (linker). Version 2.19 or later.

On Debian/Ubuntu:

```
sudo apt install cc65
```

On macOS with Homebrew:

```
brew install cc65
```

## Building

```
make
```

Output: `build/c64_boot.bin` — 8192 bytes, ready to flash as slot 0 on
a One ROM or other RBCP capable ROM emulator.

To clean:

```
make clean
```
