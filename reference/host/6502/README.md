# 6502-based Host Reference RBCP Implementations

This directory contains reference implementations of RBCP hosts for 6502-based systems. These implementations are intended to serve as examples and starting points for developers looking to implement their own RBCP hosts on 6502-based platforms.

## Contents

- [6502 RBCP Host Routines](rbcp/README.md): Generic 6502 assembly routines for communicating with an RBCP device. These can be used as building blocks for implementing an RBCP host on any 6502-based system.
- `common/`: What the C64 programs here share. `c64_hw.s` is the screen and the hardware setup, `c64_app.s` takes the machine over on entry and hands it back on exit, `c64_keys.s` scans the matrix from a table the application owns, and `rbcp_session.s` opens a session and finds a way out of it that leaves the served ROM as it was found. `rbcp_session_fake.s` answers the same calls without a device, for the demo builds.
- [C64 Kernal Bootloader](c64-boot/README.md): A complete example of an RBCP host implementation on a real 6502-based system, specifically the Commodore 64. This bootloader can be used to load and execute code from an RBCP device on a C64.
- [VIC-20 Kernal Bootloader](vic20-boot/README.md): The same for a VIC-20, built for PAL and for NTSC.
- [Apple II Bootloader](apple2-boot/README.md): The same for an Apple II, in a 2KB F8 ROM on a II or II+ and an 8KB EF ROM on a IIe.
- [C64 Pipe Throughput Test](c64-pipe-test/README.md): Measures how fast a C64 can push bytes through an RBCP pipe.
- [C64 Auxiliary I/O Tester](c64-aux-test/README.md): Drives and reads a device's auxiliary pins from a C64, showing every one of them on screen.
- [C64 LED Tester](c64-led-test/README.md): Drives a device's LEDs from a C64, showing on screen what each one should be doing.