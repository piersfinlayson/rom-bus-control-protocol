# 68K Amiga Bootloader — Handover

**Temporary.** Carries state between threads. Delete when the work is done.

The Amiga Kickstart bootloader in `amiga-boot/` is functional on real hardware
(A500 + One ROM fire-40-b, firmware 0.7.2). The 68K RBCP library it uses is in
`../rbcp/`. This file is the whole picture; the code is the detail.

## How it behaves

Boots the remembered or default image at once. Holding **both mouse buttons**
at reset brings up a menu instead — no countdown. In the menu: left click or
cursor up/down change the choice, right click or RETURN boot it, `1`-`9` pick
one of the first nine. This is the C64 model, deliberately not the Apple's.

## Verified on hardware

Over the device's channels and a couple of screen photos: enter
command-response mode; the data-section un-swap reader (device type, version,
slot names all correct); the menu renders; RGB LED cycles then breathes a
per-image colour; USB pipe log; both-buttons opens the menu; no-hold boots at
once; the boot switch at 256KB and 512KB, including loading and serving a 512KB
DiagROM. NV query works; the NV *write* path has never been exercised (needs a
keypress).

## Open bugs (from the last session, all in `amiga_boot.s`)

1. **A quick left click is missed.** You have to hold the button a moment. The
   menu polls `amiga_getkey` in `key_loop` and edge-detects on `VAR_LMB_HELD`;
   a fast press+release between polls is lost. Needs the button-down latched so
   a click can't fall between polls.
2. **The footer line is not centred.** `str_footer` is drawn left-aligned at
   `FOOTER_COL`. Centre it.
3. **Menu entries are per-entry centred, so the `1)` and `2)` don't line up.**
   `draw_list` centres each line by its own width. Wanted: left-align the
   entries as a block, and centre the *block* — measure the widest entry, take
   one start column, draw them all there.

The right mouse button read (`POTGO`=$FF00, `POTGOR` bit 10) and the
both-buttons gesture worked in testing, but if either misbehaves that read is
the first suspect.

## To do

- Rewrite both READMEs (`amiga-boot/README.md`, `68k/README.md`). The current
  ones are poor.
- Ship both a 256KB and a 512KB build (CI/release), not one or the other.
- Fix the three bugs above.
- Mouse pointer (a real sprite + reading the mouse counters + row hit-test) is
  wanted eventually; deferred.

## Build / program / test

```bash
cd reference/host/68k/amiga-boot
make                 # 256KB, 27C200
make ROM_KB=512      # 512KB, 27C400
```
`onerom` byte-swaps the image into `build/amiga_boot_swapped.bin` — that is the
one to write.

Program (512KB example; every image must be the SAME rom type as the
bootloader, so a 256KB image is duplicated to fill a 512KB slot):
```bash
onerom program --plugin usb --plugin host-control \
  --slot file=build/amiga_boot_swapped.bin,type=27c400,label="Bootloader" \
  --slot file=ks-1_3.bin,type=27c400,size-handling=dup,label="Kickstart 1.3" \
  --slot file=diagrom-16bit.bin,type=27c400,label="DiagROM V2"
```
Cold boot (device then host), which is how the menu is reached again after a
switch: `onerom reboot && onerom control reset --pin sel_c`. Read the log:
`onerom monitor log`. Peek the served ROM: `onerom peek --address 0 --length 8`.

Test images used: `/Volumes/EXT-1TB/images/mine/amiga/ks-1_3-h1.bin` (256KB,
device order) and `.../DiagRom/DiagROMV2/16bit.bin` (512KB, device order). Both
are already byte-swapped for the device.

## Design facts that cost time to learn

- **The firmware loads a flash slot into a RAM slot only if the ROM types match
  in size.** So every image in the menu must be the bootloader's type. Build at
  the largest size, duplicate smaller images to fill. This is why a 256KB
  bootloader cannot boot a 512KB DiagROM.
- **NV write needs two host RAM slots** — the commit names a spare, non-active
  slot to stage in. Serving a 512KB image leaves one slot, so NV is off at
  512KB. At 256KB this device gives two slots and NV works.
- **The bootloader runs from chip RAM ($8000)**, so replacing the served ROM
  under it is safe. It hands over by jumping through the new image's reset
  vector with the chipset quiet; OVL is left alone.
- **Byte order:** the 68K is big-endian, the device stores little-endian per
  word. The build is swapped before programming. Kickstart dumps in the test
  folder are already in device order.

## Traps in the toolchain

- **`rbcp_send_cmd` D1 clobber** (fixed): the arg-loop counter must not live in
  a register the send helper clobbers. First hardware bug found.
- **vasm ends an operand at the first space.** `X EQU FOOTER_COL + 11` silently
  drops `+ 11`. Write `FOOTER_COL+11`. This caused the countdown-digit bug.
- **RAM-section code must reach ROM data by `LEA (label).L`,** never
  PC-relative — it is assembled at the ROM address but runs from $8000. Check
  the listing has no `41FA` in the RAM section.
- `.S` branches are ±127 bytes; several loop-backs needed widening to word.

## The 68K bus mapping (why this exists)

An Amiga reads Kickstart as 16-bit words, so the device sees the ROM's word
address lines: one command byte advances the CPU address by two, the command
page is a word-address page. The back-channel's bytes are transposed — region
byte N is at CPU `BCH_ABS + (N XOR 1)` for this config. Five constants in
`rbcp_config.s` parameterise both directions; `rbcp_defs.s` derives the rest,
and the reader/mapper is `rbcp_read_data` / `rbcp_region_addr` in `rbcp.s`. The
spec's non-normative *Using RBCP on a Host Wider Than the Device* is the same
model in prose.
