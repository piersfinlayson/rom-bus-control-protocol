# C64 RBCP Terminal

A ROM image for a Commodore 64 that sends what you type down an RBCP pipe, so that it arrives in a terminal on the machine the device's USB is plugged into.

The device needs a pipe carrying bytes from the host to it. That is checked at startup and flagged on screen if it is missing.

## Controls

| Key | Action |
| --- | --- |
| `RETURN` | send the line |
| `INST/DEL` | rub out the last character |

A line holds 38 characters and the status bar shows what's left. A line scolls up once it has been sent. If sending fails, the status bar indicates the error hit and the user must press `RETURN` to try again.

## The screen

```
 RBCP TERMINAL              PIERS.ROCKS
 One ROM v0.7.2              RBCP 0.1.2



















 HELLO FROM THE C64
 THE SECOND LINE
>THE THIRD LINE
 READY                           24 LEFT
```

Lines that have been sent scroll up, so the newest is always directly above the one being typed.

## Display blanking

The display goes off while a line is going out. Otherwise the VIC-II fetching characters takes the bus off the processor, and around that handover the device can misread a command frame.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `c64_term_kernal.bin` | 8KB, 2364 | kernal | $E000 | $E100, 512 bytes |
| `c64_term_basic.bin` | 8KB, 2364 | BASIC | $A000 | $A100, 512 bytes |
| `c64_term_combined.bin` | 16KB, 23128 | shared BASIC/kernal | $A000 | $A100, 512 bytes |

The kernal and BASIC images are for a longboard C64. Use one or the other. The BASIC image requires a stock kernal image.

The combined image is for a shortboard.

## Dependencies

- [cc65](https://cc65.github.io/)

## Building

```
make
```

## Testing

Under VICE with no device fitted it draws its screen and stops at `NO DEVICE ANSWERED THE KNOCK`:

```
x64sc -default -kernal build/c64_term_kernal.bin
x64sc -default -basic build/c64_term_basic.bin
```

The 16KB image is two 8KB halves, and VICE takes them one socket at a time:

```
dd if=build/c64_term_combined.bin of=basic.bin bs=8192 count=1
dd if=build/c64_term_combined.bin of=kernal.bin bs=8192 skip=1 count=1
x64sc -default -basic basic.bin -kernal kernal.bin
```

Anything past the screen needs a One ROM running the host-control plugin, and a terminal on the machine its USB is plugged into.

```
make selftest
```

builds `build/c64_term_selftest.bin`, a BASIC socket image that types a script of its own. Program a device with it, reset the machine, and read what arrives on the USB side.
