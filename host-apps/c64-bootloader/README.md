# C64 Bootloader

A kernal bootloader for the Commdore 64.

Allows you to switch, at boot time, beween all of the kernal ROMs installed on a One ROM or other RBCP capable ROM emulator fitted in the C64's kernal socket.

Auto-boots the last booted kernal (or the first kernal) if no key is pressed during power-on.  C=, RUN STOP and Q held down at power on all enter the menu, which lists all available kernal ROMs and allows you to select one with the cursor keys and boot it with RETURN.

This bootloader is compatible with cartridges such as Kung Fu Flash.

## Usage

Install the built binary as the first ROM image slot, followed by the kernal images you wish to switch between.

For example, using One ROM and the pre-built bootloader binary:

```
onerom program  --plugin usb --plugin host-control \
                --slot file=https://images.onerom.org/roms/host-control/v0.1.0/c64_bootloader.bin,type=2364,cs1=0 \
                --slot file=kernal1.bin,type=2364,cs1=0 \
                --slot file=kernal2.bin,type=2364,cs1=0
``` 

## Building

Requires ca65/cc65/ld65.

```bash
make
```

Creates `./c64_bootloader.bin`.

## License

Copyright (C) 2026 Holger Gryska <r107sl@web.de>

MIT License
