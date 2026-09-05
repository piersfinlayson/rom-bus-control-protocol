# ROMSEL

Pick which image a One ROM serves from the BIOS socket of an 8088 machine,
from DOS, and reset into it.

Written by Adrian Black.

## What it does

Lists the images held on the device, by the names they were programmed with,
and resets the machine into whichever one is chosen. The switch happens at
once. There is no power cycle in the middle, and no power cycle will preserve
the choice either.

That last part is the important one. A RAM slot is volatile. The device
reloads its configured boot flash slot every time it powers up, so:

- The choice lasts until the machine loses power.
- An image that hangs the machine cannot be made permanent. Pull the plug and
  the boot image is back.

Making a choice survive a power cycle would need either the device's own boot
slot setting, which RBCP has no command for, or an RBCP-aware loader in the
boot image itself. Neither is this program.

## How it works

Two sessions, each with interrupts and NMI masked for its whole length.

The first reads the device: protocol version, RAM slot count and which one is
active, which flash slot booted, and the flash slot names. The back-channel
the device answers through is a region of the image currently being served, so
the bytes underneath are read before the session and written back after it,
one `SLOT_POKE` per byte, with `EXIT_CMD_RESP_RESTORE` covering the response
header. The served image is byte-for-byte what it was.

The second switches. Where the device has two or more RAM slots, the chosen
image is loaded into one nothing is reading and then made active, so the bus
goes from wholly the old image to wholly the new one in a single step. Where
it has one, the copy runs over the live image and the program waits out the
copy before jumping, which is the weaker of the two and the reason the menu
says so.

Then `CS:IP` is set to `FFFF:0000` by a far return, which is where the
processor starts out of reset. The warm boot flag at `40:72` is cleared first
so a BIOS runs its full power-on path instead of trusting what the last one
left in memory.

A far jump is not a reset pulse, but on this class of machine it is close
enough: POST reprograms the interrupt controller, the timer, the DMA
controller, the PPI and the CRTC, and every option ROM re-initialises on the
`C000`-`EFFF` scan.

## No BIOS entry points

Nothing in the program calls a routine in the ROM. It cannot: the image it
switches to may be a diagnostic ROM with no BIOS services in it at all, and in
the window between the knock and the exit every read of the served image is
taken by the device as a command byte.

- Screen output is written straight to `B800` or `B000`, the adapter chosen
  from the equipment word at `40:10`.
- Keystrokes come out of the keystroke ring in the data area at `40:1A`,
  which IRQ1 fills, rather than through `INT 16H`.
- Delays and timeouts come from latching PIT channel 0 on ports 43H and 40H,
  so they hold at 4.77 MHz and at 10.

Reads of the data area are reads of RAM. They are not calls.

## Building

