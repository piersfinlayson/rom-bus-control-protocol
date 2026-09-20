# Amiga Meter Test Harness

Runs the built meter on an emulated Amiga 500 against the fake RBCP device in
[`../../amiga-boot/test/`](../../amiga-boot/test/README.md). Both
applications drive the same device, and that README covers the commands the
device implements and the ROM files MAME needs.

## Running

From this directory:

```bash
./run.sh <rom-dir>                    # the 256 KB build
RBCP_TARGET=512 ./run.sh <rom-dir>    # the 512 KB build
```

Build the image first. `make` writes `build/amiga_meter.bin` and
`make ROM_KB=512` writes the same name, so `run.sh` checks the size on disk
and says which `make` to run when the wrong build is there.

`<rom-dir>` holds the A500 keyboard MCU dump under the name MAME gives it,
`6570-036`. Without it MAME will not start an `a500`. Nothing else is
needed: the meter never switches slots, so there is no Kickstart to hand over
to.

Every run prints a checksum complaint from MAME about the ROM in the Kickstart
socket. That file is the meter, so it does not match the dump MAME expects
there.

## A passing run

The meter draws to a bitmap, so there is nothing to print as text. The log is
the pipe report and the device's own count of the commands it answered:

```
[dev] chip RAM $001000-$03FFFF dirtied with count
[dev] ENTER_CMD_RESP page=$01FF bch=$03FC00 size=512
[pipe] RBCP METER START 0.1.0
[pipe] PH 0000 DISPLAY ON SENT 8192 ERR 0 OFF SENT 0 ERR 0 RUN LOST 0
[pipe] PH 0001 DISPLAY ON SENT 16384 ERR 0 OFF SENT 0 ERR 0 RUN LOST 0
[dev] key 'S' at frame 300
[pipe] PH 0002 DISPLAY ON SENT 21559 ERR 0 OFF SENT 3017 ERR 0 RUN LOST 0
[pipe] PH 0003 DISPLAY ON SENT 21559 ERR 0 OFF SENT 11209 ERR 0 RUN LOST 0
[pipe] PH 0004 DISPLAY ON SENT 21559 ERR 0 OFF SENT 19401 ERR 0 RUN LOST 0
[dev] 43837 commands, 0 failed, 0 lost
```

The device answers everything here, so the errors are zero and the run proves
only that both states of chip DMA were counted.

The last line is the device's own tally, and the meter's counts have to agree
with it.

## Settings

The fake device's own settings are in its README. These are the ones a run
here uses.

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_TARGET` | 256 | `256` runs the 27C200 build, `512` the 27C400 build. Both on an `a500`. |
| `RBCP_FRAMES` | 600 | Frame to stop the run on. The meter sends about sixty commands a frame, so a phase of 8192 commands takes about 140 frames. |
| `RBCP_DIRTY` | `count` | The byte chip RAM is filled with before the application sets its variables up. `count` steps `$FF` down to `$01`, a hex byte such as `FF` fills with that byte throughout, and `off` leaves chip RAM as MAME zeroes it. |
| `RBCP_FAIL_EVERY` | unset | One command in this many answered with failure, which the meter counts as an error. |
| `RBCP_LOSE_EVERY` | unset | One command in this many not answered at all, which the meter counts as lost and recovers from. |
| `RBCP_KEYS` | `300:S` | `frame:Key;frame:Key`. A key is named by any legend on its cap. `S` is the only key the meter reads, and the default press is what splits the counters. |
| `RBCP_SNAP` | unset | Save a screenshot at the end of the run, to `build/a500/0000.png`. MAME runs in a window when this is set. |

## Examples

Nine hundred frames with a device that gets one command in a thousand wrong:

```bash
RBCP_FRAMES=900 RBCP_FAIL_EVERY=1000 ./run.sh <rom-dir>
```

Switch chip DMA off at frame 200 and back on at 400, and screenshot the
result:

```bash
RBCP_FRAMES=520 RBCP_FAIL_EVERY=900 RBCP_KEYS='200:S;400:S' RBCP_SNAP=1 \
    ./run.sh <rom-dir>
```
