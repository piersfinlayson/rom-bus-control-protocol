# 6502-based Host Reference RBCP Implementations

This directory contains reference implementations of RBCP hosts for 6502-based systems. These implementations are intended to serve as examples and starting points for developers looking to implement their own RBCP hosts on 6502-based platforms.

## C64 Implementation Note

On every eighth raster line of the display window the C64's VIC-II video chip takes the bus off the processor for forty cycles or more. The address bus and the chip select change hands across that, and around the handover a device can see an access that was not one, see one access as two, or miss one, any of which slips the command frame by a byte. Measured on real machines, a C64 with the display on gets an RBCP command wrong somewhere between 1 in 500 and 1 in 20,000, depending on the C64 board type and socket the RBCP device is used in.

Clearing bit 4 of `$D011` (display enable) around an exchange stops every fetch, and with the display off nothing slips. This causes a blank screen for as long as the exchange takes, which for a few commands should be imperceptible.

Reading with the raster keeps the picture instead. Badlines fall on known raster lines, so a host that synchronises to the raster and counts its own cycles can place every command read clear of them. It is what tape loaders did to show anything while loading, and it is the harder of the two — the host has to know its own cycle counts exactly, and PAL and NTSC do not agree.

Some of the C64 implementations in this directory use display disable approach.

## Contents

- [6502 RBCP Host Routines](rbcp/README.md): Generic 6502 assembly routines for communicating with an RBCP device. These can be used as building blocks for implementing an RBCP host on any 6502-based system.
- `common/`: What the programs here share. `c64_hw.s` is the screen and the hardware setup, `c64_app.s` takes the machine over on entry and hands it back on exit, `c64_keys.s` scans the matrix from a table the application owns, and `rbcp_session.s` opens a session and finds a way out of it that leaves the served ROM as it was found. `rbcp_session_fake.s` answers the same calls without a device, for the demo builds. `rbcp_stage.s` names the three ways the library reports a command failing, and `rbcp_recover.s` is the reset and re-entry that puts a device which has stopped answering back together. Those last two are not the C64's, and the VIC-20 and Apple IIe meters use them too.
- [C64 Kernal Bootloader](c64-boot/README.md): A complete example of an RBCP host implementation on a real 6502-based system, specifically the Commodore 64. This bootloader can be used to load and execute code from an RBCP device on a C64.
- [VIC-20 Kernal Bootloader](vic20-boot/README.md): The same for a VIC-20, built for PAL and for NTSC.
- [Apple II Bootloader](apple2-boot/README.md): The same for an Apple II, in a 2KB F8 ROM on a II or II+ and an 8KB EF ROM on a IIe.
- [C64 LED Tester](c64-led-test/README.md): Drives a device's LEDs from a C64, showing on screen what each one should be doing.
- [C64 Pipe Throughput Test](c64-pipe-test/README.md): A ROM that measures how many bytes a C64 can push through an RBCP pipe, in an 8KB image for each of the two C64 ROM sockets and a 16KB image spanning both.
- [VIC-20 Pipe Throughput Test](vic20-pipe-test/README.md): The same test for a VIC-20, PAL and NTSC.
- [Apple IIe Pipe Throughput Test](apple2-pipe-test/README.md): The same test for an Apple IIe, which can be run against the fake RBCP device in MAME's Lua.
- `pipe/`: What the pipe throughput testers share, which is everything but the screen, the keys, the clock and the zero page. `pipe.s` is the menu and the run loop, `display.s` the layout, `timing.s` the one-second window, `line.s` the payload, `send_lib.s` and `send_tuned.s` the three send paths, `fault.s` what happens when a write does not go through, and `pipe_rx` the receiving end. Each machine supplies a `plat_defs.s` and a `plat.s`.
- `stress/`: What the reliability meters share, which is everything but the screen, the keys and the one thing each machine varies. `stress.s` is the loop and the counts, `display.s` the layout, `report.s` the pipe report, `ratio.s` the division and the decimal conversion behind the headline, and `session.s` the little a ROM-resident tester needs of a session. Each machine supplies a `plat_defs.s` and a `plat.s`.
- [C64 Reliability Meter](c64-rbcp-stress/README.md): A ROM that counts how many RBCP commands a device answers per one it gets wrong, in an 8KB image for each of the two C64 ROM sockets and a 16KB image spanning both.
- [VIC-20 Reliability Meter](vic20-rbcp-stress/README.md): The same meter for a VIC-20, PAL and NTSC.
- [Apple IIe Reliability Meter](apple2-rbcp-stress/README.md): The same meter for an Apple IIe, which can be run against the fake RBCP device in MAME's Lua.
- [C64 Auxiliary I/O Tester](c64-aux-io/README.md): A ROM that drives and reads a device's auxiliary pins, showing them on screen.
- [VIC-20 Auxiliary I/O Tester](vic20-aux-io/README.md): The same tester for a VIC-20, PAL and NTSC, on a machine with the 3K expansion.
- [Apple IIe Auxiliary I/O Tester](apple2-aux-io/README.md): The same tester for an Apple IIe, which can be run against the fake RBCP device in MAME's Lua.
- `aux-io/`: Code shared by the auxiliary I/O testers.
- [C64 RBCP Terminal](c64-rbcp-term/README.md): A ROM that sends what you type down an RBCP pipe (for example to USB).
- [VIC-20 RBCP Terminal](vic20-rbcp-term/README.md): The same terminal for a VIC-20, PAL and NTSC, on an unexpanded machine.
- [Apple IIe RBCP Terminal](apple2-rbcp-term/README.md): The same terminal for an Apple IIe, which can be run against the fake RBCP device in MAME's Lua.
- `term/`: Code shared by the terminal programs.