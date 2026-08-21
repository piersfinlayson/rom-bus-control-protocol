# 68K-based Host Reference RBCP Implementations

This directory contains reference implementations of RBCP hosts for 68000-family systems. They are intended as examples and starting points for developers implementing an RBCP host on a 68K platform.

## Contents

- [68K RBCP Host Routines](rbcp/README.md): Generic 68K assembly routines for communicating with an RBCP device, including the bus mapping that a 68K host needs when the device is narrower than the host's bus.
- [Amiga Kickstart Bootloader](amiga-boot/README.md): An Amiga Kickstart ROM image that talks to the device serving it. Untested on hardware.

## Why the 68K needs a bus mapping

On a 6502 the ROM is eight bits wide, the CPU bus is eight bits wide, and a byte offset in the device's slot is a byte offset in the CPU's address space. None of that holds on a 68K.

An Amiga reads its Kickstart ROM as 16-bit words, so the device observes the ROM's *word* address lines. One RBCP command byte therefore advances the CPU address by two, and the command page is a page of the word address, not of the byte address.

In the other direction, the specification assigns the back-channel's even byte offsets to D0–D7 and its odd offsets to D8–D15. A big-endian 68K reads the byte at an even CPU address from D8–D15, so the two bytes of every device word appear at the *opposite* CPU addresses to their back-channel offsets. The response header's progress field is at region offset 4 but CPU offset 5; its response field is at region offset 5 but CPU offset 4.

Both directions are handled by five constants in `rbcp_config.s` — see [rbcp/README.md](rbcp/README.md).

## Requirements

- [vasm](http://sun.hasenbraten.de/vasm/) with the M68K backend and Motorola syntax:
  ```bash
  make CPU=m68k SYNTAX=mot
  ```
  There is no official git repository; the tarball on that page is upstream.
- Optionally [One ROM](https://onerom.org)'s `onerom` tool, to byte-swap the built image into device order.
