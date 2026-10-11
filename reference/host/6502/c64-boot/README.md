# C64 RBCP Kernal Bootloader

A custom Commodore 64 kernal ROM image that acts as an RBCP-aware bootloader, allowing the user to select and boot from multiple kernal ROM images stored on a One ROM, or other RBCP capable ROM emulator, fitted in the C64's kernal socket.

This is designed to be a reference implementation of an RBCP host on a real 6502-based system.  Other, better, implementations are hoped to supercede this.

## What it does

On reset the bootloader checks whether the **Commodore (C=) key** is held:

**C= not held — auto-boot**
Loads flash slot 1 into the inactive RAM slot, switches to it, and jumps through the new kernal's reset vector. No user interaction required.

**C= held — menu**
Presents a selection menu listing all available kernal images (flash slots 1 and above). Use **CRSR UP/DOWN** to move and **RETURN** to boot the highlighted entry. Flash slot 0 (the bootloader itself) is never shown.

On any RBCP error the bootloader displays a [report](#errors) and halts. Power-cycle to recover.

Either path sends `SWITCHING TO SLOT $XX` out through the device on pipe 0 immediately before switching, naming the flash slot being booted. Where the device has a pipe, that line reaches whatever the device has at the far end — on a One ROM, a terminal on its USB serial port. It is sent last because the switch ends the command-response session, and the image that follows need not have a back-channel at all.

A device with no pipe, or one whose protocol version predates the Pipes group, is left to boot exactly as before: the bootloader asks once with `GET_PIPE_CAPABILITY` and sends nothing if the answer is no. A pipe that will not take the line is not retried and does not stop the boot.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `c64_boot.bin` | 8KB, 2364 | kernal | $E000 | $E100, 512 bytes |
| `c64_boot_combined.bin` | 16KB, 23128 | shared BASIC/kernal | $A000 | $A100, 512 bytes |

The kernal image is for a longboard C64. The combined image is for a shortboard.

## Display blanking

The display goes off while the bootloader is talking to the device due to a C64 limitation.

## Errors

If the bootloader hits an error it displays a report of every command it sent and the response. It also sends the report out of the device's pipe (via USB logging on a One ROM)

To collect the log:

1. Program the One ROM with the `usb` plugin. On a longboard:

   ```bash
   onerom program --plugin usb --plugin host-control --slot file=c64_boot.bin,type=2364,cs1=active-low --slot file=kernal.bin,type=2364,cs1=active-low
   ```

   On a shortboard:

   ```bash
   onerom program --plugin usb --plugin host-control --slot file=c64_boot_combined.bin,type=23128,cs1=active-low,cs2=active-low,cs3=active-high --slot file=basic_kernal.bin,type=23128,cs1=active-low,cs2=active-low,cs3=active-high
   ```

2. Connect the One ROM's USB to a PC, turn the C64 on and reproduce the failure.
3. When `CAPTURE DIAGS THEN PRESS RETURN` appears, run:

   ```bash
   onerom inspect peek memory --address 0x20081c00 --length 512 --output ring.bin
   ```

4. Press RETURN.
5. Photograph the screen.
6. Before turning the C64 off, run `onerom monitor log --output rbcp.txt`. Stop it with Ctrl-C after the line `END`.
7. Raise a github issue and provide:
   - the photo
   - `ring.bin`
   - `rbcp.txt`
   - your One ROM board type
   - your C64 model and PCB assembly number

If retrying the test, make sure One ROM is rebooted between tests.  The easiest way to do this is unplugging One ROM from USB when powering off/on the C64.  Another option is running the following before resetting the C64:

```bash
onerom control reboot
```

## Dependencies

- [cc65](https://cc65.github.io/) — provides `ca65` (assembler) and `ld65` (linker).

On Debian/Ubuntu:

```bash
sudo apt install cc65
```

On macOS with Homebrew:

```zsh
brew install cc65
```

## Building

```bash
make
```

Output: `build/c64_boot.bin` and `build/c64_boot_combined.bin`, ready to flash as slot 0 on a One ROM or other RBCP capable ROM emulator.

To clean:

```bash
make clean
```

## Testing

```bash
make test ROMS=<rom-dir>
make test ROMS=<rom-dir> TARGET=combined
```

runs an image under MAME against the emulated device in [`test/`](test/README.md).

## Debugging

When running against a One ROM with logging enabled, the bootloader will assume that One ROM has switched to a new slot before it has actually done so.  To work around this, build the bootloader with `PAUSE_BEFORE_RESET=1`:

```bash
PAUSE_BEFORE_RESET=1 make
```
