# ROM Bus Control Protocol (RBCP)

RBCP enables bidirectional communication between a host computer and an RBCP-capable ROM emulator using only the ROM address and data buses — no additional hardware required.

This allows a host system to query and modify the state of the emulated ROM installed within it, allowing a wide range of applications, including:

- Remote debugging of code running on real retro systems
- ROM based bootloaders (think `grub` for the C64)
- Dynamic ROM patching for games, demos and other applications

RBCP is supported by [One ROM](https://onerom.org), the most flexible replacement ROM for your retro systems.

## Contents

- [`spec/rbcp.md`](spec/rbcp.md) — The RBCP specification
- [`reference/host/`](reference/host/README.md) — Reference host implementations
  - [`6502/rbcp/`](reference/host/6502/rbcp/README.md) — Generic 6502 RBCP routines which can be used on any 6502 based system
  - [`6502/c64-boot/`](reference/host/6502/c64-boot/README.md) — A sample C64 kernal bootloader using RBCP
- [`reference/device/`](reference/device/README.md) — Reference device implementations (i.e. emulated ROMs supporting RBCP)

## Status

The specification version is indicated in the [RBCP specification](spec/rbcp.md).

The protocol and this repository are currently under active development.  It is expected that formally released versions of the specification will be made available using GitHub releases. 

## License

MIT — see [LICENSE](LICENSE).

The ROM Bus Control Protocol may be freely implemented without restriction.

## Contributing

Contributions to the specification and reference implementations are very welcome. Open an issue or submit a pull request.