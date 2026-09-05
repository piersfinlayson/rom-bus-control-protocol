# C64 Bootloader

A kernal bootloader for the Commdore 64.

Allows you to switch, at boot time, beween all of the kernal ROMs installed on a One ROM or other RBCP capable ROM emulator fitted in the C64's kernal socket.

Auto-boots the last booted kernal (or the first kernal) if no key is pressed during power-on.  C=, RUN STOP and Q held down at power on all enter the menu, which lists all available kernal ROMs and allows you to select one with the cursor keys and boot it with RETURN.

This bootloader is compatible with cartridges such as Kung Fu Flash.

## Pre-built Binaries

An 8KB kernal ROM, and a 16KB image holding basic and the kernal together for
a C64C.

https://images.onerom.org/roms/host-control/c64-bootloader/latest/c64_bootloader.bin

https://images.onerom.org/roms/host-control/c64-bootloader/latest/c64_bootloader_c64c.bin

## Source Code

The published images are built from a fork, which adds the C64C target:

https://github.com/piersfinlayson/c64-bootloader

Upstream, and where the bootloader comes from:

https://github.com/r107sl/c64-bootloader

## Usage

Install the built binary as the first ROM image slot, followed by the kernal images you wish to switch between.

For example, using One ROM and the pre-built bootloader binary:

```
onerom program  --plugin usb --plugin host-control \
                --slot file=https://images.onerom.org/roms/host-control/c64-bootloader/latest/c64_bootloader.bin,type=2364,cs1=0 \
                --slot file=kernal1.bin,type=2364,cs1=0 \
                --slot file=kernal2.bin,type=2364,cs1=0
``` 

## Building

Requires ca65/cc65/ld65.

```bash
git clone https://github.com/piersfinlayson/c64-bootloader
cd c64-bootloader
make
make TARGET=c64c
```

The default target creates `./c64_bootloader.bin`, the 8KB kernal ROM.
`TARGET=c64c` creates `./c64_bootloader_c64c.bin`, the 16KB image with basic
in the lower half and the kernal in the upper.

## License

Copyright (C) 2026 Holger Gryska <r107sl@web.de>

MIT License
