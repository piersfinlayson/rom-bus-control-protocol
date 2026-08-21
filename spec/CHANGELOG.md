# Changelog

Substantive changes to the specification are documented in this file.

## v0.1.2 - unreleased

- Add group 0x04, Pipes: transfer bytes between the host and a pipe on the device.
  A pipe carries one direction or both. PIPE_WRITE takes four bytes, all or none.
  PIPE_READ takes what the device has, and reports bytes it discarded. Additive
- Define the far end — what a device relays a pipe to and from. GET_PIPE_INFO reports
  its kind and whether it is attached, in two bits so that a device unable to tell
  stays distinct from one whose far end has gone. Additive
- Define Host, Device, Pipe, IN / OUT and Far end in Terminology. Clarification only
- Add group 0x05, Auxiliary I/O: drive and read device pins outside the ROM interface,
  addressed by group and pin number. Whether a pin may be driven is the device's
  decision, a forced pin possibly serving the image the host is executing from. Additive
- Add group 0x06, LEDs: drive and read the device's own LEDs, addressed by number. Not
  group 0x05, an LED taking a mode and a colour rather than a level. No exit variant.
  Period and hold in units of 100ms, where group 0x05 uses 10ms. Additive
- SET_LED's hold does not block, the device timing it and the hold outliving the
  session, so a host can show an indication it will not be there to end. No after
  argument
- All three colour bytes zero means the device chooses the colour. Lit versus dark is
  carried by the mode, so a host never needs black. The spec carries this reasoning,
  the value being counter-intuitive alone
- GET_LED_INFO reports the colour a monochrome LED shows, which a device may not know
- Add LOAD_AND_EXIT and EXIT_CMD_RESP_RESTORE, to put back the bytes the back-channel
  displaces in the served image, which a host could read but not write back. Restore
  takes count last, as only a final argument bans 0xAA. Additive
- Add GET_BOOT_SLOT_INFO, the flash slot the device loaded at boot and the RAM slot it
  loaded it into, which LOAD_AND_EXIT needs named. Additive
- Require a device to present either the previous or the new byte at every address
  throughout a load into the active RAM slot. Write order unspecified. Previously
  unspecified
- Specify device behaviour on an unknown GROUP or CMD: no argument bytes are consumed,
  so a zero-argument one fails cleanly and one with arguments desynchronises the
  session. Every group added after v0.1.1 carries a discovery command at CMD 0x00.
  Previously unspecified
- Take ROM type values 0x16–0x18 out of circulation. An implementation had assigned
  them before the implementation-specific range existed. No behaviour changes
- Add a Since column to every group and command, and require a host not to issue one
  newer than the device reports. Previously unspecified

To test (on hardware):

- The 6502 reference library's pipe routines and the C64 bootloader's
  `SWITCHING TO SLOT $XX` line. Both assemble and link and the code has been read,
  but neither has run. Needs a C64 and a device exposing a pipe.

## v0.1.1 - 2026-08-09

- Add 23QL512 ROM type
- Add 23C1001 (0x20), 27C200 (0x21), HM7641 (0x22) and 62256 (0x23) ROM types
- Separate 23C1010 (0x24) from 27C010 (0x0F), which previously shared 0x0F. The
  new value falls in the previously-reserved range, which hosts already handle
  gracefully
- Correct the reserved-range row (was `0x1E–0x7F`, overlapping the assigned
  0x1E/0x1F) to `0x25–0x7F`
- ENTER_CMD_RESP's back-channel start address must leave room for the 8-byte
  response header within the RAM slot. One that does not is silently discarded,
  the device having nowhere to report a failure. Previously unspecified
- A command refused as invalid in the current mode still has its argument bytes
  consumed, so a host that sent a well-formed frame is not desynchronised by the
  refusal. Previously unspecified
- The truncated record in GET_FLASH_SLOT_INFO_ALL ends in 0x00 where it carries a
  name, so every name is null-terminated and is up to one character shorter than
  the byte count implies. Previously unspecified
- Specify the back-channel on a word-organised (×16) ROM read as words: each word
  carries two consecutive region bytes, the even offset on D0–D7 and the odd
  offset on D8–D15. Clarification only
- Clarify address-line presentation: command signalling is carried on the address
  lines the device observes, which for ×16 ROMs are the word address lines. A
  device may not observe a ROM's least-significant line, in which case the host
  advances its read address by two per command byte — a per-ROM-type property
  known in advance, like the knock. Backwards compatible
- Add a non-normative section, "Using RBCP on a Host Wider Than the Device": the
  two address mappings a wider host needs, one for command signalling and one for
  the back-channel, with a worked 68000 example. Also covers several devices on
  one bus — commands are broadcast, each device keeps its own response header,
  and completion must be polled per device. Adds no requirements

## v0.1.0 - 2026-05-08

- Initial release of the specification.