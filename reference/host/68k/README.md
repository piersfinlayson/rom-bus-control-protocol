# 68K Host Reference RBCP Implementations

Reference RBCP host implementations for 68000-family systems, as examples and
starting points for your own.

## Contents

| Directory | What it is |
| --- | --- |
| [`rbcp/`](rbcp/README.md) | Generic 68K assembly routines for talking to an RBCP device, and the bus mapping a 68K host needs |
| [`amiga-boot/`](amiga-boot/README.md) | An Amiga Kickstart ROM image that picks which Kickstart the machine boots |

## Why a 68K is different

A 6502 reads its ROM a byte at a time, so an RBCP address is a CPU address and
there is nothing to work out. A 68K reads two bytes at a time. That moves every
RBCP address somewhere else in the CPU's address space, and the two bytes of
each pair arrive the opposite way round.

Your `rbcp_config.s` says how the device sits on the host's bus:

- how wide the bus is
- how wide the device is
- which lanes the device is wired to
- which way round the bytes go

See [`rbcp/README.md`](rbcp/README.md) for more details.

## Requirements

| Tool | Purpose |
| --- | --- |
| [vasm](http://sun.hasenbraten.de/vasm/) `vasmm68k_mot` | the assembler |
| [One ROM](https://onerom.org) `onerom` | byte-swaps a built image into device order |

vasm ships as a source tarball. Build it with `make CPU=m68k SYNTAX=mot`.
