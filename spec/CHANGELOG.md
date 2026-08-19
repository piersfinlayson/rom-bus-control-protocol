# Changelog

Substantive changes to the specification are documented in this file.

## v0.1.2 - unreleased

- Add group 0x04, Pipes: transfer bytes between the host and a pipe on the device,
  for a host whose own I/O is limited or absent. A pipe carries one direction or
  both, both meaning the two form one exchange, which a host cannot otherwise
  learn and a device must therefore state. PIPE_WRITE carries up to four bytes
  and takes all or none. PIPE_READ returns what the device has, up to the count
  asked for, and consumes it, an empty pipe succeeding with no data so that a host
  polling an idle pipe never has to tell it from a broken one. Its response carries
  a bit saying the device discarded bytes it could not hold, which is the only
  loss the protocol reports at all. Additive
- Define the far end — what a device relays a pipe to and from. GET_PIPE_INFO
  reports what kind of far end a pipe has and whether it is attached. A device
  knows its own far end and cannot know what a host and that far end use the pipe
  for, so the field says what it is
  rather than what it is for. Attachment is two flag bits, one saying the device
  answers at all and one carrying the answer, because a single bit would make
  every device that cannot tell indistinguishable from one whose far end has gone
  away
- Define Host, Device, Pipe, IN / OUT and Far end in Terminology. Host was used
  throughout but never defined, leaving it to be read as any computer attached to
  the device. IN and OUT are pipe directions named from the host's point of view,
  as USB names its endpoint directions. Clarification only
- Add group 0x05, Auxiliary I/O: drive and read device pins outside the ROM
  interface, addressed by group and pin number. Whether the host may drive a pin
  is the device's decision, because a forced pin may be one serving the image the
  host is executing from. SET_AUX_AND_EXIT and SET_AUX_SWITCH_EXIT act where the
  host expects no observable response. Additive
- Add LOAD_AND_EXIT and EXIT_CMD_RESP_RESTORE, to put back the bytes the
  back-channel displaces in the served image. A host could read those bytes but
  not write them back, as whatever command carries the write updates the header
  after it. LOAD_AND_EXIT is LOAD_SLOT with a silent exit. Restore takes the bytes
  from the host and covers what a reload cannot — no flash source, or a patch
  worth keeping — with count last, as only a final argument bans 0xAA. Restore
  is command-response mode only: command mode has no region to write to and no
  address to write it at. Additive
- Add GET_BOOT_SLOT_INFO, the flash slot the device loaded at boot and the RAM
  slot it loaded it into, which is what LOAD_AND_EXIT needs named. The boot
  rather than the slot last loaded, because a host that loaded a slot itself
  already knows what it put there — the boot is the only load a host cannot
  account for, and reporting only it costs a device two bytes instead of one
  per RAM slot. Just the two slots, so that what else a device might say about
  its boot stays open. Additive
- Require a device to present either the previous or the new byte at every address
  throughout a load into the active RAM slot. Write order unspecified. Previously
  unspecified
- Specify device behaviour on an unknown GROUP or CMD: no argument bytes are
  consumed, the count being defined per GROUP+CMD pair. A zero-argument unknown
  command therefore fails cleanly, one with arguments desynchronises the session
  undetectably. Every group added after v0.1.1 carries a zero-argument discovery
  command at its lowest CMD value. Previously unspecified
- Take ROM type values 0x16–0x18 out of circulation. They read as Reserved, but
  an implementation had assigned them before the implementation-specific range
  existed, and its devices carry them in flashed metadata — so the protocol can
  never use them without colliding. No host or device behaviour changes: a host
  already handles them as reserved
- Add a Since column to every group and command, and require a host not to issue
  one newer than the device reports. The discovery command protects a new group,
  nothing protects a new command in a group that already exists. Previously
  unspecified

To test (on hardware):

- The 6502 reference library's pipe routines and the C64 bootloader's
  `SWITCHING TO SLOT $XX` line. Both assemble and link, and the generated code
  has been read, but nothing has executed either — there is no 6502 emulator in
  this repository, and the conformance tester drives a device rather than
  running host code. Needs a C64 and a device exposing a pipe.

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