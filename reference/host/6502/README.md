# 6502-based Host Reference RBCP Implementations

This directory contains reference implementations of RBCP hosts for 6502-based systems. These implementations are intended to serve as examples and starting points for developers looking to implement their own RBCP hosts on 6502-based platforms.

## Contents

- [6502 RBCP Host Routines](rbcp/README.md): Generic 6502 assembly routines for communicating with an RBCP device. These can be used as building blocks for implementing an RBCP host on any 6502-based system.
- [C64 Kernal Bootloader](c64-boot/README.md): A complete example of an RBCP host implementation on a real 6502-based system, specifically the Commodore 64. This bootloader can be used to load and execute code from an RBCP device on a C64.