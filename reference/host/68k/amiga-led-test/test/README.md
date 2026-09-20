# Amiga LED Tester Test Harness

Runs the built tester on an emulated Amiga 500 against a fake RBCP device with
LEDs, so a session can be driven without hardware. It needs
[MAME](https://mamedev.org) and the A500 keyboard MCU dump.

`rbcp_dev_led.lua` watches every read in the Kickstart window, decodes the RBCP
command stream out of the addresses, and answers by substituting bytes on reads
of the back-channel region, as a real device does. It implements the commands
the tester calls and nothing else. The bootloader's device in
[`../../amiga-boot/test/`](../../amiga-boot/test/README.md) answers the LED
group from a fixed table, which is enough to be asked a question and not enough
to be driven.

LED 0 is a monochrome green status LED with three modes and the rest are RGB
with all six. That is the shape of a One ROM. `RBCP_LEDS` takes the first few
of them, so one monochrome LED, no LEDs and more LEDs than the screen holds are
each one setting.

`SET_LED` is applied the way the protocol says it should be. A monochrome LED
keeps its own colour, three zeroes leave the colour to the device, a brightness
of zero leaves that to the device too, and a mode that takes no period reports
none. A command naming a mode the LED does not have, a brightness over 100, a
hold over the maximum or a period outside the range `GET_LED_MODE_INFO` reports
is refused. A mode given a hold runs for that long and the device then puts
back what was in force when the command arrived.

`RBCP_LED_LIES` makes LED 0 report a brightness of 100 whatever it is given.
The read back check is what catches it.

## Running

From this directory:

```bash
./run.sh <rom-dir>                    # the 256 KB build
RBCP_TARGET=512 ./run.sh <rom-dir>    # the 512 KB build
```

Build the image first. `make` writes `build/amiga_led_test.bin` and
`make ROM_KB=512` writes the same name, so `run.sh` checks the size on disk and
says which `make` to run when the wrong build is there.

`<rom-dir>` holds the A500 keyboard MCU dump under the name MAME gives it,
`6570-036`. Without it MAME will not start an `a500`. Nothing else is needed:
the tester never switches slots, so there is no Kickstart to hand over to.

Every run prints a checksum complaint from MAME about the ROM in the Kickstart
socket. That file is the tester, so it does not match the dump MAME expects
there.

## A passing run

The tester draws to a bitmap, so there is nothing to print as text. The run
leaves the tester's own report down the pipe and the device's account of what
it was asked:

```
[dev] chip RAM $001000-$03FFFF dirtied with count
[dev] RESET
…
[dev] ENTER_CMD_RESP page=$01FF bch=$03FC00 size=512
[pipe] RBCP LED TESTER START 0.1.0
[dev] GET_LED_CAPABILITY 2 LEDs, max period 100, max hold 100
[pipe] LEDS 2 MAX PERIOD 100 MAX HOLD 100
[dev] GET_LED_MODE_INFO led 0 off takes period false
[pipe] LED 0 TYPE 0 MODES 07
[pipe] LED 1 TYPE 1 MODES 3F
[dev] key 'M' at frame 240
[dev] GET_LED_MODE_INFO led 0 on takes period false
[dev] SET_LED 0 on rgb 56AC4D bri 100 per 0 hold 0
[pipe] SET 0 MODE 01 COL 000000 BRI 0 PER 0 HOLD 0
[pipe] GOT 0 MODE 01 COL 56AC4D BRI 100 PER 0 AGREES
…
[dev] 1941 commands
[dev] LED 0 finished on rgb 56AC4D bri 25 per 0
[dev] LED 1 finished on rgb 75CEC8 bri 100 per 0
```

`SET` is what the host staged and `GOT` is what the device reported afterwards.
The two lines are the whole of the read back check.

The lamps are pens, so a screenshot is the only way to see them.

## Settings

Everything is an environment variable:

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_TARGET` | 256 | `256` runs the 27C200 build, `512` the 27C400 build. Both on an `a500`. |
| `RBCP_FRAMES` | 900 | Frame to stop the run on. |
| `RBCP_DIRTY` | `count` | The byte chip RAM is filled with before the application sets its variables up. `count` steps `$FF` down to `$01`, a hex byte such as `FF` fills with that byte throughout, and `off` leaves chip RAM as MAME zeroes it. |
| `RBCP_KEYS` | `240:M;300:C;360:B;420:P;480:H;540:Cursor Down;600:M` | `frame:Key;frame:Key`, each key held for six frames. A key is named by its cap or by any legend on it — `M`, `Cursor Down`, `Enter`. |
| `RBCP_LEDS` | 2 | How many LEDs the device has. 0 gives a device with none, and more than six exercises the LEDs the screen cannot show. |
| `RBCP_MAX_PERIOD` | 100 | The largest period the device accepts, in 100ms units. 0 makes it accept none, so every mode reports that it takes none. |
| `RBCP_MAX_HOLD` | 100 | The largest hold the device times, in 100ms units. 0 makes it time none. |
| `RBCP_NO_LED_GROUP` | unset | Fail every command in the LED group, which is how a device whose protocol version predates the group answers. |
| `RBCP_LED_LIES` | unset | LED 0 reports a brightness of 100 whatever it is given. |
| `RBCP_SNAP` | unset | Save a screenshot at the end of the run, to `build/a500/0000.png`. MAME runs in a window when this is set. |
| `RBCP_DEBUG` | unset | Print every command byte the device sees. |

## Examples

The parade, from a device with two LEDs, photographed part way through:

```bash
RBCP_KEYS='200:A' RBCP_FRAMES=1200 RBCP_SNAP=1 ./run.sh <rom-dir>
```

A device with more LEDs than the screen holds, and one of them reporting a
brightness of its own:

```bash
RBCP_LEDS=8 RBCP_LED_LIES=1 RBCP_KEYS='240:B' RBCP_FRAMES=340 RBCP_SNAP=1 \
    ./run.sh <rom-dir>
```

A device with no LEDs at all:

```bash
RBCP_LEDS=0 RBCP_FRAMES=260 RBCP_SNAP=1 ./run.sh <rom-dir>
```

## The ROM files

| Save as | Contents | SHA1 |
|---------|------------|------|
| `6570-036` | the A500 keyboard MCU, 2048 bytes | `83b21d0c8b93fc9b9b3b287fde4ec8f3badac5a2` |

It is a real dump nothing can stand in for. MAME looks for it in `a500kbd_us`,
`a2000kbd_us` and `a500`, and without it says `Required files are missing, the
machine cannot be run`. It comes with a MAME ROM set for the Amiga 500.
