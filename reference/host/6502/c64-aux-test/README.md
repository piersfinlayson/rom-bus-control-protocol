# RBCP Auxiliary I/O Tester

Drives and reads a device's auxiliary pins from a Commodore 64, and shows every pin of every group on screen as it happens.

A pin is a ring. Filled means the level is high, hollow means low. The colour says who owns the pin: **green** the C64 is driving it, **white** it is free and only being read, **grey** the ROM is using it and it is not ours to touch. Ring size comes from how many drivable pins the group has, so a group of two fills the screen and a group of forty still fits.

Keys: cursor left and right move between pins, up and down between groups, shift reverses as it does everywhere else on a C64. `L` `H` `Z` drive the pin low, high or release it. `B` blinks it, `T` runs a move test, `A` shows every pin including the ones the ROM owns, `R` resets the C64, `Q` quits.

---

**Breadbin C64 only.** The device replaces the 8 KB BASIC ROM, a 2364 serving $A000–$BFFF.

## The move test

`T` drives the cursor pin low, then high, then releases it, scanning every pin at each step, and reports whether any *other* pin moved with it.

That question is the point. Reading back the pin just driven proves nothing: the answer comes from the same place the drive went, so a dead pad, a dry joint and a signal that never leaves the die all read back perfectly. A pin the device is not driving is an input, and only follows if the signal crossed a wire and came back.

So the test needs a wire: two drivable pins joined, with a 10k pull-up on the net, because the device pins are high impedance as inputs and pull nothing themselves. With that fitted, drive low reads 0 and drive high reads 1, and both drive directions are proven. Release also reads 1 and cannot be told from high by this route — its only witness is the `driven` byte the device reports.

## Wiring

Auxiliary pins are whatever the device exposes and the protocol says nothing about what is attached to one, so the choice is yours and the consequences are too. On One ROM:

- **An LED** on any drivable pin, through a resistor to ground. This is the one a camera can see.
- **The loopback pair** as above.
- **The C64 reset line**, which must go to a 5V tolerant pin — SEL C, SEL D or an X pad. `R` drives it low, holds, and releases. It never drives it high: the C64 pulls that line up itself.

## Reset

`R` asks which image the machine should come back as, cursor keys pick among the flash slots holding a ROM of the served type, and RETURN goes. The chosen image is loaded into a spare RAM slot, then one `SET_AUX_SWITCH_EXIT` drives the pin low, activates that slot, and releases the pin — pin first, so the machine is held in reset for the whole switch.

It has to be one command. After a slot switch the host can rely on neither the new image having a back-channel region nor the observed addresses being unchanged, so anything that must follow a switch has to travel with it.

Picking the image the machine is already serving is the safe version: it reboots and comes back exactly as it was, which is the way to find out whether the reset wire works before anything else depends on it.

## Leaving the ROM as it was found

Every command writes the response header, and the header lives in the active RAM slot, so the served BASIC is dirty from the first command onwards. Repairing it is impossible — the write that would repair it is itself a command.

So the program takes a Fletcher-16 of $A000–$BFFF before it knocks, then looks for a flash slot holding exactly that, loads it into a spare RAM slot and reads it back with `SLOT_PEEK` to be sure. `Q` switches to that slot on the way out: it has never held a back channel, and `SWITCH_AND_EXIT` writes no header. Without such a slot there is no clean way out, and the program says so and refuses to start rather than leaving you with a broken BASIC.

## Building

Needs [cc65](https://cc65.github.io/), and `c1541` from [VICE](https://vice-emu.sourceforge.io/) for the disk image. `c1541` is inside the VICE bundle, not on a stock macOS PATH.

```bash
make C1541=/Applications/vice-arm64-gtk3-3.9/bin/c1541
```

## The demo build

`make demo` builds `rbcp_aux_demo.prg`, which answers its own questions instead of asking a device. It exists so that every screen can be looked at under an emulator, where there is no device and nothing past the knock can run. It is a separate binary and none of it is linked into the one that talks to hardware.

`BOARD` picks which imaginary board it describes, which is how each ring size and the empty-group case get exercised:

| BOARD | What it describes |
|-------|-------------------|
| `0` | Three groups: 30 GPIO of which 14 drivable, 4 image select, 2 X pads with a loopback fitted between them. |
| `1` | Two groups, no X pads, and nothing in the GPIO group drivable. |
| `2` | One group of 48 GPIO, 30 drivable, and a device that cannot time holds. |

`SCRIPT` puts the program into one named state at startup by calling the same dispatch the keyboard calls, so a screen can be captured without anything to press the keys.

```bash
make BOARD=0 SCRIPT=2 demo
x64sc -warp -limitcycles 90000000 -exitscreenshot shot.png -autostart build/rbcp_aux_demo.prg
```

`-keybuf` cannot reach this program: it reads the keyboard matrix directly with interrupts masked, so nothing the kernal buffers is ever seen. `SCRIPT` is the way in.

## Other ROM types

A flash slot is only a candidate — for the clean exit or for the reset — if it reports type 2364, and the served image is assumed to be the 8 KB at $A000–$BFFF. For another 8-bit ROM, a 23128 combined BASIC+KERNAL say:

- `rbcp_config.s`: `CONFIG_ROM_SIZE` to the image size.
- `src/aux_defs.s`: `ROM_TYPE_2364` to that type's code from the spec.
- `src/pins_dev.s`: `checksum_image` walks up from `CONFIG_ROM_BASE_HI`. A 16 KB image is not contiguous — $A000–$BFFF then $E000–$FFFF — so it must walk both halves in image order.

## Limits

Four groups and 64 pins a group. A device reporting more is shown up to the limit and says so on screen rather than truncating quietly. Four is one more than any One ROM board exposes, and 64 is what the smallest ring that still reads on video can show.
