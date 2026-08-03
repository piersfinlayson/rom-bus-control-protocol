# 68K Reference Implementation — Handover Brief

**Temporary.** Delete this file once the 68K implementation is complete. It exists to carry context between working sessions.

---

## Ground rules

These came from the repository owner and override any contrary instinct.

1. **The specification is normative. Nothing else is.** `spec/rbcp.md` is the sole source of truth.
2. **Do not consult the One ROM `host-control` plugin.** A local checkout exists at `/Users/pdf/builds/one-rom/plugins/user/host-control/`. Reading it was explicitly declined: the spec is normative, and the implementation must not be written to work around device-side bugs. If host and device disagree, that is a finding to report, not something to accommodate.
3. **The previous 68K implementation was wrong and must not be trusted.** It predated word-ROM support in the spec. It has been rewritten; do not restore anything from it without re-deriving from the spec.
4. **Ask before modifying `spec/`.** Other threads work on it concurrently. The one spec change belonging to this work is already committed — see *Accompanying specification change* below.

---

## Status

Milestone 1 is complete and builds. **Nothing has been tested on hardware.**

| Milestone | State |
|---|---|
| 1 — prove entry into command-response mode | Written, builds, unverified on hardware |
| 2 — runtime back-channel mapper; protocol version, slot info, device strings | Not started |
| 3 — menu, keyboard/LMB input | Not started |
| 4 — NV last-slot memory | Not started |
| 5 — boot switch (`SWITCH_AND_EXIT` + trampoline) | Not started |

Build:

```bash
cd reference/host/68k/amiga-boot && make
```

