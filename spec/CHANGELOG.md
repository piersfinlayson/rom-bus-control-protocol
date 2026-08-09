# Changelog

Substantive changes to the specification are documented in this file.

## v0.1.1 - 2026-08-09

- Add 23QL512 ROM type
- Add 23C1001 (0x20), 27C200 (0x21), HM7641 (0x22) and 62256 (0x23) ROM types
- Separate 23C1010 from 27C010: 0x0F now denotes 27C010 only, and 23C1010 has its
  own value (0x24).  Previously the two shared 0x0F.  Backwards compatible — the
  new value falls in the previously-reserved range, which hosts already handle
  gracefully
- Correct the reserved-range row (was `0x1E–0x7F`, overlapping the assigned
  0x1E/0x1F) to `0x25–0x7F`
- Clarify ENTER_CMD_RESP's back-channel start address: it must leave room for at
  least the 8-byte response header within the RAM slot, and a start address that
  does not — including one outside the slot — is silently discarded, since the
  device has nowhere to report a failure. Names the principle the entry's two
  outcomes already followed: failure where there is a back-channel to report it
  in, silent discard where there is not. Previously unspecified
- Clarify that a command refused for being invalid in the current mode still has
  its argument bytes consumed before being discarded, so a host that sent a
  well-formed frame is not desynchronised by the refusal. Previously unspecified
- Clarify the truncated record in GET_FLASH_SLOT_INFO_ALL: where it carries a
  name its final byte is 0x00, so every name in the response is null-terminated
  and a host never needs the byte count to find a name's end. The name is up to
  one character shorter than that count implies. Previously unspecified
- Specify how the back-channel is presented on a word-organised (×16) ROM read as
  words: each word carries two consecutive region bytes, the even offset on
  D0–D7 and the odd offset on D8–D15. Clarification only — the region was always
  defined as a region of bytes
- Clarify address-line presentation: command signalling (knock, command bytes,
  command page) is carried on the address lines the device observes at the ROM
  socket. For word-organised (×16) ROMs these are the word address lines. An
  implementation may additionally be unable to observe a ROM's least-significant
  address line, in which case the host omits it and advances its read address by
  two per command byte — a per-ROM-type property, known in advance like the knock.
  Backwards compatible.
- Add a non-normative section, "Using RBCP on a Host Wider Than the Device",
  giving host implementers the two address mappings needed when the host bus is
  wider than the device serving it — one for command signalling, one for reading
  the back-channel — together with the parameters that distinguish the cases and
  a worked 68000 example. Also covers a bus filled by several devices: commands
  are broadcast to all of them, each maintains its own complete response header
  with the headers interleaved rather than merged, completion is per-device and
  must be polled per lane, and a host should not assume it can address one device
  in isolation. Derived entirely from existing normative text; adds no
  requirements and constrains no device

## v0.1.0 - 2026-05-08

- Initial release of the specification.