# Running the meter without hardware

The Apple II bootloader comes with a fake RBCP device written in [MAME](https://mamedev.org)'s Lua, at [`../../apple2-boot/test/rbcp_dev.lua`](../../apple2-boot/test/rbcp_dev.lua). It watches every read in the ROM's address range, decodes the RBCP command stream out of the addresses, and answers by substituting bytes on reads of the back-channel region — which is what a device does. `run.sh` here points MAME at that same file with the meter in the socket instead of the bootloader.

The device it pretends to be answers every command the meter sends and gets none of them wrong, so a run left alone shows `1 IN -----` for as long as it goes. Making it get things wrong is what `RBCP_REFUSE` and `RBCP_DEAF` are for.

## Running

```bash
make test ROMS=/path/to/apple2/roms
```

or, from this directory, `./run.sh <rom-dir>`.

`<rom-dir>` holds the machine's ROM files, named as MAME names them. The unenhanced IIe table in [`../../apple2-boot/test/README.md`](../../apple2-boot/test/README.md) says which files and where they come from. Without them there is no character generator, so nothing on screen can be read as pixels. Rather than fill the gap with something made up and report a pass, `run.sh` names what is missing and stops.

Every run prints a checksum complaint from MAME about the ROM in the meter's socket. That file is the meter, so of course it does not match the dump MAME expects there.

## Settings

The fake device's own settings are in its README. The ones that matter here:

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_FRAMES` | 600 | Frame to print the text screen on and stop. |
| `RBCP_REFUSE` | unset | `GG:CC` — the command the device answers with failed, so the meter counts it wrong. `06:02` makes one command in four fail and the headline settle at `1 IN 4`. |
| `RBCP_DEAF` | unset | `GG:CC` — the command the device ignores entirely, so the token never moves. This is the failure the meter has to reset the device to get past, and it counts those as `LOST`. |
| `RBCP_DEBUG` | unset | Print every command byte the device sees. |

Pipe writes are printed as they arrive, four bytes at a time, so the report can be read.

## Examples

```bash
RBCP_FRAMES=300 ./run.sh ~/roms                    # count, and get nothing wrong
RBCP_REFUSE=06:02 RBCP_FRAMES=200 ./run.sh ~/roms  # one command in four refused
RBCP_DEAF=06:02 RBCP_FRAMES=200 ./run.sh ~/roms    # and the recovery from it
```
