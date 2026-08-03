# 68K RBCP Host Routines

Generic 68000 assembly routines implementing the host side of RBCP. They make no assumptions about the platform beyond the ability to read the ROM and a small block of RAM for working storage.

## Files

| File | Purpose |
|---|---|
| `rbcp_defs.s` | Protocol constants, the bus mapping, and the derived back-channel addresses |
| `rbcp.s` | The routines themselves |
| `sample_rbcp_config.s` | Annotated configuration to copy and edit |

Include them in that order, with your own `rbcp_config.s` first:

```
        INCLUDE "rbcp_config.s"
        INCLUDE "../rbcp/rbcp_defs.s"
        ...
        INCLUDE "../rbcp/rbcp.s"
```

`rbcp_defs.s` and `rbcp_config.s` emit no code, so they can be included before the `ORG`. `rbcp.s` must be placed where the code will execute — see *Execution environment* below.

## Bus mapping

RBCP is defined in terms of the address and data lines the *device* observes. On a 68K those are not the CPU's own lines, so the library maps between the two using five constants supplied by `rbcp_config.s`:

| Constant | Meaning |
|---|---|
| `CONFIG_RBCP_BUS_SHIFT` | log2 of the CPU address stride of one device bus cycle — 1 for a 16-bit bus, 2 for a 32-bit bus |
| `CONFIG_RBCP_DEV_SHIFT` | log2 of the bytes the device supplies per cycle — 0 for an 8-bit device, 1 for ×16 |
| `CONFIG_RBCP_DEV_MASK` | `(1 << DEV_SHIFT) - 1` |
| `CONFIG_RBCP_LANE_OFF` | CPU byte offset of this device's lane within one bus cycle |
| `CONFIG_RBCP_ENDIAN_XOR` | 1 where the host's byte order within a cycle opposes the specification's data-line assignment |

They feed two formulae. Sending a command byte:

```
cpu_addr(byte) = CMD_PAGE_ABS + (byte << BUS_SHIFT)
```

Reading back-channel region byte N:

```
cpu_addr(N) = BCH_ABS
            + ((N >> DEV_SHIFT) << BUS_SHIFT)   ; which bus cycle
            + LANE_OFF                          ; which device on the bus
            + ((N & DEV_MASK) EOR ENDIAN_XOR)   ; which byte within it
```

`rbcp_defs.s` uses the second to derive the CPU address of every response header field, and converts the CPU-address placement in your config into the device-side values `ENTER_CMD_RESP` actually takes — a command page counted in device bus cycles, and a back-channel start counted in device bytes. Those are not the same numbers as the CPU addresses they come from, which is exactly the mistake the mapping exists to prevent.

### Supported configurations

|  | `BUS_SHIFT` | `DEV_SHIFT` | `DEV_MASK` | `LANE_OFF` | `ENDIAN_XOR` |
|---|---|---|---|---|---|
| One ×16 device, 16-bit bus | 1 | 1 | 1 | 0 | 1 |
| Two 8-bit devices, 16-bit bus — high lane | 1 | 0 | 0 | 0 | 0 |
| …low lane | 1 | 0 | 0 | 1 | 0 |
| Two ×16 devices, 32-bit bus — high word | 2 | 1 | 1 | 0 | 1 |
| …low word | 2 | 1 | 1 | 2 | 1 |
| Four 8-bit devices, 32-bit bus — lane L | 2 | 0 | 0 | L | 0 |

Only the first row is exercised today. The rest are recorded because they are the shape the mapping must keep.

On a multi-device bus the address lines are shared, so **every device decodes every knock and every command**, and each maintains its **own complete** back-channel header. The headers interleave in CPU address space at the bus stride; they do not merge. A host on such a bus must poll every lane's header before treating a command as complete — this library polls one, and is therefore correct only for a single-device bus. Nor can a host rely on addressing one device in isolation: `/UDS` and `/LDS` never reach a single ×16 ROM at all, reach a pair of 8-bit ROMs only if the board wires them that way, and do not exist on 68020 and later.

## Execution environment

**This code must execute from RAM, not from the ROM the device is serving.** Instruction fetches from that ROM put their own addresses on the bus, and outside command-response mode the device treats every address read as command data. Once command-response mode is established the device filters on the command page and ROM reads elsewhere become harmless — but the knock and the `ENTER_CMD_RESP` that establish it have no such protection.

The Amiga example handles this by assembling a RAM section into the ROM image and copying it to chip RAM before any RBCP traffic.

## Calling convention

All routines preserve every register they use. `D0` is the return value: 0 with Z set on success, non-zero with Z clear on failure. Callers set `RBCP_GROUP`, `RBCP_CMD` and `RBCP_ARG0..N` in scratch RAM before calling a command helper — the 68K has no zero page, so a fixed RAM block stands in for the 6502 convention.

On failure `RBCP_ERROR_CODE` holds the stage: 1 = token never incremented, 2 = progress never reached complete, 3 = device reported failure.

## Routines

| Routine | Purpose |
|---|---|
| `rbcp_knock` | Send the `!RBCP!` knock |
| `rbcp_send_cmd` | Send GROUP, CMD and `D0.B` argument bytes |
| `rbcp_save_token` / `rbcp_poll_token` | Token snapshot and poll |
| `rbcp_poll_progress` / `rbcp_poll_progress_long` | Progress poll, normal and NV timeouts |
| `rbcp_check_response` | Read the response field |
| `rbcp_issue_cmd` / `rbcp_issue_cmd_long_poll` | The full host polling sequence |
| `rbcp_reset` (and `rbcp_reset_stage1/2/3`) | The three-stage reset sequence |
| `rbcp_cmd_enter_cmd_resp` | Knock + `ENTER_CMD_RESP` from config |
| `rbcp_cmd_nop` | `NOP` — proves a session is live |
| `rbcp_cmd_exit_cmd_resp_ack` | Acknowledged exit |

## The token is never read as a word

The specification guarantees atomicity only for individual byte writes, and directs a host wanting the full 16-bit token to read high, read low, read high and retry if the high bytes differ. This library never needs the full value: the polling sequence compares the LSB alone, which is a single atomic byte read. On a ×16 device the two token bytes are not even adjacent in CPU address space.

## Build-time assertions

`rbcp_defs.s` fails the build if the configured back-channel start is not 4-byte aligned in device terms, or if either sentinel value is `$AA`.
