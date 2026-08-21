# Amiga RBCP Kickstart Bootloader

An Amiga Kickstart ROM image that talks, over the ROM bus, to the RBCP device serving it.

**Untested on hardware.** It has never been in front of a real Amiga or a real RBCP device.

**Status: milestone 1 — proving entry into command-response mode.** This build resets the device, enters command-response mode, issues a `NOP`, and reports what happened. The menu, slot enumeration, NV storage and boot switch follow.

## Building

```bash
make
```

Requires [vasm](http://sun.hasenbraten.de/vasm/) built with `make CPU=m68k SYNTAX=mot`, and `font_8x8.bin` — a 2048-byte headerless 8×8 bitmap font, 256 glyphs of 8 bytes, one byte per scan line, MSB leftmost.

Output:

| File | Contents |
|---|---|
| `build/amiga_boot.bin` | The image in 68K byte order |
| `build/amiga_boot_swapped.bin` | The same image in device byte order |

**Write the swapped image to the device.** The 68K is big-endian, and the device stores its slot in its own byte order, so the natural image must be byte-swapped first. The swap is produced by `onerom image swap-bytes`; if `onerom` is not on your `PATH` the build still succeeds and warns, and you will need to swap the image another way.

### ROM size

Set `CONFIG_ROM_KB` in `rbcp_config.s` to 256 or 512. Everything else follows — the base address, the command page number, and the back-channel start offset. The Makefile reads the same line to size-check the output, so the two cannot disagree.

## What milestone 1 displays

```
AMIGA RBCP BOOTLOADER - MILESTONE 1: COMMAND-RESPONSE MODE

ROM:00FC0000 SZ:040000 PG:01FF BCH:03FC00 BSZ:0200
@TOK:FFFC03  @PRG:FFFC05  @RSP:FFFC04

BACK-CHANNEL RAW CPU BYTES BEFORE (EXPECT ALL ZERO):
00 00 00 00 ...

BACK-CHANNEL RAW CPU BYTES AFTER:
...

GRP:00 CMD:01 TOK:xx PRG:BB RSP:CC

OK: ENTERED COMMAND-RESPONSE MODE

OK: NOP ACKNOWLEDGED - SESSION IS LIVE
```

The two configuration rows are the point of the display. The first shows the values sent to the device — a command page of `$01FF` and a back-channel start of `$03FC00`, both counted in *device* terms. The second shows the CPU addresses the library reads the header from. `@PRG` is `$FFFC05` and `@RSP` is `$FFFC04` — one above and one below where a naive byte-for-byte reading would put them, because the specification places even back-channel offsets on D0–D7 and a big-endian 68K reads those from the higher address of a word.

The raw dumps are there so the byte-lane assignment can be read off the screen rather than assumed. Before any RBCP traffic every byte should be `$00`, since the region is zero-filled in the image; anything else means the region is not where the configuration says it is. After entry, the header bytes should appear at the CPU addresses named on the `@` row, and the decoded line below should agree with the dump.

On failure the stage is shown: 1 = no token increment, 2 = progress never completed, 3 = the device reported failure. Stage 1 on `ENTER_CMD_RESP` most often means the device silently discarded the command — a misaligned back-channel address, an out-of-range command page, or a prohibited sentinel.

The border colour also tracks progress: red on entry to `boot_rom_entry`, white then green then blue through hardware init, yellow back in `boot_rom_entry`, green on success, orange on a NOP failure, red on failure to enter. Purple means an unexpected exception.

## Design notes

### Running from RAM

The knock and command sequences work by triggering specific ROM address reads. If the code doing that is itself fetched from the ROM under test, its instruction-fetch addresses land on the bus and corrupt the sequence the device sees.

The image therefore contains a RAM section, assembled at its ROM address but copied to `$8000` in chip RAM before any RBCP traffic and executed from there. Branches within the section are PC-relative and survive the move unchanged; references *out* of it — to the font, the strings, the copper template — use explicit absolute long addressing, `LEA (label).L,A0`. A PC-relative reference to ROM data would be computed at the assembly address and resolve to the wrong place at run time.

The `.L` also stops the assembler shortening a high address to sign-extended absolute short. That form works on a 68000's 24-bit bus but not on a 32-bit one.

### Where the screen may be used

`screen_putchar` reads the font from ROM, so it must not be called between the knock and the response to `ENTER_CMD_RESP` — during that window the device treats every address read as command data. Once command-response mode is established the device filters on the command page, and ROM reads elsewhere are ignored, so the screen is free again.

### Memory map

| Range | Contents |
|---|---|
| `$0000`–`$03FF` | Exception vectors |
| `$0400`–`$041F` | Boot trampoline (reserved for the boot-switch milestone) |
| `$1000`–`$101F` | RBCP scratch RAM |
| `$1020`–`$109F` | Copper list |
| `$10A0`–`$569F` | Mono bitplane, 640×224 |
| `$56A0`–      | Application variables |
| `$7F00` | Supervisor stack top, grows down |
| `$8000`– | RAM code section |

## Files

| File | Purpose |
|---|---|
| `amiga_boot.s` | ROM header, boot, the RBCP session, screen and hex output |
| `amiga_hw.s` | ROM-section hardware init: chipset, vectors, display |
| `amiga_defs.s` | Hardware constants and the chip RAM layout |
| `rbcp_config.s` | RBCP configuration — ROM size, bus mapping, region placement |
