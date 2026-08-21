# RBCP LED Tester

Drives a device's LEDs from a Commodore 64, and shows on screen what each one should be doing.

---

**Untested on hardware.**

**Breadbin C64 only.** The device replaces the 8 KB BASIC ROM, a 2364 serving $A000–$BFFF.

## The screen is the statement

An LED is a disc, in the colour the device says it is showing, filled as brightly as the device says it is lit, with the mode written inside it. Two of them side by side, in the order the device numbers them. The one under the cursor is bracketed.

That is the whole design. You look at the screen, you look at the board, and they either agree or they do not.

Everything drawn comes from `GET_LED_INFO` and never from what the host asked for, so a device that ignores a colour or clamps a brightness shows up as itself.

The keys that pick a thing are drawn next to the thing they pick: `F1` and `F3` under the two LEDs, and the mode numbers under the modes, shown only for the modes that LED actually has. Cursor left and right also walk between LEDs, and up and down step the colour of the one under the cursor, shift reversing as it does everywhere else on a C64.

The rest are on the bottom three rows: `C` opens the colour list, `B` steps the brightness, `P` the period and `H` the hold. `SPACE` runs a parade, `A` shows every byte the device reported, `Q` quits.

## Nothing can prove an LED lit

`GET_LED_INFO` answers out of the same place `SET_LED` wrote to. A dead LED, a wrong pin and a working one all read back identically, so no amount of reading proves anything about the world. The witness has to be an eye or a camera.

What the program can do is make that eye's job easy, which is what the words inside the disc are for, and check that the device agrees with itself. After every `SET_LED` it reads every LED back and compares, field by field, against what it asked for — and only for the fields it named, since a brightness of zero, a period of zero and a colour of three zeroes all mean the device chooses. The result is one line: **read back agrees**, **read back differs**, or **the device refused that set LED**. `A` has the numbers.

`SPACE` steps every mode the LED reports, holding each long enough to see and naming it inside the disc as it goes. That is the one thing here that is about the world outside the device: one continuous thing to point a camera at, with the answer written beside it.

## The disc

The ROM character set has four diagonals and nothing else that curves, so a disc built out of it is an octagon. The VIC can take its characters from RAM instead, so the program builds a set of its own at $3000: the ROM's text characters, their inverses for reverse video, and an ellipse thirteen cells across and eleven down, sampled per pixel. That is 104 by 88 pixels of circle, and it is round because the C64's pixels are taller than they are wide.

`tools/gen_disc.py` works the characters out and writes `src/disc_glyphs.s`. The output is committed, so a build needs only cc65; `make glyphs` regenerates it.

## What it does, as it does it

A blink blinks, a breathe fades, a cycle turns through the hues, a beacon flashes twice and waits. The device says which mode each LED is in and how long one repetition takes, which is enough to draw the same thing here, on the C64's own clock, timed off a CIA counter.

The two clocks are not synchronised and cannot be. That is not what this is for: the point is that the board and the screen are both worth looking at, doing the same thing at the same time.

A disc is redrawn only when what it should look like has changed, and the redraw waits for the beam to reach the lower border first. Without either, a screen whose whole job is to be looked at would flicker and tear.

## Colour

The colour list is the C64's own fifteen, and picking one sends that colour's real RGB triple. So the disc on the screen and the LED on the board are the same number rather than approximations of each other, which is what makes a side by side comparison mean anything. The values are VICE's, which is as close to a real machine as this gets without measuring one.

Black is not offered. The specification is explicit that whether an LED is lit is carried by its mode, so a colour being set is always one meant to be seen.

An LED whose colour the device chose, or that reports none, is drawn grey and says **DEVICE**. A colour that is not one of the fifteen — a device's own choice, or a monochrome LED's fixed colour — is drawn as the nearest of them and named as that. It is a disc and a word that come out of it, not a match.

## Brightness

A C64 character cell has one colour and no brightness. Below full, the disc is the same ellipse ANDed with a halftone — a chequerboard at half, one pixel in four below that — so dimming changes how densely it is filled and never its shape. At full it uses the colour's brighter partner where it has one, which gives four steps up from dark and is what a breathe fades through.

An LED whose mode is Off is drawn as a dark grey disc rather than as nothing, because that is what an unlit LED looks like sitting on a board: a grey lens where a lit one was.

An LED that is dark for an instant of a blink or a breathe is not that. It has gone out, and the way to draw gone out is for there to be nothing there, so those steps are black. A breathe that bottomed out at grey looked like it had hit a floor.

## What the keys will and will not send

