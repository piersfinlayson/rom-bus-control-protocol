# ROM Bus Control Protocol (RBCP)

Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

Version: 0.1.0

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

**Session:** A single interaction between the host and device, initiated by a knock. In command mode, each command constitutes its own session. In command-response mode, a session spans from the knock through to the host exiting command-response mode.

**Knock:** The sequence of ROM address reads that initiates a session. The device detects the knock by monitoring A0–A7 and uses it to establish framing.

**Slot:** A fixed-size region of storage containing a ROM image. Two categories of slot are defined: flash slots, which are persistent storage locations on the device, and RAM slots, which are volatile working buffers from which the device actively serves ROM data to the host. A ROM image must be loaded from a flash slot into a RAM slot before it can be served, and one is typically loaded into RAM by the device at boot time.  Different devices may have different slot sizes, counts and supported ROM types. The host discovers the available slots and their properties by issuing commands in command-response mode.

**Active slot:** The RAM slot currently being served to the host as ROM data.

**Back-channel region:** A structured region within the active RAM slot, maintained by the device during command-response mode, through which the device communicates response data to the host. The host reads this region as ordinary ROM data.

**Response header:** The first 8 bytes of the back-channel region, present in all configurations. Contains the token, progress, response, and last-command fields.

***Response data section***: The portion of the back-channel region immediately following the response header, beginning at offset 8. Contains command-specific response data. Its size is the back-channel region size minus 8 bytes.

**Token:** A monotonically incrementing counter in the response header, incremented by the device on receipt of each command. Used by the host to detect that a command has been received.

**Progress:** A boolean field in the response header indicating whether the device has completed processing the most recently received command. Takes one of two states: complete or pending.

**Response:** A boolean field in the response header indicating whether the most recently completed command succeeded. Takes one of two states: status-OK or failed.

**Complete / Pending:** The two states of the progress field. The complete value and its bitwise inverse (pending) are either protocol defaults or configured by the host via CONFIG_CMD_RESP or CONFIG_AND_ENTER_CMD_RESP.

**Status-OK / Failed:** The two states of the response field. The status-OK value and its bitwise inverse (failed) are either protocol defaults or configured by the host via CONFIG_CMD_RESP or CONFIG_AND_ENTER_CMD_RESP.

---

## Versioning and Compatibility

RBCP uses semantic versioning (major.minor.patch). The current version is indicated at the top of this document. A version is stable when it has been tagged in the GitHub repo and published as a GitHub release.

During the 0.x.y series, minor version increments may introduce breaking changes. A host implementation written against version 0.Y.z is guaranteed to interoperate correctly with any device implementing version 0.Y.w where w >= z.

From version 1.0.0 onwards, major version alone defines the compatibility contract. A host written against version X.Y.z is guaranteed to interoperate correctly with any device implementing version X.W.w where W > Y or (W == Y and w >= z).

Patch increments are backwards-compatible. A device implementing version X.Y.w is guaranteed to support all behaviour defined by version X.Y.z where z <= w.

A host should query the device version using GET_PROTOCOL_VERSION and reject a device whose version falls outside the bounds it was written for.

---

## Physical Medium

RBCP operates over the ROM bus. The relevant lines are:

- **Address lines:** carry host-to-device data. The host encodes commands as sequences of ROM address reads. The device captures these by monitoring the address bus. Only the least significant 8 bits of the address lines (A0–A7) are used for RBCP signaling in this version of the protocol. Upper address bits are ignored by the protocol. This ensures compatibility with the smallest ROM types — the 2704 (4Kbit, 512 bytes) has only 9 address lines. Future versions of the protocol may utilise additional address bits.
- **Data lines:** carry device-to-host data. The device writes response data into a designated region of ROM address space; the host reads this back as ordinary ROM data reads.
- **CS (Chip Select):** defines valid bus cycles. The device captures address values only when all CS lines are active. The exact CS lines present depend on the ROM socket standard in use — for example /CE and /OE on a 27C512, or /CS on a 2364. Devices should implement a debounce algorithm to avoid false triggering on noisy or poorly behaved bus implementations.

Future versions of the protocol may utilise additional ROM bus lines for signaling, including R/W, /WE, /BYTE, and address latch signals such as /AS, where these are present in the target ROM socket.

