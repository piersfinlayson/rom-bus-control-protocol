# Host Reference RBCP Implementations

This directory contains reference implementations of RBCP hosts for various platforms. These implementations are intended to serve as examples and starting points for developers looking to implement their own RBCP hosts on different systems.

They were all developed and tested against [One ROM](https://onerom.org), but should work against all complete, compliant implementations of the RBCP specification of the appropriate version.

## Contents

- [`6502/`](6502/README.md) — 6502-based systems
  - [`6502/rbcp/`](6502/rbcp/README.md) — Generic 6502 RBCP routines
  - [`6502/c64-boot/`](6502/c64-boot/README.md) — A C64 kernal bootloader
  - [`6502/vic20-boot/`](6502/vic20-boot/README.md) — A VIC-20 kernal bootloader
  - [`6502/apple2-boot/`](6502/apple2-boot/README.md) — An Apple II and IIe ROM bootloader
  - [`6502/c64-pipe-test/`](6502/c64-pipe-test/README.md) — A C64 pipe throughput test
  - [`6502/vic20-pipe-test/`](6502/vic20-pipe-test/README.md) — A VIC-20 pipe throughput test
  - [`6502/apple2-pipe-test/`](6502/apple2-pipe-test/README.md) — An Apple IIe pipe throughput test
  - [`6502/pipe/`](6502/pipe/README.md) — Shared 6502 pipe throughput test routines
  - [`6502/c64-aux-io/`](6502/c64-aux-io/README.md) — A C64 auxiliary I/O tester
  - [`6502/c64-led-test/`](6502/c64-led-test/README.md) — A C64 LED tester
  - [`6502/c64-rbcp-stress/`](6502/c64-rbcp-stress/README.md) — A C64 RBCP reliability meter
  - [`6502/vic20-rbcp-stress/`](6502/vic20-rbcp-stress/README.md) — A VIC-20 RBCP reliability meter
  - [`6502/apple2-rbcp-stress/`](6502/apple2-rbcp-stress/README.md) — An Apple IIe RBCP reliability meter
  - [`6502/stress/`](6502/stress/README.md) — Shared 6502 RBCP reliability meter routines
  - [`6502/vic20-aux-io/`](6502/vic20-aux-io/README.md) — A VIC-20 auxiliary I/O tester
  - [`6502/apple2-aux-io/`](6502/apple2-aux-io/README.md) — An Apple IIe auxiliary I/O tester
  - [`6502/c64-rbcp-term/`](6502/c64-rbcp-term/README.md) — A C64 RBCP terminal
  - [`6502/vic20-rbcp-term/`](6502/vic20-rbcp-term/README.md) — A VIC-20 RBCP terminal
  - [`6502/apple2-rbcp-term/`](6502/apple2-rbcp-term/README.md) — An Apple IIe RBCP terminal
- [`68k/`](68k/README.md) — 68000-family systems
  - [`68k/rbcp/`](68k/rbcp/README.md) — Generic 68K RBCP routines, including the bus mapping needed where the device is narrower than the host's bus
  - [`68k/amiga-common/`](68k/amiga-common/README.md) — Shared Amiga application routines
  - [`68k/amiga-boot/`](68k/amiga-boot/README.md) — An Amiga Kickstart bootloader
  - [`68k/amiga-rbcp-stress/`](68k/amiga-rbcp-stress/README.md) — An Amiga RBCP reliability meter
  - [`68k/amiga-pipe-test/`](68k/amiga-pipe-test/README.md) — An Amiga pipe throughput test
  - [`68k/amiga-rbcp-term/`](68k/amiga-rbcp-term/README.md) — An Amiga RBCP terminal
  - [`68k/amiga-aux-io/`](68k/amiga-aux-io/README.md) — An Amiga auxiliary I/O tester
  - [`68k/amiga-led-test/`](68k/amiga-led-test/README.md) — An Amiga LED tester
- [`x86/`](x86/README.md) — x86 PCs
  - [`x86/romsel/`](x86/romsel/README.md) — A DOS program that picks which image a One ROM serves from an 8088 machine's BIOS socket, and resets into it

## Host Word Size

Hosts come in 8-bit, 16-bit and 32-bit word width.

The 6502 and 8088 processor implementations are built to support 8-bit words.  Hence a byte offset in the device's slot is a byte offset in the CPU's address space.

A 68K processor may use 16 or 32-bit words. The current 68k reference implementation is built expecting a single 16-bit ROM (as opposed to 2 8-bit ROMs). Therefore a command byte advances the CPU address by two and the command page is a page of the word address, not a byte address. In the other direction the specification assigns even back-channel offsets to D0–D7, which a big-endian 68K reads from the *higher* CPU address of a word — so the back-channel's bytes appear at the opposite CPU addresses to their region offsets.
