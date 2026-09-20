# Amiga Auxiliary I/O Tester Test Harness

A fake RBCP device written in [MAME](https://mamedev.org)'s Lua, so the real
binary can be run on an emulated Amiga 500 and driven from the keyboard.

`rbcp_dev_auxio.lua` watches every read in the Kickstart window, decodes the
RBCP command stream out of the addresses, and answers by substituting bytes on
reads of the back-channel region, as a real device does. It is the
[bootloader's device](../../amiga-boot/test/README.md) with the auxiliary board
from the [Apple II
harness](../../../6502/apple2-boot/test/rbcp_dev.lua) in it.

The device has four pin groups.

| Group | Pins | Drivable |
| --- | --- | --- |
| GPIO | 10 | the even pins from 2 up |
| image select | 4 | none |
| X pads | 2 | pad 0, wired to pad 1 |
| the ROM socket | 34 | none, and they move as the machine reads |

The socket group is the address and data lines the device serves the ROM
through, reported as GPIO because the protocol names no type for a bus. They
carry the last bus cycle the device saw, the way a real board's do. That puts
fifty pins on the all-pins page.

A pin's state survives `RBCP_RESET` and a `SET_AUX` asking for a hold is not
answered until the hold has elapsed.

Pipe writes are collected until the line feed that ends a line and printed
whole, so the tester's log is readable as it runs.

## Running

From this directory:

```bash
./run.sh <rom-dir>                    # the 256 KB build
RBCP_TARGET=512 ./run.sh <rom-dir>    # the 512 KB build
```

Build first. `make` writes `build/amiga_auxio.bin` and `make ROM_KB=512` writes
the same name, so `run.sh` checks the size on disk and names the `make` to run
when the wrong build is there.

`<rom-dir>` holds the A500 keyboard MCU dump under the name MAME gives it,
`6570-036`. Without it MAME will not start an `a500`. The
[bootloader harness](../../amiga-boot/test/README.md) says where the file comes
from and what its SHA1 is.

Every run prints a checksum complaint from MAME about the ROM in the Kickstart
socket. That file is the tester, so it does not match the dump MAME expects
there.

## A passing run

The tester draws to a bitmap, so the pipe log and the device's own tally are
all there is to read as text. Driving GPIO 2 high:

```
[dev] chip RAM $001000-$03FFFF dirtied with count
[dev] ENTER_CMD_RESP page=$01FF bch=$03FC00 size=512
[dev] GET_FLASH_SLOT_INFO_ALL 5 of 5
[pipe] RBCP AUX I/O START 0.1.0
[pipe] One ROM v0.7.2, 5 flash ROM slots, 2 RAM slots
[dev] GET_AUX_GROUP_INFO 0 = type $01, 10 pins
[dev] GET_AUX_GROUP_INFO 1 = type $80, 4 pins
[dev] GET_AUX_GROUP_INFO 2 = type $81, 2 pins
[dev] GET_AUX_GROUP_INFO 3 = type $01, 34 pins
[pipe] GROUP 0 TYPE 01 PINS 10 DRIVABLE 4
[pipe] GROUP 1 TYPE 80 PINS 4 DRIVABLE 0
[pipe] GROUP 2 TYPE 81 PINS 2 DRIVABLE 1
[pipe] GROUP 3 TYPE 01 PINS 34 DRIVABLE 0
[dev] key 'H' at frame 200
[dev] SET_AUX 0/2 high hold 0
[pipe] SET 0/2 HIGH TAKEN
[dev] 1586 commands, 0 failed, 0 lost
```

`RBCP_SNAP` saves the screen as a PNG, which is the only way to see the pins.

## Settings

These are the settings that reach this tester. The rest are the bootloader
harness's.

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_TARGET` | 256 | `256` runs the 27C200 build, `512` the 27C400 build. Both on an `a500`. |
| `RBCP_FRAMES` | 600 | Frame to stop the run on. |
| `RBCP_DIRTY` | `count` | The byte chip RAM is filled with before the application sets its variables up. `count` steps `$FF` down to `$01` and never writes a zero, a hex byte such as `FF` fills throughout, and `off` leaves chip RAM as MAME zeroes it. |
| `RBCP_KEYS` | unset | `frame:Key;frame:Key`, each key held for six frames. A key is named by its cap or by any legend on it — `H`, `Cursor Down`, `Enter`. |
| `RBCP_NO_AUX` | unset | Give the device no auxiliary pins, so `GET_AUX_CAPABILITY` reports a group count of zero and the tester stops on its own error screen. |
| `RBCP_RAM_SLOTS` | 2 | One leaves the device no spare slot to stage an image in, so the reset screen offers no choice and exits with `SET_AUX_AND_EXIT` instead of `SET_AUX_SWITCH_EXIT`. |
| `RBCP_AUX_MAX_HOLD` | 255 | The longest hold the device will time, in units of 10ms. A value under 20 is one the tester has to cut its reset pulse down to, and zero is one that cannot pulse a pin at all. |
| `RBCP_REFUSE` | unset | `GG:CC` — the command the device answers with failed. `05:03` refuses every `SET_AUX`. |
| `RBCP_SLOW_CMD` | unset | `GG:CC:reads` — the command the device is slow over, and how many reads of the progress byte the host spins through before it says complete. `05:02:60` makes `GET_AUX_PIN_INFO` take about 390µs longer than the rest. |
| `RBCP_SNAP` | unset | Save a screenshot at the end of the run, to `build/a500/0000.png`. MAME runs in a window when this is set. |
| `RBCP_DEBUG` | unset | Print every command byte the device sees. |

## Examples

Drive GPIO 2 high and photograph the pins:

```bash
RBCP_FRAMES=300 RBCP_KEYS='200:H' RBCP_SNAP=1 ./run.sh <rom-dir>
```

Move the cursor two pins along, drive that one, then page through to the
all-pins page:

```bash
RBCP_FRAMES=600 RBCP_KEYS='150:Cursor Down;220:Cursor Down;300:H;370:];430:];490:];550:]' \
    RBCP_SNAP=1 ./run.sh <rom-dir>
```

Take the reset screen and go through with it, which ends the run at the switch:

```bash
RBCP_FRAMES=420 RBCP_KEYS='150:R;260:Enter' ./run.sh <rom-dir>
```

Open the command timer with one command made slow. The device answers inside
the read that asks, so without that every command costs the same:

```bash
RBCP_SLOW_CMD=05:02:60 RBCP_FRAMES=330 RBCP_KEYS='200:T' RBCP_SNAP=1 ./run.sh <rom-dir>
```

A device with no pins at all, which is a legal device:

```bash
RBCP_NO_AUX=1 RBCP_FRAMES=260 RBCP_SNAP=1 ./run.sh <rom-dir>
```