A mode the LED does not report is refused before it is sent, and so is a colour on an LED that has none, a period on a mode that takes none, and a hold on a device that times none. The device reported all of that, and this is what those reports are for. Anything that does reach the device and is refused shows up on the read back line.

Brightness, period and hold each step a short list rather than taking a typed number. A C64 keyboard is a bad way to type a number and a bad number is worth nothing here — what these are for is putting an LED somewhere a camera can see. Each list starts at the entry that leaves the choice to the device.

## Leaving the ROM as it was found

Every command writes the response header, and the header lives in the active RAM slot, so the served BASIC is dirty from the first command onwards. Repairing it is impossible — the write that would repair it is itself a command.

So the program takes a Fletcher-16 of $A000–$BFFF before it knocks, then looks for a flash slot holding exactly that, loads it into a spare RAM slot and reads it back with `SLOT_PEEK` to be sure. `Q` switches to that slot on the way out: it has never held a back channel, and `SWITCH_AND_EXIT` writes no header. Without such a slot there is no clean way out, and the program says so and refuses to start rather than leaving you with a broken BASIC.

This is [`../common/rbcp_session.s`](../common/rbcp_session.s), shared with the auxiliary I/O tester.

## Building

Needs [cc65](https://cc65.github.io/), and `c1541` from [VICE](https://vice-emu.sourceforge.io/) for the disk image. `c1541` is inside the VICE bundle, not on a stock macOS PATH.

```bash
make C1541=/Applications/vice-arm64-gtk3-3.9/bin/c1541
```

## The demo build

`make demo` builds `rbcp_led_demo.prg`, which answers its own questions instead of asking a device. It exists so that every screen can be looked at under an emulator, where there is no device and nothing past the knock can run. It is a separate binary and none of it is linked into the one that talks to hardware.

`BOARD` picks which imaginary device it describes:

| BOARD | What it describes |
|-------|-------------------|
| `0` | A monochrome green status LED and an RGB one, on a device that can time both a period and a hold. |
| `1` | One RGB LED, on a device that accepts neither a period nor a hold. |
| `2` | No LEDs at all. |
| `3` | Three LEDs, one more than this shows, and LED 0 reports a brightness of its own whatever it is given. |

`SCRIPT` puts the program into one named state at startup by calling the same dispatch the keyboard calls, so a screen can be captured without anything to press the keys.

| SCRIPT | The screen it reaches |
|--------|-----------------------|
| `1` | An RGB LED lit, in a colour it was given. |
| `2` | Breathing, at half brightness, with a period. |
| `3` | The colour list. |
| `4` | Every byte the device reported. |
| `5` | A mode this LED does not have, refused. |
| `6` | A parade, run to the end. |
| `7` | Half brightness on the first LED — dithered, and on board 3 the read back catching the device out. |
| `8` | A hold on a device that times none. |
| `9` | A beacon, which is the fastest thing here to move. |

```bash
make BOARD=0 SCRIPT=2 demo
x64sc -warp -limitcycles 90000000 -exitscreenshot shot.png -autostart build/rbcp_led_demo.prg
```

`-keybuf` cannot reach this program: it reads the keyboard matrix directly with interrupts masked, so nothing the kernal buffers is ever seen. `SCRIPT` is the way in.

## Other ROM types

A flash slot is only a candidate for the clean exit if it reports the type in `rbcp_config.s`, and the served image is assumed to be the 8 KB at $A000–$BFFF. For another 8-bit ROM, a 23128 combined BASIC+KERNAL say:

- `rbcp_config.s`: `CONFIG_ROM_SIZE` to the image size, and `CONFIG_ROM_TYPE` to that type's code from the spec.
- `../common/rbcp_session.s`: `checksum_image` walks up from `CONFIG_ROM_BASE_HI`. A 16 KB image is not contiguous — $A000–$BFFF then $E000–$FFFF — so it must walk both halves in image order.

## Limits

Two LEDs, each big enough to say inside itself what it is doing. That is what a One ROM has — one status LED and one RGB — and a third disc of this size does not fit across 40 columns. A device reporting more is shown as its first two and says so on screen rather than truncating quietly.

Modes above `0x05` are shown by number rather than by name, and are drawn still: there is nothing to animate without knowing what the mode does. `SET_LED` is never sent with one — a host issuing a mode the protocol does not define is doing so without discovery, which this program has no way to offer.

The character set is 256 characters and the text and its inverses take half of them, which is what fixes the disc at three brightness levels rather than four.

The animation is timed off CIA2 Timer B against PAL phi2. On an NTSC machine every step is about 1.7% short, which nothing here measures and no eye can see.
