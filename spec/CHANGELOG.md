# Changelog

Substantive changes to the specification are documented in this file.

## v0.1.1 - 2026-??-??

- Add 23QL512 ROM type
- Add 23C1001 (0x20), 27C200 (0x21), HM7641 (0x22) and 62256 (0x23) ROM types
- Separate 23C1010 from 27C010: 0x0F now denotes 27C010 only, and 23C1010 has its
  own value (0x24).  Previously the two shared 0x0F.  Backwards compatible — the
  new value falls in the previously-reserved range, which hosts already handle
  gracefully
- Correct the reserved-range row (was `0x1E–0x7F`, overlapping the assigned
  0x1E/0x1F) to `0x25–0x7F`

## v0.1.0 - 2026-05-08

- Initial release of the specification.