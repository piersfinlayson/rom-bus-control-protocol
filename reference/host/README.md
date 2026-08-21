# Host Reference RBCP Implementations

This directory contains reference implementations of RBCP hosts for various platforms. These implementations are intended to serve as examples and starting points for developers looking to implement their own RBCP hosts on different systems.

## Contents

- [`6502/`](6502/README.md) — 6502-based systems
  - [`6502/rbcp/`](6502/rbcp/README.md) — Generic 6502 RBCP routines
  - [`6502/c64-boot/`](6502/c64-boot/README.md) — A C64 kernal bootloader
  - [`6502/vic20-boot/`](6502/vic20-boot/README.md) — A VIC-20 kernal bootloader
  - [`6502/apple2-boot/`](6502/apple2-boot/README.md) — An Apple II and IIe ROM bootloader
- [`68k/`](68k/README.md) — 68000-family systems
  - [`68k/rbcp/`](68k/rbcp/README.md) — Generic 68K RBCP routines, including the bus mapping needed where the device is narrower than the host's bus
  - [`68k/amiga-boot/`](68k/amiga-boot/README.md) — An Amiga Kickstart bootloader

## A note on host width

The 6502 implementations have the simplest possible relationship to the protocol: the ROM is eight bits wide, the CPU bus is eight bits wide, and a byte offset in the device's slot is a byte offset in the CPU's address space.

That does not hold on a 68K. A word-organised ROM read as words presents the device with the ROM's *word* address lines, so a command byte advances the CPU address by two and the command page is a page of the word address. In the other direction the specification assigns even back-channel offsets to D0–D7, which a big-endian 68K reads from the *higher* CPU address of a word — so the back-channel's bytes appear at the opposite CPU addresses to their region offsets.

The [68K routines](68k/rbcp/README.md) reduce all of this to five configuration constants.