Needs [Open Watcom](https://github.com/open-watcom/open-watcom-v2) with
`wcc`, `wlink` and `wmake` on the path, and `WATCOM`, `INCLUDE` and `LIB` set
for a 16-bit DOS target. It hosts on DOS, Windows and Linux, and the DOS and
Linux builds are byte-identical. There is no macOS build.

The build tool is Open Watcom's own `wmake`, not GNU make.

```
wmake
```

`wmake clean` removes the output, which all goes in `build/`. Any of the
[settings](#settings) can be overridden on the command line:

```
wmake STRIDE=2
```

## An image from disk

```
ROMSEL GLABIOS.ROM
```

Name an image file and it joins the menu as entry `F`. Choosing it writes the
image into a spare RAM slot and boots it, without ever flashing it to the
device. Nothing about the device's flash slots changes, and a power cycle
leaves no trace of it.

**This needs a device with two or more RAM slots.** `SLOT_POKE` is the only
write the protocol has, and the back-channel it is polled through is a region
of the *active* slot, so the target has to be a slot nothing is reading. The
menu says so rather than trying, where the device has only one.

The file is read whole before any session starts, because the session runs
with interrupts disabled and DOS cannot be called there. It must be no larger
than the socket and its size must divide into it. A shorter image is repeated
to fill, for the same reason the device programmer has a `size=dup`: without
something at the top of the window there is no code at the reset vector.

The protocol writes one byte per command, so an 8 KB image is 8192 commands
and takes a noticeable few seconds. A bar is drawn as it goes. That drawing is
a write to video memory, which is why it is allowed from inside a session
where a BIOS call would not be.

## Switches

| Switch | What |
|--------|------|
| *filename* | An image to write into a spare RAM slot, offered as menu entry `F`. |
| `/L` | List the slots and quit. Changes nothing. |
| `/D` | Show the settings in force and the region bytes before and after the attempt. |
| `/P` | Leave parity and I/O channel checking disabled on exit. |
| `/Y` | Skip the confirmation before resetting. |
| `/?` | Usage. |

`/D` is the one to reach for on first contact with hardware. It prints the ROM
window, command page, back-channel and stride actually compiled in, then the
first 16 bytes of the back-channel region as they were before the attempt and
as they were after it.

Those two lines are the whole diagnosis. Identical means nothing decoded the
knock, so the ROM window or the command page does not match where this machine
maps the socket, or there is a real EPROM in it. Different means the device is
listening and something about the settings was refused.

## Settings

All of these describe the installation rather than the protocol, and all are
in `config.h` with a `wmake` override.

| Setting | Default | What it is |
|---------|---------|------------|
| `ROM_SEG` | `0xFE00` | Segment the ROM window starts at. `FE00:0000` is `F000:E000`, an 8 KB XT BIOS. |
| `ROM_SIZE` | `0x2000` | Size of the served image. |
| `STRIDE` | `1` | Host address bytes per device bus cycle. |
| `CMD_PAGE` | `0x10` | Command page, as a page number within the image. |
| `BCH_OFF` | `0x1800` | Back-channel offset within the slot. 4-byte aligned, must not overlap the command page. |
| `BCH_SIZE` | `160` | Back-channel size. 8 header, 4 preamble, then 32 per flash slot, so 160 lists four. |

### Stride

Stride is a property of the device, not of the processor reading it: it is
whether the device can sample the least significant address line at the rate
commands arrive. An 8088 reading a byte-wide EPROM presents every address line
as a real address line, with no byte-select and no word addressing, so nothing
about the host makes it anything other than 1.

The specification's one documented exception is One ROM's 40-pin hardware,
which does not observe that line for the 8-bit ROMs it serves. A 28-pin part
observes all of them. The setting exists so that case has somewhere to live,
and 1 is right here.

## Protocol versions

`GET_BOOT_SLOT_INFO`, `LOAD_AND_EXIT` and `EXIT_CMD_RESP_RESTORE` all arrived
in RBCP 0.1.2. A device reporting 0.1.1 does not have them, and issuing one is
worse than useless: a command the device has no definition for takes no
argument bytes off the wire, so everything after it is read as the next
command frame. `EXIT_CMD_RESP_RESTORE` carries nine.

So the version is read first and those three are gated on it, and a device
that will not report a version is treated as the older kind. The boot slot is
simply reported as unknown, which the protocol already allows for. The exit
puts the header back with `EXIT_CMD_RESP_SILENT` followed by eight
command-mode `SLOT_POKE` writes, which exist from 0.1.0 and work on either
kind of device.

Note that a device's own version and the protocol revision it implements are
two different numbers. A plugin numbered v0.1.2 reporting protocol 0.1.1 is
not a contradiction, and it is the reported protocol revision that decides
which commands may be issued. `/D` shows both.

## NMI, parity and the session

A session runs with interrupts disabled and NMI masked, because an interrupt
would vector into the ROM and every read of the served image between the knock
and the exit is either a command byte or a read of a region that is currently
displaced.

Masking at port A0H is not sufficient on its own. It stops the processor
seeing an NMI, but the system board parity flag still latches, and unmasking
then fires whatever was recorded while the session ran. The symptom is a
parity message appearing the instant the menu is drawn rather than during the
session.

So the two sources are gated at their own port as well. On a 5160, port 61H
bit 4 is the memory parity check and bit 5 the I/O channel check, both zero to
enable and one to disable, and setting bit 4 clears a latched flag as well as
disabling the check. That is the sequence the BIOS uses itself, at
`GLABIOS.ASM:3751`. The port is read and written back rather than assigned,
since the same register carries the keyboard clock and enable lines and the
timer 2 gate.

On the way out both flags are cleared and the two bits are put back as they
were found. `/P` leaves them disabled instead.

Note what that does and does not settle. Gating the check stops a latched flag
from surfacing as an NMI. If the underlying parity error is real, it is still
real and the machine still has it, so a message that only ever appears while
this program runs and never otherwise is worth telling apart from one that
does not.

### Refresh

Refresh is not affected by any of this and is not a candidate. On this machine
PIT channel 1 runs at divisor 18 and drives DMA channel 0, which is a hardware
handshake needing neither the processor nor interrupts. Nothing here touches
channel 1 or the DMA controller. Disabling interrupts does not stop refresh.

## Programming the device

```
onerom program --plugin host-control \
    --slot file=GLABIOS.ROM,type=2764,label="GlaBIOS 0.8" \
    --slot file=ibm5160.rom,type=2764,label="IBM 5160" \
    --slot file=turboxt.rom,type=2764,label="Turbo XT" \
    --slot file=diag.bin,type=2764,size=dup,label="Diagnostics"
```

The label is what the menu shows, and only the first 30 characters fit.

`size=dup` fills the socket with repeated copies of a short image. A 2 KB
diagnostic ROM needs it: without something at the top of the window there is
no code at the reset vector for the jump to land on.

## Failure modes

| What it says | What it means |
|--------------|---------------|
| No answer | Nothing decoded the knock. Wrong ROM window, wrong stride, wrong command page, or a real EPROM in the socket. |
| Device refused the command | The device answered and said no. A back-channel that is misaligned, overlaps the command page or runs past the end of the slot. |
| Command received but never completed | The device took the command and stopped. |

Every one of these leaves the served image as it was and returns to DOS.

There is one case where it cannot. If the device answers the knock but then
refuses to say which RAM slot is active, or a write-back fails part way, the
program has nowhere to put the displaced bytes. It says so on a screen of its
own, exits with status 2, and the machine should be powered off rather than
warm booted: a BIOS checksums its own ROM at power-on, and that image would
now fail. Everything still works until then.

## Before running it

Close your files. This resets the machine, and DOS gets no warning.