Requires `vasmm68k_mot` (installed on the original machine; build from the tarball at http://sun.hasenbraten.de/vasm/ with `make CPU=m68k SYNTAX=mot` — there is no official git repo). `onerom` is optional and produces the byte-swapped image.

---

## The problem this implementation exists to solve

A 6502 host has the simplest possible relationship to RBCP: the ROM is 8 bits, the CPU bus is 8 bits, and a byte offset in the device's slot is a byte offset in CPU address space. None of that holds on a 68K, and the previous implementation assumed it did.

### Command direction

An Amiga reads Kickstart as 16-bit words, so this is the spec's *word-organised (×16) ROM, addressed as words* case. The device observes the ROM's **word** address lines. Therefore:

- One command byte advances the CPU address by **2**, not 1.
- The command page is a page of the **word** address, not the byte address.

### Back-channel direction

Per `spec/rbcp.md` § *Back-Channel on a Word-Organised ROM*, region byte N is on D0–D7 for even N and D8–D15 for odd N. On a big-endian 68K the byte at an **even** CPU address comes from D8–D15 and the byte at an **odd** CPU address from D0–D7.

So region byte N lives at CPU address `BCH_ABS + (N XOR 1)`. Every pair is transposed. This is precisely the case the spec's closing paragraph anticipates: *"a host whose word byte ordering differs from the ROM's data pin ordering must account for that difference itself."*

---

## The bus mapping model

Five constants in `rbcp_config.s` carry everything platform-specific. `rbcp_defs.s` derives the rest.

| Constant | Meaning |
|---|---|
| `CONFIG_RBCP_BUS_SHIFT` | log2 of the CPU address stride of one device bus cycle — 1 for a 16-bit bus, 2 for 32-bit |
| `CONFIG_RBCP_DEV_SHIFT` | log2 of bytes the device supplies per cycle — 0 for 8-bit, 1 for ×16 |
| `CONFIG_RBCP_DEV_MASK` | `(1 << DEV_SHIFT) - 1` |
| `CONFIG_RBCP_LANE_OFF` | CPU byte offset of this device's lane within one bus cycle |
| `CONFIG_RBCP_ENDIAN_XOR` | 1 where host byte order within a cycle opposes the spec's data-line assignment |

Two formulae:

```
cpu_addr(command byte) = CMD_PAGE_ABS + (byte << BUS_SHIFT)

cpu_addr(region byte N) = BCH_ABS
                        + ((N >> DEV_SHIFT) << BUS_SHIFT)   ; which bus cycle
                        + LANE_OFF                          ; which device
                        + ((N & DEV_MASK) EOR ENDIAN_XOR)   ; byte within it
```

### Configurations

|  | `BUS_SHIFT` | `DEV_SHIFT` | `DEV_MASK` | `LANE_OFF` | `ENDIAN_XOR` |
|---|---|---|---|---|---|
| One ×16 device, 16-bit bus (A500) | 1 | 1 | 1 | 0 | 1 |
| Two 8-bit devices, 16-bit bus — high lane | 1 | 0 | 0 | 0 | 0 |
| …low lane | 1 | 0 | 0 | 1 | 0 |
| Two ×16 devices, 32-bit bus — high word | 2 | 1 | 1 | 0 | 1 |
| …low word | 2 | 1 | 1 | 2 | 1 |
| Four 8-bit devices, 32-bit bus — lane L | 2 | 0 | 0 | L | 0 |

Only row 1 is implemented and exercised. Rows 2–6 are phase 2; they are recorded now because retrofitting them would mean touching every access again.

### Multi-device semantics (phase 2)

Worked through and agreed, not yet implemented:

- Address lines are shared, so **every device decodes every knock and every command**. Commands are broadcast.
- Each device maintains its **own complete** back-channel header inside its own slot. The headers **interleave** in CPU address space at the bus stride — they are not split or merged.
- Completion is **per-device and unsynchronised**. A host must poll every lane's header before treating a command as complete. The current library polls one lane and is correct only for a single-device bus.
- `SWITCH_AND_EXIT` has no back-channel, so on a split ROM the halves change under the CPU at different instants. The trampoline must already be resident in RAM and touch no ROM until every device has settled.
- **A host cannot rely on addressing one device in isolation.** `/UDS` and `/LDS` never reach a single ×16 ROM (its chip select comes from the address decoder and it drives all 16 data lines every cycle); they reach a pair of 8-bit ROMs only if that board happens to wire them so; and they do not exist on 68020 and later, where byte strobes are synthesised by external glue. Broadcast is the design assumption.

---

## What was wrong in the previous implementation

Recorded so it is not reintroduced.

| Defect | Was | Now |
|---|---|---|
| Command page computed from the byte address | `$3FE` — out of range for a 256 KB ×16 ROM (17 word lines, max `$1FF`), so `ENTER_CMD_RESP` would be silently discarded | `$1FF`, derived |
| Back-channel offsets unswapped | token `+$02`, progress `+$04`, response `+$05` | `+$03`, `+$05`, `+$04` |
| ROM data referenced PC-relative from RAM-resident code | `LEA font_data(PC),A0` and every `LEA str_*(PC),A0` — displacement computed at the ROM assembly address, executed from `$8000`, resolving to garbage | `LEA (label).L,A0`, verified as `41F9` absolute long in the listing |
| `LSL #1` justified as "A-1/A0 not used" | Right shift, wrong case — that is the *byte-select-not-observed* case | Documented as word-addressing |
| Stale comments | Claimed back-channel at `$FFFD00`, command page at `$FFFF00` | Match the code |
| `RBCP_SUPPORTED_PATCH` | 0 | 1 (spec is 0.1.1) |

---

## Design decisions worth keeping

**The token is never read as a word.** `spec/rbcp.md` guarantees atomicity only for individual byte writes and directs a host wanting the full u16 to read high / read low / read high and retry. The polling sequence needs only the LSB, which is one atomic byte read. On a ×16 device the two token bytes are not even adjacent in CPU address space. A word read there would *look* correct — the big-endian pair happens to reassemble into the right little-endian value — which is exactly why it's a trap.

**All RBCP code runs from RAM.** Instruction fetches from the ROM under test put their own addresses on the bus, and outside command-response mode the device treats every address read as command data. The image contains a RAM section copied to `$8000` before any RBCP traffic. Branches within it are PC-relative and survive the move; references out of it use absolute long.

**`screen_putchar` reads the font from ROM**, so it must never be called between the knock and the response to `ENTER_CMD_RESP`. After entry the device filters on the command page and ROM reads elsewhere are harmless.

**Explicit `.L` on high addresses** also prevents the assembler shortening to sign-extended absolute short, which works on a 68000's 24-bit bus but not on a 32-bit one.

---

## Verification performed

Assembly-time only. No hardware.

- Builds clean at both 256 KB and 512 KB (`CONFIG_ROM_KB`), correct image sizes.
- Derived symbols checked against hand-derivation via the assembler listing:
  - 256 KB: base `$FC0000`, command page `$1FF`, back-channel start `$3FC00`
  - 512 KB: base `$F80000`, command page `$3FF`, back-channel start `$7FC00`
  - Header CPU addresses: GRP `+1`, CMD `+0`, token LSB `+3`, progress `+5`, response `+4`
- Instruction encodings confirmed in the listing: `E349` (`LSL.W #1,D1`), `1039` (byte reads at the swapped absolute addresses), `41F9` (absolute long `LEA`, never `41FA`).
- Both build-time assertions confirmed to fire, by deliberately breaking each: `$AA` sentinel, misaligned back-channel start.
- Reserved regions zero-filled in the image at the right offsets; `onerom image swap-bytes` confirmed to be a true byte swap.

---

## How to tell milestone 1 works

Write **`build/amiga_boot_swapped.bin`** to the device — not `amiga_boot.bin`. The device must serve it as a 256 KB ×16 ROM (`27C200`) for the default `CONFIG_ROM_KB EQU 256`, or `27C400` for 512.

### The decisive test

The AFTER dump's first eight bytes should read:

```
01 00 xx xx CC BB 00 00
```

`CMD`, `GROUP`, token MSB, token LSB, response, progress, reserved — every pair transposed. If instead it reads:

```
00 01 xx xx BB CC 00 00
```

the mapping is inverted and the fix is one constant: `CONFIG_RBCP_ENDIAN_XOR EQU 0`. Everything else re-derives. **You will reach this via a stage 1 failure, not a success** — with the mapping inverted the token poll reads the MSB, which is `$00` and never changes.

### Decision tree

| Symptom | Meaning |
|---|---|
| No display, no border colour changes | CPU never ran — wrong image written (swap direction) |
| Purple border | Unexpected exception |
| Title screen appears | RAM copy, absolute-long addressing and font reads all work |
| BEFORE dump not all zero | Back-channel region isn't where the config says, or the wrong image is on the device. No protocol conclusion after this is trustworthy |
| Stage 1, AFTER dump all zeros | Device accepted nothing — command stride, command page, or silent discard |
| Stage 1, AFTER dump non-zero | Device responded, we're reading the wrong bytes — the inverted-mapping signature |
| Stage 2 | Token moved but progress never reached `$BB`. Token and progress share parity, so a mapping error would kill both — points at the sentinel value |
| Stage 3 | Device processed and reported failure — back-channel too large for the RAM slot, or already in command-response mode |
| "OK: ENTERED" then NOP fails | Entry succeeded but the device is filtering on a different command page. In-range but wrong page produces exactly this |

Border colours before the screen comes up: red → white → green → blue → yellow, then green in `boot_ram_entry`.

---

## Next steps

1. **Runtime back-channel mapper.** The blocker for everything else. Fixed header offsets are resolved at assembly time, but a linear index into the response data section is *not* a linear CPU offset, so variable-length reads (device type, version, slot records, NV peek) need a runtime address computation, plus a copy helper that un-swaps a region into a RAM buffer so existing linear string code works on it. `rbcp_defs.s` notes where this goes. `CONFIG_RBCP_DEV_SHIFT` may be 0, and `LSR #0` is not encodable on the 68000 — use conditional assembly.
2. Protocol version check, `GET_RAM_SLOT_INFO_ALL`, `GET_FLASH_SLOT_INFO_ALL`, device type/version.
3. Menu, keyboard and LMB input. `kbd_init` and the key/scancode constants are already present and unused.
4. NV last-slot memory.
5. Boot switch: `SWITCH_AND_EXIT` plus the chip RAM trampoline at `$0400` (address reserved in `amiga_defs.s`).

Loose ends:

- `font_8x8_swapped.bin` is a leftover from the wrong byte-order model. The whole image is swapped on the way to the device, so the CPU sees natural order everywhere and a pre-swapped font is wrong. Left in place rather than deleted; it should go.
- The copper list is NTSC (`DIWSTOP $F4C1`). The PAL variant is no longer present as a comment. Make it switchable if PAL is wanted.

---

## Accompanying specification change

`spec/rbcp.md` gained a **non-normative** section, *Using RBCP on a Host Wider Than the Device*, committed alongside this implementation. It covers:

- The two address mappings — one for command signalling, one for the back-channel — and the four installation properties that parameterise them.
- The table of installations, and a worked 68000 example carrying the `$1FF` command page and the transposed header offsets.
- The warning that a linear index into the response data section is not a linear host address offset.
- Multi-device buses: commands are broadcast; each device maintains its own complete header; headers interleave rather than merge; completion is per-device and must be polled per lane; `SWITCH_AND_EXIT` skews across devices; a host should not assume it can address one device in isolation.

It is non-normative because none of it constrains a device — a device cannot observe how wide the host's bus is or how many peers it has — and the pin assignment it derives from is already normative. It is guidance for host authors, and its absence is what let the previous 68K implementation be written wrongly and still look plausible.

The spec section and this implementation are two expressions of the same model. **If one changes, change the other.** The spec's `BUS_STRIDE` / `DEV_BYTES` / `LANE_OFFSET` / `ENDIAN_SWAP` are the code's `CONFIG_RBCP_BUS_SHIFT` / `CONFIG_RBCP_DEV_SHIFT` + `DEV_MASK` / `CONFIG_RBCP_LANE_OFF` / `CONFIG_RBCP_ENDIAN_XOR`; the code uses shifts because they assemble to single instructions.