The electrical characteristics of all bus lines are defined by the ROM socket standard in use. RBCP inherits these definitions and does not redefine them.

All multi-byte values in RBCP are little-endian.

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

While not strictly necessary, particularly if a device was powered on at the same time as a device, it is highly recommended to reset the device before initiating communication. This ensures that the device starts in a known state and can help prevent synchronization issues which can be caused by the host reseting mid-communication.  While this reset is unlikely to be foolproof (no host-initiated reset can be), this significant reduces the likelihood of failure to synchronize at the start of a communication.

The recommended reset sequence is:
1. Issue the RBCP_RESET command 4 times in succession, with no knock in-front or in-between them.
2. Pause to allow the device to reset.  The amount of time required is implementation-specific, but a reset is likely to be a fast operation on the device.
3. Issue a knock followed by an RBCP_RESET.
4. Pause to allow the device to reset.  The amount of time required is implementation-specific, but a reset is likely to be a fast operation on the device.

This sequence ensures that, if the device is already in command-response mode, even mid-command, it should detect that RBCP_RESET and reset (exiting command-response mode).  If it were originally in command mode, even mid command, the number of bytes sent is longer than any command, and hence the device will end command processing.

The knock and then RBCP_RESET ensures that the device then resets if it were originally in command mode.

The group and command bytes of RBCP_RESET are deliberately chosen to be mode unique across all commands, and identical to each other, meaning that whether the device was expecting a group or command byte next, it will receive the reset group or command value.

---

## Session Initiation — The Knock

Every RBCP session begins with a knock sequence: a series of contiguous ROM address reads whose low-order address bits (A0–A7) match a predefined pattern. The device detects this pattern by monitoring the address bus.

The knock sequence is variable in length and is defined by the device implementation. It must be agreed between the device and all host implementations targeting it. The sequence should be long enough to make accidental activation statistically negligible — for example, a 6-character ASCII sequence such as `!RBCP!` encoded in A0–A7.

The knock precedes every session, including re-entry after exiting command-response mode.

There is no lightweight re-entry mechanism in this version of the protocol. One may be included in a future version.

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

The maximum argument count for any command defined by this version of the protocol is 5 (SLOT_POKE). For future extensibility, a host recovering from desync in command mode need transmit at most 8 additional address reads before a knock can re-establish framing. Future versions of the protocol will not exceed this maximum without incrementing the protocol version.

---

## Command Groups

| Group | Name | Valid Modes | Description |
|-------|------|-------------|-------------|
| 0x00 | Control | Command, Command-Response | Session and mode management |
| 0x01 | Read | Command-Response only | Query the device for information |
| 0x02 | Modify | Command, Command-Response | Change device state |
| 0xAA | Reset | Command, Command-Response | Reset the device's RBCP implementation |

---

## Command Reference

### Group 0x00 — Control

