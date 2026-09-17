# Working on the 68K code

The Amiga bootloader is in `amiga-boot/`, the RBCP library it links in
`rbcp/`. The READMEs cover using them.

## The device

- **NV storage is the last 4KB of the host-control plugin**, `$1002F000` on
  this board. Flash is XIP from `$10000000`, 64KB each of firmware, USB plugin,
  then host-control. `onerom inspect peek memory --address 0x1002F000 --length
  16` reads the stored slot without going through the bootloader. Programming
  the device erases it to `$FF`.
- **NV write needs two host RAM slots.** The commit names a spare, non-active
  slot to stage in, so it works wherever serving the image leaves one over —
  256KB on this device.
- **The firmware loads a flash slot into a RAM slot where the ROM types match
  in size**, which is why every image in a menu is the bootloader's own type.
- **`onerom monitor log` consumes the log as it runs.** Attach it to a file in
  the background before the run you want, or the session reaches a reader that
  never prints it.
- **`onerom reboot` restarts the host too.** The mouse buttons have to be held
  already when it is issued for the menu to appear.

## The Amiga

- **The bootloader runs from chip RAM at `$8000`**, so replacing the served ROM
  under it is safe. It hands over through the new image's reset vector with the
  chipset quiet, and leaves OVL alone.
- **The left mouse button is CIA-A PRA bit 6, the right is `POTGOR` bit 10**,
  with `POTGO` driven `$FF00`.
- **`key_loop` polls `amiga_getkey` every 10-20us.** A click lasts tens of
  milliseconds and so spans thousands of polls — a click that appears lost is
  contact bounce. `LMB_DEBOUNCE` sets how long the button reads up before
  another press is taken.

## vasm

- **An operand ends at the first space.** `X EQU FOOTER_COL + 11` silently
  drops the `+ 11`. Write `FOOTER_COL+11`.
- **RAM-section code reaches ROM data by `LEA (label).L`**, never
  PC-relative — it is assembled at the ROM address and runs from `$8000`. A
  PC-relative LEA shows in the listing as `41FA`.
- **`.S` branches are ±127 bytes.** Adding code to a routine can push an
  existing branch out of range.

## The bus mapping

`rbcp/README.md` has the model. In this configuration back-channel region byte
N sits at CPU `BCH_ABS + (N XOR 1)`. The code is `rbcp_read_data` and
`rbcp_region_addr` in `rbcp/rbcp.s`, driven by five constants in
`amiga-boot/rbcp_config.s`.
