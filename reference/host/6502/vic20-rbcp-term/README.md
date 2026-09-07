# VIC-20 RBCP Terminal

A ROM image for a Commodore VIC-20 that sends what you type down an RBCP pipe, so that it arrives in a terminal on the machine the device's USB is plugged into. It runs on an unexpanded machine.

The device needs a pipe carrying bytes from the host to it. That is checked at startup and flagged on screen if it is missing.

## Controls

| Key | Action |
| --- | --- |
| `RETURN` | send the line |
| `INST/DEL` | rub out the last character |

A line holds 20 characters and the status bar shows what's left. A line scrolls up once it has been sent. If sending fails, the status bar indicates the error hit and the user must press `RETURN` to try again.

## The screen

```
RBCP TERM  PIERS.ROCKS
One ROM v0.7.2
RBCP 0.1.2

















 HELLO FROM THE VIC
>THE SECOND LINE
 READY        05 LEFT
```

Lines that have been sent scroll up, so the newest is always directly above the one being typed.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `vic20_term_pal.bin` | 8KB, 2364 | kernal | $E000 | $E100, 512 bytes |
| `vic20_term_ntsc.bin` | 8KB, 2364 | kernal | $E000 | $E100, 512 bytes |

## Dependencies

- [cc65](https://cc65.github.io/)

## Building

```
make
```

## Testing

Under VICE with no device fitted it draws its screen and stops at `NO DEVICE`:

```
xvic -default -kernal build/vic20_term_pal.bin
xvic -default -ntsc -kernal build/vic20_term_ntsc.bin
```

Anything past the screen needs a One ROM running the host-control plugin, and a terminal on the machine its USB is plugged into.

```
make selftest
```

builds `build/vic20_term_selftest.bin`, a PAL image that types a script of its own. Program a device with it, reset the machine, and read what arrives on the USB side.