| CMD | Name | Args | Description |
|-----|------|------|-------------|
| 0x00 | NOP | 0 | No operation. In command-response mode the device acknowledges via the standard header sequence, allowing the host to verify the device is alive and processing commands. |
| 0x01 | CONFIG_CMD_RESP | 4: A0=location, A1=size, A2=complete, A3=status-OK | Configures command-response mode parameters. If not issued, the device uses the [protocol defaults](#protocol-defaults). May be issued in either mode. A0 indexes the [location table](#location-table) defining where the back-channel region sits within the slot. A1 indexes the [size table](#size-table) defining the data section size. A2 is the boolean value the device will write to the progress field to indicate completion; its bitwise inverse indicates pending. A3 is the boolean value the device will write to the response field to indicate success; its bitwise inverse indicates failure. See [Protocol Defaults](#protocol-defaults). CONFIG_CMD_RESP cannot be confirmed as it issued before ENTER_CMD_RESP so no back-channel exists to verify reception. A misreceived CONFIG_CMD_RESP will cause the host to poll the wrong location or interpret the wrong bytes after entering command-response mode. Hosts should treat any subsequent failure to observe a token increment or progress transition as a possible CONFIG_CMD_RESP misconfiguration. Not supported when in command-response mode - the device should return faiulure. |
| 0x02 | ENTER_CMD_RESP | 0 | Enters command-response mode using the parameters set by CONFIG_CMD_RESP, or [protocol defaults](#protocol-defaults) if not configured. Not supported when in command-response mode - the device should return failure. |
| 0x03 | CONFIG_AND_ENTER_CMD_RESP | 4: As per CONFIG_CMD_RESP | Configures command-response mode parameters and enters command-response mode in a single command. This is atomic and therefore safer than issuing CONFIG_CMD_RESP followed by ENTER_CMD_RESP, which risks desynchronization if a command is misreceived between them. The arguments are the same as for CONFIG_CMD_RESP. Not supported when in command-response mode. |
| 0x04 | EXIT_CMD_RESP_ACK | 0 | Exits command-response mode. The device completes the full command processing sequence, including setting progress = complete, before exiting command-response mode. The host should poll progress for complete as normal. Once complete is observed, the device has exited command-response mode and the back-channel region is no longer maintained.|
| 0x05 | EXIT_CMD_RESP_SILENT | 0 | Exits command-response mode without updating the [response header](#response-header). |
| 0x06 | SWITCH_AND_EXIT | 1: A0=slot | Activates the specified RAM slot and exits command-response mode silently. This command is terminal to the current control-response session. The device switches to the specified slot and exits command-response mode without updating the response header. The host must not poll the back-channel region after issuing this command — the device begins serving the new slot immediately and the previous back-channel region is invalidated. |

CMD 0xAA is reserved and must never be assigned.

### Group 0x01 — Read

| CMD | Name | Args | Description |
|-----|------|------|-------------|
| 0x00 | GET_FLASH_SLOT_COUNT | 0 | Requests the device to write the total number of available (populated, non plugin or other special) flash slots available on the device into the first byte of the command-response region. See [GET_FLASH_SLOT_COUNT Response Format](#get_flash_slot_count-response-format). |
| 0x01 | GET_FLASH_SLOT_INFO | 1: A0=slot | Requests the device to populate the command-response region with information about the specified flash ROM slot. See [GET_FLASH_SLOT_INFO Response Format](#get_flash_slot_info-response-format). Only succeeds if there is sufficient space, which means a back channel size of at least 64 bytes. |
| 0x02 | GET_FLASH_SLOT_INFO_ALL | 0 | Requests the device to populate the command-response region with information about available (populated, non plugin or other special) flash ROM slots. This provides the entirety of the information exposed by GET_FLASH_SLOT_COUNT and GET_FLASH_SLOT_INFO in a single request response. See [GET_FLASH_SLOT_INFO_ALL Response Format](#get_flash_slot_info_all-response-format). |
| 0x03 | GET_RAM_SLOT_INFO_ALL | 0 | Requests the device to populate the command-response region with information about available RAM slots. See [GET_RAM_SLOT_INFO Response Format](#get_ram_slot_info-response-format). |
| 0x04 | GET_DEVICE_TYPE | 0 | Requests the device to write its type (e.g. One ROM) into the command-response region as ASCII. Unused bytes are filled with 0x00. Null-terminated. A device must provide a type. See [GET_DEVICE_TYPE Response Format](#get_device_type-response-format). |
| 0x05 | GET_DEVICE_VERSION | 0 | Requests the device to write its version (e.g. v1.0.0) into the command-response region as ASCII. Unused bytes are filled with 0x00. Null-terminated. A device must provide a version. See [GET_DEVICE_VERSION Response Format](#get_device_version-response-format). |
| 0x06 | GET_PROTOCOL_VERSION | 0 | Requests the device to write the RBCP protocol version it implements into the response data section. See [GET_PROTOCOL_VERSION Response Format](#get_protocol_version-response-format). |
| 0x07 | SLOT_PEEK | 5: A0=slot, A1/A2/A3=24-bit address (little-endian), A4=count | Requests the device to read one or more bytes from the specified RAM slot at the specified address and write them into the response data section. A count of zero indicates 256 bytes should be read. This command fails if there is insufficient space in the response data section to accommodate the requested bytes. |

CMD 0xAA is reserved and must never be assigned.

### Group 0x02 — Modify

| CMD | Name | Args | Description |
|-----|------|------|-------------|
| 0x00 | SLOT_POKE | 5: A0=slot, A1/A2/A3=24-bit address (little-endian), A4=byte | Writes a single byte into the specified RAM slot at the specified address. May be used for patching vectors or other known locations prior to activating that slot or entering command-response mode. The target slot need not be active. In fact, patching multi-byte values such as interrupt vectors should only be done to inactive slots. Because SLOT_POKE writes one byte at a time, there is no atomic write of a 16-bit value — a vector partially written to an active slot will be transiently inconsistent and will corrupt any interrupt that occurs between the two writes. The safe pattern is: LOAD_SLOT the target image into an inactive RAM slot, issue SLOT_POKE commands to patch any vectors in that inactive slot, then issue SWITCH_AND_EXIT to make it active. The vector bytes are consistent at the instant the slot becomes active. |
| 0x01 | SWITCH_SLOT | 1: A0=slot | Activates the specified RAM slot. |
| 0x02 | LOAD_SLOT | 2: A0=RAM slot, A1=flash slot | Copies the specified ROM image from the slot on the ROM into the specified RAM slot. Does not activate the slot. |
| 0x03 | SLOT_POKE_ALL_BYTE | 2: A0=RAM slot, A1=byte | Fills the specified RAM slot with the specified byte. Does not activate the slot. |

CMD 0xAA is reserved and must never be assigned.

### Group 0xAA - Reset

| CMD | Name | Args | Description |
|-----|------|------|-------------|
| 0xAA | RBCP_RESET | 0 | Resets the device's RBCP implementation. This can be used to set the device implementation to a known good state before issuing subsequent commands. This command doesn't change any flash or RAM slot contents nor does it change the active RAM slot. There is never any respons from this command - if it is executed in command-response mode, the device immediately and silently exits from that mode. |

---

## Protocol Defaults

The following default values are defined by the protocol and are used when CONFIG_CMD_RESP has not been issued:

| Parameter | Default | Inverse |
|-----------|---------|---------|
| complete | 0xAA | 0x55 (pending) |
| status-OK | 0xCC | 0x33 (failed) |

These defaults have a 1/128 probability of clashing with the pre-existing contents of the progress or response locations in the target slot. The host may already know the pre-existing values — for example because the host implementation itself populated them — in which case no read is required. Otherwise, the host should read those locations first and issue CONFIG_CMD_RESP with alternative values if a clash is detected.

---

## Command-Response Mode

### Back-Channel Region

When command-response mode is active, the device maintains a structured region within the active RAM slot. The host reads this region as ordinary ROM data. The location and size of this region within the slot is determined by the format identifier supplied in CONFIG_CMD_RESP.

The device must not interpret address reads that fall within the back-channel region as command bytes.

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

The progress and response fields are boolean values: each has exactly two meaningful states, defined by the configured value and its bitwise inverse. Before issuing CONFIG_CMD_RESP the host must choose complete and status-OK values that differ from the current contents of the progress and response locations in the target slot.

Since pending is the bitwise inverse of complete, at most one of the two can match any given byte value at a location. A safe choice of complete byte is therefore always available.

The host may already know the pre-existing values at those locations — for example because the host implementation populated them itself. Otherwise the host should read those locations and select values accordingly.

The device sets progress = pending before incrementing the token, ensuring no false-complete condition is possible during the transition into command-response mode.

---

## Format Identifiers

The location and size of the back-channel region within the RAM slot are configured independently via two table-indexed bytes supplied as arguments to [CONFIG_CMD_RESP](#group-0x00--control). The device guarantees that all addresses in the active slot outside the back-channel region are served unmodified.

The back-channel region is always 4-byte aligned. The region consists of the 8-byte [response header](#response-header) followed immediately by any remaining data section.

### Location Table

Defines the start address of the back-channel region within the RAM slot.

| ID | Description |
|----|-------------|
| 0x00 | Start of slot |
| 0x01 | End of slot minus total region size |
| 0x02–0x7F | Reserved |
| 0x80–0xFF | Implementation-specific |

For location 0x01 the device is responsible for computing the start address as slot_end minus total region size. Given that total region size is always a multiple of 8, the resulting address is guaranteed to be 4-byte aligned.

### Size Table

Defines the size of the back-channel region, which includes the response header and response data section.

| ID | Back-Channel Region Size |
|----|------------------|
| 0x00 | 8 bytes (header only) |
| 0x01 | 16 bytes |
| 0x02 | 32 bytes |
| 0x03 | 64 bytes |
| 0x04 | 128 bytes |
| 0x05 | 256 bytes |
| 0x06 | 512 bytes |
| 0x07 | 1024 bytes |
| 0x08 | 2048 bytes |
| 0x09 | 4096 bytes |
| 0x0A | 8192 bytes |
| 0x0B | 16384 bytes |
| 0x0C | 32768 bytes |
| 0x0D–0x7F | Reserved |
| 0x80–0xFF | Implementation-specific |

If the requested back-channel region size exceeds the available space in the RAM slot, the device should return failure to CONFIG_CMD_RESP and reject the command.

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
| 2 | 1 | partial_flag | 0x01 if a truncated record follows the complete records, 0x00 otherwise. Where partial_flag is 0x01, the number of bytes present for the partial record is: data_section_size − 8 (the header) - 4 − (whole_count × 32). |
| 3 | 1 | Reserved | Must be zero |

### Records

Each complete record is 32 bytes:

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | rom_type | ROM type identifier |
| 1 | 31 | name | Slot name as ASCII. Unused bytes are filled with 0x00. Null-terminated. A zero length name is a valid response where the device has no name associated with the slot. |

Records follow the preamble in slot index order. `whole_count` complete records are returned first. If `partial_flag` is 0x01, a truncated record follows, containing as many bytes of that record as the data section (minus space for header) permits.

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
| 0x0F | 27C010 / 23C1010 |
| 0x10 | 27C020 |
| 0x11 | 27C040 |
| 0x12 | 27C080 |
| 0x13 | 27C400 |
| 0x14 | 6116 |
| 0x15 | 27C301 |
| 0x16–0x18 | Reserved |
| 0x19 | SST39SF040 |
| 0x1A | 28C16 |
| 0x1B | 28C64 |
| 0x1C | 28C256 |
| 0x1D | 28C512 |
| 0x1E–0x7F | Reserved |
| 0x80–0xFE | Reserved for implementation-specific use |
| 0xFF | Invalid/ROM not being served |

Note that the ROM type values above are defined by the protocol independently of any specific device implementation. A device is not required to support all ROM types listed.

---

## Example — C64 Kernal Bootloader

This illustrates a typical RBCP session for a C64 kernal bootloader application. It is intended to be illustrative rather than normative.

1. Bootloader kernal boots and detects whether the C= key is held.
2. Copies itself into RAM and begins executing from there.
3. Issues CONFIG_AND_ENTER_CMD_RESP with location and size and chosen complete/status-OK bytes.
4. Polls token LSB then progress to confirm command-response mode is active.
5. Issues GET_FLASH_SLOT_INFO_ALL.
6. Reads flash slot count, names and types from the response region.
7. **Auto-boot path:** selects target slot, issues LOAD_SLOT then SWITCH_AND_EXIT.
8. **Menu path:** presents a menu, scanning the keyboard as needed (exiting and re-entering command-response mode via a full knock each time to service IRQs), then issues LOAD_SLOT and SWITCH_AND_EXIT on selection.
9. **Menu path:** The device activates the new ROM slot. The bootloader jumps through the reset vector of the newly loaded ROM.

---

## Future Considerations

All items in this section, including future modes, are subject to change and should not be relied upon.

- SLOT_POKE_MULT: write a stream of consecutive bytes in a single command
- Pagination for GET_FLASH_SLOT_INFO when slot count or name lengths exceed the response region
- Lightweight re-entry into command-response mode without a full knock
- Out-Stream, In-Stream and Bi-Stream mode definitions
- Additional format identifiers for other platforms and ROM socket types
- Utilisation of additional ROM bus lines (R/W, /WE, /BYTE, /AS) in future protocol versions

---

## Attribution

Inspired by the [One ROM](https://onerom.org/) project and discussions associated with that project, in particular [this thread](https://github.com/piersfinlayson/one-rom/issues/170) with:
- [r107sl](https://github.com/r107sl)
- [MacGyver4B](https://github.com/MacGyver4B)
- [Steph71](https://github.com/Steph71)

The overall concept of a host communicating with a ROM emulator using the address and data lines was originally shared with the author by [Jaime Idolpx](https://github.com/idolpx) and together they did much original brainstorming in this area.