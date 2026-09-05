# C64 RBCP Reliability Meter

A ROM image for a Commodore 64 that measures how reliably a One ROM answers RBCP commands. It runs a fixed set of commands in a loop and shows the failure rate as a ratio.

## Purpose

Every command the meter sends is one the device should answer, so a failure is never a result — it is the measurement. The figure is for comparison: the same device gives different answers in two C64s, a VIC-20 and an Apple IIe, and the useful question is how different and why. Quote the number with the machine it came from.

## The screen

```
 RBCP RELIABILITY METER     PIERS.ROCKS

 ONE ROM
 V0.7.2
 RBCP 0.1.2
 REPORTING ON PIPE 00

 ON 1 IN 2946        OFF 1 IN -----

 SENT    3396123    ERR       1000
                   LOST         17

 COMMAND            SENT           ERROR
 NOP              849030             250
 PROTO VER        849031             249
 LED INFO         849031             251
 LED MODE         849031             250

> ON  SENT    2946123     ERR       1000
  OFF SENT     450000     ERR          0


 PRESS S TO SWITCH THE SCREEN
```

The highlighted band is the answer, with a figure for each state of the display, because one figure covering both would say how long the run spent in each rather than anything about the machine. Either half reads `-----` until the first failure at that setting. `LOST` counts the commands the device never answered at all, and is part of the error count above it rather than an addition to it.

The per-command table separates a fault reaching every command from one confined to a single group. The pair at the bottom gives each display state its own counts, sent as well as error: without the sent count, a state that has come through half a million commands untouched reads exactly like one that was never tried.

## Commands

| Command | Frame | Arguments |
| --- | --- | --- |
| NOP | `00 00` | none |
| GET_PROTOCOL_VERSION | `01 06` | none |
| GET_LED_INFO | `06 01 00` | LED 0 |
| GET_LED_MODE_INFO | `06 02 00 00` | mode 0 of LED 0 |

Four frames of three different lengths made of different bytes, so a fault in how the device takes bytes off the bus should reach all four and mangle each differently, where one confined to a single group shows in a single row. LED 0 and mode 0 exist on any device with LEDs, and a device with no LEDs fails both LED commands every time.

`CONFIG_RBCP_TIMEOUT_RETRIES` is zero, a retry being able to hide what this exists to count.

## The display

The VIC-II takes cycles from the processor. Every eighth raster line in the display window is a badline, where it halts the 6510 for forty cycles or more to fetch a row of characters. Blanking the display stops all of it, and as far as the device is concerned the two cases are different machines, so `S` switches between them and the counts are kept apart for the whole run. The meter never switches the display itself, the number having to stay readable.

## Loop padding

Before each command the loop wastes between nought and fifteen cycles, the count coming off a shift register rather than off anything to do with the picture. Without it every pass takes the same time, its commands land at the same points against the video, and the run measures one alignment out of the many the machine has — whichever the build happened to compile to. Lengthening a line of the log once moved the figure from 1 in 431 to 1 in 910 and changed nothing else. With the padding each phase samples many alignments, so a short run is worth reading.

## The failure record

```
THE DEVICE REFUSED THE COMMAND
SENT 06 01 00 00 00   TOK 1B
GOT  06 06   TOK 1C  PRG BB  RSP 33
```

The first line is which of the three ways it went wrong: the device did not take the command, took it and never finished, or refused it. `SENT` is the frame that went out with the token the host read before sending, and `GOT` is the response header as the device had written it when the host gave up. Read together they are the diagnosis, a `GOT` row naming a command other than the one on the `SENT` row being a frame the device did not receive as it was sent.

## Recovery

A failure the device answered leaves the session in step, because the device discards the rest of the frame before reporting completion. The meter counts it and carries on.

A failure the device did not answer is different, since a frame that slipped by a byte onto a command taking arguments leaves the device waiting for arguments that will never come. `rbcp_reset` exists for exactly that, flushing a partially received command of up to nine argument bytes and two framing bytes. The meter resets the device, enters command-response mode again and continues, counting these as `LOST`. Three resets without an answer end the run.

## The pipe report

The screen is the headline rather than the history, and a machine left running overnight has a history worth keeping. Where the device offers a host-to-device pipe, every failure and a line every 8192 commands go out of it as plain text.

```
RBCP METER START
FAIL 03 SCREEN ON LED INFO SENT 06 01 00 00 00 TOK 1B GOT 06 06 1C BB33 RUN SENT 8193 ERR 3
PH 0000 SCREEN ON SENT 6103 ERR 3 1 IN 2034 OFF SENT 2090 ERR 0 RUN LOST 1
RECOVERED
```

Every count belongs to whatever the line named last, `SCREEN ON` and `SCREEN OFF` making the counts after them that state's and `RUN` making them the whole run's. A phase line carries each state separately, since pressing `S` partway through a phase would otherwise leave a line naming one state and counting both. A VIC-20 or an Apple IIe varies nothing, so its lines carry one set of figures and name no state.

Lines go out four bytes to a PIPE_WRITE, and one the device will not take after four goes is abandoned, leaving a short line where the next line's leading newline falls. `RECOVERED` follows a failure the device did not answer once the session is open again, and `RECOVER FAILED` ends the run. Phase lines are the heartbeat as well as the result, so a run that has stopped saying them has stopped.

Pipe writes are RBCP commands down the same path as the ones being counted, so none of them is counted. Where the device has no such pipe the screen says so and the run is read off the display.

## Images

| Image | Size | Socket | Command page | Back channel |
| --- | --- | --- | --- | --- |
| `c64_meter_kernal.bin` | 8KB, 2364 | kernal, $E000-$FFFF | $E000 | $E100, 512 bytes |
| `c64_meter_basic.bin` | 8KB, 2364 | BASIC, $A000-$BFFF | $A000 | $A100, 512 bytes |
| `c64_meter_combined.bin` | 16KB, 23128 | BASIC and kernal both | $A000 | $A100, 512 bytes |

The kernal image is the ordinary one. The BASIC image is the same program in the other socket, entered the way BASIC is, through the word at $A000, which holds the meter's entry point rather than BASIC's — the two sockets differ electrically, and running one program in each attributes a difference to the socket rather than to the program. The combined image spans both, its first half blank but for the command page and the back channel, so the half the machine boots out of is never written to.

Everything the meter runs is copied to RAM at $0800 before the first knock, so no instruction is ever fetched out of the image the device is serving.

## Building

Needs cc65.

```
make
```

## Testing

Every figure this program reports comes from a device, so there is no demo build. Under VICE with no device fitted it draws its screen and stops at `NO DEVICE ANSWERED THE KNOCK`:

```
x64sc -default -kernal build/c64_meter_kernal.bin
x64sc -default -basic build/c64_meter_basic.bin
```

The 16KB image is two 8KB halves, and VICE takes them one socket at a time:

```
dd if=build/c64_meter_combined.bin of=basic.bin bs=8192 count=1
dd if=build/c64_meter_combined.bin of=kernal.bin bs=8192 skip=1 count=1
x64sc -default -basic basic.bin -kernal kernal.bin
```

That covers the screen and the refusal path. The rest needs a One ROM in the socket running the host-control plugin, and a USB host reading the log channel for the pipe report.
