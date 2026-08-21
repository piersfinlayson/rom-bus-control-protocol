# Testing the Apple II bootloader without hardware

A fake RBCP device written in [MAME](https://mamedev.org)'s Lua, so the real binary can be run against an emulated Apple II and driven through the menu.

`rbcp_dev.lua` watches every read in the ROM's address range, decodes the RBCP command stream out of the addresses, and answers by substituting bytes on reads of the back-channel region — which is what a device does. It implements the commands this bootloader calls and no others. Pipe writes are printed, so the log lines can be read.

The device it pretends to be has five flash slots, two RAM slots, one pipe, a byte of writable non-volatile storage, and two LEDs of which the second is the RGB one — so the search for the lowest-numbered RGB LED is exercised rather than assumed to land on zero.

## Running

```bash
make test    ROMS=/path/to/apple2/roms    # the 2KB build, on an Apple II+
make test-ef ROMS=/path/to/apple2/roms    # the 8KB build, on an unenhanced IIe
```

or, from this directory, `./run.sh <rom-dir>` and `RBCP_TARGET=ef ./run.sh <rom-dir>`. A leading `~` in a make variable is not expanded by every shell, so give `ROMS` a full path or one starting `$HOME`.

`<rom-dir>` holds the machine's ROM files, named as MAME names them — see the tables below for which files and where to get them. There is no default and nothing is read from the environment. Without them there is no character generator, so nothing on screen can be read as pixels, and no stock image for the fake device to serve after the slot switch, so the hand-over cannot be followed. Rather than fill the gaps with something made up and report a pass, `run.sh` names what is missing and stops.

Every run prints a checksum complaint from MAME about the ROM in the bootloader's socket. That file is the bootloader, so of course it does not match the dump MAME expects there.

## Where the ROM files come from

The [Apple II Documentation Project](https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Computers/Apple%20II/) mirror carries them, under `Computers/Apple II/`. Both MAME and this test want them named as MAME names them, and the mirror names them by what they are, so the mapping is below. Every SHA1 is the one MAME expects, so a downloaded file can be checked with `shasum` before it is used. `run.sh` does no hashing of its own — MAME hashes everything it is handed and says what it found.

Apple ][+, from [`Apple II plus/ROM Images/`](https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Computers/Apple%20II/Apple%20II%20plus/ROM%20Images/):

| Save as | File on the mirror | SHA1 |
|---------|--------------------|------|
| `341-0011.d0` | Apple II plus ROM Pages D0-D7 - 341-0011 - Applesoft BASIC.bin | `0287ebcef2c1ce11dc71be15a99d2d7e0e128b1e` |
| `341-0012.d8` | Apple II plus ROM Pages D8-DF - 341-0012 - Applesoft BASIC.bin | `a75ce5aab6401355bf1ab01b04e4946a424879b5` |
| `341-0013.e0` | Apple II plus ROM Pages E0-E7 - 341-0013 - Applesoft BASIC.bin | `8d82a1da63224859bd619005fab62c4714b25dd7` |
| `341-0014.e8` | Apple II plus ROM Pages E8-EF - 341-0014 - Applesoft BASIC.bin | `37501be96d36d041667c15d63e0c1eff2f7dd4e9` |
| `341-0015.f0` | Apple II plus ROM Pages F0-F7 - 341-0015 - Applesoft BASIC.bin | `e6bf91ed28464f42b807f798fc6422e5948bf581` |
| `341-0020-00.f8` | Apple II plus ROM Pages F8-FF - 341-0020 - Autostart Monitor.bin | `a28852ff997b4790e53d8d0352112c4b1a395098` |
| `341-0036.chr` | Apple II plus Video ROM - 341-0036 - Rev. 7.bin | `f9d312f128c9557d9d6ac03bfad6c3ddf83e5659` |

Enhanced IIe, from [`Apple IIe/ROM Images/`](https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Computers/Apple%20II/Apple%20IIe/ROM%20Images/). MAME calls this machine `apple2ee`, and `342-0303-a.e8` is the EF ROM an Apple IIe One ROM would replace:

| Save as | File on the mirror | SHA1 |
|---------|--------------------|------|
| `342-0303-a.e8` | Apple IIe Enhanced ROM Pages E0-FF - 342-0303-A - 1984.bin | `afb09bb96038232dc757d40c0605623cae38088e` |
| `342-0304-a.e10` | Apple IIe Enhanced ROM Pages C0-DF - 342-0304-A - 1984.bin | `3aecc56a26134df51e65e17f33ae80c1f1ac93e6` |
| `342-0265-a.chr` | Apple IIe Enhanced Video ROM - 342-0265-A - US 1983.bin | `b2b5d87f52693817fc747df087a4aa1ddcdb1f10` |
| `341-0132-d.e12` | Apple IIe Enhanced Keyboard ROM - 341-0132-D - US-Dvorak 1984.bin | `8e14e85c645187504ec9d162b3ea614a0c421d32` |

Unenhanced IIe, MAME's `apple2e`, which is what `RBCP_TARGET=ef` runs on:

| Save as | File on the mirror | SHA1 |
|---------|--------------------|------|
| `342-0134-a.64` | Apple IIe ROM Pages E0-FF - 342-0134-A - 1982.bin | `8895a4b703f2184b673078f411f4089889b61c54` |
| `342-0135-b.64` | Apple IIe ROM Pages C0-DF - 342-0135-A - 1982.bin | `523838c19c79f481fa02df56856da1ec3816d16e` |
| `342-0132-c.e12` | Apple IIe Keyboard ROM - 342-0132-C - US-Dvorak 1983.bin | `12a2e718f5f4acd69b6c33a45a4a940b1440a481` |
| `342-0133-a.chr` | Apple IIe Video ROM - 342-0133-A - US 1982.bin | does not match |

The mirror labels the CD ROM revision A, but its contents are what MAME expects for revision B, so save it under the name in the table. The video ROM is a different dump to MAME's and its SHA1 will not match — it renders correctly all the same, so it is worth having rather than a stand-in.

Nothing else is needed. MAME fits a Mockingboard in slot 4 and a Disk II controller in slot 6 by default, and both have ROMs of their own that the mirror does not carry. `run.sh` leaves those two slots empty, since this test uses neither. The cost is that there is no disk to boot after the hand-over, so the monitor falls through to BASIC.

## Settings

Everything is an environment variable:

| Variable | Default | Meaning |
|----------|---------|---------|
| `RBCP_TARGET` | f8 | `f8` runs the 2KB build on an `apple2p`, `ef` the 8KB build on an `apple2e`. |
| `RBCP_NV` | 255 | The slot the device has stored. 255 stands for never written. |
| `RBCP_KEYS` | none | Keys to press, in order, one every 20 frames. A key in braces is an input port field held for three frames, such as `{Cursor Right}`. |
| `RBCP_KEY_AT` | 150 | Frame the first key is pressed on. |
| `RBCP_FRAMES` | 600 | Frame to print the text screen on and stop. |
| `RBCP_DEBUG` | unset | Print every command byte the device sees. |

The screen is printed as 24 rows of 40 columns. Lower case marks inverse video, which is how the highlighted line and the title show up.

## Examples

Let the countdown run out, with nothing stored:

```bash
make test
```

Stop the countdown, move down twice, boot what is highlighted:

```bash
RBCP_KEYS='x{Cursor Right}{Cursor Right}
' ./run.sh
```

Boot the stored choice, showing the menu part way through the countdown:

```bash
RBCP_NV=3 RBCP_FRAMES=120 ./run.sh
```
