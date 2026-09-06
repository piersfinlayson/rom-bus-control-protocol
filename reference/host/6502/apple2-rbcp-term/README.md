# Apple IIe RBCP Terminal

This has not been run on real hardware.

A ROM image for an Apple IIe that sends what you type down an RBCP pipe, so that it arrives in a terminal on the machine the device's USB is plugged into.

The device needs a pipe carrying bytes from the host to it. That is checked at startup and flagged on screen if it is missing.

## Controls

| Key | Action |
| --- | --- |
| `RETURN` | send the line |
| `DELETE` | rub out the last character |

A line holds 38 characters and the status bar shows what's left. A line scrolls up once it has been sent. If sending fails, the status bar indicates the error hit and the user must press `RETURN` to try again.

## The screen

```
 RBCP TERMINAL              PIERS.ROCKS
 One ROM v0.7.2              RBCP 0.1.2



















 HELLO FROM THE APPLE
>THE SECOND LINE
 READY                           23 LEFT
```

Lines that have been sent scroll up, so the newest is always directly above the one being typed.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `apple2_term.bin` | 8KB | EF, $E000 | $FE00 | $FFB0, 64 bytes |

II and II+ ROMs are 2KB. The terminal does not fit in two kilobytes so II/II+ ROMs as are provided. It would be possible to build a multi ROM image.

## Dependencies

- [cc65](https://cc65.github.io/)

## Building

```
make
```

## Testing

```
make test ROMS=/path/to/apple2/roms
```

builds the self-typing image and runs it on an emulated IIe against a fake RBCP device, printing what went down the pipe and the text screen at the end. `ROMS` is a directory holding the machine's own ROM files, named as MAME names them.

An example to get mame to type on the emulated Apple IIe:

```
RBCP_KEYS='HELLO FROM THE APPLE{Return}' test/run.sh /path/to/apple2/roms build/apple2_term.bin
```
