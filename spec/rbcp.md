# ROM Bus Control Protocol (RBCP)

Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

Version: 0.1.2

This specification may be freely implemented without restriction.

---

## Introduction

The ROM Bus Control Protocol (RBCP) is a communication protocol that allows a host computer to control a device fitted in a ROM socket, using the ROM address and data buses as the communication medium.

The host encodes commands as sequences of ROM address reads. The device decodes these and acts on them. In [command-response mode](#command-response-mode), the device writes responses into a region of the ROM address space, which the host reads back as ordinary ROM data.

RBCP is defined independently of any specific device or host architecture. It may be implemented by any device capable of monitoring the address bus and serving data on the data bus — including microcontrollers, CPLDs (Complex Programmable Logic Devices), and FPGAs. A specific device implementation's device-side code is common across all host platforms and architectures that target it. Host-side implementations will differ per platform and architecture.

---

## Motivation

### Why a ROM Bus Protocol?

ROM emulators have historically been passive devices: the host reads from them and they serve data. RBCP extends this relationship to allow bidirectional communication, enabling use cases such as:

- **Kernal bootloaders:** a ROM emulator serving a custom kernal that allows the user to select and switch between multiple stored ROM images at runtime, without a power cycle.
- **Runtime ROM patching:** a host application that instructs the ROM emulator to modify the contents of the ROM image being served, for example to patch bugs or inject new behaviour.
- **Data streaming:** transferring data between the host and an external interface (such as USB) connected to the ROM emulator, using the ROM bus as the transport.

### Why This Protocol?

The ROM bus imposes significant constraints. The host can only communicate with the device by performing ROM address reads — it cannot write to a ROM (as there is no write line), and the device cannot assert any signal lines on the host. Any protocol must therefore work within these constraints.

RBCP is designed around the following principles:

- **No additional hardware:** communication uses only the lines already present in the ROM socket. No additional connections to the host are required.
- **Minimal host complexity:** the host need only perform ROM address reads and data reads. This is achievable in assembly language on any architecture that can access ROM.
- **Robustness over efficiency:** the [knock](#session-initiation--the-knock) provides a flexible and reliable session initiation mechanism, and [command framing](#command-framing) is kept simple and consistent.
- **Architecture independence:** RBCP makes no assumptions about the host CPU, address space layout, or available instructions beyond the ability to perform ROM reads.

---

## Terminology

**Host:** The computer the device is fitted in, whose ROM socket the device occupies and whose address and data lines carry RBCP. The host initiates every session. Where this specification says host, it means this computer, and never a computer attached to the device by any other interface.

**Device:** The implementation occupying the host's ROM socket, which decodes RBCP commands from the address lines and serves data on the data lines.

**Session:** A single interaction between the host and device, initiated by a knock. In command mode, each command constitutes its own session. In command-response mode, a session spans from the knock through to the host exiting command-response mode.

**Knock:** The sequence of ROM address reads that initiates a session. The device detects the knock by monitoring A0–A7 and uses it to establish framing.

**Slot:** A fixed-size region of storage containing a ROM image. Two categories of slot are defined: flash slots, which are persistent storage locations on the device, and RAM slots, which are volatile working buffers from which the device actively serves ROM data to the host. A ROM image must be loaded from a flash slot into a RAM slot before it can be served, and one is typically loaded into RAM by the device at boot time.  Different devices may have different slot sizes, counts and supported ROM types. The host discovers the available slots and their properties by issuing commands in command-response mode.

**Active slot:** The RAM slot currently being served to the host as ROM data.

**Command page:** A 16-bit value specifying which upper address bits the device uses to filter command bytes during command-response mode. The device treats only address reads whose upper address bits (above A7) match the command page as command bytes. Outside command-response mode, the command page has no effect.

**Back-channel region:** A structured region within the active RAM slot, maintained by the device during command-response mode, through which the device communicates response data to the host. The host reads this region as ordinary ROM data.

**Response header:** The first 8 bytes of the back-channel region, present in all configurations. Contains the token, progress, response, and last-command fields.

**Response data section**: The portion of the back-channel region immediately following the response header, beginning at offset 8. Contains command-specific response data. Its size is the back-channel region size minus 8 bytes.

**Token:** A monotonically incrementing counter in the response header, incremented by the device on receipt of each command. Used by the host to detect that a command has been received.

**Progress:** A boolean field in the response header indicating whether the device has completed processing the most recently received command. Takes one of two states: complete or pending.

**Response:** A boolean field in the response header indicating whether the most recently completed command succeeded. Takes one of two states: status-OK or failed.

**Complete / Pending:** The two states of the progress field. The complete value and its bitwise inverse (pending) are either protocol defaults or configured by the host via ENTER_CMD_RESP.

**Status-OK / Failed:** The two states of the response field. The status-OK value and its bitwise inverse (failed) are either protocol defaults or configured by the host via ENTER_CMD_RESP.

**Pipe:** An ordered sequence of bytes between the host and a far end, relayed by the device. Carries one direction or both, and is addressed by a single-byte number.

**IN / OUT:** The two directions a pipe may carry, named from the host's point of view, as USB names its endpoint directions. OUT is host to device — the host writes and the device drains. IN is device to host — the device fills and the host reads. The reference point is the host in both cases: an IN pipe carries bytes into the host, not into the device.

**Far end:** What the device relays a pipe to and from. A pipe runs from the host, through the device, to its far end.

---

## Versioning and Compatibility

RBCP uses semantic versioning (major.minor.patch). The current version is indicated at the top of this document. A version is stable when it has been tagged in the GitHub repo and published as a GitHub release.

During the 0.x.y series, minor version increments may introduce breaking changes. A host implementation written against version 0.Y.z is guaranteed to interoperate correctly with any device implementing version 0.Y.w where w >= z.

From version 1.0.0 onwards, major version alone defines the compatibility contract. A host written against version X.Y.z is guaranteed to interoperate correctly with any device implementing version X.W.w where W > Y or (W == Y and w >= z).

Patch increments are backwards-compatible. A device implementing version X.Y.w is guaranteed to support all behaviour defined by version X.Y.z where z <= w.

A host should query the device version using GET_PROTOCOL_VERSION and reject a device whose version falls outside the bounds it was written for.

Every command group, and every command within a group, carries the version that introduced it in the Since column of the [command groups](#command-groups) table and of each group's command table. A host must not issue a command whose Since value exceeds the version the device reports.

The two cases behave differently if it does. A group the device does not implement at all can be probed, because every group introduced after 0.1.1 carries a zero-argument discovery command at its lowest CMD value. A command added to a group the device does implement cannot — see [Unknown GROUP and CMD](#unknown-group-and-cmd).

---

## Physical Medium

RBCP operates over the ROM bus. The relevant lines are:

- **Address lines:** carry host-to-device data. The host encodes commands as sequences of ROM address reads. The device captures these by monitoring the address bus. The least significant 8 bits of the address lines (A0–A7) carry RBCP command data. The mapping from a host's read address to these command lines varies by ROM and device; see [Address Line Presentation](#address-line-presentation). In command mode, upper address bits are ignored by the protocol. In command-response mode, the device uses the upper address bits to filter command bytes: only address reads whose upper address bits match the configured [command page](#command-page) are treated as command bytes. This ensures compatibility with the smallest ROM types — the 2704 (4Kbit, 512 bytes) has only 9 address lines. Future versions of the protocol may utilise additional address bits.
- **Data lines:** carry device-to-host data. The device writes response data into a designated region of ROM address space; the host reads this back as ordinary ROM data reads.
- **CS (Chip Select):** defines valid bus cycles. The device captures address values only when all CS lines are active. The exact CS lines present depend on the ROM socket standard in use — for example /CE and /OE on a 27C512, or /CS on a 2364. Devices should implement a debounce algorithm to avoid false triggering on noisy or poorly behaved bus implementations.

Future versions of the protocol may utilise additional ROM bus lines for signaling, including R/W, /WE, /BYTE, and address latch signals such as /AS, where these are present in the target ROM socket.

The electrical characteristics of all bus lines are defined by the ROM socket standard in use. RBCP inherits these definitions and does not redefine them.

All multi-byte values in RBCP are little-endian.

### Address Line Presentation

RBCP command data — the knock, command bytes, and the command page — is carried
on the address lines the device observes at the ROM socket. In this document,
A0–A7 denotes the eight least-significant of those *observed* lines: to send a
command byte the host reads at an address whose observed A0–A7 equal the byte's
value, and successive command bytes advance the least-significant observed line
(A0) by one. How that maps onto the host's own read address depends on the ROM
and the device:

- **Byte-organised ROM, all address lines observed.** A0 is the ROM's
  least-significant address line; the host advances its read address by one per
  command byte.
- **Word-organised (×16) ROM, addressed as words.** The observed lines are the
  ROM's word address lines and A0 is the least-significant word line; the host
  advances its read address by one word per command byte.
- **A ROM whose least-significant address line the device does not observe.**
  The observed A0 is the ROM's *next* address line up, the ROM's
  least-significant line carries no command information, and the host advances
  its read address by two per command byte. This arises where that line is not
  observable at command-capture rate — for example the byte-select of a ×16 ROM
  the host reads a byte at a time (it is not a word address line), or a byte
  ROM whose least-significant line is routed, on a given device, to a pin the
  device cannot sample.

Which case applies is a static property of the device for a given emulated ROM
type. It cannot be discovered through RBCP — the knock must already be framed
correctly to begin any session — so, like the knock sequence, it must be agreed
in advance between the device and every host implementation targeting it.

This affects only the host-to-device (command) direction. The back-channel is
read as ordinary ROM data and is unaffected by which address lines the device
observes; how its bytes are presented on a word-organised ROM is covered under
[Back-Channel on a Word-Organised ROM](#back-channel-on-a-word-organised-rom).

#### Back-Channel on a Word-Organised ROM

The back-channel region is always a region of bytes at a byte offset within the
active RAM slot, whatever the organisation of the ROM being served.

On a byte-organised ROM, or on a word-organised ROM the host reads a byte at a
time, the host reads back-channel byte N at the ROM address carrying that byte.

On a word-organised (×16) ROM read as words, each word carries two consecutive
bytes of the region: the byte at an even offset on D0–D7, and the byte at the
next, odd offset on D8–D15. To read back-channel byte N the host therefore reads
word N/2, taking D0–D7 if N is even and D8–D15 if N is odd.

The 4-byte alignment required of the back-channel start address guarantees that
offset 0 of the region — and therefore every even offset — falls on D0–D7.

The data lines are named here, rather than "the low byte of the word", because
those are not the same statement on every host: a host whose word byte ordering
differs from the ROM's data pin ordering must account for that difference
itself. The pin assignment above is normative.

#### Examples (non-normative)

- A **2364** (8 KB, 8-bit) is a byte ROM: the device observes all of A0–A12,
  A0 is its least-significant line, and command bytes are one byte apart.
- A **27C400** (512 KB, ×16) **read as 16-bit words** — as a 68000-based system
  reads it — presents word lines A0–A17; A0 is the least-significant word line
  and command bytes are one word apart.
- The same **27C400 read one byte at a time**, the host asserting `/BYTE`,
  presents a byte-select (A-1) below word A0. A device that observes only the
  word lines does not see A-1, so command bytes are two byte-addresses apart and
  A-1 carries no command data.
- An **8-bit 40-pin mask ROM** whose least-significant address line is routed,
  on a given device, to a pin it cannot sample at command-capture rate: the
  device observes from the ROM's second line up, so command bytes are two
  byte-addresses apart and the ROM's A0 carries no command data.

**Device example (non-normative).** On its 40-pin hardware variant, the One ROM
host-control plugin does not observe the least-significant address line of the
8-bit ROMs it serves, so a host advances its read address by two per command
byte for those ROMs. A 16-bit ROM on the same hardware is addressed by word and
uses the word address lines directly.

---

## Using RBCP on a Host Wider Than the Device (non-normative)

This section is guidance for host implementers. It introduces no requirements.
Everything in it is derived from [Address Line
Presentation](#address-line-presentation), [Back-Channel on a Word-Organised
ROM](#back-channel-on-a-word-organised-rom) and the [Response
Header](#response-header). A device cannot observe how wide the host's bus is,
nor how many other devices share it, so nothing here constrains a device
implementation.

Where the host's bus is the same width as the device — an 8-bit CPU reading an
8-bit ROM — the protocol's terms and the host's own terms coincide: the lines
the device observes are the host's address lines, and a byte offset within the
device's slot is a byte offset in the host's address space. Neither coincidence
survives a host whose bus is wider than the device serving it. A 16-bit host
reading a word-organised ROM, a 16-bit host reading a pair of 8-bit ROMs, and a
32-bit host reading two word-organised ROMs are all in this position.

Two mappings are then required, and they are not the same mapping. Both can be
expressed in terms of four properties of the installation, all of them static:

| Property | Meaning |
|----------|---------|
| `BUS_STRIDE` | Host address bytes spanned by one device bus cycle |
| `DEV_BYTES` | Bytes the device supplies per bus cycle (1 for an 8-bit device, 2 for ×16) |
| `LANE_OFFSET` | Host byte offset, within one bus cycle, of the lane this device drives |
| `ENDIAN_SWAP` | Whether the host's byte ordering within a bus cycle opposes the data-line assignment |

### Sending a command byte

The device's observed A0 is the host address line immediately above whatever
lines select a byte within a bus cycle. One command byte therefore advances the
host's read address by one full bus cycle:

```
host_address(command_byte) = command_page_base + command_byte * BUS_STRIDE
```

The same conversion applies to the command page itself. The command page is the
observed address bits above A7, and the observed lines are the device's — so a
host holding a host-relative offset must divide by `BUS_STRIDE` before taking
the page number. Using the host's own byte-address page instead is a common
error, and on a device with few enough address lines it produces a page value
outside the range the ROM type permits, which ENTER_CMD_RESP silently discards.

### Reading the back-channel

The back-channel is a region of device bytes. Region byte N appears at:

```
host_address(N) = back_channel_base
                + (N / DEV_BYTES) * BUS_STRIDE      // which bus cycle
                + LANE_OFFSET                        // which device on the bus
                + swap(N mod DEV_BYTES)              // which byte within it
```

where `swap(k)` is `k` when `ENDIAN_SWAP` is false, and `DEV_BYTES - 1 - k`
when it is true.

`ENDIAN_SWAP` exists because the pin assignment is normative while host byte
ordering is not. The specification places the even region offset on D0–D7 and
the odd offset on D8–D15; a big-endian host reads the byte at an even address
from the *upper* half of the bus, so on such a host the two bytes of every
device word appear at the opposite host addresses to their region offsets. A
little-endian host of the same width needs no swap. This is the difference the
[back-channel section](#back-channel-on-a-word-organised-rom) requires the host
to account for; naming it as a parameter is simply a way of accounting for it
once.

A consequence worth stating plainly: a linear index into the response data
section is not a linear host address offset. Reading a name, a version string
or a block of peeked bytes with a simple incrementing pointer is correct only
where `DEV_BYTES` is 1 and `LANE_OFFSET` is 0.

### Parameters by installation

Assuming a big-endian host:

| Installation | `BUS_STRIDE` | `DEV_BYTES` | `LANE_OFFSET` | `ENDIAN_SWAP` |
|--------------|--------------|-------------|---------------|---------------|
| 8-bit host, 8-bit device | 1 | 1 | 0 | no |
| 16-bit host, one ×16 device | 2 | 2 | 0 | yes |
| 16-bit host, two 8-bit devices — upper lane | 2 | 1 | 0 | no |
| …lower lane | 2 | 1 | 1 | no |
| 32-bit host, two ×16 devices — upper word | 4 | 2 | 0 | yes |
| …lower word | 4 | 2 | 2 | yes |
| 32-bit host, four 8-bit devices — lane L | 4 | 1 | L | no |

### Worked example

A 68000-based system reads a 256 KB word-organised Kickstart ROM mapped at
`$FC0000`, with the command page and a 512-byte back-channel placed in the last
1 KB of the image. `BUS_STRIDE` is 2, `DEV_BYTES` is 2, `LANE_OFFSET` is 0, and
`ENDIAN_SWAP` is true.

The command page is at host address `$FFFE00`, a host-relative offset of
`$3FE00`. Dividing by `BUS_STRIDE` gives device bus cycle `$1FF00`, so the
command page sent in ENTER_CMD_RESP is `$1FF` — not `$3FE`, which is what the
host-relative offset alone would suggest, and which exceeds the range a ROM with
17 word address lines permits.

The back-channel is at host address `$FFFC00`, host-relative `$3FC00`, giving a
device byte offset of `$3FC00` — the same number here only because `BUS_STRIDE`
and `DEV_BYTES` are equal.

The response header then appears at these host addresses:

| Field | Region offset | Host offset |
|-------|---------------|-------------|
| Last command GROUP | 0 | +1 |
| Last command CMD | 1 | +0 |
| Token LSB | 2 | +3 |
| Token MSB | 3 | +2 |
| Progress | 4 | +5 |
| Response | 5 | +4 |

Note that the two token bytes are not adjacent, and that the pair is
transposed. A host that reads the token as a single 16-bit big-endian value
obtains the correct little-endian result by coincidence — and must still not do
so, because the [response header](#response-header) guarantees atomicity only
for individual byte writes.

### Several devices on one bus

Where the host's bus is filled by more than one device, the address lines are
shared between them. This has consequences a host must design for.

**Commands are broadcast.** Every device whose chip select is asserted decodes
the same knock, the same GROUP and CMD, and the same argument bytes, and acts on
all of them. For a ROM image split across devices this is usually what is
wanted: one LOAD_SLOT loads the corresponding image into every half, and one
SWITCH_AND_EXIT switches them together.

**Each device maintains its own complete back-channel.** The back-channel is a
region within the device's own slot, so every device writes a full 8-byte
response header, and those headers interleave in host address space at
`BUS_STRIDE` — they are neither split across devices nor merged. A host reads
one device's header by holding that device's `LANE_OFFSET` throughout; mixing
lanes within a single header reads fields from different devices.

**Completion is per-device and unsynchronised.** Each device runs its own copy
of the [command processing sequence](#command-processing-sequence) on its own
schedule. A host that polls one lane learns only that one device has finished. A
host on such a bus should poll every lane's token and progress, and treat a
command as complete only when the last of them reports completion.

**SWITCH_AND_EXIT has no completion to poll.** On a split ROM the halves
therefore become active at slightly different instants, and there is an interval
during which the host would fetch from a partly-switched image. Host code
running across that interval must already be resident in RAM and must not touch
the ROM until every device has settled.

**A host should not assume it can address one device in isolation.** It is
tempting to reach a single lane with a narrower access, but whether that works
is a property of the installation rather than of the host architecture. A single
word-organised device is selected by an address decode and drives its full width
on every cycle, so a narrower read is indistinguishable to it. Several narrow
devices may or may not have their chip selects gated per lane, depending on how
the board is wired. Some host architectures provide no per-lane strobes at all.
Treating commands as broadcast is the assumption that holds in every case.

---

## Modes

RBCP defines five operational modes. Two are currently specified; three are reserved for future definition.

| Mode | Description |
|------|-------------|
| **Command** | Host sends commands to the device. No back-channel. No confirmation possible. |
| **Command-Response** | Host sends commands; device responds via a designated region of ROM address space. Turn-based. |
| **Out-Stream** | Host streams data continuously to the device. |
| **In-Stream** | Device streams data continuously to the host via ROM address space. |
| **Bi-Stream** | Both directions streaming simultaneously and independently. |

Out-Stream, In-Stream and Bi-Stream are reserved for future definition. Their definitions, including any protocol changes required to support them, are subject to change.

When operating in Command mode:
- Every command is a separate session, framed by a knock. The device processes each command immediately on receipt and does not maintain any state between commands.
- There is no back-channel, so the device cannot acknowledge receipt or indicate success or failure. The host must assume that any well-formed command was received and is being processed, and that any malformed command was not received.
- As the device is unable to confirm completion of a command, the host should allow a reasonable amount of time for the device to process each command before issuing the next one. What constitutes a reasonable amount of time is currently left to a device implementation and may vary by command.  For this reason, Command-Response mode is much preferred where possible. 

---

## Communication Initiation - Resetting the Device

While not strictly necessary, particularly if a device was powered on at the same time as a device, it is highly recommended to reset the device before initiating communication. This ensures that the device starts in a known state and can help prevent synchronization issues which can be caused by the host reseting mid-communication.  While this reset is unlikely to be completely foolproof (no host-initiated reset can be), this significantly reduces the likelihood of failure to synchronize at the start of a communication.

The recommended reset sequence is:
1. Issue the RBCP_RESET command 5 times in succession (10 bytes), with no knock in-front or in-between them.
2. Pause to allow the device to complete any in-progress command. The amount of time required is implementation-specific.
3. Issue a single RBCP_RESET.
4. Pause to allow the device to reset.  The amount of time required is implementation-specific, but a reset is likely to be a fast operation on the device.
5. Issue a knock followed by an RBCP_RESET.
6. Pause to allow the device to reset.  The amount of time required is implementation-specific, but a reset is likely to be a fast operation on the device.

The maximum argument count for any command is 9 (ENTER_CMD_RESP). If the device is mid-argument collection, the 5 RBCP_RESET transmissions (10 bytes) are sufficient to flush any outstanding argument bytes and trigger execution of whatever command was in progress. The pause in step 2 allows that command to complete. The RBCP_RESET in step 3 then resets a now-idle device. The knock and final RBCP_RESET in step 5 ensure that the device resets if it was originally in command mode.

The group and command bytes of RBCP_RESET are deliberately chosen to be mode unique across all commands, and identical to each other, meaning that whether the device was expecting a group or command byte next, it will receive the reset group or command value.

As the RBCP_RESET command uses a value of 0xAA for the group and command bytes, to allow the device to identify if an RBCP_RESET has potentially been started mid command, values of 0xAA are invalid in all last command arguments.  If a device received a command with the final argument set to 0xAA, it rejects the command.  Argument ordering is used to avoid cases where a final argument might need to take a value of 0xAA.

For this reset to work it is crucial that the reset is issued using the command page — if the device was in command-response mode, it is filtering command bytes using the command page, and will ignore any command bytes that do not match that page.

---

## Session Initiation — The Knock

Every RBCP session begins with a knock sequence: a series of contiguous ROM address reads whose low-order address bits (A0–A7) match a predefined pattern. The device detects this pattern by monitoring the address bus.

The knock sequence is variable in length and is defined by the device implementation. It must be agreed between the device and all host implementations targeting it. The sequence should be long enough to make accidental activation statistically negligible — for example, a 6-character ASCII sequence such as `!RBCP!` encoded in A0–A7.

The knock precedes every session, including re-entry after exiting command-response mode.

---

## Command Framing

All commands share the same frame structure:

```
[GROUP] [CMD] [A0] [A1] ... [An]
```

- **GROUP** (1 byte): functional group identifier
- **CMD** (1 byte): command identifier within the group
- **A0, A1, ... An**: argument bytes, each 1 byte, transmitted in the order listed. The count is fixed per GROUP+CMD pair.

There is no length field in the frame. Both host and device use a per-command definition to determine how many argument bytes follow GROUP and CMD. Where a command requires fewer arguments than the maximum, no padding is required.

### Command Mode Constraint

In command mode there is no back-channel and therefore no confirmation. If the host and device lose sync, the device will continue to consume address reads as argument bytes of the current partially-received command until that command's expected argument count is satisfied, before it can detect a new command or knock. Only after all expected bytes of the interrupted command have been consumed can a new knock re-establish session framing. Host implementations must take care to issue well-formed command sequences.

The maximum argument count for any command defined by this version of the protocol is 9 (ENTER_CMD_RESP). For future extensibility, a host recovering from desync in command mode need transmit at most 10 additional address reads before a knock can re-establish framing. Future versions of the protocol will not exceed this maximum without incrementing the protocol version.

A command refused because it is not valid in the current mode is nonetheless framed like any other: the device consumes its argument bytes before discarding it. A device that discarded such a command without taking its arguments off the wire would leave those bytes to be read as the next command frame, desynchronising a host that had done nothing malformed. The command has no other effect.

### Unknown GROUP and CMD

The rule above applies to a command the device knows but cannot accept. A device that receives a GROUP or CMD it does not implement at all is in a different position: argument counts are defined per GROUP+CMD pair, so a device with no definition for the pair cannot know how many argument bytes follow. It therefore consumes **no** argument bytes. In command-response mode it completes the normal [command processing sequence](#command-processing-sequence) with response = failed. In command mode it has no means of reporting anything.

The consequence for a host is that an unknown command taking no argument bytes fails cleanly — the token increments, response = failed, and the session remains correctly framed — while an unknown command taking one or more argument bytes desynchronises the session, the host's argument bytes being consumed as the following frame's GROUP, CMD and arguments. The host has no way to detect this, and the frames it sends afterwards are decoded as commands it did not issue.

Every command group introduced by a version of this specification later than 0.1.1 must therefore include a discovery command that takes zero argument bytes, and that command must be assigned the lowest CMD value in the group. A host must issue that discovery command, and observe success, before issuing any argument-taking command from the group. This allows a host written against a later version of the specification to probe a device implementing an earlier one without desynchronising it. Placing the command at the lowest CMD value makes the probe mechanical — CMD 0x00 of any group is the safe one to issue — rather than something a host must look up per group.

The discovery command covers a group added by a later version, not a command added to a group that already exists. The group's own discovery command succeeds on a device that lacks the newer command, so it distinguishes nothing, and an argument-taking command the device does not know desynchronises the session as described above. The version check in [Versioning and Compatibility](#versioning-and-compatibility) is the only protection.

A host may instead establish which groups a device implements from the version reported by GET_PROTOCOL_VERSION. In command mode there is no response of any kind, so no discovery is possible at all, and a host must rely on a version obtained during an earlier command-response session, or on knowledge held out of band.

---

## Command Groups

| Group | Name | Since | Valid Modes | Description |
|-------|------|-------|-------------|-------------|
| 0x00 | Control | 0.1.0 | Command, Command-Response | Session and mode management |
| 0x01 | Read | 0.1.0 | Command-Response only | Query the device for information |
| 0x02 | Modify | 0.1.0 | Command, Command-Response | Change device state |
| 0x03 | NV Storage | 0.1.0 | Command-Response only | Query and modify dedicated non-volatile storage on the device |
| 0x04 | Pipes | 0.1.2 | Command-Response only | Transfer bytes between the host and a pipe on the device |
| 0x05 | Auxiliary I/O | 0.1.2 | Command-Response only | Drive and read device pins that are not part of the ROM interface |
| 0xAA | Reset | 0.1.0 | Command, Command-Response | Reset the device's RBCP implementation |

The Since column gives the specification version in which a group was introduced. The command tables below carry the same column per command.

---

## Command Reference

### Group 0x00 — Control

Commands in this group manage the session and mode of the device. All commands in this group are valid in both command and command-response modes, except where noted.

| CMD | Name | Since | Args | Description |
|-----|------|-------|------|-------------|
| 0x00 | NOP | 0.1.0 | 0 | No operation. In command-response mode the device acknowledges via the standard header sequence, allowing the host to verify the device is alive and processing commands. |
| 0x01 | ENTER_CMD_RESP | 0.1.0 | 9: A0/A1=command page (16-bit LE), A2/A3/A4=back-channel start address (24-bit LE), A5/A6=back-channel size in bytes (16-bit LE), A7=complete, A8=status-OK | Configures command-response mode parameters and enters command-response mode. A0/A1 specify the command page: during command-response mode the device treats only address reads whose upper address bits match this value as command bytes. A2/A3/A4 specify the start address of the back-channel region within the active RAM slot; this address must be 4-byte aligned, and must leave room for at least the 8-byte [response header](#response-header) within the RAM slot — if it is not aligned, or if it does not leave that room (including where it lies outside the slot entirely), the device silently discards the command. A5/A6 specify the size of the back-channel region in bytes; if the requested size exceeds the available space in the RAM slot, the device returns failure. A7 is the boolean value the device will write to the progress field to indicate completion; its bitwise inverse indicates pending. A8 is the boolean value the device will write to the response field to indicate success; its bitwise inverse indicates failure. Neither A7 nor A8 may be 0xAA — if either is, the device silently discards the command. If the command page is out of range for the ROM type currently being served, the device silently discards the command. Not supported when in command-response mode — the device returns failure. The division between the two outcomes above follows from what the device can do: it returns failure where it has a back-channel to report one in, and silently discards the command where it does not. |
| 0x02 | EXIT_CMD_RESP_ACK | 0.1.0 | 0 | Exits command-response mode. The device completes the full command processing sequence, including setting progress = complete, before exiting command-response mode. The host should poll progress for complete as normal. Once complete is observed, the device has exited command-response mode and the back-channel region is no longer maintained.|
| 0x03 | EXIT_CMD_RESP_SILENT | 0.1.0 | 0 | Exits command-response mode without updating the [response header](#response-header). |
| 0x04 | SWITCH_AND_EXIT | 0.1.0 | 1: A0=slot | Activates the specified RAM slot and exits command-response mode silently. This command is terminal to the current control-response session. The device switches to the specified slot and exits command-response mode without updating the response header. The host must not poll the back-channel region after issuing this command — the device begins serving the new slot immediately and the previous back-channel region is invalidated. An A0 value of 0xAA is invalid.  If received the slot is NOT switched, but the exit DOES complete. |
| 0x05 | LOAD_AND_EXIT | 0.1.2 | 2: A0=RAM slot, A1=flash slot | As LOAD_SLOT, but exits command-response mode without updating the [response header](#response-header). Where the RAM slot named is the active one, this restores the whole of the served image, including the bytes the back-channel region occupies — see [Loading the Active Slot](#loading-the-active-slot). This command is terminal to the current command-response session. The host must not poll the back-channel region after issuing it. A0 or A1 values of 0xAA are invalid. If received the slot is NOT loaded, but the exit DOES complete. |
| 0x06 | EXIT_CMD_RESP_RESTORE | 0.1.2 | 9: A0-A7=bytes, A8=count | Writes count bytes, taken from A0 onwards, from the start of the back-channel region and exits command-response mode without further updating the [response header](#response-header). This lets the host put back the bytes the response header displaced. Bytes of the region beyond those this command writes are the host's to put back first, with SLOT_POKE — each such write dirties only the header, which this command then covers. This command is terminal to the current command-response session. The host must not poll the back-channel region after issuing it. Argument bytes beyond count are ignored by the device, but are still transmitted, as the argument count is fixed. All 256 values are valid in A0 to A7. A8 must be in the range 0x01 to 0x08. If it is not, no bytes are written, but the exit DOES complete. Not supported in command mode, where there is no back-channel region to write to — the device consumes the arguments and discards the command. |

CMD 0xAA is reserved and must never be assigned.

### Group 0x01 — Read

Commands in this group query the device for information. All commands in this group are valid in command-response mode only.

| CMD | Name | Since | Args | Description |
|-----|------|-------|------|-------------|
| 0x00 | GET_FLASH_SLOT_COUNT | 0.1.0 | 0 | Requests the device to write the total number of available (populated, non plugin or other special) flash slots available on the device into the first byte of the command-response region. See [GET_FLASH_SLOT_COUNT Response Format](#get_flash_slot_count-response-format). |
| 0x01 | GET_FLASH_SLOT_INFO | 0.1.0 | 1: A0=slot | Requests the device to populate the command-response region with information about the specified flash ROM slot. See [GET_FLASH_SLOT_INFO Response Format](#get_flash_slot_info-response-format). Only succeeds if there is sufficient space, which means a back channel size of at least 64 bytes. An A0 value of 0xAA is invalid and rejected. |
| 0x02 | GET_FLASH_SLOT_INFO_ALL | 0.1.0 | 0 | Requests the device to populate the command-response region with information about available (populated, non plugin or other special) flash ROM slots. This provides the entirety of the information exposed by GET_FLASH_SLOT_COUNT and GET_FLASH_SLOT_INFO in a single request response. See [GET_FLASH_SLOT_INFO_ALL Response Format](#get_flash_slot_info_all-response-format). |
| 0x03 | GET_RAM_SLOT_INFO_ALL | 0.1.0 | 0 | Requests the device to populate the command-response region with information about available RAM slots. See [GET_RAM_SLOT_INFO Response Format](#get_ram_slot_info-response-format). |
| 0x04 | GET_DEVICE_TYPE | 0.1.0 | 0 | Requests the device to write its type (e.g. One ROM) into the command-response region as ASCII. Unused bytes are filled with 0x00. Null-terminated. A device must provide a type. See [GET_DEVICE_TYPE Response Format](#get_device_type-response-format). |
| 0x05 | GET_DEVICE_VERSION | 0.1.0 | 0 | Requests the device to write its version (e.g. v1.0.0) into the command-response region as ASCII. Unused bytes are filled with 0x00. Null-terminated. A device must provide a version. See [GET_DEVICE_VERSION Response Format](#get_device_version-response-format). |
| 0x06 | GET_PROTOCOL_VERSION | 0.1.0 | 0 | Requests the device to write the RBCP protocol version it implements into the response data section. See [GET_PROTOCOL_VERSION Response Format](#get_protocol_version-response-format). |
| 0x07 | SLOT_PEEK | 0.1.0 | 5: A0=count, A1/A2/A3=24-bit address (little-endian), A4=slot | Requests the device to read one or more bytes from the specified RAM slot at the specified address and write them into the response data section. A count of zero indicates 256 bytes should be read. This command fails if there is insufficient space in the response data section to accommodate the requested bytes.  An A4 value of 0xAA is invalid and rejected. |
| 0x08 | GET_BOOT_SLOT_INFO | 0.1.2 | 0 | Requests the device to report which flash slot it loaded at boot, and which RAM slot it loaded that image into. See [GET_BOOT_SLOT_INFO Response Format](#get_boot_slot_info-response-format). |

CMD 0xAA is reserved and must never be assigned.

### Group 0x02 — Modify

Commands in this group change the state of the device. All commands in this group are valid in both command and command-response modes, except where noted.

| CMD | Name | Since | Args | Description |
|-----|------|-------|------|-------------|
| 0x00 | SLOT_POKE | 0.1.0 | 5: A0=byte, A1/A2/A3=24-bit address (little-endian), A4=slot | Writes a single byte into the specified RAM slot at the specified address. May be used for patching vectors or other known locations prior to activating that slot or entering command-response mode. The target slot need not be active. In fact, patching multi-byte values such as interrupt vectors should only be done to inactive slots. Because SLOT_POKE writes one byte at a time, there is no atomic write of a 16-bit value — a vector partially written to an active slot will be transiently inconsistent and will corrupt any interrupt that occurs between the two writes. The safe pattern is: LOAD_SLOT the target image into an inactive RAM slot, issue SLOT_POKE commands to patch any vectors in that inactive slot, then issue SWITCH_AND_EXIT to make it active. The vector bytes are consistent at the instant the slot becomes active.  An A4 value of 0xAA is invalid and rejected. |
| 0x01 | SWITCH_SLOT | 0.1.0 | 1: A0=slot | Activates the specified RAM slot. An A0 value of 0xAA is invalid and rejected. |
| 0x02 | LOAD_SLOT | 0.1.0 | 2: A0=RAM slot, A1=flash slot | Copies the specified ROM image from the slot on the ROM into the specified RAM slot. Does not activate the slot. Where the RAM slot named is the active one, see [Loading the Active Slot](#loading-the-active-slot). A0 or A1 values of 0xAA are invalid and rejected. |
| 0x03 | SLOT_POKE_ALL_BYTE | 0.1.0 | 2: A0=byte, A1=RAM slot | Fills the specified RAM slot with the specified byte. Does not activate the slot. An A1 value of 0xAA is invalid and rejected. |

CMD 0xAA is reserved and must never be assigned.

#### Loading the Active Slot

LOAD_SLOT and LOAD_AND_EXIT may name the active RAM slot, which the device continues to serve while the copy runs. Throughout the copy every address must present either its previous byte or its new byte, and never a third value. A device that clears the slot before copying into it does not meet this requirement.

The order in which the device writes the bytes is not specified, and a host must not rely on one. Only the value present at each address is constrained.

The host cannot detect a device that breaks this. It may read any address at any time, for any purpose, and a transient value it reads is indistinguishable from ROM content.

### Group 0x03 — NV Storage
 
Commands in this group allow the host to query and modify dedicated non-volatile storage on the device. All commands in this group are valid in command-response mode only.
 
NV storage is an optional device feature. The host should query GET_NV_CAPABILITY before issuing any other NV commands. A device that does not support NV storage returns a size of zero from GET_NV_CAPABILITY; all other NV commands return failure on such a device.
 
Write operations follow a transactional model. The host initiates a write transaction with NV_POKE_BEGIN, which loads the current NV storage contents into a RAM staging buffer. The host then issues one or more NV_POKE commands to modify individual bytes in the staging buffer. The transaction is resolved either by NV_POKE_COMMIT, which writes the staging buffer back to NV storage and frees it, or NV_POKE_DISCARD, which abandons all staged changes and frees the staging buffer. Only one write transaction may be in progress at a time.
 
For the common case of updating a single byte, NV_POKE_COMMIT_BYTE performs the full transaction — BEGIN, POKE, COMMIT — as a single command. It fails if a write transaction is already in progress.

A RAM slot must be provided by the host for the device to use as a staging area of the NV writes.  This means that any RAM slot specified will be overwritten by the device and should not be used for any other purpose while a write transaction is in progress.  If the device only supports a single RAM slot, it cannot perform multiple write transactions and hence GET_NV_CAPABILITY reports any NV storage as read-only.

NV_PEEK always reads directly from NV storage, regardless of whether a write transaction is in progress. This allows the host to inspect the actual state of NV storage after a failed commit — for example to verify what was written before deciding whether to retry NV_POKE_COMMIT or issue NV_POKE_DISCARD.
 
If command-response mode exits for any reason while a write transaction is in progress — whether via EXIT_CMD_RESP_ACK, EXIT_CMD_RESP_SILENT, SWITCH_AND_EXIT, or RBCP_RESET — the device silently discards the staging buffer. Exit commands are never rejected on account of an in-progress transaction. RBCP_RESET in particular must unconditionally discard any in-progress transaction, as it is a recovery mechanism. The host is responsible for issuing NV_POKE_COMMIT or NV_POKE_DISCARD before exiting command-response mode if staged changes are to be resolved cleanly.
 
The NV storage address space is a maximum of 32KB. The location MSB in NV_PEEK and NV_POKE encodes the upper address bits; values above 0x7F are invalid, causing the device to reject the command. This constraint ensures that 0xAA is always detectable as a reset signal in the final argument position of both commands.

Before having been written by any host, the entire NV storage on any device is initialized to 0xFF.

Care should be taken when running timers to police a response from the device for NV_POKE_COMMIT and NV_POKE_COMMIT_BYTE, as both of these commands is likely to involve the device erasing flash - which is a long (ms) operation.
 
| CMD | Name | Since | Args | Description |
|-----|------|-------|------|-------------|
| 0x00 | GET_NV_CAPABILITY | 0.1.0 | 0 | Requests the device to report its NV storage capabilities. See [GET_NV_CAPABILITY Response Format](#get_nv_capability-response-format). |
| 0x01 | NV_PEEK | 0.1.0 | 3: A0=count, A1=location_LSB, A2=location_MSB | Reads one or more bytes directly from NV storage at the specified location and writes them into the response data section. A count of zero indicates 256 bytes should be read. The location MSB must not exceed 0x7F; if it does, the device rejects the command. Always reads from NV storage, regardless of whether a write transaction is in progress. Fails if there is insufficient space in the response data section to accommodate the requested bytes, or if the requested range exceeds the NV storage size. |
| 0x02 | NV_POKE_BEGIN | 0.1.0 | 1: A0=RAM slot | Initiates a write transaction by loading the current NV storage contents into a RAM staging buffer, using the RAM slot specified. Fails if NV storage is not writable, if a write transaction is already in progress or if the RAM slot specified is invalid, active or too small. An A0 value of 0xAA is invalid and rejected. |
| 0x03 | NV_POKE | 0.1.0 | 3: A0=byte, A1=location_LSB, A2=location_MSB | Writes a single byte into a staging buffer using the specified RAM slotat the specified location. The location MSB must not exceed 0x7F; if it does, the device rejects the command. Fails if no write transaction is in progress, or if the location exceeds the NV storage size. |
| 0x04 | NV_POKE_COMMIT | 0.1.0 | 0 | Commits the staging buffer to NV storage and frees the staging buffer. Fails if no write transaction is in progress, or if the write to NV storage fails. In the event of failure the staging buffer is retained, allowing the host to retry or discard. The protocol does not guarantee that a failed commit leaves NV storage in either its pre- or post-commit state — the degree of atomicity is implementation-defined. Device implementations should document their atomicity guarantees. |
| 0x05 | NV_POKE_DISCARD | 0.1.0 | 0 | Discards the staging buffer without writing to NV storage and frees the staging buffer. Fails if no write transaction is in progress. |
| 0x06 | NV_POKE_COMMIT_BYTE | 0.1.0 | 4: A0=byte, A1=location_LSB, A2=location_MSB, A3=RAM slot | Performs a complete single-byte write transaction: loads NV storage into a staging buffer using the specified RAM slot, writes the specified byte at the specified location, commits to NV storage, and frees the staging buffer. Fails if NV storage if not writable, if a write transaction is already in progress, or if the RAM slot specified is invalid, active or too small. The location MSB must not exceed 0x7F; if it does, the device rejects the command. Atomicity guarantees are the same as for NV_POKE_COMMIT. An A3 value of 0xAA is invalid and rejected. |
 
CMD 0xAA is reserved and must never be assigned.
 
### Group 0x04 — Pipes

Commands in this group transfer bytes between the host and a pipe on the device. All commands in this group are valid in command-response mode only.

A pipe carries an ordered sequence of bytes in each direction it supports, in the shape its [type](#pipe-types) describes, and runs from the host, through the device, to the pipe's far end. The device relays. In the OUT direction it drains what the host writes and passes it on to the far end. In the IN direction it takes bytes from the far end and fills the pipe for the host to read.

The far end is whatever the device relays to and from — a USB interface, a serial port, a networked device, something inside the device itself, or nothing at all, where the bytes go no further.

This protocol describes the far end in two respects:

- what kind of thing it is
- whether it is attached

Nothing else identifies it to the host.

Pipes are an optional device feature. The host should query GET_PIPE_CAPABILITY before issuing any other command in this group. A device that exposes no pipes reports a count of zero from GET_PIPE_CAPABILITY. All other commands in this group return failure on such a device.

A pipe is addressed by a single byte. Pipe numbering is contiguous and starts from zero. A device exposing n pipes numbers them 0 to n-1 with no gaps. A pipe number is a final argument in GET_PIPE_INFO and PIPE_READ, so 0xAA is not a valid pipe number and a device may expose at most 170 pipes.

A pipe supports one direction or both, as reported in the [pipe flags](#get_pipe_info-response-format). A device that sets both direction bits asserts that the pipe's two directions form one exchange: what receives the bytes the host writes is what supplies the bytes the host reads. It is not an echo — the bytes the host reads are not the bytes it wrote. The directions are independent in every other respect, each with its own buffering, and a host must test each flag bit rather than inferring one direction from the other.

A device may report whether a pipe's far end is attached. Not every far end has such a concept, and a device with no way to tell declines to answer rather than guessing. Bit 2 of the pipe flags says the device reports attachment at all, and bit 3 carries the answer. A host must read bit 3 only where bit 2 is set, and must read both bits clear as the device declining to answer rather than as a negative one.

Attachment says what the device believes about its far end, and what counts as attached is the device's own decision. It promises nothing either way: a write to an attached pipe may reach nothing, and a write to an unattached one may still arrive. Attachment is a property of the pipe rather than of a direction, so one answer covers both.

PIPE_WRITE transfers all of the bytes offered or none of them. Where the device cannot accept them all it returns failure and transfers nothing, leaving the host to retry or to discard the bytes. A device never blocks waiting for space to become available. No further command can be issued until this one has run the [command processing sequence](#command-processing-sequence) to completion, so a device that blocked would stall the session for as long as the far end refused to drain. GET_PIPE_INFO reports the space currently available, allowing a host that has been refused to decide whether to retry immediately or to back off.

Success means the device accepted the bytes, not that they reached the far end. A device may accept bytes and discard them afterwards, and there may be nothing at the far end to reach.

PIPE_READ returns what the device has, up to the count asked for, and consumes it. Reading an empty pipe succeeds with no data rather than failing, so that a host polling an idle pipe never has to tell a quiet pipe from a broken one. A device answers with whatever it holds at that moment and never blocks waiting for more to arrive. No further command can be issued until this one completes, so a device that blocked would stall the session for as long as the far end stayed silent.

Where the far end supplies bytes faster than the host reads them, a device with nowhere to put them discards them. The PIPE_READ response says that this has happened. It does not say where — the discarded bytes may fall anywhere in or adjacent to the data returned, and a host that must resynchronise does so on framing of its own.

| CMD | Name | Since | Args | Description |
|-----|------|-------|------|-------------|
| 0x00 | GET_PIPE_CAPABILITY | 0.1.2 | 0 | Requests the device to report how many pipes it exposes. See [GET_PIPE_CAPABILITY Response Format](#get_pipe_capability-response-format). Fails if the response data section is smaller than 8 bytes. |
| 0x01 | GET_PIPE_INFO | 0.1.2 | 1: A0=pipe | Requests the device to report what the specified pipe is, which directions it carries, how much each of them can move right now, and what its far end is. See [GET_PIPE_INFO Response Format](#get_pipe_info-response-format). Fails if the pipe is not one the device exposes, or if the response data section is smaller than 8 bytes. An A0 value of 0xAA is invalid and rejected. |
| 0x02 | PIPE_WRITE | 0.1.2 | 6: A0/A1/A2/A3=data, A4=pipe, A5=count | Transfers count bytes, taken from A0 onwards, to the specified pipe. A5 must be in the range 0x01 to 0x04 — any other value is invalid and the device rejects the command. Argument bytes beyond count are ignored by the device, but are still transmitted, as the argument count is fixed. All 256 values are valid in A0 to A3. Either all count bytes are transferred or none are: the device returns failure if it cannot accept them all, and in that case transfers nothing. Fails if the pipe is not one the device exposes, or if the pipe does not support the OUT direction. |
| 0x03 | PIPE_READ | 0.1.2 | 2: A0=count, A1=pipe | Reads up to count bytes from the specified pipe into the response data section, consuming what it returns. A count of zero indicates 256 bytes. The device returns as many bytes as it has, up to count, and an empty pipe is a success carrying no data. See [PIPE_READ Response Format](#pipe_read-response-format). Fails, consuming nothing, if the pipe is not one the device exposes, if the pipe does not support the IN direction, or if the response data section cannot hold 8 bytes plus the number of bytes requested. An A1 value of 0xAA is invalid and rejected. |

CMD 0xAA is reserved and must never be assigned.

### Group 0x05 — Auxiliary I/O

Commands in this group drive and read device pins that may not be part of the ROM interface. All commands in this group are valid in command-response mode only.

An auxiliary pin is a pin the device exposes to the host — a header pad, a spare device pin, a pad whose jumper has been removed. **This protocol makes no claim about what is attached to such a pin.** The device may not know: a wire may reach a host reset line, a disk drive, a printer, a relay, an indicator LED, or a jumper being sensed. The commands in this group are therefore simple GPIO-style primitives.

Auxiliary I/O is an optional device feature. The host should query GET_AUX_CAPABILITY before issuing any other command in this group. A device that exposes no auxiliary pins reports a group count of zero from GET_AUX_CAPABILITY. All other commands in this group return failure on such a device, except SET_AUX_AND_EXIT and SET_AUX_SWITCH_EXIT, which have no response header to report it in. Neither sets a pin nor switches a slot, but the exit DOES complete.

A pin is addressed by two bytes: a pin group and a pin number within that group. Both are contiguous and start from zero. A device exposing n groups numbers them 0 to n-1, and a group holding n pins numbers them 0 to n-1, with no gaps in either. A group is a final argument in several commands in this group, so 0xAA is not a valid group number and a device may expose at most 170 groups. A pin number is not a final argument in any command, so 0xAA is a valid pin number and a group may hold 256 pins.

Each group has a [type](#auxiliary-pin-group-types) describing what kind of pins it holds.

The same pin may appear in more than one group. Groups are alternative ways of naming a device's pins, not a partition of them. Where a pin appears in several groups, every group reports the same properties for it, and driving it through one group is indistinguishable from driving it through another.

A pin's state persists across the end of a command-response session and across RBCP_RESET. Only a device reset restores a pin to its power-on state.

| CMD | Name | Since | Args | Description |
|-----|------|-------|------|-------------|
| 0x00 | GET_AUX_CAPABILITY | 0.1.2 | 0 | Requests the device to report how many auxiliary pin groups it exposes and the limits that apply to them. See [GET_AUX_CAPABILITY Response Format](#get_aux_capability-response-format). Fails if the response data section is smaller than 8 bytes. |
| 0x01 | GET_AUX_GROUP_INFO | 0.1.2 | 1: A0=group | Requests the device to report what kind of pins the specified group holds and how many of them there are. See [GET_AUX_GROUP_INFO Response Format](#get_aux_group_info-response-format). Fails if the group is not one the device exposes, or if the response data section is smaller than 8 bytes. An A0 value of 0xAA is invalid and rejected. |
| 0x02 | GET_AUX_PIN_INFO | 0.1.2 | 2: A0=pin, A1=group | Requests the device to report what the specified pin may be used for and the level currently present on it. See [GET_AUX_PIN_INFO Response Format](#get_aux_pin_info-response-format). Fails if the group or the pin is not one the device exposes, or if the response data section is smaller than 8 bytes. An A1 value of 0xAA is invalid and rejected. |
| 0x03 | SET_AUX | 0.1.2 | 5: A0=state, A1=after, A2=hold, A3=pin, A4=group | Places the specified pin in the specified [state](#auxiliary-pin-states). Where hold is non-zero the device holds that state for the requested duration and then applies after. The device times the hold, and does not complete the command until it has elapsed and after has been applied. Fails if the group or the pin is not one the device exposes, if the pin is not drivable, if state is not a defined value, if hold is non-zero and after is not a defined value, or if hold exceeds the maximum reported by GET_AUX_CAPABILITY. An A4 value of 0xAA is invalid and rejected. |
| 0x04 | SET_AUX_AND_EXIT | 0.1.2 | 5: as SET_AUX | As SET_AUX, but exits command-response mode without updating the [response header](#response-header). This command is terminal to the current command-response session. The host must not poll the back-channel region after issuing it. A host uses this where it expects to be unable to observe a response. An A4 value of 0xAA is invalid and rejected. |
| 0x05 | SET_AUX_SWITCH_EXIT | 0.1.2 | 7: A0=state, A1=after, A2=hold, A3=flags, A4=pin, A5=group, A6=slot | Sets the specified pin and activates the specified RAM slot, in the order given by flags, then exits command-response mode without updating the [response header](#response-header). This command is terminal to the current command-response session. See [SET_AUX_SWITCH_EXIT Ordering](#set_aux_switch_exit-ordering). An A6 value of 0xAA is invalid. If received, neither the pin is set nor the slot switched, but the exit DOES complete. |

CMD 0xAA is reserved and must never be assigned.

SET_AUX_AND_EXIT and SET_AUX_SWITCH_EXIT never update the response header, as EXIT_CMD_RESP_SILENT, SWITCH_AND_EXIT and RBCP_RESET do not. As with any exit from command-response mode, an in-progress NV write transaction is silently discarded.

#### SET_AUX_SWITCH_EXIT Ordering

The flags argument of SET_AUX_SWITCH_EXIT selects the order of its two operations. Bit 0 is the least significant bit of the byte.

| Bit | Value | Meaning |
|-----|-------|---------|
| 0 | 0 | Set the pin first, then activate the slot |
| 0 | 1 | Activate the slot first, then set the pin |
| 7:1 | — | Reserved. Must be zero. If any reserved bit is set, neither the pin is set nor the slot switched, but the exit DOES complete. |

Under set-first ordering the device does not apply after until the slot switch has completed. The effective hold is therefore the greater of the requested hold and the time the switch takes.

### Group 0xAA - Reset

This group defines a single, special command for resetting the device's RBCP implementation. This is a non-standard command that does not follow the normal command processing sequence, and is designed to be reliably detectable even if issued mid-command or mid-knock, making it suitable for recovering from desynchronization or other error states.

| CMD | Name | Since | Args | Description |
|-----|------|-------|------|-------------|
| 0xAA | RBCP_RESET | 0.1.0 | 0 | Resets the device's RBCP implementation. This can be used to set the device implementation to a known good state before issuing subsequent commands. This command doesn't change any flash or RAM slot contents nor does it change the active RAM slot. There is never any response from this command - if it is executed in command-response mode, the device immediately and silently exits from that mode. |

---

## Protocol Defaults

The following values are the protocol-recommended defaults for complete and status-OK, for use when the host has no specific reason to choose other values:

| Parameter | Default | Inverse |
|-----------|---------|---------|
| complete | 0xBB | 0x44 (pending) |
| status-OK | 0xCC | 0x33 (failed) |

These defaults have a 1/128 probability of clashing with the pre-existing contents of the progress or response locations in the target slot. The host may already know the pre-existing values — for example because the host implementation itself populated them — in which case no read is required. Otherwise, the host should read those locations first and supply alternative values in ENTER_CMD_RESP if a clash is detected.

---

## Command-Response Mode

### Back-Channel Region

When command-response mode is active, the device maintains a structured region within the active RAM slot. The host reads this region as ordinary ROM data. The location and size of this region are specified by the host in the ENTER_CMD_RESP command as a 24-bit start address and a 16-bit size in bytes. The start address must be 4-byte aligned.

### Command Page

During command-response mode, the device filters incoming address reads using the command page configured in ENTER_CMD_RESP. Only reads whose upper address bits (above A7) match the command page value are treated as command bytes. This allows the host to designate a specific page of the ROM address space for command signaling, keeping it distinct from normal ROM data reads and from the back-channel region.

### Response Header

The first 8 bytes of the back-channel region form the response header, present in all format identifiers.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | Last Command | The GROUP and CMD bytes of the most recently received command. Updated as part of the [command processing sequence](#command-processing-sequence). The host is not required to read this field as part of normal command execution. |
| 2 | 2 | Token | Monotonically incrementing counter, wrapping from 0xFFFF to 0x0000. Incremented by exactly 1 by the device on receipt of every command. The LSB is incremented first; when it wraps from 0xFF to 0x00 the MSB is incremented. All individual byte writes are atomic. The host polling sequence relies on reading the LSB only, which is guaranteed atomic. Hosts requiring the full u16 value should use a read-high/read-low/read-high sequence and retry if the two high-byte reads differ. The device must not initialise the token on entering command-response mode.  Instead the device increments whatever value is already present and the host must snapshot the current value before issuing the command to enter command-response mode, and use the token incrementing sequence to detect command completion, as for other commands in command-response mode. |
| 4 | 1 | Progress | Boolean field. Contains the configured complete value when the device has finished processing the last command, and its bitwise inverse (pending) while processing is in progress. |
| 5 | 1 | Response | Boolean field. Contains the configured status-OK value if the last completed command succeeded, and its bitwise inverse (failed) if it did not. |
| 6 | 2 | Reserved | Must be set to zero by the device.  Must not be assumed to have any particular value by the host. |

Command-specific response data follows the header at offset 8, in the space provided by the active format identifier, assuming sufficient ROM space has been allocated.

### Command Processing Sequence

On receipt of a command the device performs the following steps in order:

1. Set progress = pending
2. Increment token (LSB first, then MSB if LSB wraps)
3. Update last command
4. Process command
5. Set response = OK or FAILED
6. Set progress = complete

The device processes one command at a time. In command-response mode, the device will not begin processing a new command until the current one has completed. The behaviour of issuing a new command while one is outstanding is undefined — the device may queue it,may discard it, or may discard a portion of it.  Issuing new commands while one is outstanding is therefore dangerous, as it can risk desynchronizing the host and device.

### Host Polling Sequence

To issue a command the host should:

1. Record the current token LSB value
2. Issue the command using the read combination, defined by the command's GROUP and CMD bytes followed by its argument bytes
3. Poll token LSB until it differs from the recorded value (including handling wraparound)
4. Poll progress until it equals the configured complete value
5. Read the response field to determine success or failure
6. Read any command-specific response data

### Bootstrap — Entering Command-Response Mode

The progress and response fields are boolean values: each has exactly two meaningful states, defined by the configured value and its bitwise inverse. Before issuing ENTER_CMD_RESP the host must choose complete and status-OK values that differ from the current contents of the progress and response locations in the target slot. Neither value may be 0xAA.

Since pending is the bitwise inverse of complete, at most one of the two can match any given byte value at a location. A safe choice of complete byte is therefore always available.

The host may already know the pre-existing values at those locations — for example because the host implementation populated them itself. Otherwise the host should read those locations and select values accordingly.

The device sets progress = pending before incrementing the token, ensuring no false-complete condition is possible during the transition into command-response mode.

If the token LSB does not increment within a reasonable timeout after issuing ENTER_CMD_RESP, the host should assume the command was silently discarded — due to an invalid argument such as a misaligned back-channel address, an out-of-range command page, or a prohibited complete or status-OK value — and that command-response mode has not been entered.  For safety it is advisable to reset the device before attempting to enter command-response mode, as described in [Communication Initiation - Resetting the Device](#communication-initiation---resetting-the-device).

---

## GET_FLASH_SLOT_COUNT Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | total_count | Total number of available (populated, non plugin or other special) flash slots on the device. The host can use this information to determine valid slot indices for subsequent GET_FLASH_SLOT_INFO commands. |

## GET_FLASH_SLOT_INFO Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | rom_type | ROM type identifier for the specified flash slot. See [ROM Types](#rom-types). |
| 1 | 31 | name | Slot name as ASCII. Unused bytes are filled with 0x00. Null-terminated. A zero length name is a valid response where the device has no name associated with the slot. |

## GET_FLASH_SLOT_INFO_ALL Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

### Preamble

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | total_count | Total number of flash slots available on the device |
| 1 | 1 | whole_count | Number of complete records returned |
| 2 | 1 | partial_flag | 0x01 if a truncated record follows the complete records, 0x00 otherwise. Where partial_flag is 0x01, the number of bytes present for the partial record is: data_section_size − 4 − (whole_count × 32). |
| 3 | 1 | Reserved | Must be zero |

### Records

Each complete record is 32 bytes:

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | rom_type | ROM type identifier |
| 1 | 31 | name | Slot name as ASCII. Unused bytes are filled with 0x00. Null-terminated. A zero length name is a valid response where the device has no name associated with the slot. |

Records follow the preamble in slot index order. `whole_count` complete records are returned first. If `partial_flag` is 0x01, a truncated record follows, containing as many bytes of that record as the data section (minus space for header) permits.

Where the truncated record carries a name — that is, where two or more bytes are present — its final byte is set to 0x00, so the partial name is null-terminated as a complete record's name is. The name is therefore up to one character shorter than the byte count implies. This is deliberate: it means a host reads every name in the response the same way, and never needs the byte count to know where a name ends. Where only one byte is present it is the `rom_type`, and no name follows.

The host can determine whether all slots were returned by comparing `whole_count` (plus `partial_flag`) against `total_count`.

If the data section is only the size of the header, the host may return status-OK, but no record data is present.

---

## GET_RAM_SLOT_INFO Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | total_count | Total number of RAM slots available on the device |
| 1 | 1 | active_slot | Index of the currently active RAM slot.  Maybe 0xFF if no slot is active |
| 2 | 1 | rom_type | ROM type currently being served |
| 3 | 1 | Reserved | Must be zero |

No per-slot records follow. RAM slots are an internal device resource; the host requires only the aggregate information above.

## GET_DEVICE_TYPE Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 24 | device_type | Device type as ASCII. Unused bytes are filled with 0x00. Null-terminated. A device must provide a type. |

## GET_DEVICE_VERSION Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 24 | device_version | Device version as ASCII. Unused bytes are filled with 0x00. Null-terminated. A device must provide a version. |

## GET_PROTOCOL_VERSION Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | major | Major version number |
| 1 | 1 | minor | Minor version number |
| 2 | 1 | patch | Patch version number |
| 3 | 1 | Reserved | Must be zero |

## GET_BOOT_SLOT_INFO Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | flash_slot | Flash slot the device loaded at boot, or 0xFF where it loaded none or does not know. |
| 1 | 1 | ram_slot | RAM slot it loaded that image into, or 0xFF on the same terms. |
| 2 | 2 | Reserved | Must be zero |

Both fields describe the boot, and the device does not update them. A host that has since loaded a slot or switched slots knows what it did, so the device reports only what the host has no other way to learn.

## GET_NV_CAPABILITY Response Format
 
The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.
 
| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 2 | size | Total NV storage size in bytes. A value of zero indicates NV storage is not present on this device. |
| 2 | 1 | writable | 0x01 if the device supports NV storage write operations; 0x00 if read-only. Only meaningful if size is non-zero. |
| 3 | 1 | Reserved | Must be zero. |
 
## NV_PEEK Response Format
 
The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.
 
| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | count | data | The requested bytes read directly from NV storage. A count of zero in the command corresponds to 256 bytes here. | 
 
## GET_PIPE_CAPABILITY Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | count | Number of pipes this device exposes. A value of zero indicates the device exposes no pipes. Pipes are numbered 0 to count-1, and count never exceeds 170. |
| 1 | 7 | Reserved | Must be set to zero by the device. Must not be assumed to have any particular value by the host. |

No per-pipe records follow. Pipe numbering is contiguous and starts from zero, so the count alone gives the host every valid pipe number. The properties of each are obtained with GET_PIPE_INFO.

## GET_PIPE_INFO Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | type | What kind of pipe this is. See [Pipe Types](#pipe-types). |
| 1 | 1 | flags | Bit 0: the pipe supports the OUT direction. Bit 1: the pipe supports the IN direction. Bit 2: the device reports whether the pipe's far end is attached. Bit 3: the far end is attached. Meaningful only where bit 2 is set, and must be set to zero by the device where bit 2 is clear. At least one of bits 0 and 1 is always set. Bits 4–7 reserved, and must be set to zero by the device. |
| 2 | 1 | free | Number of bytes the device is able to accept in the OUT direction at the instant the command was processed, saturating at 0xFF. Zero where the pipe does not support OUT. A PIPE_WRITE of no more than this many bytes is not guaranteed to succeed: the value may be stale by the time the host acts on it. |
| 3 | 1 | waiting | Number of bytes the device is able to return in the IN direction at the instant the command was processed, saturating at 0xFF. Zero where the pipe does not support IN. A PIPE_READ of no more than this many bytes is not guaranteed to return them all: the value may be stale by the time the host acts on it. |
| 4 | 1 | far_end | What kind of far end this pipe has. See [Far End Types](#far-end-types). |
| 5 | 3 | Reserved | Must be set to zero by the device. Must not be assumed to have any particular value by the host. |

## PIPE_READ Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | count | Number of bytes returned, where bit 1 of flags is clear. A zero then means the pipe was empty. Where bit 1 of flags is set the host already knows the number, having asked for it, and this field carries it as the command did — so a full 256-byte read reads as zero here. |
| 1 | 1 | flags | Bit 0: bytes were discarded before the host could read them. Bit 1: the device returned the full count requested. Set on every read that returns it, not only on a read of 256 bytes. Bits 2–7 reserved, and must be set to zero by the device. |
| 2 | 1 | waiting | Number of bytes the device is able to return in the IN direction on a further read, measured after this read has taken its own, saturating at 0xFF. A PIPE_READ of no more than this many bytes is not guaranteed to return them all: the value may be stale by the time the host acts on it. |
| 3 | 5 | Reserved | Must be set to zero by the device. Must not be assumed to have any particular value by the host. |
| 8 | count | data | The bytes read from the pipe, in the order the device holds them. A count of zero with bit 1 of flags set is 256 bytes here, as it is in the command. |

Bit 0 of flags says only that bytes were lost. It does not say where — see [Group 0x04](#group-0x04--pipes). A device sets it when it discards bytes and clears it when it reports it, so it always describes the interval since the host was last told. A read that fails reports nothing and clears nothing.

## GET_AUX_CAPABILITY Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | group_count | Number of auxiliary pin groups this device exposes. A value of zero indicates the device exposes no auxiliary pins. Groups are numbered 0 to group_count-1. |
| 1 | 1 | max_hold | The largest hold duration the device accepts, in units of 10ms. A value of zero indicates the device does not support timed holds, and rejects any SET_AUX with a non-zero hold. A host wanting a pulse from such a device must time it itself with two commands. |
| 2 | 6 | Reserved | Must be set to zero by the device. Must not be assumed to have any particular value by the host. |

## GET_AUX_GROUP_INFO Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | type | What kind of pins this group holds. See [Auxiliary Pin Group Types](#auxiliary-pin-group-types). |
| 1 | 1 | pin_count | Number of pins in this group. Pins are numbered 0 to pin_count-1. A value of zero indicates 256 pins. A group is never empty. |
| 2 | 6 | Reserved | Must be set to zero by the device. Must not be assumed to have any particular value by the host. |

## GET_AUX_PIN_INFO Response Format

The response data section begins immediately after the [response header](#response-header) at offset 8 within the back-channel region.

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | flags | Bit 0: the host may drive this pin with SET_AUX. Bit 1: level and driven below are meaningful. Bits 2–7 reserved, and must be set to zero by the device. |
| 1 | 1 | level | The level present on the pin at the instant the command was processed, 0 or 1. Must be set to zero by the device where bit 1 of flags is clear. |
| 2 | 1 | driven | 1 if the device is driving the pin, 0 if it is not. Must be set to zero by the device where bit 1 of flags is clear. |
| 3 | 5 | Reserved | Must be set to zero by the device. Must not be assumed to have any particular value by the host. |

## Auxiliary Pin Group Types

The following auxiliary pin group type identifiers are defined by the protocol. A single byte is used to identify the pin group type in [GET_AUX_GROUP_INFO](#get_aux_group_info-response-format) responses.

| Value | Group Type |
|-------|------------|
| 0x00 | None |
| 0x01 | GPIO |
| 0x02–0x7F | Reserved |
| 0x80–0xFE | Reserved for implementation-specific use |
| 0xFF | Invalid |

A group of type None holds pins the device does not categorise. A group of type GPIO holds the device's own general-purpose I/O pins, numbered as the device's documentation numbers them.

Host implementations must handle reserved values gracefully, as new group types may be defined in future protocol versions without a non-backwards compatible version increase.

## Auxiliary Pin States

The following states are defined by the protocol for the state and after arguments of [SET_AUX](#group-0x05--auxiliary-io) and its variants.

| Value | State |
|-------|-------|
| 0x00 | Drive low |
| 0x01 | Drive high |
| 0x02 | Release to high impedance |
| 0x03–0xFF | Invalid |

The hold argument is expressed in units of 10ms. A value of zero holds the state until a subsequent SET_AUX changes it. A non-zero value must not exceed the maximum reported by [GET_AUX_CAPABILITY](#get_aux_capability-response-format).

## Pipe Types

The following pipe type identifiers are defined by the protocol. A single byte is used to identify the pipe type in [GET_PIPE_INFO](#get_pipe_info-response-format) responses.

| Value | Pipe Type |
|-------|-----------|
| 0x00 | Raw |
| 0x01–0x7F | Reserved |
| 0x80–0xFE | Reserved for implementation-specific use |
| 0xFF | Invalid |

A pipe of type Raw carries a free-running sequence of bytes in each direction it supports, with no framing imposed by the protocol. It is the type to use where nothing is required beyond the bytes reaching the far end, or arriving from it. A host that requires no particular type should use the lowest-numbered pipe of type 0x00 that carries the direction it needs.

Host implementations must handle reserved values gracefully, as new pipe types may be defined in future protocol versions without a non-backwards compatible version increase.

## Far End Types

The following far end identifiers are defined by the protocol. A single byte is used to identify the far end in [GET_PIPE_INFO](#get_pipe_info-response-format) responses.

| Value | Far End |
|-------|---------|
| 0x00 | Unspecified |
| 0x01 | USB CDC |
| 0x02 | Network |
| 0x03 | Physical serial port |
| 0x04–0x7F | Reserved |
| 0x80–0xFE | Reserved for implementation-specific use |
| 0xFF | Invalid |

A device may report Unspecified for any far end, including one a defined value describes, and including a pipe that reaches nothing at all.

Host implementations must handle reserved values gracefully, as new far ends may be defined in future protocol versions without a non-backwards compatible version increase.

---

## ROM Types

The following ROM type identifiers are defined by the protocol. A single byte
is used to identify the ROM type in [GET_FLASH_SLOT_INFO](#get_flash_slot_info-response-format)
and [GET_RAM_SLOT_INFO](#get_ram_slot_info-response-format) responses.

| Value | ROM Type |
|-------|----------|
| 0x00 | 2316 |
| 0x01 | 2332 |
| 0x02 | 2364 |
| 0x03 | 23128 |
| 0x04 | 23256 |
| 0x05 | 23512 |
| 0x06 | 2704 |
| 0x07 | 2708 |
| 0x08 | 2716 |
| 0x09 | 2732 |
| 0x0A | 2764 |
| 0x0B | 27128 |
| 0x0C | 27256 |
| 0x0D | 27512 |
| 0x0E | 231024 |
| 0x0F | 27C010 |
| 0x10 | 27C020 |
| 0x11 | 27C040 |
| 0x12 | 27C080 |
| 0x13 | 27C400 |
| 0x14 | 6116 |
| 0x15 | 27C301 |
| 0x16–0x18 | Not available |
| 0x19 | SST39SF040 |
| 0x1A | 28C16 |
| 0x1B | 28C64 |
| 0x1C | 28C256 |
| 0x1D | 28C512 |
| 0x1E | 23QL512 |
| 0x1F | 23QL384 |
| 0x20 | 23C1001 |
| 0x21 | 27C200 |
| 0x22 | HM7641 |
| 0x23 | 62256 |
| 0x24 | 23C1010 |
| 0x25–0x7F | Reserved |
| 0x80–0xFE | Reserved for implementation-specific use |
| 0xFF | Invalid/ROM not being served |

The values 0x16–0x18 were assigned by an implementation before the
implementation-specific range existed. The protocol will not assign them. A host
treats them as it treats a reserved value.

Note that the ROM type values above are defined by the protocol independently of any specific device implementation. A device is not required to support all ROM types listed.  Host implementations must handle reserved values gracefully, as new ROM types may be defined in future protocol versions without a non-backwards compatible version increase.

---

## Example — C64 Kernal Bootloader

This illustrates a typical RBCP session for a C64 kernal bootloader application. It is intended to be illustrative rather than normative.

1. Bootloader kernal boots and detects whether the C= key is held.
2. Copies itself into RAM and begins executing from there.
3. Issues ENTER_CMD_RESP with command page, back-channel start address, size, and chosen complete/status-OK bytes.
4. Polls token LSB then progress to confirm command-response mode is active.
5. Issues GET_FLASH_SLOT_INFO_ALL.
6. Reads flash slot count, names and types from the response region.
7. **Auto-boot path:** selects target slot, issues LOAD_SLOT then SWITCH_AND_EXIT.
8. **Menu path:** presents a menu, scanning the keyboard as needed, then issues LOAD_SLOT and SWITCH_AND_EXIT on selection.
9. **Menu path:** The device activates the new ROM slot. The bootloader jumps through the reset vector of the newly loaded ROM.

As an optional extra, the bootloader could also store the last-selected slt index in NV storage using NV_POKE_COMMIT_BYTE, and read it back on boot to auto-boot the last selection without presenting the menu.

---

## Future Considerations

All items in this section, including future modes, are subject to change and should not be relied upon.

- SLOT_POKE_MULT: write a stream of consecutive bytes in a single command
- Pagination for GET_FLASH_SLOT_INFO when slot count or name lengths exceed the response region
- Labels for auxiliary pins, naming the role a pin plays in an installation rather than its identity, so that a host with a user interface can present something better than a pin number without being built for the installation
- Out-Stream, In-Stream and Bi-Stream mode definitions
- Utilisation of additional ROM bus lines (R/W, /WE, /BYTE, /AS) in future protocol versions

---

## Attribution

Inspired by the [One ROM](https://onerom.org/) project and discussions associated with that project, in particular [this thread](https://github.com/piersfinlayson/one-rom/issues/170) with:
- [r107sl](https://github.com/r107sl)
- [MacGyver4B](https://github.com/MacGyver4B)
- [Steph71](https://github.com/Steph71)

The overall concept of a host communicating with a ROM emulator using the address and data lines was originally shared with the author by [Jaime Idolpx](https://github.com/idolpx) and together they did much original brainstorming in this area.